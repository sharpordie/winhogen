#!/usr/bin/env pwsh

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

Function Export-Members {

    Param(
        [ValidateSet("Development", "GameStreaming", "Gaming")] [String] $Variant,
        [String] $Country = "Romance Standard Time",
        [String] $Machine = "WINHOGEN"
    )

    Switch ($Variant) {
        "Development" {
            Return @(
                "Update-Windows '$Country' '$Machine'"
                # "Update-Noxplayer"
            )
        }
        "GameStreaming" {
            Return @(
                "Update-Windows '$Country' '$Machine'"
                "Update-Sunshine"
            )
        }
        "Gaming" {
            Return @(
                "Update-Windows '$Country' '$Machine'"
                "Update-Bluestacks"
            )
        }
    }

}

Function Import-Library {

    Param(
        [String] $Library,
        [Switch] $Testing
    )

    If (-Not ([Management.Automation.PSTypeName]"$Library").Type ) {
        if (-Not (Get-Package "$Library")) {
            Install-Package "$Library" -Scope "CurrentUser" -Source "https://www.nuget.org/api/v2" -Force -SkipDependencies
        }
        $Results = (Get-ChildItem -Filter "*.dll" -Recurse (Split-Path (Get-Package -Name "$Library").Source)).FullName
        $Content = $Results | Where-Object { $_ -Like "*standard2.0*" } | Select-Object -Last 1
        If ($Testing) { Try { Add-Type -Path "$Content" -EA SI } Catch { $_.Exception.LoaderExceptions } }
        Else { Try { Add-Type -Path "$Content" -EA SI } Catch {} }
    }

}

Function Invoke-Browser {

    Import-Library "System.Text.Json"
    Import-Library "Microsoft.Bcl.AsyncInterfaces"
    Import-Library "Microsoft.CodeAnalysis"
    Import-Library "Microsoft.Playwright"
    & taskkill /f /im node.exe
    $Null = [Microsoft.Playwright.Program]::Main(@("install", "chromium"))
    & taskkill /f /im node.exe
    [Microsoft.Playwright.Playwright]::CreateAsync().GetAwaiter().GetResult()

}

Function Invoke-Restart {

    $Current = $Script:MyInvocation.MyCommand.Path
    $Program = "$Env:LocalAppData\Microsoft\WindowsApps\wt.exe"
    $Heading = (Get-Item "$Current").BaseName.ToUpper()
    $Command = "$Program --title $Heading pwsh -ep bypass -noexit -nologo -file $Current"
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    New-ItemProperty "$RegPath" "$Heading" -Value "$Command"
    Invoke-Gsudo { Get-LocalUser -Name "$Env:Username" | Set-LocalUser -Password ([SecureString]::New()) }
    Start-Sleep 4 ; Restart-Computer -Force

}

Function Invoke-Scraper {

    Param(
        [String] $Address
    )

    If ($PSVersionTable.PSVersion -Lt [Version] "7.0.0.0") {
        Invoke-WebRequest "$Address"
    }
    Else {
        $Handler = Invoke-Browser
        $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
        $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
        $WebPage.GoToAsync("$Address").GetAwaiter().GetResult()
        # $Scraped = $WebPage.ContentAsync().GetAwaiter().GetResult()
        $Scraped = $WebPage.QuerySelectorAsync("body > :first-child").GetAwaiter().GetResult()
        $Scraped = $Scraped.InnerTextAsync().GetAwaiter().GetResult()
        $WebPage.CloseAsync().GetAwaiter().GetResult()
        $Browser.CloseAsync().GetAwaiter().GetResult()
        $Browser = $Null
        Write-Output ($Scraped.ToString() | ConvertFrom-Json).tag_name
    }

    # Try {
    #     Invoke-WebRequest "$Address"
    # }
    # Catch {
    #     $Handler = Invoke-Browser
    #     $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $True }).GetAwaiter().GetResult()
    #     $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
    #     $WebPage.GoToAsync("$Address").GetAwaiter().GetResult()
    #     $Scraped = $WebPage.ContentAsync().GetAwaiter().GetResult()
    #     $WebPage.CloseAsync().GetAwaiter().GetResult()
    #     $Browser.CloseAsync().GetAwaiter().GetResult()
    #     $Scraped
    # }

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

Function Update-Bluestacks {

    Param(
        [ValidateSet("7", "9", "11")] [String] $Android = "11"

    )

    Remove-Feature "HyperV"

    $Starter = (Get-Item "$Env:ProgramFiles\BlueStacks*\HD-Player.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    # $Present = $Current -Ne "0.0.0.0"

    $Address = "https://support.bluestacks.com/hc/en-us/articles/4402611273485-BlueStacks-5-offline-installer"
    $Results = [Regex]::Matches((Invoke-Scraper "$Address"), "windows/nxt/([\d.]+)/(?<sha>[0-9a-f]+)/")
    $Version = $Results.Groups[1].Value
    $Hashing = $results.Groups[2].Value
    $Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 6))

    If (-Not $Updated) {
        $Address = "https://cdn3.bluestacks.com/downloads/windows/nxt/$Version/$Hashing/FullInstaller/x64/BlueStacksFullInstaller_${Version}_amd64_native.exe"
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        $ArgList = "--defaultImageName Rvc64 --imageToLaunch Rvc64"
        If ($Android -Eq "7") { $ArgList = "-s --defaultImageName Nougat64 --imageToLaunch Nougat64" }
        If ($Android -Eq "9") { $ArgList = "-s --defaultImageName Pie64 --imageToLaunch Pie64" }
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Start-Sleep 4 ; Remove-Desktop "BlueStacks*.lnk"
    }

    # $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Hyper-V-All" -Online).State }
    # If ($Content.Value -Eq "Enabled" -And $Android -Eq "7") {
    #     $Altered = (Get-Item "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs\BlueStacks*.lnk" -EA SI).FullName
    #     If ($Null -Ne $Altered) {
    #         $Content = [IO.File]::ReadAllBytes("$Altered")
    #         $Content[0x15] = $Content[0x15] -Bor 0x20
    #         Invoke-Gsudo { [IO.File]::WriteAllBytes("$Using:Altered", $Using:Content) }
    #     }
    # }

}

Function Update-Gsudo {

    $Starter = "${Env:ProgramFiles(x86)}\gsudo\gsudo.exe"
    $Current = Try { (Get-Item "$Starter" -EA SI).VersionInfo.FileVersion.ToString() } Catch { "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    $Address = "https://api.github.com/repos/gerardog/gsudo/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
    # $Address = "https://github.com/gerardog/gsudo/releases/latest"
    # $Version = [Regex]::Matches((Invoke-Scraper "$Address"), "gsudo v([\d.]+)").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    Try {
        If (-Not $Updated) {
            $Address = "https://github.com/gerardog/gsudo/releases/download/v$Version/gsudoSetup.msi"
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
    $Version = [Regex]::Matches((Invoke-Scraper "$Address"), "LDPlayer_([\d.]+).exe").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        Remove-Feature "HyperV"
        $Address = "https://encdn.ldmnq.com/download/package/LDPlayer_$Version.exe"
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        $Current = $Script:MyInvocation.MyCommand.Path
        Invoke-Gsudo {
            . $Using:Current
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
        }
        Remove-Desktop "LDM*.lnk" ; Remove-Desktop "LDP*.lnk"
    }

}

Function Update-Powershell {

    $Starter = (Get-Item "$Env:ProgramFiles\PowerShell\*\pwsh.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }

    $Address = "https://api.github.com/repos/powershell/powershell/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        Invoke-Gsudo { Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet" *> $Null }
    }

    If ($PSVersionTable.PSVersion -Lt [Version] "7.0.0.0") { Invoke-Restart }

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
    $Current = $Script:MyInvocation.MyCommand.Path
    $Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName.ToUpper()

    # Output greeting
    Clear-Host ; $ProgressPreference = "SilentlyContinue"
    Write-Output "+---------------------------------------------------------------+"
    Write-Output "|                                                               |"
    Write-Output "|  > WINHOGEN                                                   |"
    Write-Output "|                                                               |"
    Write-Output "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                        |"
    Write-Output "|                                                               |"
    Write-Output "+---------------------------------------------------------------+"

    Invoke-Scraper "https://api.github.com/repos/gerardog/gsudo/releases/latest"
    Exit

    # Handle security
    $Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
    $Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
    Write-Host "$Loading" -FO DarkYellow -NoNewline
    Remove-Feature "Uac" ; Update-Element "Plan" "Ultimate"
    $Correct = (Update-Gsudo) -And ! (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
    If (-Not $Correct) { Write-Host "$Failure`n" -FO Red ; Exit } ; Update-Powershell

    Invoke-Scraper "https://api.github.com/repos/gerardog/gsudo/releases/latest"

    # Handle elements
    $Members = Export-Members -Variant "Gaming" -Machine "WINHOGEN"

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