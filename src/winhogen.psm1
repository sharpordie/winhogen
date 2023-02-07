#!/usr/bin/env pwsh

Function Update-Ldplayer {

    $Current = (Get-Package "LDPlayer" -ProviderName "Programs" -EA SI).Version
    If ($Null -Eq $Current) { $Current = "0.0.0.0" }
    # $Present = $Current -Ne "0.0.0.0"

    $Address = "https://www.ldplayer.net/other/version-history-and-release-notes.html"
    $Pattern = "LDPlayer_([\d.]+).exe"
    $Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "$Pattern").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://encdn.ldmnq.com/download/package/LDPlayer_$Version.exe"
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")

        Invoke-Gsudo {
            $Current = Split-Path $Script:MyInvocation.MyCommand.Path
            Add-Type -Path "$Current\libs\Interop.UIAutomationClient.dll"
            Add-Type -Path "$Current\libs\FlaUI.Core.dll"
            Add-Type -Path "$Current\libs\FlaUI.UIA3.dll"
            Add-Type -Path "$Current\libs\System.Drawing.Common.dll"
            Add-Type -Path "$Current\libs\System.Security.Permissions.dll"
            $Handler = [FlaUI.UIA3.UIA3Automation]::New()
            $Started = [FlaUI.Core.Application]::Launch("$Using:Fetched")
            $Window1 = $Started.GetMainWindow($Handler)
            $Window1.Focus()
            $Scraped = $Window1.BoundingRectangle
            $FactorX = $Scraped.X + ($Scraped.Width / 2)
            $FactorY = $Scraped.Y + ($Scraped.Height / 2) + 60
            $Centrum = [Drawing.Point]::New($FactorX, $FactorY)
            Start-Sleep 4
            [FlaUI.Core.Input.Mouse]::LeftClick($Centrum)
            Start-Sleep 50
            $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
            $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::F4
            [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
        }

        Remove-Item "$Env:Public\Desktop\LDM*.lnk" -EA SI
        Remove-Item "$Env:Public\Desktop\LDP*.lnk" -EA SI
        Remove-Item "$Env:UserProfile\Desktop\LDM*.lnk" -EA SI
        Remove-Item "$Env:UserProfile\Desktop\LDP*.lnk" -EA SI
    }

}