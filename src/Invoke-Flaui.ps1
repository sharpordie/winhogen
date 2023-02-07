#!/usr/bin/env pwsh

Function Update-Ldplayer {

    $Current = (Get-Package "LDPlayer" -ProviderName "Programs" -EA SI).Version
    If ($Null -Eq $Current) { $Current = "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    $Fetched = "src\LDPlayer_9.0.36.exe"
   
    Invoke-Gsudo {
        Add-Type -Path "src\Libs\Interop.UIAutomationClient.dll"
        Add-Type -Path "src\Libs\FlaUI.Core.dll"
        Add-Type -Path "src\Libs\FlaUI.UIA3.dll"
        Add-Type -Path "src\Libs\System.Drawing.Common.dll"
        Add-Type -Path "src\Libs\System.Security.Permissions.dll"
        $Handler = [FlaUI.UIA3.UIA3Automation]::New()
        $Invoked = [FlaUI.Core.Application]::Launch("$Using:Fetched")
        $Window1 = $Invoked.GetMainWindow($Handler)
        $Window1.Focus()
        $Scraped = $Window1.BoundingRectangle
        $FactorX = $Scraped.X + ($Scraped.Width / 2)
        $FactorY = $Scraped.Y + ($Scraped.Height / 2) + 60
        $Centrum = [Drawing.Point]::New($FactorX, $FactorY)
        Start-Sleep 4
        [FlaUI.Core.Input.Mouse]::LeftClick($Centrum);
        Start-Sleep 50
        $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
        $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::F4
        [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
    } 
    

}

Update-Ldplayer