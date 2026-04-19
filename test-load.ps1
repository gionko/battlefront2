$sig = @'
using System;
using System.Runtime.InteropServices;
public static class K {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern IntPtr LoadLibraryA(string lpFileName);
    [DllImport("kernel32.dll")]
    public static extern int GetLastError();
}
'@
Add-Type -TypeDefinition $sig -Language CSharp

$path = 'C:\ProgramData\Kyber\Module\Kyber.dll'
Write-Output "Attempting LoadLibraryA on: $path"
$h = [K]::LoadLibraryA($path)
$err = [K]::GetLastError()
Write-Output "HMODULE: $h"
Write-Output "GetLastError: $err (0x{0:X})" -f $err
if ($h -eq [IntPtr]::Zero) {
    $msg = ([System.ComponentModel.Win32Exception]$err).Message
    Write-Output "Error message: $msg"
}
