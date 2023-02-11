#!/usr/bin/env pwsh

$ProgressPreference = "SilentlyContinue"

#Region Services

Function Assert-Pending {

    $RegKey0 = "HKLM:\Software\Microsoft\Windows\CurrentVersion"
    $RegKey1 = "$RegKey0\Component Based Servicing\RebootPending"
    $RegKey2 = "$RegKey0\WindowsUpdate\Auto Update\RebootRequired"
    $RegKey3 = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    If (Get-ChildItem "$RegKey1" -EA Ignore) { Return $True }
    If (Get-Item "$RegKey2" -EA Ignore) { Return $True }
    If (Get-ItemProperty "$RegKey3" -Name PendingFileRenameOperations -EA Ignore) { Return $True }
    Try { 
        $Factors = [WmiClass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
        $Pending = $Factors.DetermineIfRebootPending()
        If (($Null -Ne $Pending) -And $Pending.RebootPending) {
            Return $True
        }
    }
    Catch {}
    Return $False

}

Function Enable-Feature {

    Param(
        [String] $Feature
    )

    Switch ($Feature) {
        "HyperV" {
            $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Hyper-V-All" -Online).State }
            If ($Content.Value -Ne "Enabled") {
                $Address = "https://cdn3.bluestacks.com/support_files/HD-EnableHyperV.exe"
                $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
                Invoke-Gsudo { Start-Process "$Using:Fetched" ; Start-Sleep 10 ; Stop-Process -Name "HD-EnableHyperV" }
                Invoke-Restart
            }
        }
        "RemoteDesktop" {
            Invoke-Gsudo {
                $RegPath = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
                Set-ItemProperty -Path "$RegPath" -Name "fDenyTSConnections" -Value 0
                Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
            }
        }
        "Uac" {
            $Content = @(
                '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
                'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 5'
                'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 1'
            ) -Join "`n"
            $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
            [IO.File]::WriteAllText("$Created", $Content)
            Try { Start-Process "powershell" "-ep bypass -file `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait } Catch { }
            Remove-Item "$Created" -Force
        }
        "Wsl" {
            $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Windows-Subsystem-Linux" -Online).State }
            If ($Content.Value -Ne "Enabled") {
                Invoke-Gsudo {
                    $ProgressPreference = "SilentlyContinue"
                    Enable-WindowsOptionalFeature -Online -FE "VirtualMachinePlatform" -All -NoRestart *> $Null
                    Enable-WindowsOptionalFeature -Online -FE "Microsoft-Windows-Subsystem-Linux" -All -NoRestart *> $Null
                }
                Invoke-Restart
            }
        }
    }

}

Function Import-Library {

    Param(
        [String] $Library,
        [Switch] $Testing
    )

    If (-Not ([Management.Automation.PSTypeName]"$Library").Type ) {
        Install-Package "$Library" -Scope "CurrentUser" -Source "https://www.nuget.org/api/v2" -Force -SkipDependencies
        $Results = (Get-ChildItem -Filter "*.dll" -Recurse (Split-Path (Get-Package -Name "$Library").Source)).FullName
        $Content = $Results | Where-Object { $_ -Like "*standard2.0*" } | Select-Object -Last 1
        If ($Testing) { Try { Add-Type -Path "$Content" -EA SI } Catch { $_.Exception.LoaderExceptions ; Return $False } }
        Else { Add-Type -Path "$Content" -EA SI }
    }

}

Function Invoke-Browser {

    Param(
        [String] $Startup = "https://www.bing.com",
        [String] $Factors,
        [Switch] $Firefox,
        [Switch] $Visible
    )

    Update-Powershell
    Import-Library "System.Text.Json"
    Import-Library "Microsoft.Bcl.AsyncInterfaces"
    Import-Library "Microsoft.CodeAnalysis"
    Import-Library "Microsoft.Playwright"
    [Microsoft.Playwright.Program]::Main(@("install", "firefox"))
    $Handler = [Microsoft.Playwright.Playwright]::CreateAsync().GetAwaiter().GetResult()
    If ($Firefox) { $Browser = $Handler.Firefox.LaunchAsync(@{ "Headless" = !$Visible }).GetAwaiter().GetResult() }
    Else { $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = !$Visible }).GetAwaiter().GetResult() }
    $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
    $WebPage.GoToAsync("$Startup").GetAwaiter().GetResult()
    $WebPage.CloseAsync().GetAwaiter().GetResult()
    $Browser.CloseAsync().GetAwaiter().GetResult()

    # Update-Powershell
    # $Members = @("Microsoft.Bcl.AsyncInterfaces", "Microsoft.CodeAnalysis", "Microsoft.Playwright", "System.Text.Json")
    # Foreach ($Element In $Members) {
    #     If (-Not (Get-Package -Name "$Element" -EA SI)) {
    #         Install-Package "$Element" -Scope "CurrentUser" -Source "https://www.nuget.org/api/v2" -Force -SkipDependencies
    #     }
    # }
    # $Members = @("System.Text.Json", "Microsoft.Bcl.AsyncInterfaces", "Microsoft.Playwright")
    # Foreach ($Element In $Members) {
    #     If (-Not ([System.Management.Automation.PSTypeName]"$Element").Type ) {
    #         $Results = (Get-ChildItem -Filter "*.dll" -Recurse (Split-Path (Get-Package -Name "$Element").Source)).FullName
    #         $Content = $Results | Where-Object { $_ -Like "*standard2.0*" } | Select-Object -Last 1
    #         Try { Add-Type -Path "$Content" -EA SI } Catch { $_.Exception.LoaderExceptions ; Return $False }
    #     }
    # }

}

Function Invoke-Restart {

    Update-Powershell
    $Current = $Script:MyInvocation.MyCommand.Path
    $Program = "$Env:LocalAppData\Microsoft\WindowsApps\wt.exe"
    $Heading = (Get-Item "$Current").BaseName
    $Command = "$Program --title $Heading pwsh -ep bypass -noexit -nologo -file $Current"
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    New-ItemProperty "$RegPath" "$Heading" -Value "$Command"
    Invoke-Gsudo { Get-LocalUser -Name "$Env:Username" | Set-LocalUser -Password ([SecureString]::New()) }
    Start-Sleep 4 ; Restart-Computer -Force

}

Function Remove-Desktop {

    Param(
        [String] $Pattern
    )

    Remove-Item -Path "$Env:Public\Desktop\$Pattern"
    Remove-Item -Path "$Env:UserProfile\Desktop\$Pattern"

}

Function Remove-Feature {

    Param(
        [String] $Feature
    )

    Switch ($Feature) {
        "HyperV" {
            $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Hyper-V-All" -Online).State }
            If ($Content.Value -Eq "Enabled") {
                $Address = "https://cdn3.bluestacks.com/support_files/HD-DisableHyperV_native_v2.exe"
                $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
                Invoke-Gsudo { Start-Process "$Using:Fetched" ; Start-Sleep 10 ; Stop-Process -Name "HD-DisableHyperV" }
                If (Assert-Pending -Eq $True) { Invoke-Restart }
            }
        }
        "Uac" {
            $Content = @(
                '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
                'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 0'
                'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 0'
            ) -Join "`n"
            $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
            [IO.File]::WriteAllText("$Created", $Content)
            Try { Start-Process "powershell" "-ep bypass -file `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait } Catch { }
            Remove-Item "$Created" -Force
        }
    }

}

Function Update-Element {

    Param(
        [String] $Element,
        [String] $Payload
    )

    Switch ($Element) {
        "Computer" {
            If ([String]::IsNullOrWhiteSpace("$Payload")) { Return }
            If ((Hostname) -Ne "$Payload") {
                Invoke-Gsudo { Rename-Computer -NewName "$Using:Payload" -EA SI *> $Null }
            }
        }
        "Plan" {
            $Program = "C:\Windows\System32\powercfg.exe"
            $Picking = (& "$Program" /l | ForEach-Object { If ($_.Contains("($Payload")) { $_.Split()[3] } })
            If ([String]::IsNullOrEmpty("$Picking") -And $Payload -Eq "Ultra") { Return }
            If ([String]::IsNullOrEmpty("$Picking")) { & "$Program" /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 }
            $Picking = (& "$Program" /l | ForEach-Object { If ($_.Contains("($Payload")) { $_.Split()[3] } })
            & "$Program" /s "$Picking"
            If ($Payload -Eq "Ultimate") {
                $Desktop = $Null -Eq (Get-WmiObject Win32_SystemEnclosure -ComputerName "localhost" | Where-Object ChassisTypes -In "{9}", "{10}", "{14}")
                $Desktop = $Desktop -Or $Null -Eq (Get-WmiObject Win32_Battery -ComputerName "localhost")
                If (-Not $Desktop) { & "$Program" /setacvalueindex $Picking sub_buttons lidaction 000 }
            }
        }
        "Timezone" {
            Set-TimeZone -Name "$Payload"
            Invoke-Gsudo {
                Start-Process "w32tm" "/unregister" -WindowStyle Hidden -Wait
                Start-Process "w32tm" "/register" -WindowStyle Hidden -Wait
                Start-Process "net" "start w32time" -WindowStyle Hidden -Wait
                Start-Process "w32tm" "/resync /force" -WindowStyle Hidden -Wait
            }
        }
    }

}

Function Update-LnkFile {

    Param(
        [String] $LnkFile,
        [String] $Starter,
        [String] $ArgList,
        [String] $Message,
        [String] $Picture,
        [String] $WorkDir,
        [Switch] $AsAdmin
    )

    $Wscript = New-Object -ComObject WScript.Shell
    $Element = $Wscript.CreateShortcut("$LnkFile")
    If ($Starter) { $Element.TargetPath = "$Starter" }
    If ($ArgList) { $Element.Arguments = "$ArgList" }
    If ($Message) { $Element.Description = "$Message" }
    $Element.IconLocation = If ($Picture -And (Test-Path "$Picture")) { "$Picture" } Else { "$Starter" }
    $Element.WorkingDirectory = If ($WorkDir -And (Test-Path "$WorkDir")) { "$WorkDir" } Else { Split-Path "$Starter" }
    $Element.Save()
    If ($AsAdmin) { 
        $Content = [IO.File]::ReadAllBytes("$LnkFile")
        $Content[0x15] = $Content[0x15] -Bor 0x20
        [IO.File]::WriteAllBytes("$LnkFile", $Content)
    }

}

Function Update-SysPath {

    Param (
        [String] $Payload,
        [ValidateSet("Machine", "Process", "User")] [String] $Section
    )

    If (-Not (Test-Path "$Payload")) { Return }

    If ($Section -Ne "Process" ) {
        $OldPath = [Environment]::GetEnvironmentVariable("PATH", "$Section")
        $OldPath = $OldPath -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Payload))\\?" }
        $NewPath = ($OldPath + $Payload) -Join ";"
        Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PATH", "$Using:NewPath", "$Using:Section") }
    }

    $OldPath = $Env:Path -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Payload))\\?" }
    $NewPath = ($OldPath + $Payload) -Join ";" ; $Env:Path = $NewPath -Join ";"

}

#EndRegion

Function Update-Gsudo {

    $Current = (Get-Package "*gsudo*" -EA SI).Version
    If ($Null -Eq $Current) { $Current = "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0" ; If ($Present) { Return $True }

    $Address = "https://api.github.com/repos/gerardog/gsudo/releases/latest"
    $Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    Try {
        If (-Not $Updated) {
            $Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
            $Address = $Results.Where( { $_.browser_download_url -Like "*.msi" } ).browser_download_url
            $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		    (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
            If (-Not $Present) { Start-Process "msiexec" "/i `"$Fetched`" /qn" -Verb RunAs -Wait }
            Else { Invoke-Gsudo { msiexec /i "$Using:Fetched" /qn } }
            Start-Sleep 4
        }
        Update-SysPath "${Env:ProgramFiles(x86)}\gsudo" "Process"
        Return $True
    }
    Catch { 
        Return $False
    }

}

Function Update-Ldplayer {

    $Current = (Get-Package "*ldplayer*" -EA SI).Version
    If ($Null -Eq $Current) { $Current = "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    $Address = "https://www.ldplayer.net/other/version-history-and-release-notes.html"
    $Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "LDPlayer_([\d.]+).exe").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        Remove-Feature "HyperV"
        $Address = "https://encdn.ldmnq.com/download/package/LDPlayer_$Version.exe"
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        # $Current = Split-Path $Script:MyInvocation.MyCommand.Path
        $Current = $Script:MyInvocation.MyCommand.Path
        Invoke-Gsudo {
            # . $Using:Current
            # Add-Type -Path "$Using:Current\libs\Interop.UIAutomationClient.dll"
            # Add-Type -Path "$Using:Current\libs\FlaUI.Core.dll"
            # Add-Type -Path "$Using:Current\libs\FlaUI.UIA3.dll"
            # Add-Type -Path "$Using:Current\libs\System.Drawing.Common.dll"
            # Add-Type -Path "$Using:Current\libs\System.Security.Permissions.dll"
            . $Script:MyInvocation.MyCommand.Path
            Import-Library "Interop.UIAutomationClient"
            Import-Library "FlaUI.Core"
            Import-Library "FlaUI.UIA3"
            Import-Library "System.Drawing.Common"
            Import-Library "System.Security.Permissions"
            $Handler = [FlaUI.UIA3.UIA3Automation]::New()
            $Started = [FlaUI.Core.Application]::Launch("$Using:Fetched")
            $Window1 = $Started.GetMainWindow($Handler)
            $Window1.Focus()
            $Scraped = $Window1.BoundingRectangle
            $FactorX = $Scraped.X + ($Scraped.Width / 2)
            $FactorY = $Scraped.Y + ($Scraped.Height / 2) + 60
            $Centrum = [Drawing.Point]::New($FactorX, $FactorY)
            Start-Sleep 4 ; [FlaUI.Core.Input.Mouse]::LeftClick($Centrum)
            While (-Not (Test-Path "$Env:UserProfile\Desktop\LDPlayer*.lnk")) { Start-Sleep 2 }
            $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
            $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::F4
            Start-Sleep 4 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
        } -LoadProfile
        Remove-Desktop "LDM*.lnk" ; Remove-Desktop "LDP*.lnk"
    }

}

Function Update-Powershell {

    $Starter = (Get-Item "$Env:ProgramFiles\PowerShell\*\pwsh.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    # $Present = $Current -Ne "0.0.0.0"

    $Address = "https://api.github.com/repos/powershell/powershell/releases/latest"
    $Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        Invoke-Gsudo { Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet" }
        If ([Version] "$Current" -Lt [Version] "7.0.0.0") { Invoke-Restart }
    }

}

Function Update-Windows {

    Param (
        [String] $Country = "Romance Standard Time",
        [String] $Machine
    )

    # Update timezone
    Update-Element "Timezone" "$Country"

    # Update computer
    Update-Element "Computer" "$Machine"

    # Enable remote desktop
    Enable-Feature "RemoteDesktop"

}

If ($MyInvocation.InvocationName -Ne ".") {

    # Change headline
    Clear-Host ; $Current = $Script:MyInvocation.MyCommand.Path
    $Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName

    # Output greeting
    Write-Output "+---------------------------------------------------------------+"
    Write-Output "|                                                               |"
    Write-Output "|  > WINHOGEN                                                   |"
    Write-Output "|                                                               |"
    Write-Output "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                        |"
    Write-Output "|                                                               |"
    Write-Output "+---------------------------------------------------------------+"

    # Handle security
    $Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
    $Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
    Write-Host "$Loading" -FO DarkYellow -NoNewline
    Remove-Feature "Uac" ; Update-Element "Plan" "Ultimate"
    $Correct = (Update-Gsudo) -And ! (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
    If (-Not $Correct) { Write-Host "$Failure`n" -FO Red ; Exit } ; Update-Powershell

    Update-Ldplayer ; Exit

    # Handle elements
    $Members = @(
        "Invoke-Browser -Firefox -Visible"
        # "Update-Windows 'Romance Standard Time' 'CODHOGEN'"
        # "Update-Ldplayer"
    )

    # Output progress
    $Maximum = (65 - 20) * -1
    $Shaping = "`r{0,$Maximum}{1,-3}{2,-6}{3,-3}{4,-8}"
    $Heading = "$Shaping" -F "FUNCTION", " ", "STATUS", " ", "DURATION"
    Write-Host "$Heading"
    Foreach ($Element In $Members) {
        $Started = Get-Date
        $Running = $Element.Split(' ')[0].ToUpper()
        $Shaping = "`n{0,$Maximum}{1,-3}{2,-6}{3,-3}{4,-8}"
        $Loading = "$Shaping" -F "$Running", "", "ACTIVE", "", "--:--:--"
        Write-Host "$Loading" -ForegroundColor DarkYellow -NoNewline
        Try {
            Invoke-Expression $Element *> $Null
            $Elapsed = "{0:hh}:{0:mm}:{0:ss}" -F ($(Get-Date) - $Started)
            $Shaping = "`r{0,$Maximum}{1,-3}{2,-6}{3,-3}{4,-8}"
            $Success = "$Shaping" -F "$Running", "", "WORKED", "", "$Elapsed"
            Write-Host "$Success" -ForegroundColor Green -NoNewLine
        }
        Catch {
            $Elapsed = "{0:hh}:{0:mm}:{0:ss}" -F ($(Get-Date) - $Started)
            $Shaping = "`r{0,$Maximum}{1,-3}{2,-6}{3,-3}{4,-8}"
            $Failure = "$Shaping" -F "$Running", "", "FAILED", "", "$Elapsed"
            Write-Host "$Failure" -ForegroundColor Red -NoNewLine
        }
    }

    # Revert security
    Enable-Feature "Uac" ; gsudo -k *> $Null

    # Output new line
    Write-Host "`n"

}