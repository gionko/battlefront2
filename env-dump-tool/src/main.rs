use std::env;
use std::ffi::c_void;
use std::mem::size_of;
use std::ptr;
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::System::Diagnostics::Debug::ReadProcessMemory;
use windows::Win32::System::Threading::{
    OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_VM_READ,
};

// NtQueryInformationProcess via direct FFI to ntdll
#[link(name = "ntdll")]
extern "system" {
    fn NtQueryInformationProcess(
        handle: HANDLE,
        info_class: i32,
        info_buf: *mut c_void,
        info_len: u32,
        return_len: *mut u32,
    ) -> i32;
}

#[repr(C)]
#[derive(Default)]
struct ProcessBasicInformation {
    exit_status: i32,
    peb_base_address: usize,
    affinity_mask: usize,
    base_priority: i32,
    unique_process_id: usize,
    inherited_from_unique_process_id: usize,
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <pid>", args[0]);
        std::process::exit(1);
    }
    let pid: u32 = args[1].parse().expect("invalid pid");

    unsafe {
        let handle = OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
            false,
            pid,
        )
        .expect("OpenProcess failed — run as admin");

        let mut pbi = ProcessBasicInformation::default();
        let mut len = 0u32;
        let status = NtQueryInformationProcess(
            handle,
            0,
            &mut pbi as *mut _ as *mut c_void,
            size_of::<ProcessBasicInformation>() as u32,
            &mut len,
        );
        if status != 0 {
            eprintln!("NtQueryInformationProcess failed: 0x{:X}", status);
            CloseHandle(handle).ok();
            std::process::exit(1);
        }

        // PEB -> ProcessParameters @ PEB+0x20
        let mut pp_addr: usize = 0;
        ReadProcessMemory(
            handle,
            (pbi.peb_base_address + 0x20) as *const c_void,
            &mut pp_addr as *mut _ as *mut c_void,
            size_of::<usize>(),
            None,
        )
        .expect("read PEB failed");

        // ProcessParameters.Environment @ +0x80
        let mut env_addr: usize = 0;
        ReadProcessMemory(
            handle,
            (pp_addr + 0x80) as *const c_void,
            &mut env_addr as *mut _ as *mut c_void,
            size_of::<usize>(),
            None,
        )
        .expect("read ProcessParameters failed");

        // ProcessParameters.EnvironmentSize @ +0x3F0
        let mut env_size: u32 = 0;
        ReadProcessMemory(
            handle,
            (pp_addr + 0x3F0) as *const c_void,
            &mut env_size as *mut _ as *mut c_void,
            size_of::<u32>(),
            None,
        )
        .expect("read env size failed");

        let size = env_size as usize;
        let size = if size == 0 || size > 1 << 20 { 1 << 15 } else { size };

        let mut buf = vec![0u8; size];
        let mut bytes_read = 0usize;
        ReadProcessMemory(
            handle,
            env_addr as *const c_void,
            buf.as_mut_ptr() as *mut c_void,
            size,
            Some(&mut bytes_read),
        )
        .expect("read env block failed");

        let wide: Vec<u16> = buf[..bytes_read]
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();

        // env block is \0-separated wide strings, terminated by \0\0
        let text = String::from_utf16_lossy(&wide);
        for v in text.split('\0') {
            let v = v.trim();
            if v.is_empty() {
                continue;
            }
            // Filter only interesting vars
            if v.starts_with("KYBER_")
                || v.starts_with("MAXIMA_")
                || v.starts_with("EA")
                || v.starts_with("MX")
                || v.starts_with("Origin")
                || v.starts_with("Content")
                || v.starts_with("PATH=")
                || v.starts_with("GRPC_")
            {
                println!("{}", v);
            }
        }

        CloseHandle(handle).ok();
    }
}
