$dumpExe = "D:\LanpartyStorage\tools\Kyber-ver-beta10\env-dump-tool\target\release\env-dump.exe"
$outputFile = "D:\LanpartyStorage\tools\Kyber-ver-beta10\env-dump.log"
"" | Out-File $outputFile  # truncate

Write-Output "Polling for starwarsbattlefrontii and maxima-bootstrap. Press Ctrl+C to stop."
$seenGame = @{}
$seenBoot = @{}
while ($true) {
    # Game
    Get-Process starwarsbattlefrontii -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $seenGame.ContainsKey($_.Id)) {
            $seenGame[$_.Id] = $true
            $header = "=== $(Get-Date -Format HH:mm:ss.fff) GAME PID $($_.Id) ==="
            Write-Output $header
            $header | Out-File -Append $outputFile
            $out = & $dumpExe $_.Id 2>&1
            $out | Out-File -Append $outputFile
            $out | Write-Output
        }
    }
    # Bootstrap
    Get-Process maxima-bootstrap -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $seenBoot.ContainsKey($_.Id)) {
            $seenBoot[$_.Id] = $true
            $header = "=== $(Get-Date -Format HH:mm:ss.fff) BOOTSTRAP PID $($_.Id) ==="
            Write-Output $header
            $header | Out-File -Append $outputFile
            $out = & $dumpExe $_.Id 2>&1
            $out | Out-File -Append $outputFile
            $out | Write-Output
        }
    }
    Start-Sleep -Milliseconds 300
}
