param([Parameter(Mandatory=$true)][string]$ProcName)

$sig = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public static class PE {
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_BASIC_INFORMATION {
        public IntPtr ExitStatus;
        public IntPtr PebBaseAddress;
        public IntPtr AffinityMask;
        public IntPtr BasePriority;
        public UIntPtr UniqueProcessId;
        public IntPtr InheritedFromUniqueProcessId;
    }
    [DllImport("ntdll.dll")]
    public static extern int NtQueryInformationProcess(IntPtr handle, int cls, ref PROCESS_BASIC_INFORMATION info, int size, out int returnLength);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out int read);
    public const int PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    public const int PROCESS_VM_READ = 0x10;

    public static string DumpEnv(int pid) {
        IntPtr h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, false, pid);
        if (h == IntPtr.Zero) return "OpenProcess failed: " + Marshal.GetLastWin32Error();
        try {
            var pbi = new PROCESS_BASIC_INFORMATION();
            int len;
            int ntst = NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(pbi), out len);
            if (ntst != 0) return "NtQueryInformationProcess failed: 0x" + ntst.ToString("X");
            // ProcessParameters at PEB offset 0x20 on x64
            byte[] pp = new byte[8];
            int r;
            if (!ReadProcessMemory(h, new IntPtr(pbi.PebBaseAddress.ToInt64() + 0x20), pp, 8, out r)) return "Read PEB failed: " + Marshal.GetLastWin32Error();
            long ppAddr = BitConverter.ToInt64(pp, 0);
            // Environment pointer at ProcessParameters + 0x80 on x64
            byte[] envPtr = new byte[8];
            if (!ReadProcessMemory(h, new IntPtr(ppAddr + 0x80), envPtr, 8, out r)) return "Read ProcessParameters failed: " + Marshal.GetLastWin32Error();
            long envAddr = BitConverter.ToInt64(envPtr, 0);
            // Environment size at ProcessParameters + 0x3F0 on x64
            byte[] envSize = new byte[4];
            if (!ReadProcessMemory(h, new IntPtr(ppAddr + 0x3F0), envSize, 4, out r)) return "Read env size failed: " + Marshal.GetLastWin32Error();
            int size = BitConverter.ToInt32(envSize, 0);
            if (size <= 0 || size > 1048576) size = 32768;
            byte[] envBlock = new byte[size];
            if (!ReadProcessMemory(h, new IntPtr(envAddr), envBlock, size, out r)) return "Read env block failed: " + Marshal.GetLastWin32Error();
            return Encoding.Unicode.GetString(envBlock, 0, r).Replace("\0", "\n");
        } finally { CloseHandle(h); }
    }
}
'@
Add-Type -TypeDefinition $sig -Language CSharp

$procs = Get-Process -Name $ProcName -ErrorAction SilentlyContinue
if (-not $procs) { Write-Output "No process named $ProcName"; exit 1 }
foreach ($p in $procs) {
    Write-Output "=== PID $($p.Id) $($p.ProcessName) ==="
    $env_text = [PE]::DumpEnv($p.Id)
    # Only show KYBER_ variables
    $env_text.Split("`n") | Where-Object { $_ -match '^KYBER_|^MAXIMA_|^EA' } | ForEach-Object { Write-Output $_ }
    Write-Output ""
}
