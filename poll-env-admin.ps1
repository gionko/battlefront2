$dumpExe = "D:\LanpartyStorage\tools\Kyber-ver-beta10\env-dump-tool\target\release\env-dump.exe"
$outFile = "D:\LanpartyStorage\tools\Kyber-ver-beta10\env-captured.txt"
"" | Out-File $outFile
$seen = @{}
Write-Host "Polling (run as admin). Ctrl+C to stop." -ForegroundColor Cyan
for ($i = 0; $i -lt 600; $i++) {
    foreach ($name in 'starwarsbattlefrontii','maxima-bootstrap') {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $seen.ContainsKey($_.Id)) {
                $seen[$_.Id] = $true
                $header = "=== $(Get-Date -Format HH:mm:ss.fff) $name PID=$($_.Id) ==="
                Write-Host $header -ForegroundColor Yellow
                $header | Out-File -Append $outFile
                $out = & $dumpExe $_.Id 2>&1
                $out | Out-File -Append $outFile
                $out | ForEach-Object { Write-Host $_ }
            }
        }
    }
    Start-Sleep -Milliseconds 500
}
Write-Host "Done. Output saved to $outFile" -ForegroundColor Green
