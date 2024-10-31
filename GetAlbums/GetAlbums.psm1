function Get-Albums {
    [CmdletBinding()]
    param (
        [ValidatePattern('^\d\d\d\d$', ErrorMessage = "You should specify the year.")]
        [string]$Year = (Get-Date).Year.ToString()
    )
    $artists = Get-Content -LiteralPath "$PSScriptRoot\artists.json" -Raw | ConvertFrom-Json
    foreach ($artist in $artists) {
        $job = Start-Job -ArgumentList $artist, $Year {
            $a, $y = $args
            $st = Get-Date
            $discogs = @{
                Uri = "https://api.discogs.com/artists/$($a.id)/releases?sort=year&sort_order=desc&per_page=100"
                UserAgent = 'PwShCheckScript/v1'
            }
            try { $response = Invoke-RestMethod @discogs }
            catch { return [PSCustomObject]@{ Status = $false }}
            $files = Get-ChildItem -Path "D:\Music\$($a.folder)" -File -Name | Where-Object { $_.Substring(0, 4) -ge $y }
            $albums = $response.releases | Where-Object { ($_.type -eq 'master') -and ($_.role -eq 'main') -and ($_.year -ge $y) }
            $result = [PSCustomObject]@{ Status = $true; Albums = @() }
            if ($albums.Count -gt 0) {
                $albums | Foreach-Object {
                    $result.Albums += [PSCustomObject]@{
                        Title = "$($_.year) $($_.title)"
                        HaveIt = ($files -contains "$($_.year) $($_.title).flac")
                    }
                }
            }
            if (($t = (New-TimeSpan -Start $st -End (Get-Date)).TotalSeconds) -lt 4) { Start-Sleep -Seconds (4 - $t) }
            return $result
        }
        $c = @('Yellow', $Host.UI.RawUI.BackgroundColor)
        $i = 0
        [Console]::CursorVisible = $false
        while ($job.State -eq 'Running') {
            Write-Host $artist.title.SubString(0, $i) -BackgroundColor $c[0] -ForegroundColor $c[1] -NoNewLine
            Write-Host ($artist.title.SubString($i) + "`r") -BackgroundColor $c[1] -ForegroundColor $c[0] -NoNewLine
            if ($i -lt $artist.title.Length) { $i++ } else { $i = 0; $c[0], $c[1] = $c[1], $c[0] }
            Start-Sleep -Seconds 0.1
        }
        [Console]::CursorVisible = $true
        $result = Receive-Job -Job $job
        if ($result.Status) {
            Write-Host $artist.title -ForegroundColor ($result.Albums.HaveIt -contains $false ? 'Green' : 'DarkBlue')
            $result.Albums | ForEach-Object {
                Write-Host "  $($_.Title)" -ForegroundColor ($_.HaveIt ? 'DarkGray' : $Host.UI.RawUI.ForegroundColor)
            }
        } else { Write-Host $artist.title -ForegroundColor Red }
    }
}
Export-ModuleMember -Function Get-Albums