$dlls = 'vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll','msvcp140_1.dll','msvcp140_2.dll','dbghelp.dll','VERSION.dll'
foreach ($d in $dlls) {
    $p = "C:\Windows\System32\$d"
    $e = Test-Path $p
    Write-Output ("$d`t$e")
}
