function Write-Time {
    Write-Host ("[{0}] " -f (Get-Date -Format "HH\:mm\:ss")) -NoNewLine -ForegroundColor DarkGray
}
function Start-SteamIdle {
    [Alias('ssi')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateCount(1, 4)]
        [Alias('i')]
        [uint[]]$AppId,
        [Alias('t')]
        [ValidateSet(10, 15, 20, 30)]
        [byte]$IdleFor = 10
    )
    $steam = Get-Process -Name 'steam' -ErrorAction SilentlyContinue
    if ($AppId -and $steam) {
        "Start idle {0} game{1}" -f $AppId.Count, ($AppId.Count -gt 1 ? 's' : '') | Write-Host

        try {
            $tmpimgs = @()
            $AppId | ForEach-Object {
                $tmpimgs += New-TemporaryFile
                Invoke-RestMethod -Uri "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$_/header_292x136.jpg" -OutFile $tmpimgs[-1]
            }
            magick $tmpimgs.FullName +append "$($Env:TEMP)\ssi.six"
            Get-Content -Path "$($Env:TEMP)\ssi.six"
        }
        catch { "Can't load images" | Write-Host -ForegroundColor Red }
        finally { $tmpimgs, "$($Env:TEMP)\ssi.six" | Remove-Item -ErrorAction SilentlyContinue }

        $nokeypress = $true
        [Console]::CursorVisible = $false
        while ($nokeypress) {
            $running = New-Item -Path "$Env:TEMP\steam-idle-running" -ItemType File -Force
            $AppId | ForEach-Object {
                Start-Job -ArgumentList "$PSScriptRoot\Facepunch.Steamworks.Win64.dll", $_, $running -ScriptBlock {
                    Add-Type -Path $Args[0]
                    [Steamworks.SteamClient]::Init($Args[1])
                    while ($Args[2] | Test-Path) { Start-Sleep -Seconds 0.5 }
                    [Steamworks.SteamClient]::Shutdown()
                } > $null
            }
            $then = [DateTime]::Now
            $span = [TimeSpan]::FromMinutes($IdleFor)
            $progress = {
                $p = [Math]::Round((29 * $AppId.Count - 2) * $span.TotalSeconds / [TimeSpan]::FromMinutes($IdleFor).TotalSeconds)
                $s = $AppId.Count -in 1, 3 ? ("{0}{1}{0}" -f (' ' * [Math]::Round((29 * $AppId.Count - 7) / 2)), $span.ToString('mm\:ss')) :
                    ("{0}{1}{0}" -f (' ' * [Math]::Round((29 * $AppId.Count - 6) / 2)), $span.ToString('m\:ss'))
                '[' | Write-Host -NoNewline
                if ($p -ne 0) { $s.Substring(0, $p) | Write-Host -NoNewline -ForegroundColor $Host.UI.RawUI.BackgroundColor -BackgroundColor $Host.UI.RawUI.ForegroundColor }
                if ($p -ne (29 * $AppId.Count - 2)) { $s.Substring($p) | Write-Host -NoNewline -ForegroundColor $Host.UI.RawUI.ForegroundColor -BackgroundColor $Host.UI.RawUI.BackgroundColor }
                "]`r" | Write-Host -NoNewline
            }
            while ($nokeypress -and ($span -gt 0)) {
                if ([Console]::KeyAvailable) { if (([Console]::ReadKey($true)).Key -eq [ConsoleKey]::Escape) { $nokeypress = $false }}
                $span = [TimeSpan]::FromMinutes($IdleFor) - ([DateTime]::Now - $then)
                & $progress
                Start-Sleep -Seconds 0.5
            }
            $running | Remove-Item
            Start-Sleep -Seconds ($nokeypress ? 5 : 1)
            Get-Job | Stop-Job | Remove-Job
        }
        [Console]::CursorVisible = $true
        Write-Host
    }
}
Export-ModuleMember -Function Start-SteamIdle -Alias ssi