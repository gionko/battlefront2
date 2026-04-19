$sig = @'
using System;
using System.Runtime.InteropServices;
public static class K {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern IntPtr LoadLibraryExA(string lpFileName, IntPtr hFile, uint flags);
    [DllImport("kernel32.dll")]
    public static extern int GetLastError();
    public const uint LOAD_WITH_ALTERED_SEARCH_PATH = 0x00000008;
    public const uint LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR = 0x00000100;
    public const uint LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x00000800;
    public const uint DONT_RESOLVE_DLL_REFERENCES = 0x00000001;
}
'@
Add-Type -TypeDefinition $sig -Language CSharp

$path = 'C:\ProgramData\Kyber\Module\Kyber.dll'

# 1. Try LOAD_WITH_ALTERED_SEARCH_PATH
Write-Output "[Test 1] LoadLibraryEx with LOAD_WITH_ALTERED_SEARCH_PATH"
$h = [K]::LoadLibraryExA($path, [IntPtr]::Zero, [K]::LOAD_WITH_ALTERED_SEARCH_PATH)
$err = [K]::GetLastError()
$msg = if ($err -ne 0) { ([System.ComponentModel.Win32Exception]$err).Message } else { 'OK' }
Write-Output "  HMODULE: $h | GetLastError: $err ($msg)"

# 2. DONT_RESOLVE_DLL_REFERENCES — loads the DLL itself without resolving imports. If THIS succeeds, the issue is dependency resolution, not the DLL file itself.
Write-Output "[Test 2] LoadLibraryEx with DONT_RESOLVE_DLL_REFERENCES (skip dep resolution)"
$h2 = [K]::LoadLibraryExA($path, [IntPtr]::Zero, [K]::DONT_RESOLVE_DLL_REFERENCES)
$err2 = [K]::GetLastError()
$msg2 = if ($err2 -ne 0) { ([System.ComponentModel.Win32Exception]$err2).Message } else { 'OK' }
Write-Output "  HMODULE: $h2 | GetLastError: $err2 ($msg2)"

# 3. LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32
Write-Output "[Test 3] LoadLibraryEx with SEARCH_DLL_LOAD_DIR | SEARCH_SYSTEM32"
$flags3 = [K]::LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR -bor [K]::LOAD_LIBRARY_SEARCH_SYSTEM32
$h3 = [K]::LoadLibraryExA($path, [IntPtr]::Zero, $flags3)
$err3 = [K]::GetLastError()
$msg3 = if ($err3 -ne 0) { ([System.ComponentModel.Win32Exception]$err3).Message } else { 'OK' }
Write-Output "  HMODULE: $h3 | GetLastError: $err3 ($msg3)"
