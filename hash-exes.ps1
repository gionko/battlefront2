$files = Get-ChildItem 'D:\LanpartyStorage\STAR WARS Battlefront II exex\*' -File | Where-Object { $_.Extension -match '\.exe|\.ea|\.steam' -or $_.Name -like '*.exe*' }
Write-Output ("Name`tSize`tFileVersion`tSHA256`tMatch")
foreach ($f in $files) {
    $h = (Get-FileHash -Algorithm SHA256 $f.FullName).Hash
    $v = (Get-Item $f.FullName).VersionInfo.FileVersion
    $match = if ($h -eq '7880E40D79E981B064BAAF06F10785601222C6E227A656B70112C24B1F82E2CE') { 'MATCH-KYBER' } else { '' }
    Write-Output "$($f.Name)`t$($f.Length)`t$v`t$h`t$match"
}
