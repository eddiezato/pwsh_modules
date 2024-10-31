using namespace System.Collections
function ConvertTo-JXL {
    [Alias('c2jxl')]
    [CmdletBinding(DefaultParameterSetName = 'default')]
    param (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [array] $InputObjects,
        [Alias('t')][ValidateSet(1, 2, 3, 4)]
        [byte] $Threads = 2,
        [Alias('e')][ValidateSet(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)]
        [byte] $Effort = 7,
        [Alias('nj')]
        [switch] $NoJpegTranscode,
        [Alias('d')][Parameter(ParameterSetName = 'distance')]
        [string] $Distance,
        [Alias('m')][Parameter(ParameterSetName = 'modular')]
        [switch] $Modular,
        [Alias('z')]
        [switch] $Zip,
        [Alias('p')]
        [switch] $Pause
    )
    begin {
        $x_jpg = 'jpe?g|jfif'
        $x_png = 'png|gif|webp'
        $beforeTitle = [Console]::Title
        $nw = [Console]::WindowWidth - 103
        $targets = @()
    }
    end {
        $InputObjects = Get-Item -LiteralPath ($PSCmdlet.MyInvocation.ExpectingInput ? $input : $InputObjects)
        $files = $InputObjects | Where-Object { -not $_.PSIsContainer -and $_.Extension -match "\.($x_jpg|$x_png)" }
        if ($files.Length) { $targets += [PSCustomObject]@{ Name = '<files>'; Dest = $null; Files = $files }}
        $InputObjects | Where-Object { $_.PSIsContainer } | Foreach-Object {
            $files = $_.GetFiles() | Where-Object { $_.Extension -match "\.($x_jpg|$x_png)" }
            if ($files.Length) {
                $targets += [PSCustomObject]@{
                    Name = ($_.Name.Length -gt $nw) ? ($_.Name.SubString(0, $nw - 3) + '...') : $_.Name
                    Dest = $_.FullName + '_jxl'
                    Files = $files
                }
            }
        }
        Remove-Variable files
        if ($allFiles = $targets.Files.Length) {
            [Console]::Title = '[0%] to JXL'
            "Input images: jpeg `e[93m{0}`e[0m, png `e[91m{1}`e[0m, gif `e[94m{2}`e[0m, webp `e[92m{3}`e[0m`n" -f
                ($targets.Files | Where-Object { $_.Extension -match "\.($x_jpg)" }).Count,
                ($targets.Files | Where-Object { $_.Extension -match "\.png" }).Count,
                ($targets.Files | Where-Object { $_.Extension -match "\.gif" }).Count,
                ($targets.Files | Where-Object { $_.Extension -match "\.webp" }).Count
        } else { throw 'nothing to encode' }
        $doneFiles = 0
        $errors = $false
        foreach ($item in $targets) {
            if ($item.Dest -and -not (Test-Path -LiteralPath $item.Dest)) { New-Item -Path $item.Dest -ItemType Directory | Out-Null }
            $hash = @{ i = 0; e = @() } # hash to store index and errors
            $sync = [Hashtable]::Synchronized($hash) # sync hashtable to read values outside of jobs
            $job = $item.Files | Foreach-Object -ThrottleLimit $Threads -AsJob -Parallel {
                $temp = (${using:item}.Dest, (New-Guid).Guid.Replace('-','')) -join '\'
                $ready4cjxl = $true
                $settings = @('-e', $using:Effort)
                if (($_.Extension -match "\.(${using:x_jpg})") -and -not $using:NoJpegTranscode) {
                    $temp += '.jpg'
                    $s = @('-copy', 'none', '-optimize', '-outfile', $temp, $_.FullName)
                    switch (exiv2 -g Exif.Image.Orientation -Pv $_.FullName *>&1) {
                        '6' { $s = @('-rotate', '90') + $s }
                        '8' { $s = @('-rotate', '270') + $s }
                    }
                    $me = jpegtran @s *>&1
                    if ($LastExitCode) { ($using:sync).e += [PSCustomObject]@{ Task = 'jpegtran'; File = $_.FullName; Message = $me }; $ready4cjxl = $false }
                    $me = exiv2 @('-M', "set Exif.Photo.UserComment jpeg-transcode", 'mo', $temp) *>&1
                    if ($LastExitCode) { ($using:sync).e += [PSCustomObject]@{ Task = 'exiv2'; File = $_.FullName; Message = $me }; $ready4cjxl = $false }
                } else {
                    $temp += '.png'
                    $me = magick @($_.FullName, '-strip', '-depth', '16', "png48:$temp") *>&1
                    if ($LastExitCode) { ($using:sync).e += [PSCustomObject]@{ Task = 'magick'; File = $_.FullName; Message = $me }; $ready4cjxl = $false }
                    switch ($PSCmdlet.ParameterSetName) {
                        'distance' { $settings += '-d', $using:Distance }
                        'modular' { $settings += '-m', '1' }
                    }
                }
                if ($ready4cjxl) {
                    $jxl = ${using:item}.Dest ? ("{0}\{1}.jxl" -f ${using:item}.Dest, $_.BaseName) : ($_.FullName -replace "\$($_.Extension)$", '.jxl')
                    $settings += $temp, $jxl
                    $me = cjxl @settings *>&1
                    if ($LastExitCode) { ($using:sync).e += [PSCustomObject]@{ Task = 'cjxl'; File = $_.FullName; Message = $me }; throw }
                    Remove-Item -LiteralPath $temp -Force
                }
                ($using:sync).i++
            }
            Write-Host ("{0} [ 0 of {1}]" -f $item.Name.PadRight($nw, ' '), $item.Files.Length.ToString().PadRight(94, ' ')) -NoNewLine
            [Console]::CursorLeft = $nw + 2
            $d = 0
            [Console]::CursorVisible = $false
            while ($job.State -eq 'Running') {
                if ($d -lt $sync.i) {
                    $d = $sync.i
                    $s = " $d of $($item.Files.Length)".PadRight(100, ' ')
                    $p = [Math]::Round(100 * $d / $item.Files.Length)
                    Write-Host $s.SubString(0, $p) -NoNewLine -BackgroundColor White -ForegroundColor Black
                    Write-Host $s.SubString($p) -NoNewLine
                    [Console]::CursorLeft = $nw + 2
                    $p = [Math]::Round(($doneFiles + $d) * 100 / $allFiles)
                    #Write-Host "`e]9;4;1;$p`e\" -NoNewLine
                    [Console]::Title = "[$p%] to JXL"
                }
                Start-Sleep -Seconds 0.1
            }
            [Console]::CursorVisible = $true
            $doneFiles += $item.Files.Length
            if ($sync.e) {
                $oldoutput = $PSStyle.OutputRendering
                $PSStyle.OutputRendering = 'PlainText'
                $errors = $true
                $sync.e | Format-List | Out-File -FilePath 'errors.log' -Append
                $PSStyle.OutputRendering = $oldoutput
            }
            if ($item.Dest) { $jxlfiles = Get-ChildItem -LiteralPath $item.Dest -Include '*.jxl' -File }
            else {
                $jxlfiles = @()
                $item.Files | Foreach-Object {
                    if (Test-Path -LiteralPath ($_.FullName -replace "\$($_.Extension)$", '.jxl')) {
                        $jxlfiles += Get-Item -LiteralPath ($_.FullName -replace "\$($_.Extension)$", '.jxl')
                    }
                }
            }
            Write-Host "`r"(' ' * ([Console]::WindowWidth - 1)) -NoNewLine
            $size = ($item.Files | Measure-Object -Sum Length).Sum
            $jxlsize = ($jxlfiles | Measure-Object -Sum Length).Sum
            $sizepr = [Math]::Round($jxlsize / $size, 4)
            "`r{0}  {1} `e[90m-> `e[{2}m{3}`e[0m {4} `e[90m->`e[0m {5} `e[90m[`e[{6}m{7}`e[90m]`e[0m" -f $item.Name.PadRight($nw, ' '),
                $item.Files.Length.ToString().PadLeft(5, ' '),
                ($item.Files.Length -eq $jxlfiles.Length ? '92' : '91'),
                $jxlfiles.Length.ToString().PadRight(5, ' '),
                ([Math]::Round($size / 1MB, 2)).ToString('0.00').PadLeft(8, ' '),
                ([Math]::Round($jxlsize / 1MB, 2)).ToString("0.00 `e[90mMiB`e[0m").PadRight(23, ' '),
                ($sizepr -lt 1 ? '92' : '91'),
                $sizepr.ToString('00.00%')
        }
        Write-Host "`nEncoding completed " -NoNewLine
        #Write-Host "`e]9;4;0`e\" -NoNewLine
        [Console]::Title = '[100%] to JXL'
        if ($errors) { "with `e[91merrors`e[0m, see `e[94merrors.log`e[0m for information"}
        else {
            "`e[92msuccessfully`e[0m`n"
            if ($Zip) {
                #Write-Host "`e]9;4;3`e\" -NoNewLine
                foreach ($item in $targets) {
                    if ($item.Dest) {
                        "Zipping `e[93m$($item.Name)`e[0m"
                        7z a -tzip -bso0 -bse1 -bsp1 "$($item.Dest).zip" "$($item.Dest)\*.jxl"
                    }
                }
                #Write-Host "`e]9;4;0`e\" -NoNewLine
                "Compression to zip is `e[92mdone`e[0m"
            }
        }
        [Console]::Title = $beforeTitle
        if ($Pause) {
            Write-Host 'Press any key...' -NoNewline
            $Host.UI.RawUI.FlushInputBuffer();
            $host.UI.RawUI.ReadKey() | Out-Null
        }
    }
}
Export-ModuleMember -Function ConvertTo-JXL -Alias c2jxl