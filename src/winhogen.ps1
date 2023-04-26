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

Function Deploy-Library {

    Param(
        [ValidateSet("Flaui", "Playwright")] [String] $Library
    )

    Switch ($Library) {
        "Flaui" {
            Import-Library "Interop.UIAutomationClient" | Out-Null
            Import-Library "FlaUI.Core" | Out-Null
            Import-Library "FlaUI.UIA3" | Out-Null
            Import-Library "System.Drawing.Common" | Out-Null
            Import-Library "System.Security.Permissions" | Out-Null
            [FlaUI.UIA3.UIA3Automation]::New()
        }
        "Playwright" {
            $Current = $Script:MyInvocation.MyCommand.Path
            If (Test-Path "$Current") { Invoke-Gsudo { . $Using:Current ; Deploy-Library Playwright | Out-Null } }
            Import-Library "System.Text.Json" | Out-Null
            Import-Library "Microsoft.Bcl.AsyncInterfaces" | Out-Null
            Import-Library "Microsoft.CodeAnalysis" | Out-Null
            Import-Library "Microsoft.Playwright" | Out-Null
            [Microsoft.Playwright.Program]::Main(@("install", "chromium")) | Out-Null
            [Microsoft.Playwright.Playwright]::CreateAsync().GetAwaiter().GetResult()
        }
    }

}

Function Enable-Feature {

    Param(
        [ValidateSet("Activation", "HyperV", "NightLight", "RemoteDesktop", "Sleeping", "Uac", "Wsl")] [String] $Feature
    )

    Switch ($Feature) {
        "Activation" {
            $Content = (Write-Output ((cscript /nologo "C:\Windows\System32\slmgr.vbs" /xpr) -Join ""))
            If (-Not $Content.Contains("permanently activated")) {
                Invoke-Gsudo { & ([ScriptBlock]::Create((Invoke-RestMethod "https://massgrave.dev/get"))) /HWID /S }
                # $Current = $Script:MyInvocation.MyCommand.Path
                # Invoke-Gsudo {
                #     . $Using:Current ; Start-Sleep 4
                #     $Fetched = Invoke-Fetcher "Webclient" "https://massgrave.dev/get.ps1"
                #     Start-Process "powershell" "-ep bypass -f `"$Fetched`"" -WindowStyle Hidden
                #     Add-Type -AssemblyName System.Windows.Forms
                #     Start-Sleep 8 ; [Windows.Forms.SendKeys]::SendWait("1")
                #     Start-Sleep 30 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                #     Start-Sleep 6 ; [Windows.Forms.SendKeys]::SendWait("1")
                # }
            }
        }
        "HyperV" {
            $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Hyper-V-All" -Online).State }
            If ($Content.Value -Ne "Enabled") {
                $Address = "https://cdn3.bluestacks.com/support_files/HD-EnableHyperV.exe"
                $Fetched = Invoke-Fetcher "Webclient" "$Address"
                Invoke-Gsudo { Start-Process "$Using:Fetched" ; Start-Sleep 20 ; Stop-Process -Name "HD-EnableHyperV" }
                Invoke-Restart
            }
        }
        "NightLight" {
            $Handler = Deploy-Library Flaui
            Start-Process "ms-settings:display"
            Try {
                Start-Sleep 4 ; $Desktop = $Handler.GetDesktop()
                Start-Sleep 2 ; $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByName("Settings"))
                $Window1.Focus() ; Start-Sleep 2
                $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByAutomationId("SystemSettings_Display_BlueLight_AutomaticOnScheduleWithTime_ButtonEntityItem"))
                $Element.Click()
                Start-Sleep 2
                $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByAutomationId("SystemSettings_Display_BlueLight_ManualToggleOn_Button"))
                If ($Null -Ne $Element) { $Element.Click() }
                $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
                $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::F4
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
            }
            Catch {
                Stop-Process -Name "SystemSettings" -EA SI
            }
            $Handler.Dispose() | Out-Null
        }
        "RemoteDesktop" {
            Invoke-Gsudo {
                $RegPath = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
                Set-ItemProperty -Path "$RegPath" -Name "fDenyTSConnections" -Value 0
                Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
            }
        }
        "Sleeping" {
            $Content = @()
            $Content += '[DllImport("kernel32.dll", CharSet = CharSet.Auto,SetLastError = true)]'
            $Content += 'public static extern void SetThreadExecutionState(uint esFlags);'
            $Handler = Add-Type -MemberDefinition "$($Content | Out-String)" -Name System -Namespace Win32 -PassThru
            $Handler::SetThreadExecutionState([uint32]"0x80000000") # ES_CONTINUOUS
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
            Enable-Feature "HyperV"
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

Function Expand-Version {

    Param (
        [String] $Payload
    )

    If ([String]::IsNullOrWhiteSpace($Payload)) { Return "0.0.0.0" }
    $Version = $(powershell -Command "(Get-Package `"$Payload`" -EA SI).Version")
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = (Get-AppxPackage "$Payload" -EA SI).Version }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = Try { (Get-Command "$Payload" -EA SI).Version } Catch { $Null } }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = Try { (Get-Item "$Payload" -EA SI).VersionInfo.FileVersion } Catch { $Null } }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = Try { Invoke-Expression "& `"$Payload`" --version" -EA SI } Catch { $Null } }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = "0.0.0.0" }
    # Return [Regex]::Matches($Version, "([\d.]+)").Groups[1].Value
    Return [Regex]::Match($Version, "[\d.]+").Value.Trim(".")

}

Function Export-Members {

    Param(
        [ValidateSet("Coding", "Gaming", "Laptop", "Stream", "Tester")] [String] $Variant
    )

    Switch ($Variant) {
        "Coding" {
            @(
                "Update-Windows"
                "Update-Nvidia 'Game'"
                "Update-AndroidStudio"
                "Update-Chromium"
                # "Update-DockerDesktop"
                "Update-Git 'main' '72373746+sharpordie@users.noreply.github.com' 'sharpordie'"
                "Update-Pycharm"
                "Update-VisualStudio2022"
                "Update-VisualStudioCode"
                # "Update-Antidote"
                # "Update-Bluestacks '7'"
                # "Update-DbeaverUltimate"
                "Update-Figma"
                "Update-Jdownloader"
                # "Update-JoalDesktop"
                "Update-Keepassxc"
                # "Update-Mambaforge"
                "Update-Mpv"
                "Update-Flutter"
                "Update-Maui"
                # "Update-Python"
                "Update-Qbittorrent"
                "Update-Scrcpy"
                "Update-Spotify"
                # "Update-VmwareWorkstation"
                "Update-YtDlg"
            )
        }
        "Gaming" {
            @(
                "Update-Windows"
                "Update-Bluestacks"
                "Update-Steam"
            )
        }
        "Laptop" {
            @(
                "Update-Appearance"
                "Update-Windows"
                "Update-AndroidStudio"
                "Update-Chromium"
                "Update-Git 'main' '72373746+sharpordie@users.noreply.github.com' 'sharpordie'"
                "Update-VisualStudio2022"
                "Update-VisualStudioCode"
                "Update-Figma"
                "Update-Flutter"
                "Update-Jdownloader"
                "Update-Keepassxc"
                "Update-Mambaforge"
                "Update-Maui"
                "Update-Mpv"
                "Update-Pycharm"
                "Update-Qbittorrent"
                "Update-Scrcpy"
                "Update-Ventura"
                "Update-YtDlg"
            )
        }
        "Stream" {
            @(
                "Update-Windows"
                "Update-Steam"
                "Update-Sunshine"
            )
        }
        "Tester" {
            @(
                "Update-Windows"
                # "Update-AndroidStudio"
                # "Update-Chromium"
                "Update-Git 'main' '72373746+sharpordie@users.noreply.github.com' 'sharpordie'"
                # "Update-Pycharm"
                # "Update-VisualStudio2022"
                # "Update-VisualStudioCode"
                # "Update-Antidote"
                # "Update-DbeaverUltimate"
                "Update-Figma"
                # "Update-Flutter"
                # "Update-Jdownloader"
                # "Update-JoalDesktop"
                # "Update-Keepassxc"
                # "Update-Mambaforge"
                # "Update-Maui"
                "Update-Mpv"
                # "Update-Python"
                # "Update-Qbittorrent"
                # "Update-Scrcpy"
                # "Update-Spotify"
                # "Update-Steam"
                # "Update-VmwareWorkstation"
                # "Update-YtDlg"
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
        If (-Not (Get-Package "$Library" -EA SI)) { Install-Package "$Library" -Scope "CurrentUser" -Source "https://www.nuget.org/api/v2" -Force -SkipDependencies | Out-Null }
        $Results = (Get-ChildItem -Filter "*.dll" -Recurse (Split-Path (Get-Package -Name "$Library").Source)).FullName
        $Content = $Results | Where-Object { $_ -Like "*standard2.0*" } | Select-Object -Last 1
        If ($Testing) { Try { Add-Type -Path "$Content" -EA SI | Out-Null } Catch { $_.Exception.LoaderExceptions } }
        Else { Try { Add-Type -Path "$Content" -EA SI | Out-Null } Catch {} }
    }

}

Function Invoke-Extract {

    Param (
        [String] $Archive,
        [String] $Deposit,
        [String] $Secrets
    )

    If (-Not (Test-Path "$Env:LocalAppData\Microsoft\WindowsApps\7z.exe")) { Update-Nanazip }
    If (-Not $Deposit) { $Deposit = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName }
    If (-Not (Test-Path "$Deposit")) { New-Item "$Deposit" -ItemType Directory -EA SI }
    & "$Env:LocalAppData\Microsoft\WindowsApps\7z.exe" x "$Archive" -o"$Deposit" -p"$Secrets" -y -bso0 -bsp0
    Return "$Deposit"

}

Function Invoke-Fetcher {

    Param(
        [ValidateSet("Browser", "Filecr", "Jetbra", "Webclient")] [String] $Fetcher,
        [String] $Payload,
        [String] $Fetched
    )

    Switch ($Fetcher) {
        "Browser" {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $WebPage.GoToAsync("about:blank").GetAwaiter().GetResult() | Out-Null
            $Waiting = $WebPage.WaitForDownloadAsync()
            $WebPage.GoToAsync("$Payload") | Out-Null
            $Attempt = $Waiting.GetAwaiter().GetResult()
            $Attempt.PathAsync().GetAwaiter().GetResult() | Out-Null
            $Suggest = $Attempt.SuggestedFilename
            $Fetched = Join-Path "$Env:Temp" "$Suggest"
            $Attempt.SaveAsAsync("$Fetched").GetAwaiter().GetResult() | Out-Null
            $WebPage.CloseAsync().GetAwaiter().GetResult() | Out-Null
            $Browser.CloseAsync().GetAwaiter().GetResult() | Out-Null
            Return "$Fetched"
        }
        "Filecr" {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $Waiting = $WebPage.WaitForDownloadAsync()
            $WebPage.SetViewportSizeAsync(1400, 400).GetAwaiter().GetResult() | Out-Null
            $WebPage.GoToAsync("$Payload").GetAwaiter().GetResult() | Out-Null
            # $WebPage.WaitForSelectorAsync("#sh_pdf_download-2 > form > a").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForSelectorAsync(".btn-primary_dark").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(2000).GetAwaiter().GetResult() | Out-Null
            $WebPage.EvaluateAsync("document.querySelector('.btn-primary_dark').click()", "").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForSelectorAsync("a.sh_download-btn.done").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(6000).GetAwaiter().GetResult() | Out-Null
            $WebPage.EvaluateAsync("document.querySelector('a.sh_download-btn.done').click()", "").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(2000).GetAwaiter().GetResult() | Out-Null
            $WebPage.Mouse.ClickAsync(10, 10, @{ "ClickCount" = 2 }).GetAwaiter().GetResult() | Out-Null
            $Attempt = $Waiting.GetAwaiter().GetResult()
            $Attempt.PathAsync().GetAwaiter().GetResult() | Out-Null
            $Suggest = $Attempt.SuggestedFilename
            $Fetched = "$Env:Temp\$Suggest"
            $Attempt.SaveAsAsync("$Fetched").GetAwaiter().GetResult() | Out-Null
            $WebPage.CloseAsync().GetAwaiter().GetResult() | Out-Null
            $Browser.CloseAsync().GetAwaiter().GetResult() | Out-Null
            Return "$Fetched"
        }
        "Jetbra" {
            # TODO: Handle host is unavailable exception
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $Waiting = $WebPage.WaitForDownloadAsync()
            $WebPage.GoToAsync("https://jetbra.in/s").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(10000).GetAwaiter().GetResult() | Out-Null
            $Address = $WebPage.EvaluateAsync("document.querySelectorAll('#checker\\.results a')[0].href", "").GetAwaiter().GetResult()
            $WebPage.GoToAsync("$Address").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(2000).GetAwaiter().GetResult() | Out-Null
            $WebPage.EvaluateAsync("document.querySelector('body > header > p > a:nth-child(1)').click()", "").GetAwaiter().GetResult() | Out-Null
            $Attempt = $Waiting.GetAwaiter().GetResult()
            $Attempt.PathAsync().GetAwaiter().GetResult() | Out-Null
            $Suggest = $Attempt.SuggestedFilename
            $Fetched = "$Env:Temp\$Suggest"
            $Attempt.SaveAsAsync("$Fetched").GetAwaiter().GetResult() | Out-Null
            $WebPage.CloseAsync().GetAwaiter().GetResult() | Out-Null
            $Browser.CloseAsync().GetAwaiter().GetResult() | Out-Null
            Return "$Fetched"
        }
        "Webclient" {
            If (-Not $Fetched) { $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Payload" -Leaf)" }
            (New-Object Net.WebClient).DownloadFile("$Payload", "$Fetched") ; Return "$Fetched"
        }
    }

}

Function Invoke-Restart {

    $Current = $Script:MyInvocation.MyCommand.Path
    $Program = "$Env:LocalAppData\Microsoft\WindowsApps\wt.exe"
    $Heading = (Get-Item "$Current").BaseName.ToUpper()
    $Command = "$Program --title $Heading pwsh -ep bypass -noexit -nologo -file $Current"
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    New-ItemProperty "$RegPath" "$Heading" -Value "$Command" | Out-Null
    Invoke-Gsudo { Get-LocalUser -Name "$Env:Username" | Set-LocalUser -Password ([SecureString]::New()) }
    Remove-Feature "Uac" # TODO: Remove maybe
    Start-Sleep 4 ; Restart-Computer -Force ; Start-Sleep 2

}

Function Invoke-Scraper {

    Param(
        [ValidateSet("Html", "Json", "BrowserHtml", "BrowserJson", "Jetbra")] [String] $Scraper,
        [String] $Payload
    )

    Switch ($Scraper) {
        "Html" {
            Return Invoke-WebRequest "$Payload"
        }
        "Json" {
            Return Invoke-WebRequest "$Payload" | ConvertFrom-Json
        }
        "BrowserHtml" {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $WebPage.GoToAsync("$Payload").GetAwaiter().GetResult() | Out-Null
            $Scraped = $WebPage.QuerySelectorAsync("body").GetAwaiter().GetResult()
            $Scraped = $Scraped.InnerHtmlAsync().GetAwaiter().GetResult()
            $WebPage.CloseAsync().GetAwaiter().GetResult() | Out-Null
            $Browser.CloseAsync().GetAwaiter().GetResult() | Out-Null
            Return $Scraped.ToString()
        }
        "BrowserJson" {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $WebPage.GoToAsync("$Payload").GetAwaiter().GetResult() | Out-Null
            $Scraped = $WebPage.QuerySelectorAsync("body > :first-child").GetAwaiter().GetResult()
            $Scraped = $Scraped.InnerHtmlAsync().GetAwaiter().GetResult()
            $WebPage.CloseAsync().GetAwaiter().GetResult()
            $Browser.CloseAsync().GetAwaiter().GetResult()
            Return $Scraped.ToString() | ConvertFrom-Json
        }
        "Jetbra" {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $WebPage.GoToAsync("https://jetbra.in/s").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(10000).GetAwaiter().GetResult() | Out-Null
            $Address = $WebPage.EvaluateAsync("document.querySelectorAll('#checker\\.results a')[0].href", "").GetAwaiter().GetResult()
            $WebPage.GoToAsync("$Address").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(2000).GetAwaiter().GetResult() | Out-Null
            $WebPage.Locator(":has-text('$Payload') ~ p").ClickAsync().GetAwaiter().GetResult() | Out-Null
            $WebPage.CloseAsync().GetAwaiter().GetResult() | Out-Null
            $Browser.CloseAsync().GetAwaiter().GetResult() | Out-Null
            Return "$(Get-Clipboard)".Trim()
        }
    }

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
        [ValidateSet("HyperV", "NightLight", "Sleeping", "Uac")] [String] $Feature
    )

    Switch ($Feature) {
        "HyperV" {
            $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Hyper-V-All" -Online).State }
            If ($Content.Value -Eq "Enabled") {
                $Address = "https://cdn3.bluestacks.com/support_files/HD-DisableHyperV_native_v2.exe"
                $Fetched = Invoke-Fetcher "Webclient" "$Address"
                Invoke-Gsudo { Start-Process "$Using:Fetched" ; Start-Sleep 20 ; Stop-Process -Name "HD-DisableHyperV" }
                If (Assert-Pending -Eq $True) { Invoke-Restart }
            }
        }
        "NightLight" {
            $Handler = Deploy-Library Flaui
            Start-Process "ms-settings:display"
            Try {
                Start-Sleep 2 ; $Desktop = $Handler.GetDesktop()
                Start-Sleep 2 ; $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByName("Settings"))
                $Window1.Focus()
                Start-Sleep 2
                $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByAutomationId("SystemSettings_Display_BlueLight_AutomaticOnScheduleWithTime_ButtonEntityItem"))
                $Element.Click()
                Start-Sleep 2
                $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByAutomationId("SystemSettings_Display_BlueLight_ManualToggleOff_Button"))
                If ($Null -Ne $Element) { $Element.Click() }
                $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
                $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::F4
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
            }
            Catch {
                Stop-Process -Name "SystemSettings" -EA SI
            }
            $Handler.Dispose() | Out-Null
        }
        "Sleeping" {
            $Content = @()
            $Content += '[DllImport("kernel32.dll", CharSet = CharSet.Auto,SetLastError = true)]'
            $Content += 'public static extern void SetThreadExecutionState(uint esFlags);'
            $Handler = Add-Type -MemberDefinition "$($Content | Out-String)" -Name System -Namespace Win32 -PassThru
            $Handler::SetThreadExecutionState([uint32]"0x80000000" -Bor [uint32]"0x00000002") # ES_DISPLAY_REQUIRED
        }
        "Uac" {
            $Content = @(
                '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
                'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 0'
                'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 0'
            ) -Join "`n"
            $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
            [IO.File]::WriteAllText("$Created", $Content)
            $Present = $(Expand-Version "*gsudo*") -Ne "0.0.0.0"
            If (-Not $Present) { Try { Start-Process "powershell" "-ep bypass -file `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait } Catch { } }
            Else { Invoke-Gsudo { Try { Start-Process "powershell" "-ep bypass -file `"$Using:Created`"" -WindowStyle Hidden -Wait } Catch { } } }
            Remove-Item "$Created" -Force
        }
    }

}

Function Update-Element {

    Param(
        [ValidateSet("Computer", "DesktopBackground", "LockscreenBackground", "Plan", "Timezone", "Volume")] [String] $Element,
        [String] $Payload
    )

    Switch ($Element) {
        "Computer" {
            If ([String]::IsNullOrWhiteSpace("$Payload")) { Return }
            If ((Hostname) -Ne "$Payload") {
                Invoke-Gsudo { Rename-Computer -NewName "$Using:Payload" -EA SI *> $Null }
            }
        }
        "DesktopBackground" {
            If (-Not (Test-Path -Path "$Payload")) { return }
            $Content = @()
            $Content += 'using System.Runtime.InteropServices;'
            $Content += 'public static class BackgroundChanger'
            $Content += '{'
            $Content += '   public const int SetDesktopWallpaper = 20;'
            $Content += '   public const int UpdateIniFile = 0x01;'
            $Content += '   public const int SendWinIniChange = 0x02;'
            $Content += '   [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]'
            $Content += '   private static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);'
            $Content += '   public static void SetBackground(string path)'
            $Content += '   {'
            $Content += '       SystemParametersInfo(SetDesktopWallpaper, 0, path, UpdateIniFile | SendWinIniChange);'
            $Content += '   }'
            $Content += '}'
            $Content = $Content | Out-String
            Add-Type -TypeDefinition "$Content"
            [BackgroundChanger]::SetBackground($Payload)
        }
        "LockscreenBackground" {
            $KeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            Set-ItemProperty "$KeyPath" "SubscribedContent-338387Enabled" -Value "0"
            $KeyPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
            Invoke-Gsudo {
                New-Item "$Using:KeyPath" -Force -EA SI | Out-Null
                New-ItemProperty "$Using:KeyPath" "LockScreenImageStatus" -Value "1" -Force | Out-Null
                New-ItemProperty "$Using:KeyPath" "LockScreenImagePath" -Value "$Using:Payload" -Force | Out-Null
                New-ItemProperty "$Using:KeyPath" "LockScreenImageUrl" -Value "$Using:Payload" -Force | Out-Null
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
        "Volume" {
            $Wscript = New-Object -ComObject WScript.Shell
            1..50 | ForEach-Object { $Wscript.SendKeys([Char]174) }
            If ($Payload -Ne 0) { 1..$($Payload / 2) | ForEach-Object { $Wscript.SendKeys([Char]175) } }
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
    $Pattern = "^$([Regex]::Escape($Payload))\\?"
    If ($Section -Ne "Process" ) {
        $OldPath = [Environment]::GetEnvironmentVariable("PATH", "$Section")
        $OldPath = $OldPath -Split ";" | Where-Object { $_ -NotMatch "$Pattern" }
        $NewPath = ($OldPath + $Payload) -Join ";"
        Invoke-Gsudo {
            [Environment]::SetEnvironmentVariable("PATH", "$Using:NewPath", "$Using:Section")
        }
    }
    $OldPath = $Env:Path -Split ";" | Where-Object { $_ -NotMatch "$Pattern" }
    $NewPath = ($OldPath + $Payload) -Join ";" ; $Env:Path = $NewPath -Join ";"

}

Function Update-SysPathOld {
    
    Param (
        [String] $Deposit,
        [ValidateSet("Machine", "Process", "User")] [String] $Section,
        [Switch] $Prepend
    )

    $Changed = [Environment]::GetEnvironmentVariable("PATH", "$Section")
    $Changed = If ($Changed.Contains(";;")) { $Changed.Replace(";;", ";") } Else { $Changed }
    $Changed = If ($Changed.EndsWith(";")) { $Changed } Else { "${Changed};" }
    $Changed = If ($Changed.Contains($Deposit)) { $Changed } Else { If ($Prepend) { "${Deposit};${Changed}" } Else { "${Changed}${Deposit};" } }
    If ($Section -Eq "Machine") { Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PATH", "$Using:Changed", "$Using:Section") } }
    Else { [Environment]::SetEnvironmentVariable("PATH", "$Changed", "$Section") }
    [Environment]::SetEnvironmentVariable("PATH", "$Changed", "Process")

}

#EndRegion

Function Update-AndroidCmdline {

    Update-MicrosoftOpenjdk
    $SdkHome = "$Env:LocalAppData\Android\Sdk"
    $Starter = "$SdkHome\cmdline-tools\latest\bin\sdkmanager.bat"
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-90)

    If (-Not $Updated) {
        $Address = "https://developer.android.com/studio#command-tools"
        $Release = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "commandlinetools-win-(\d+)").Groups[1].Value
        $Address = "https://dl.google.com/android/repository/commandlinetools-win-${Release}_latest.zip"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $Extract = Invoke-Extract "$Fetched"
        New-Item "$SdkHome" -ItemType Directory -EA SI
        $Manager = "$Extract\cmdline-tools\bin\sdkmanager.bat"
        Write-Output $("y`n" * 10) | & "$Manager" --sdk_root="$SdkHome" "cmdline-tools;latest"
    }

    Invoke-Gsudo { [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$Using:SdkHome", "Machine") }
    [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$SdkHome", "Process")
    Update-SysPath "$SdkHome\cmdline-tools\latest\bin" "Machine"
    Update-SysPath "$SdkHome\emulator" "Machine"
    Update-SysPath "$SdkHome\platform-tools" "Machine"

}

Function Update-AndroidStudio {

    Update-AndroidCmdline
    $Starter = "$Env:ProgramFiles\Android\Android Studio\bin\studio64.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://raw.githubusercontent.com/scoopinstaller/extras/master/bucket/android-studio.json"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").version , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 6)

    If (-Not $Updated) {
        $Address = "https://redirector.gvt1.com/edgedl/android/studio/install/$Version/android-studio-$Version-windows.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
    }

    If (-Not $Present) {
        Write-Output $("y`n" * 10) | sdkmanager "build-tools;33.0.2"
        Write-Output $("y`n" * 10) | sdkmanager "emulator"
        Write-Output $("y`n" * 10) | sdkmanager "extras;google;Android_Emulator_Hypervisor_Driver"
        # Write-Output $("y`n" * 10) | sdkmanager "extras;intel;Hardware_Accelerated_Execution_Manager"
        Write-Output $("y`n" * 10) | sdkmanager "patcher;v4"
        Write-Output $("y`n" * 10) | sdkmanager "platform-tools"
        Write-Output $("y`n" * 10) | sdkmanager "platforms;android-33"
        Write-Output $("y`n" * 10) | sdkmanager "platforms;android-33-ext5"
        Write-Output $("y`n" * 10) | sdkmanager "sources;android-33"
        Write-Output $("y`n" * 10) | sdkmanager "system-images;android-33;google_apis;x86_64"
        Write-Output $("y`n" * 10) | sdkmanager --licenses
        Write-Output $("y`n" * 10) | sdkmanager --update
        avdmanager create avd -n "Pixel_3_API_33" -d "pixel_3" -k "system-images;android-33;google_apis;x86_64"
    }

    If (-Not $Present) {
        Add-Type -AssemblyName System.Windows.Forms ; Start-Process "$Starter"
        Start-Sleep 10 ; [Windows.Forms.SendKeys]::SendWait("{TAB}") ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 20 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 2) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 2) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 3) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 6 ; [Windows.Forms.SendKeys]::SendWait("%{F4}")
    }

}

Function Update-Antidote {

    Param(
        [Switch] $Autorun
    )

    $Starter = (Get-Item "$Env:ProgramFiles\Drui*\Anti*\Appl*\Bin6*\Antidote.exe" -EA SI).FullName
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://filecr.com/windows/antidote"
    # $Results = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "<title>Antidote ([\d]+) v([\d.]+) .*</title>")
    # $Version = "$($Results.Groups[1].Value).$($Results.Groups[2].Value)"
    # $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Present) {
        $Fetched = Invoke-Fetcher "Filecr" "$Address"
        $Deposit = Invoke-Extract -Archive "$Fetched" -Secrets "123"
        $RootDir = (Get-Item "$Deposit\Ant*\Ant*").FullName
        $Archive = (Get-Item "$RootDir\Anti*.exe").FullName
        $Extract = Invoke-Extract -Archive "$Archive"
        $Modules = (Get-Item "$Extract\*\msi\druide").FullName
        $Adjunct = "TRANSFORMS=`"$Modules\Antidote11-Interface-en.mst`""
        Invoke-Gsudo { Start-Process "msiexec.exe" "/i `"$Using:Modules\Antidote11.msi`" $Using:Adjunct /qn" -Wait }
        $Adjunct = "TRANSFORMS=`"$Modules\Antidote11-Module-francais-Interface-en.mst`""
        Invoke-Gsudo { Start-Process "msiexec.exe" "/i `"$Using:Modules\Antidote11-Module-francais.msi`" $Using:Adjunct /qn" -Wait }
        $Adjunct = "TRANSFORMS=`"$Modules\Antidote11-English-module-Interface-en.mst`""
        Invoke-Gsudo { Start-Process "msiexec.exe" "/i `"$Using:Modules\Antidote11-English-module.msi`" $Using:Adjunct /qn" -Wait }
        $Adjunct = "TRANSFORMS=`"$Modules\Antidote-Connectix11-Interface-en.mst`""
        Invoke-Gsudo { Start-Process "msiexec.exe" "/i `"$Using:Modules\Antidote-Connectix11.msi`" $Using:Adjunct /qn" -Wait }
        Foreach ($MspFile In $(Get-Item "$RootDir\Updates\*.msp")) { Invoke-Gsudo { Start-Process "msiexec.exe" "/p `"$($Using:MspFile.FullName)`" /qn" -Wait } }
        $Altered = "$RootDir\Crack\Antidote.exe"
        $Current = (Get-Item "$Env:ProgramFiles\Drui*\Anti*\Appl*\Bin6*\Antidote.exe" -EA SI).FullName
        Invoke-Gsudo { [IO.File]::Copy("$Using:Altered", "$Using:Current", $True) }
    }

    If (-Not $Present) {
        Stop-Process -Name "AgentConnectix" -EA SI
        Stop-Process -Name "Antidote" -EA SI
        Stop-Process -Name "Connectix" -EA SI
        $Handler = Deploy-Library Flaui
        $Starter = (Get-Item "$Env:ProgramFiles\Drui*\Anti*\Appl*\Bin6*\Antidote.exe" -EA SI).FullName
        $Started = [FlaUI.Core.Application]::Launch("$Starter")
        $Window1 = $Started.GetMainWindow($Handler)
        $Window1.Focus() ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER) ; Start-Sleep 4
        $Window2 = $Started.GetMainWindow($Handler)
        $Window2.Focus() ; Start-Sleep 1
        $Button2 = $Window2.FindFirstDescendant($Handler.ConditionFactory.ByName("Manual activation…"))
        $Button2.Click() ; Start-Sleep 6
        $Window3 = $Started.GetMainWindow($Handler)
        $Window3.Focus() ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type("John") ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB) ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type("Doe") ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB) ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB) ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type("123-456-789-012-A11") ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE) ; Start-Sleep 4
        $Window4 = $Started.GetMainWindow($Handler)
        $Window4.Focus() ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type("BV-12345-67890-12345-67890-12345") ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB) ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB) ; Start-Sleep 1
        [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE) ; Start-Sleep 4
        Stop-Process -Name "AgentConnectix" -EA SI
        Stop-Process -Name "Antidote" -EA SI
        Stop-Process -Name "Connectix" -EA SI
        $Started.Dispose() | Out-Null ; $Handler.Dispose() | Out-Null
    }

    If (-Not $Autorun) {
        Invoke-Gsudo { Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "AgentConnectix64" -EA SI }
    }

}

Function Update-Appearance {

    # Change pinned elements
    $ShellAp = New-Object -ComObject Shell.Application
    $ShellAp.Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}").Items() | ForEach-Object { $_.InvokeVerb("unpinfromhome") }
    $ShellAp.Namespace("$Env:Temp").Self.InvokeVerb("pintohome")
    $ShellAp.Namespace("$Env:UserProfile").Self.InvokeVerb("pintohome")
    $ShellAp.Namespace("$Env:UserProfile\Downloads").Self.InvokeVerb("pintohome")
    New-Item -Path "$Env:UserProfile\Projects" -ItemType Directory -EA SI ; $ShellAp.Namespace("$Env:UserProfile\Projects").Self.InvokeVerb("pintohome")

    # Enable file extensions
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

    # Enable hidden files
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1

    # Remove recent files
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0

    # Remove taskbar items
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Type DWord -Value 0

    # Remove pinned applications
    Try {
        ((New-Object -Com Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items() | `
            Where-Object { $_.Name -Eq "Microsoft Edge" }).Verbs() | `
            Where-Object { $_.Name.replace('&', '') -Match "Unpin from taskbar" } | `
            ForEach-Object { $_.DoIt() }
    }
    Catch {}
    Try {
        ((New-Object -Com Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items() | `
            Where-Object { $_.Name -Eq "Microsoft Store" }).Verbs() | `
            Where-Object { $_.Name.replace('&', '') -Match "Unpin from taskbar" } | `
            ForEach-Object { $_.DoIt() }
    }
    Catch {}

    # Update desktop background
    $Deposit = "$Env:UserProfile\Pictures\Backgrounds"
    $Picture = "$Deposit\android-higher-darker.png"
    $Address = "https://raw.githubusercontent.com/sharpordie/andpaper/main/src/android-higher-darker.png"
    New-Item -Path "$Deposit" -ItemType Directory -EA SI
    If (-Not (Test-Path -Path "$Picture")) { Invoke-Fetcher "Webclient" "$Address" "$Picture" }
    Update-Element "DesktopBackground" "$Picture"

    # Update lockscreen background
    $Deposit = "$Env:UserProfile\Pictures\Backgrounds"
    $Picture = "$Deposit\android-bottom-darker.png"
    $Address = "https://raw.githubusercontent.com/sharpordie/andpaper/main/src/android-bottom-darker.png"
    New-Item -Path "$Deposit" -ItemType Directory -EA SI
    If (-Not (Test-Path -Path "$Picture")) { Invoke-Fetcher "Webclient" "$Address" "$Picture" }
    Update-Element "LockscreenBackground" "$Picture"

    # Reboot explorer
    Stop-Process -Name "explorer"

}

Function Update-Bluestacks {

    Param(
        [ValidateSet("7", "9", "11")] [String] $Android = "11"
    )

    $Starter = (Get-Item "$Env:ProgramFiles\BlueStacks*\HD-Player.exe" -EA SI).FullName
    $Current = Expand-Version "$Starter"
    $Address = "https://support.bluestacks.com/hc/en-us/articles/4402611273485-BlueStacks-5-offline-installer"
    $Results = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "windows/nxt/([\d.]+)/(?<sha>[0-9a-f]+)/")
    $Version = $Results.Groups[1].Value
    $Hashing = $Results.Groups[2].Value
    $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 6)

    If (-Not $Updated) {
        $Address = "https://cdn3.bluestacks.com/downloads/windows/nxt/$Version/$Hashing/FullInstaller/x64/BlueStacksFullInstaller_${Version}_amd64_native.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $ArgList = "-s --defaultImageName Rvc64 --imageToLaunch Rvc64"
        If ($Android -Eq "9") { $ArgList = "-s --defaultImageName Pie64 --imageToLaunch Pie64" }
        If ($Android -Eq "7") { $ArgList = "-s --defaultImageName Nougat64 --imageToLaunch Nougat64" }
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Start-Sleep 4 ; Remove-Desktop "BlueStacks*.lnk"
    }

    $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Hyper-V-All" -Online).State }
    If ($Content.Value -Eq "Enabled" -And $Android -Eq "7") {
        $Maximum = $Version.SubString(0, 1)
        $Altered = (Get-Item "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs\BlueStacks $Maximum.lnk" -EA SI).FullName
        If ($Null -Ne $Altered) {
            $Content = [IO.File]::ReadAllBytes("$Altered")
            $Content[0x15] = $Content[0x15] -Bor 0x20
            Invoke-Gsudo { [IO.File]::WriteAllBytes("$Using:Altered", $Using:Content) | Out-Null }
        }
    }

}

Function Update-Chromium {

    Param (
        [String] $Deposit = "$Env:UserProfile\Downloads\DDL",
        [String] $Startup = "about:blank"
    )

    $Starter = "$Env:ProgramFiles\Chromium\Application\chrome.exe"
    $Current = Expand-Version "*chromium*"
    $Present = $Current -Ne "0.0.0.0"
    $Address = "https://api.github.com/repos/macchrome/winchrome/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name, "[\d.]+").Value
    $Updated = $Present -And [Version] $Current.Replace(".0", "") -Ge [Version] "$Version"
    
    If (-Not $Updated) {
        $Results = (Invoke-Scraper "Json" "$Address").assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*installer.exe" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "--system-level --do-not-launch-chrome" -Wait }
    }

    If (-Not $Present) {
        Add-Type -AssemblyName System.Windows.Forms
        New-Item "$Deposit" -ItemType Directory -EA SI
        Start-Process "$Starter" "--lang=en --start-maximized"
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://settings/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("before downloading")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 3)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("$Deposit")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("custom-ntp")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 5)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("^a")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("$Startup")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 2)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://settings/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("search engines")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 3)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("duckduckgo")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("extension-mime-request-handling")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 2)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("hide-sidepanel-button")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("remove-tabsearch-button")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("win-10-tab-search-caption-button")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 2)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("show-avatar-button")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 3)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("^+b")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

        $Address = "https://api.github.com/repos/NeverDecaf/chromium-web-store/releases/latest"
        $Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*.crx" } ).browser_download_url
        Update-ChromiumExtension "$Address"

        Update-ChromiumExtension "omoinegiohhgbikclijaniebjpkeopip" # clickbait-remover-for-you
        Update-ChromiumExtension "bcjindcccaagfpapjjmafapmmgkkhgoa" # json-formatter
        Update-ChromiumExtension "ibplnjkanclpjokhdolnendpplpjiace" # simple-translate
        Update-ChromiumExtension "mnjggcdmjocbbbhaepdhchncahnbgone" # sponsorblock-for-youtube
        Update-ChromiumExtension "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock-origin
    }

    Remove-Desktop "Chromium*.lnk"
    Update-ChromiumExtension "https://github.com/iamadamdev/bypass-paywalls-chrome/archive/master.zip"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Address = "https://raw.githubusercontent.com/DanysysTeam/PS-SFTA/master/SFTA.ps1"
    Invoke-Expression ((New-Object Net.WebClient).DownloadString("$Address"))
    $FtaList = @(".htm", ".html", ".pdf", ".shtml", ".svg", ".xht", ".xhtml")
    Foreach ($Element In $FtaList) { Set-FTA "ChromiumHTM" "$Element" }
    $PtaList = @("ftp", "http", "https")
    Foreach ($Element In $PtaList) { Set-PTA "ChromiumHTM" "$Element" }

}

Function Update-ChromiumExtension {

    Param (
        [String] $Payload
    )

    $Package = $Null
    $Starter = "$Env:ProgramFiles\Chromium\Application\chrome.exe"
    If (Test-path "$Starter") {
        If ($Payload -Like "http*") {
            $Address = "$Payload"
            $Package = Invoke-Fetcher "Webclient" "$Address"
        }
        Else {
            $Version = Try { (Get-Item "$Starter" -EA SI).VersionInfo.FileVersion.ToString() } Catch { "0.0.0.0" }
            $Address = "https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3"
            $Address = "${Address}&prodversion=${Version}&x=id%3D${Payload}%26installsource%3Dondemand%26uc"
            $Package = Invoke-Fetcher "Webclient" "$Address" "$Env:Temp\$Payload.crx"
        }
        If ($Null -Ne $Package -And (Test-Path "$Package")) {
            Add-Type -AssemblyName System.Windows.Forms
            If ($Package -Like "*.zip") {
                $Deposit = "$Env:ProgramFiles\Chromium\Unpacked\$($Payload.Split("/")[4])"
                $Present = Test-Path "$Deposit"
                Invoke-Gsudo { New-Item "$Using:Deposit" -ItemType Directory -EA SI }
                # Update-Nanazip ; $Extract = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName
                # Start-Process "7z.exe" "x `"$Package`" -o`"$Extract`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
                $Extract = Invoke-Extract "$Package"
                $Topmost = (Get-ChildItem -Path "$Extract" -Directory | Select-Object -First 1).FullName
                Invoke-Gsudo { Copy-Item -Path "$Using:Topmost\*" -Destination "$Using:Deposit" -Recurse -Force }
                If ($Present) { Return }
                Start-Process "$Starter" "--lang=en --start-maximized"
                Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://extensions/")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("$Deposit")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
                Start-Process "$Starter" "--lang=en --start-maximized"
                Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://extensions/")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
            }
            Else {
                Start-Process "$Starter" "`"$Package`" --start-maximized --lang=en"
                Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
                Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
            }
        }
    }

}

Function Update-DbeaverUltimate {

    Update-MicrosoftOpenjdk
    $BaseDir = "$Env:ProgramFiles\DBeaverUltimate"
    $Starter = (Get-Item "$BaseDir\Uninstall.exe" -EA SI).FullName
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://filecr.com/windows/dbeaver-ultimate"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "<title>DBeaver ([\d.]+) .*</title>").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Fetched = Invoke-Fetcher "Filecr" "$Address"
        $Deposit = Invoke-Extract -Archive "$Fetched" -Secrets "123"
        $RootDir = (Get-Item "$Deposit\D*").FullName
        $Program = (Get-Item "$RootDir\dbeaver*.exe").FullName
        Invoke-Gsudo { Start-Process "$Using:Program" "/S /allusers" -Wait }
        If (-Not $Present) {
            $RarFile = (Get-Item "$RootDir\*.rar").FullName
            $Extract = Invoke-Extract -Archive "$RarFile"
            $RarFile = (Get-Item "$Extract\*.rar").FullName
            $Extract = Invoke-Extract -Archive "$RarFile"
            $JarFile = (Get-Item "$Extract\*.jar").FullName
            $Current = $Script:MyInvocation.MyCommand.Path
            Invoke-Gsudo {
                . $Using:Current ; Start-Sleep 4
                Update-Element "Volume" 0
                $Handler = Deploy-Library Flaui
                Start-Process "java" "-jar `"$Using:JarFile`"" 
                Start-Sleep 8 ; $Desktop = $Handler.GetDesktop()
                $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByClassName("SunAwtFrame"))
                $Window1.Focus()
                $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::CONTROL
                $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::KEY_A
                Start-Sleep 4 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type("$Env:Username")
                [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type(" ")
                [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type(" ")
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
                [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                $Payload = (Get-Item "$Using:BaseDir\plugins\com.dbeaver.lm.core_*.jar").FullName
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type("$Payload")
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                $Payload = (Get-Item "$Using:BaseDir\plugins\com.dbeaver.app.ultimate_*.jar").FullName
                $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::CONTROL
                $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::KEY_A
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type("$Payload")
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER)
                Start-Sleep 2 ; Stop-Process -Name "java" -EA SI ; Start-Sleep 2
                Update-Element "Volume" 40
                Try {
                    Start-Process "$Using:BaseDir\dbeaver.exe" ; Start-Sleep 20
                    $Desktop = $Handler.GetDesktop()
                    $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByName("Windows Security Alert"))
                    $Button1 = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Allow access"))
                    $Button1.Click()
                }
                Catch {}
                Start-Sleep 4 ; Stop-Process -Name "dbeaver" -EA SI
                Start-Sleep 2 ; Start-Process "$Using:BaseDir\dbeaver.exe" ; Start-Sleep 20
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER)
                $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::CONTROL
                $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::KEY_V
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::SHIFT
                $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER)
                Stop-Process -Name "dbeaver" -EA SI
                $Handler.Dispose() | Out-Null
            }
        }
    }

}

Function Update-DockerDesktop {

    $Starter = "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://community.chocolatey.org/packages/docker-desktop"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "Docker Desktop ([\d.]+)</title>").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        Update-Wsl
        $Address = "https://desktop.docker.com/win/stable/Docker Desktop Installer.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "install --quiet --accept-license" -Wait }
        Remove-Desktop "Docker*.lnk"
        If (-Not $Present) { Invoke-Restart }
    }

    $Configs = "$Env:AppData\Docker\settings.json"
    If (Test-Path "$Configs") {
        $Content = Get-Content "$Configs" | ConvertFrom-Json
        $Content.analyticsEnabled = $False
        $Content.autoStart = $True
        $Content.disableTips = $True
        $Content.disableUpdate = $True
        $Content.displayedTutorial = $True
        $Content.licenseTermsVersion = 2
        $Content.openUIOnStartupDisabled = $True
        $Content | ConvertTo-Json | Set-Content "$Configs"
    }

}

Function Update-Dotnet {

    Param (
        [String] $Deposit = "$Env:UserProfile\Projects\_modules"
    )

    $Current = Expand-Version "dotnet"
    $Address = "https://raw.githubusercontent.com/scoopinstaller/main/master/bucket/dotnet-sdk.json"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").version, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://dotnetcli.blob.core.windows.net/dotnet/Sdk/$Version/dotnet-sdk-$Version-win-x64.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/install /quiet /norestart" -Wait }
    }

    Update-SysPath "$Env:ProgramFiles\dotnet\" "Machine"
    New-Item -Path "$Deposit" -ItemType Directory -EA SI
    dotnet nuget add source "https://api.nuget.org/v3/index.json" --name "nuget" | Out-Null
    dotnet nuget add source "$Deposit" --name "local" | Out-Null
    Invoke-Gsudo { [Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "1", "Machine") }
    Invoke-Gsudo { [Environment]::SetEnvironmentVariable("DOTNET_NOLOGO", "1", "Machine") }

}

Function Update-Figma {

    $Starter = "$Env:LocalAppData\Figma\Figma.exe"
    $Current = Expand-Version "$Starter"
    $Present = $Current -Ne "0.0.0.0"
    $Address = "https://desktop.figma.com/win/RELEASE.json"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").version, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://desktop.figma.com/win/FigmaSetup.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $ArgList = "/s /S /q /Q /quiet /silent /SILENT /VERYSILENT"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
    }

    If (-Not $Present) {
        Start-Sleep 8 ; Start-Process "$Starter" ; Start-Sleep 8
        Stop-Process -Name "Figma" -EA SI ; Stop-Process -Name "figma_agent" -EA SI ; Start-Sleep 4
        $Configs = Get-Content "$Env:AppData\Figma\settings.json" | ConvertFrom-Json
        Try { $Configs.showFigmaInMenuBar = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "showFigmaInMenuBar" -Value $False }
        $Configs | ConvertTo-Json | Set-Content "$Env:AppData\Figma\settings.json"
    }

}

Function Update-Flutter {

    Update-Git
    $Deposit = "$Env:LocalAppData\Android\Flutter"
    git clone "https://github.com/flutter/flutter.git" -b stable "$Deposit"

    Update-SysPath "$Deposit\bin" "Machine"
    flutter channel stable ; flutter precache ; flutter upgrade
    Write-Output $("y`n" * 10) | flutter doctor --android-licenses
    dart --disable-analytics ; flutter config --no-analytics

    $Browser = "$Env:ProgramFiles\Chromium\Application\chrome.exe"
    If (Test-Path "$Browser") {
        Invoke-Gsudo { [Environment]::SetEnvironmentVariable("CHROME_EXECUTABLE", "$Using:Browser", "Machine") }
        [Environment]::SetEnvironmentVariable("CHROME_EXECUTABLE", "$Browser", "Process")
    }

    $Product = "$Env:ProgramFiles\Android\Android Studio"
    Update-JetbrainsPlugin "$Product" "6351"  # dart
    Update-JetbrainsPlugin "$Product" "9212"  # flutter
    Update-JetbrainsPlugin "$Product" "13666" # flutter-intl
    Update-JetbrainsPlugin "$Product" "14641" # flutter-riverpod-snippets

    Update-VisualStudioCodeExtension "Dart-Code.flutter"
    Update-VisualStudioCodeExtension "alexisvt.flutter-snippets"
    Update-VisualStudioCodeExtension "pflannery.vscode-versionlens"
    Update-VisualStudioCodeExtension "robert-brunhage.flutter-riverpod-snippets"
    Update-VisualStudioCodeExtension "usernamehw.errorlens"

    $Program = "$Env:ProgramFiles\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe"
    If (Test-Path "$Program") { Update-VisualStudio2022Workload "Microsoft.VisualStudio.Workload.NativeDesktop" }

}

Function Update-Git {

    Param (
        [String] $Default = "main",
        [String] $GitMail,
        [String] $GitUser
    )

    $Starter = "$Env:ProgramFiles\Git\git-bash.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://api.github.com/repos/git-for-windows/git/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name.Replace("windows.", "") , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*64-bit.exe" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $ArgList = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART, /NOCANCEL, /SP- /COMPONENTS=`"`""
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
    }

    Update-SysPath "$Env:ProgramFiles\Git\cmd" "Process"
    If (-Not [String]::IsNullOrWhiteSpace($GitMail)) { git config --global user.email "$GitMail" }
    If (-Not [String]::IsNullOrWhiteSpace($GitUser)) { git config --global user.name "$GitUser" }
    git config --global http.postBuffer 1048576000
    git config --global init.defaultBranch "$Default"
    
}

Function Update-Gsudo {

    $Current = Expand-Version "*gsudo*"
    $Present = $Current -Ne "0.0.0.0"
    $Address = "https://api.github.com/repos/gerardog/gsudo/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    Try {
        If (-Not $Updated) {
            $Results = (Invoke-Scraper "Json" "$Address").assets
            $Address = $Results.Where( { $_.browser_download_url -Like "*x64*msi" } ).browser_download_url
            $Fetched = Invoke-Fetcher "Webclient" "$Address"
            If (-Not $Present) { Start-Process "msiexec" "/i `"$Fetched`" /qn" -Verb RunAs -Wait }
            Else { Invoke-Gsudo { msiexec /i "$Using:Fetched" /qn } }
            Start-Sleep 4
        }
        Update-SysPath "$Env:ProgramFiles\gsudo\Current" "Process"
        Return $True
    }
    Catch { 
        Return $False
    }

}

Function Update-Jdownloader {

    Param (
        [String] $Deposit = "$Env:UserProfile\Downloads\JD2"
    )

    $Starter = "$Env:ProgramFiles\JDownloader\JDownloader2.exe"
    $Present = Test-Path "$Starter"

    If (-Not $Present) {
        $Address = "http://installer.jdownloader.org/clean/JD2SilentSetup_x64.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "-q" -Wait }
        Remove-Desktop "JDownloader*.lnk"
    }

    If (-Not $Present) {
        New-Item "$Deposit" -ItemType Directory -EA SI
        $AppData = "$Env:ProgramFiles\JDownloader\cfg"
        $Config1 = "$AppData\org.jdownloader.settings.GeneralSettings.json"
        $Config2 = "$AppData\org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
        $Config3 = "$AppData\org.jdownloader.extensions.extraction.ExtractionExtension.json"
        Start-Process "$Starter" ; While (-Not (Test-Path "$Config1")) { Start-Sleep 2 }
        Stop-Process -Name "JDownloader2" -EA SI ; Start-Sleep 2
        $Configs = Get-Content "$Config1" | ConvertFrom-Json
        Try { $Configs.defaultdownloadfolder = "$Deposit" } Catch { $Configs | Add-Member -Type NoteProperty -Name "defaultdownloadfolder" -Value "$Deposit" }
        Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config1" }
        $Configs = Get-Content "$Config2" | ConvertFrom-Json
        Try { $Configs.bannerenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "bannerenabled" -Value $False }
        Try { $Configs.clipboardmonitored = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "clipboardmonitored" -Value $False }
        Try { $Configs.donatebuttonlatestautochange = 4102444800000 } Catch { $Configs | Add-Member -Type NoteProperty -Name "donatebuttonlatestautochange" -Value 4102444800000 }
        Try { $Configs.donatebuttonstate = "AUTO_HIDDEN" } Catch { $Configs | Add-Member -Type NoteProperty -Name "donatebuttonstate" -Value "AUTO_HIDDEN" }
        Try { $Configs.myjdownloaderviewvisible = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "myjdownloaderviewvisible" -Value $False }
        Try { $Configs.premiumalertetacolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalertetacolumnenabled" -Value $False }
        Try { $Configs.premiumalertspeedcolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalertspeedcolumnenabled" -Value $False }
        Try { $Configs.premiumalerttaskcolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalerttaskcolumnenabled" -Value $False }
        Try { $Configs.specialdealoboomdialogvisibleonstartup = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "specialdealoboomdialogvisibleonstartup" -Value $False }
        Try { $Configs.specialdealsenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "specialdealsenabled" -Value $False }
        Try { $Configs.speedmetervisible = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "speedmetervisible" -Value $False }
        Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config2" }
        $Configs = Get-Content "$Config3" | ConvertFrom-Json
        Try { $Configs.enabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "enabled" -Value $False }
        Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config3" }
        Update-ChromiumExtension "fbcohnmimjicjdomonkcbcpbpnhggkip" # myjdownloader-browser-ext
    }

}

Function Update-JoalDesktop {

    $Starter = "$Env:LocalAppData\Programs\joal-desktop\JoalDesktop.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://api.github.com/repos/anthonyraymond/joal-desktop/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-Scraper "Json" "$Address").assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*win-x64.exe" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
        Remove-Desktop "Joal*.lnk"
    }

}

Function Update-Jetbra {

    $Deposit = "$Env:UserProfile\.jetbra"
    $Starter = "$Deposit\ja-netfilter.jar"
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-360)

    If (-Not $Updated) {
        Remove-Item "$Deposit" -Recurse -Force -EA SI
        $Fetched = Invoke-Fetcher "Jetbra"
        $Extract = Invoke-Extract "$Fetched" "$(Split-Path "$Deposit")"
        Rename-Item -Path "$Extract\jetbra" -NewName "$Deposit"
        $Scripts = "$Deposit\scripts"
        Add-Type -AssemblyName System.Windows.Forms
        Start-Process "cscript" "$Scripts\uninstall-current-user.vbs" -WorkingDirectory "$Scripts" -WindowStyle Hidden
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Process "cscript" "$Scripts\install-current-user.vbs" -WorkingDirectory "$Scripts" -WindowStyle Hidden
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 4 ; Invoke-Restart
    }

}

Function Update-JetbrainsPlugin {

    Param(
        [String] $Deposit,
        [String] $Element
    )

    If (-Not (Test-Path "$Deposit") -Or ([String]::IsNullOrWhiteSpace($Element))) { Return }
    $Release = (Get-Content "$Deposit\product-info.json" | ConvertFrom-Json).buildNumber
    $Release = [Regex]::Matches("$Release", "([\d.]+)\.").Groups[1].Value
    $DataDir = (Get-Content "$Deposit\product-info.json" | ConvertFrom-Json).dataDirectoryName
    $Adjunct = If ("$DataDir" -Like "AndroidStudio*") { "Google\$DataDir" } Else { "JetBrains\$DataDir" }
    $Plugins = "$Env:AppData\$Adjunct\plugins" ; New-Item "$Plugins" -ItemType Directory -EA SI
    :Outer For ($I = 1; $I -Le 3; $I++) {
        $Address = "https://plugins.jetbrains.com/api/plugins/$Element/updates?page=$I"
        $Content = Invoke-WebRequest "$Address" | ConvertFrom-Json
        For ($J = 0; $J -Le 19; $J++) {
            $Maximum = $Content["$J"].until.Replace("`"", "").Replace("*", "9999")
            $Minimum = $Content["$J"].since.Replace("`"", "").Replace("*", "9999")
            If ([String]::IsNullOrWhiteSpace($Maximum)) { $Maximum = "9999.0" }
            If ([String]::IsNullOrWhiteSpace($Minimum)) { $Maximum = "0000.0" }
            If ([Version] "$Minimum" -Le "$Release" -And "$Release" -Le "$Maximum") {
                $Address = $Content["$J"].file.Replace("`"", "")
                $Address = "https://plugins.jetbrains.com/files/$Address"
                $Fetched = Invoke-Fetcher "Webclient" "$Address"
                Invoke-Extract "$Fetched" "$Plugins"
                Break Outer
            }
        }
        Start-Sleep 1
    }

}

Function Update-Keepassxc {

    $Starter = "$Env:ProgramFiles\KeePassXC\KeePassXC.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://api.github.com/repos/keepassxreboot/keepassxc/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-Scraper "Json" "$Address").assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*Win64.msi" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" /qn" -Wait }
        Start-Sleep 2 ; Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "KeePassXC" -EA SI
    }

}

Function Update-Ldplayer {

    $Starter = (Get-Item "C:\LDPlayer\LDPlayer*\dnplayer.exe" -EA SI).FullName
    $Current = Expand-Version "$Starter"
    $Address = "https://www.ldplayer.net/other/version-history-and-release-notes.html"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "LDPlayer_([\d.]+).exe").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 6)

    If (-Not $Updated) {
        $Address = "https://encdn.ldmnq.com/download/package/LDPlayer_$Version.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $Current = $Script:MyInvocation.MyCommand.Path
        Invoke-Gsudo {
            . $Using:Current ; Start-Sleep 4
            $Handler = Deploy-Library Flaui
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
            Start-Sleep 4 ; $Started.Dispose() | Out-Null ; $Handler.Dispose() | Out-Null
        }
        Remove-Desktop "LDM*.lnk" ; Remove-Desktop "LDP*.lnk"
    }

}

Function Update-Mambaforge {

    $Deposit = "$Env:LocalAppData\Programs\Mambaforge"
    $Present = Test-Path "$Deposit\Scripts\mamba.exe"

    If (-Not $Present) {
        $Address = "https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Windows-x86_64.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $ArgList = "/S /InstallationType=JustMe /RegisterPython=0 /AddToPath=1 /NoRegistry=1 /D=$Deposit"
        Start-Process "$Fetched" "$ArgList" -Wait
    }

    Update-SysPath "$Deposit\Scripts" "User"
    conda config --set auto_activate_base false
    conda update --all -y

}

Function Update-Maui {

    Update-VisualStudio2022
    Update-VisualStudio2022Workload "Microsoft.VisualStudio.Workload.NetCrossPlat"
    Invoke-Gsudo { [Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "1", "Machine") }
    Invoke-Gsudo { [Environment]::SetEnvironmentVariable("DOTNET_NOLOGO", "1", "Machine") }
    Enable-Feature "HyperV"
    
    $SdkHome = "${Env:ProgramFiles(x86)}\Android\android-sdk"
    $Deposit = (Get-Item "$SdkHome\cmdline-tools\*\bin" -EA SI).FullName
    If ($Null -Ne $Deposit) {
        $Creator = "$Deposit\avdmanager.bat"
        $Starter = "$Deposit\sdkmanager.bat"
        Invoke-Gsudo { Write-Output $("y`n" * 10) | & "$Using:Starter" --sdk_root="$Using:SdkHome" "build-tools;31.0.0" }
        Invoke-Gsudo { Write-Output $("y`n" * 10) | & "$Using:Starter" --sdk_root="$Using:SdkHome" "emulator" }
        Invoke-Gsudo { Write-Output $("y`n" * 10) | & "$Using:Starter" --sdk_root="$Using:SdkHome" "extras;intel;Hardware_Accelerated_Execution_Manager" }
        Invoke-Gsudo { Write-Output $("y`n" * 10) | & "$Using:Starter" --sdk_root="$Using:SdkHome" "platform-tools" }
        Invoke-Gsudo { Write-Output $("y`n" * 10) | & "$Using:Starter" --sdk_root="$Using:SdkHome" "platforms;android-31" }
        Invoke-Gsudo { Write-Output $("y`n" * 10) | & "$Using:Starter" --sdk_root="$Using:SdkHome" "system-images;android-31;google_apis;x86_64" }
        Invoke-Gsudo { Write-Output $("y`n" * 10) | & "$Using:Starter" --sdk_root="$Using:SdkHome" --licenses }
        Invoke-Gsudo { Write-Output $("y`n" * 10) | & "$Using:Starter" --sdk_root="$Using:SdkHome" --update }
        & "$Creator" create avd -n "Pixel_3_API_31" -d "pixel_3" -k "system-images;android-31;google_apis;x86_64"
    }

    Update-VisualStudio2022Extension "MattLaceyLtd.MauiAppAccelerator"
    Update-VisualStudio2022Extension "TeamXavalon.XAMLStyler2022"
    Update-VisualStudioCodeExtension "nromanov.dotnet-meteor"

}

Function Update-MicrosoftOpenjdk {

    $Current = Expand-Version "*microsoft*openjdk*"
    $Address = "https://learn.microsoft.com/en-us/java/openjdk/download"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "OpenJDK ([\d.]+) LTS").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://aka.ms/download-jdk/microsoft-jdk-$Version-windows-x64.msi"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" INSTALLLEVEL=3 /quiet" -Wait }
    }

    $Deposit = (Get-Item "$Env:ProgramFiles\Microsoft\jdk-*\bin" -EA SI).FullName
    Update-SysPath "$Deposit" "Process"

}

Function Update-Mpv {

    $Starter = "$Env:LocalAppData\Programs\Mpv\mpv.exe"
    $Address = "https://sourceforge.net/projects/mpv-player-windows/files/64bit"
    $Results = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "mpv-x86_64-([\d]{8})-git-([\a-z]{7})\.7z")
    $Version = $Results.Groups[1].Value
    $Release = $results.Groups[2].Value
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-10)
    
    If (-Not $Updated) {
        $Address = "https://sourceforge.net/projects/mpv-player-windows/files/64bit/mpv-x86_64-$Version-git-$Release.7z"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $Deposit = Split-Path "$Starter" ; Invoke-Extract "$Fetched" "$Deposit"
        $LnkFile = "$Env:AppData\Microsoft\Windows\Start Menu\Programs\mpv.lnk"
        Update-LnkFile -LnkFile "$LnkFile" -Starter "$Starter"
        Start-Sleep 4 ; Invoke-Gsudo { & "$Using:Deposit\installer\mpv-install.bat" }
        Start-Sleep 4 ; Stop-Process -Name "SystemSettings" -EA SI
    }

    $Configs = Join-Path "$(Split-Path "$Starter")" "mpv\mpv.conf"
    Set-Content -Path "$Configs" -Value "profile=gpu-hq"
    Add-Content -Path "$Configs" -Value "vo=gpu-next"
    Add-Content -Path "$Configs" -Value "hwdec=auto-copy"
    Add-Content -Path "$Configs" -Value "keep-open=yes"
    Add-Content -Path "$Configs" -Value "ytdl-format=`"bestvideo[height<=?2160]+bestaudio/best`""
    Add-Content -Path "$Configs" -Value "[protocol.http]"
    Add-Content -Path "$Configs" -Value "force-window=immediate"
    Add-Content -Path "$Configs" -Value "hls-bitrate=max"
    Add-Content -Path "$Configs" -Value "cache=yes"
    Add-Content -Path "$Configs" -Value "[protocol.https]"
    Add-Content -Path "$Configs" -Value "profile=protocol.http"
    Add-Content -Path "$Configs" -Value "[protocol.ytdl]"
    Add-Content -Path "$Configs" -Value "profile=protocol.http"

}

Function Update-Nanazip {

    $Current = Expand-Version "*nanazip*"
    $Address = "https://api.github.com/repos/m2team/nanazip/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-Scraper "Json" "$Address").assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*.msixbundle" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo {
            $ProgressPreference = "SilentlyContinue"
            Add-AppxPackage -Path "$Using:Fetched" -DeferRegistrationWhenPackagesAreInUse -ForceUpdateFromAnyVersion
        }
    }

}

Function Update-Noxplayer {

    $Starter = "${Env:ProgramFiles(x86)}\Nox\bin\Nox.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://support.bignox.com/en/win-release"
    $Version = [Regex]::Matches((Invoke-Scraper "BrowserHtml" "$Address"), ".*V([\d.]+) Release Note").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 5)

    If (-Not $Updated) {
        $Address = "https://www.bignox.com/en/download/fullPackage/win_64_9?formal"
        $Fetched = Invoke-Fetcher "Browser" "$Address"
        $Current = $Script:MyInvocation.MyCommand.Path
        Invoke-Gsudo {
            . $Using:Current ; Start-Sleep 4
            Deploy-Library Flaui
            Start-Process "$Using:Fetched"
            Add-Type -AssemblyName System.Windows.Forms
            $FactorX = ([Windows.Forms.SystemInformation]::PrimaryMonitorSize.Width / 2)
            $FactorY = ([Windows.Forms.SystemInformation]::PrimaryMonitorSize.Height / 2) + 85
            $Centrum = [Drawing.Point]::New($FactorX, $FactorY)
            Start-Sleep 12 ; [FlaUI.Core.Input.Mouse]::LeftClick($Centrum) ; Start-Sleep 6
            $FactorX = ([Windows.Forms.SystemInformation]::PrimaryMonitorSize.Width / 2) + 100
            $FactorY = ([Windows.Forms.SystemInformation]::PrimaryMonitorSize.Height / 2) + 185
            $Centrum = [Drawing.Point]::New($FactorX, $FactorY)
            Start-Sleep 6 ; [FlaUI.Core.Input.Mouse]::LeftClick($Centrum) ; Start-Sleep 6
            While (-Not (Test-Path "$Env:UserProfile\Desktop\Nox*.lnk")) { Start-Sleep 2 }
            Start-Sleep 4 ; Stop-Process -Name "*nox*setup*" -EA SI
        }
        Remove-Desktop "Nox*.lnk" ; Remove-Desktop "Nox*Ass*.lnk"
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "NoxMultiPlayer" -EA SI
    }

}

Function Update-Nvidia {

    Param(
        [ValidateSet("Cuda", "Game")] [String] $Release
    )

    Switch ($Release) {
        "Cuda" {
            $Current = Expand-Version "*cuda*runtime*"
            $Present = $Current -Ne "0.0.0.0"
            $Address = "https://raw.githubusercontent.com/scoopinstaller/main/master/bucket/cuda.json"
            $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").version, "[\d.]+").Value
            $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 4)

            If (-Not $Updated) {
                $Address = (Invoke-Scraper "Json" "$Address").architecture."64bit".url.Replace("#/dl.7z", "")
                $Fetched = Invoke-Fetcher "Webclient" "$Address"
                Invoke-Gsudo { Start-Process "$Using:Fetched" "/s /noreboot" -Wait }
                Remove-Desktop "GeForce*.lnk"
            }
        }
        "Game" {
            $Current = Expand-Version "*nvidia*graphics*driver*"
            $Present = $Current -Ne "0.0.0.0"
            $Address = "https://community.chocolatey.org/packages/geforce-game-ready-driver"
            $Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "Geforce Game Ready Driver ([\d.]+)</title>").Groups[1].Value
            $Updated = [Version] "$Current" -Ge [Version] "$Version"

            If (-Not $Updated) {
                $Address = "https://us.download.nvidia.com/Windows/$Version/$Version-desktop-win10-win11-64bit-international-dch-whql.exe"
                $Fetched = Invoke-Fetcher "Webclient" "$Address"
                $Extract = Invoke-Extract "$Fetched"
                Invoke-Gsudo { Start-Process "$Using:Extract\setup.exe" "Display.Driver HDAudio.Driver -clean -s -noreboot" -Wait }
            }
        }
    }

    If (-Not $Present) {
        $Deposit = Get-AppxPackage "*NVIDIAControlPanel*" | Select-Object -ExpandProperty InstallLocation
        $Starter = "$Deposit\nvcplui.exe"
        If (Test-Path "$Starter") {
            $Handler = Deploy-Library Flaui
            Stop-Process -Name "nvcplui" -EA SI ; Start-Sleep 2
            $Started = [FlaUI.Core.Application]::Launch("$Starter")
            $Window1 = $Started.GetMainWindow($Handler) ; Start-Sleep 4 ; $Window1.Focus() ; Start-Sleep 2
            Try { $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Agree and Continue")) ; $Element.Click() ; Start-Sleep 8 ; $Window1.Close() } Catch {}
            Stop-Process -Name "nvcplui" -EA SI ; Start-Sleep 2
            $Started = [FlaUI.Core.Application]::Launch("$Starter")
            $Window1 = $Started.GetMainWindow($Handler) ; Start-Sleep 4 ; $Window1.Focus() ; Start-Sleep 2
            Try { $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Maximize")) ; $Element.Click() } Catch {}
            Start-Sleep 2 ; $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Change resolution"))
            $Element.Click()
            Start-Sleep 2 ; $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Use NVIDIA color settings"))
            $Element.Click()
            $Factor1 = $Handler.ConditionFactory.ByName("Output dynamic range:")
            $Factor2 = $Handler.ConditionFactory.ByControlType("ComboBox")
            Start-Sleep 2 ; $Element = $Window1.FindFirstDescendant($Factor1.And($Factor2))
            $Element.Click()
            Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type("F")
            Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER)
            Start-Sleep 2 ; $Element = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Apply"))
            $Element.Click()
            Start-Sleep 5 ; $Window1.Close()
            Start-Sleep 4 ; $Started.Dispose() | Out-Null ; $Handler.Dispose() | Out-Null
        }
    }

}

Function Update-Powershell {

    $Starter = (Get-Item "$Env:ProgramFiles\PowerShell\*\pwsh.exe" -EA SI).FullName
    $Current = Expand-Version "$Starter"
    $Address = "https://api.github.com/repos/powershell/powershell/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        Invoke-Gsudo {
            $ProgressPreference = "SilentlyContinue"
            Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet" *> $Null
        }
    }

    If ([Version] $PSVersionTable.PSVersion.ToString() -Lt [Version] "7.0.0.0") { Invoke-Restart }

}

Function Update-Pycharm {

    Param (
        [String] $Deposit = "$Env:userProfile\Projects",
        [String] $Margins = 140
    )

    Update-Jetbra
    $Starter = "$Env:ProgramFiles\JetBrains\PyCharm\bin\pycharm64.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://data.services.jetbrains.com/products/releases?code=PCP&latest=true&type=release"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").PCP[0].version , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        If ($Present) {
            Invoke-Gsudo { Start-Process "$Env:ProgramFiles\JetBrains\PyCharm\bin\Uninstall.exe" "/S" -Wait }
            Remove-Item -Path "$Env:ProgramFiles\JetBrains\PyCharm" -Recurse -Force
            Remove-Item -Path "HKCU:\SOFTWARE\JetBrains\PyCharm" -Recurse -Force
        }
        $Address = (Invoke-Scraper "Json" "$Address").PCP[0].downloads.windows.link
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $ArgList = "/S /D=$Env:ProgramFiles\JetBrains\PyCharm"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        $Created = "$([Environment]::GetFolderPath("CommonStartMenu"))\Programs\JetBrains\PyCharm.lnk"
        Remove-Item "$Created" -EA SI
        $Forward = Get-Item "$([Environment]::GetFolderPath("CommonStartMenu"))\Programs\JetBrains\*PyCharm*.lnk"
        Invoke-Gsudo { Rename-Item -Path "$Using:Forward" -NewName "$Using:Created" }
    }

    If (-Not $Present) {
        $License = Invoke-Scraper "Jetbra" "PyCharm"
        $Handler = Deploy-Library Flaui
        $Started = [FlaUI.Core.Application]::Launch("$Starter")
        $Window1 = $Started.GetMainWindow($Handler)
        $Window1.Focus()
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 4 ; $Desktop = $Handler.GetDesktop()
        $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByName("Licenses"))
        $Scraped = $Window1.BoundingRectangle
        $FactorX = $Scraped.X + ($Scraped.Width / 2)
        $FactorY = $Scraped.Y + ($Scraped.Height / 2)
        Start-Sleep 4 ; [FlaUI.Core.Input.Mouse]::LeftClick([Drawing.Point]::New($FactorX, $FactorY - 105))
        Start-Sleep 2 ; [FlaUI.Core.Input.Mouse]::LeftClick([Drawing.Point]::New($FactorX, $FactorY))
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type("$License")
        Start-Sleep 8 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Try {
            Start-Sleep 8 ; $Desktop = $Handler.GetDesktop()
            $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByName("Windows Security Alert"))
            $Button1 = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Allow access"))
            $Button1.Click()
        }
        Catch {}
        $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
        $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::F4
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
        Start-Sleep 4 ; Stop-Process -Name "pycharm64" -EA SI
        Start-Sleep 4 ; $Started.Dispose() | Out-Null ; $Handler.Dispose() | Out-Null
    }

}

Function Update-Python {

    Param (
        [Int] $Leading = 3,
        [Int] $Backing = 11
    )

    $Current = Expand-Version "*python*evelopment*"
    $Address = "https://www.python.org/downloads/windows/"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "python-($Leading\.$Backing\.[\d.]+)-").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Ongoing = Invoke-Gsudo { [Environment]::GetEnvironmentVariable("PATH", "Machine") }
        $Changed = "$Ongoing" -Replace "C:\\Program Files\\Python[\d]+\\Scripts\\;" -Replace "C:\\Program Files\\Python[\d]+\\;"
        Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PATH", "$Using:Changed", "Machine") }
        $Address = "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $ArgList = "/quiet InstallAllUsers=1 AssociateFiles=0 PrependPath=1 Shortcuts=0 Include_launcher=0 InstallLauncherAllUsers=0"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait } ; Start-Sleep 4
        Update-SysPath "$Env:ProgramFiles\Python$Leading$Backing" "Machine"
        Update-SysPath "$Env:ProgramFiles\Python$Leading$Backing\Scripts" "Machine"
        Invoke-Gsudo { python -m pip install --upgrade pip }
        Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "1", "Machine") }
    }

    If (-Not $Updated) {
        New-Item "$Env:AppData\Python\Scripts" -ItemType Directory -EA SI
        $Address = "https://install.python-poetry.org/"
        $Fetched = Invoke-Fetcher "Webclient" "$Address" "$Env:Temp\install-poetry.py"
        python "$Fetched" --uninstall
        python "$Fetched"
        Update-SysPath "$Env:AppData\Python\Scripts" "Machine"
        poetry config virtualenvs.in-project true
        poetry self update
    }

}

Function Update-Qbittorrent {

    Param (
        [String] $Deposit = "$Env:UserProfile\Downloads\P2P",
        [String] $Loading = "$Env:UserProfile\Downloads\P2P\Incompleted"
    )

    $Starter = "$Env:ProgramFiles\qBittorrent\qbittorrent.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://www.qbittorrent.org/download.php"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "Latest:\s+v([\d.]+)").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://downloads.sourceforge.net/project/qbittorrent/qbittorrent-win32/qbittorrent-$Version/qbittorrent_${Version}_x64_setup.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
    }

    $Configs = "$Env:AppData\qBittorrent\qBittorrent.ini"
    New-Item "$Deposit" -ItemType Directory -EA SI
    New-Item "$Loading" -ItemType Directory -EA SI
    New-Item "$(Split-Path "$Configs")" -ItemType Directory -EA SI
    Set-Content -Path "$Configs" -Value "[LegalNotice]"
    Add-Content -Path "$Configs" -Value "Accepted=true"
    Add-Content -Path "$Configs" -Value "[Preferences]"
    Add-Content -Path "$Configs" -Value "Bittorrent\MaxRatio=0"
    Add-Content -Path "$Configs" -Value "Downloads\SavePath=$($Deposit.Replace("\", "/"))"
    Add-Content -Path "$Configs" -Value "Downloads\TempPath=$($Loading.Replace("\", "/"))"
    Add-Content -Path "$Configs" -Value "Downloads\TempPathEnabled=true"

}

Function Update-Rider {

    Param (
        [String] $Deposit = "$Env:userProfile\Projects",
        [String] $Margins = 160
    )

    Update-Jetbra
    $Starter = "$Env:ProgramFiles\JetBrains\Rider\bin\rider64.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://data.services.jetbrains.com/products/releases?code=RD&latest=true&type=release"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").RD[0].version , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        If ($Present) {
            Invoke-Gsudo { Start-Process "$Env:ProgramFiles\JetBrains\Rider\bin\Uninstall.exe" "/S" -Wait }
            Remove-Item -Path "$Env:ProgramFiles\JetBrains\Rider" -Recurse -Force
            Remove-Item -Path "HKCU:\SOFTWARE\JetBrains\Rider" -Recurse -Force
        }
        $Address = (Invoke-Scraper "Json" "$Address").RD[0].downloads.windows.link
        # $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $Fetched = "$Env:UserProfile\Desktop\JetBrains.Rider-2022.3.2.exe" # TODO: Remove dummies
        $ArgList = "/S /D=$Env:ProgramFiles\JetBrains\Rider"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        $Created = "$([Environment]::GetFolderPath("CommonStartMenu"))\Programs\JetBrains\Rider.lnk"
        Remove-Item "$Created" -EA SI
        $Forward = Get-Item "$([Environment]::GetFolderPath("CommonStartMenu"))\Programs\JetBrains\*Rider*.lnk"
        Invoke-Gsudo { Rename-Item -Path "$Using:Forward" -NewName "$Using:Created" }
    }

    If (-Not $Present) {
        Remove-Item "$Env:AppData\JetBrains\consentOptions" -Recurse -EA SI
        
        $License = Invoke-Scraper "Jetbra" "Rider"
        $Library = Deploy-Library "Flaui"
        $Started = [FlaUI.Core.Application]::Launch("$Starter")
        $Factory = $Library.ConditionFactory
        $Matcher = [FlaUI.Core.Definitions.PropertyConditionFlags]::MatchSubstring

        Start-Sleep 6 ; $Desktop = $Library.GetDesktop()
        Start-Sleep 2 ; $Window1 = $Desktop.FindFirstDescendant($Factory.ByName("Agreement", $Matcher))
        Start-Sleep 2 ; $Window1.Focus()
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)

        Start-Sleep 2 ; $Desktop = $Library.GetDesktop()
        Start-Sleep 2 ; $Window1 = $Desktop.FindFirstDescendant($Factory.ByName("Data", $Matcher))
        Start-Sleep 2 ; $Window1.Focus()
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)

        Start-Sleep 2 ; $Desktop = $Library.GetDesktop()
        Start-Sleep 2 ; $Window1 = $Desktop.FindFirstDescendant($Factory.ByName("Import", $Matcher))
        Start-Sleep 2 ; $Window1.Focus()
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)

        Start-Sleep 2 ; $Desktop = $Library.GetDesktop()
        Start-Sleep 2 ; $Window1 = $Desktop.FindFirstDescendant($Factory.ByName("Customize", $Matcher))
        Start-Sleep 2 ; $Window1.Focus()
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)

        Start-Sleep 4 ; $Desktop = $Library.GetDesktop()
        Start-Sleep 2 ; $Window1 = $Desktop.FindFirstDescendant($Factory.ByName("Licenses"))
        Start-Sleep 2 ; $Window1.Focus()
        $Scraped = $Window1.BoundingRectangle
        $FactorX = $Scraped.X + ($Scraped.Width / 2)
        $FactorY = $Scraped.Y + ($Scraped.Height / 2)
        Start-Sleep 4 ; [FlaUI.Core.Input.Mouse]::LeftClick([Drawing.Point]::New($FactorX, $FactorY - 105))
        Start-Sleep 2 ; [FlaUI.Core.Input.Mouse]::LeftClick([Drawing.Point]::New($FactorX, $FactorY))
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type("$License")
        Start-Sleep 8 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)

        $Window1.Focus() ; Start-Sleep 2
        $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
        $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::F4
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
        Start-Sleep 4 ; Stop-Process -Name "rider64" -EA SI

        Try {
            Start-Sleep 8 ; $Desktop = $Library.GetDesktop()
            Start-Sleep 2 ; $Window1 = $Desktop.FindFirstDescendant($Factory.ByName("Windows Security Alert"))
            $Window1.Focus()
            Start-Sleep 2 ; $Button1 = $Window1.FindFirstDescendant($Factory.ByName("Allow access"))
            $Button1.Click()
        }
        Catch {}

        Start-Sleep 4 ; $Started.Dispose() | Out-Null ; $Library.Dispose() | Out-Null
    }

    If ($Deposit) {
        New-Item -Path "$Deposit" -ItemType Directory -EA SI
        Invoke-Gsudo { Add-MpPreference -ExclusionPath "$Using:Deposit" *> $Null }
        $BaseDir = Get-Item "$Env:AppData\JetBrains\Rider*"
        $Configs = Get-Item "$BaseDir\options\ide.general.xml"
        If ($Null -Eq $Configs) { 
            New-Item -Path "$BaseDir\options" -ItemType Directory -EA SI
            New-Item -Path "$BaseDir\options\ide.general.xml" -ItemType File -EA SI
            Set-Content -Path "$BaseDir\options\ide.general.xml" -Value "<application><component name=`"GeneralSettings`"></component></application>" | Out-Null
        }
        $Configs = Get-Item "$BaseDir\options\ide.general.xml"
        $General = [Xml] (Get-Content -Path "$Configs")
        $Element = $General.SelectSingleNode("//*[@name=`"defaultProjectDirectory`"]")
        If ($Null -Ne $Element) { 
            $Element.SetAttribute("value", "$Deposit") 
            $General.Save("$Configs")
        }
        Else {
            $Subject = $General.SelectSingleNode('//*[@name="GeneralSettings"]')
            $Element = $General.CreateElement("option")
            $Element.SetAttribute("name", "defaultProjectDirectory")
            $Element.SetAttribute("value", "$Deposit")
            $Subject.AppendChild($Element)
            $General.Save("$Configs")
        }
    }

}

Function Update-Scrcpy {

    $Deposit = "$Env:LocalAppData\Programs\Scrcpy"
    $Starter = "$Deposit\scrcpy.exe"
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-120)

    If (-Not $Updated) {
        Remove-Item "$Deposit" -Recurse -Force -EA SI
        $Address = "https://api.github.com/repos/genymobile/scrcpy/releases/latest"
        $Results = (Invoke-Scraper "Json" "$Address").assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*win64*.zip" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $Extract = Invoke-Extract "$Fetched" "$(Split-Path "$Deposit")"
        Rename-Item -Path "$Extract\scr*" -NewName "$Deposit"
    }

    Update-SysPath "$Deposit" "Machine"

}

Function Update-Spotify {

    $Current = Expand-Version "*spotify*"
    $Address = "https://raw.githack.com/scoopinstaller/extras/master/bucket/spotify.json"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").version , "[\d.]+(?=\.)").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://raw.githack.com/amd64fox/SpotX/main/scripts/Install_Auto.bat"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Invoke-Expression "echo ``n | cmd /c '$Using:Fetched'" }
        Invoke-Gsudo { Start-Sleep 2 ; Stop-Process -Name "Spotify" }
        Remove-Desktop "Spotify*.lnk"
    }

    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Spotify" -EA SI

}

Function Update-Steam {

    $Current = Expand-Version "*steam*"
    $Address = "https://community.chocolatey.org/packages/steam"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "Steam ([\d.]+)</title>").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "http://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
        Remove-Desktop "Steam*.lnk"
        Start-Sleep 2 ; Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Steam" -EA SI
    }

}

Function Update-Ventura {

    Update-Wsl ; $Program = "$Env:LocalAppData\Microsoft\WindowsApps\ubuntu.exe"
    Start-Process "$Program" "run sudo add-apt-repository -y ppa:wslutilities/wslu" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run sudo apt update && sudo apt install -y curl git-all imagemagick wslu" -WindowStyle Hidden -Wait

    $Address = "https://github.com/notAperson535/OneClick-macOS-Simple-KVM.git"
    $Deposit = "/mnt/c/users/$Env:Username/Documents"
    Start-Process "$Program" "run cd $Deposit && git clone $Address ventura" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run cd $Deposit/ventura && git pull" -WindowStyle Hidden -Wait

    $IconUrl = "https://raw.githubusercontent.com/sharpordie/winhogen/main/assets/ventura.ico"
    Start-Process "$Program" "run cd $Deposit/ventura ; [[ ! -f ventura.ico ]] && curl '$IconUrl' -o ventura.ico" -WindowStyle Hidden -Wait
    $Address = "https://downloads.realvnc.com/download/file/viewer.files/VNC-Viewer-7.1.0-Windows-64bit.exe"
    Start-Process "$Program" "run cd $Deposit/ventura ; [[ ! -f vncviewer.exe ]] && curl '$Address' -o vncviewer.exe" -WindowStyle Hidden -Wait

    $Created = "$Deposit/ventura/launcher.sh"
    Start-Process "$Program" "run echo '($Deposit/ventura/vncviewer.exe localhost:5900 -WarnUnencrypted=0 &) && HEADLESS=1 $Deposit/ventura/basic.sh' > '$Created'" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run chmod +x '$Created'" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run wslusc --gui --icon '$Deposit/ventura/ventura.ico' --name 'Ventura' $Created" -WindowStyle Normal -Wait
    Move-Item "$Env:UserProfile\Desktop\Ventura.lnk" "$Env:AppData\Microsoft\Windows\Start Menu\Programs" -Force -EA SI
    Start-Process "$Program" "run cd $Deposit/ventura ; [[ ! -f BaseSystem.dmg ]] && HEADLESS=1 echo 6 | ./setup.sh || ./launcher.sh" -WindowStyle Hidden

}

Function Update-VisualStudio2022 {

    Param(
        [String] $Deposit = "$Env:UserProfile\Projects",
        [String] $Serials = "TD244-P4NB7-YQ6XK-Y8MMM-YWV2J",
        [Switch] $Preview
    )

    $Adjunct = If ($Preview) { "Preview" } Else { "Professional" }
    $Storage = "$Env:ProgramFiles\Microsoft Visual Studio\2022\$Adjunct"
    $Starter = "$Storage\Common7\IDE\devenv.exe"
    $Present = Test-Path "$Starter"
    Update-VisualStudio2022Workload "Microsoft.VisualStudio.Workload.CoreEditor" -Preview:$Preview

    If (-Not $Present) {
        Invoke-Gsudo { Start-Process "$Using:Starter" "/ResetUserData" -Wait }
        Add-Type -AssemblyName "System.Windows.Forms" ; Start-Process "$Starter"
        Start-Sleep 25 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 4)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}") ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 20 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 8
    }

    $Program = "$Storage\Common7\IDE\StorePID.exe"
    # Invoke-Gsudo { Start-Process "$Using:Program" "$Using:Serials 09662" -WindowStyle Hidden -Wait }
    Invoke-Gsudo { & "$Using:Program" $Using:Serials 09662 }

    $Config1 = "$Env:LocalAppData\Microsoft\VisualStudio\17*\Settings\CurrentSettings.vssettings"
    $Config2 = "$Env:LocalAppData\Microsoft\VisualStudio\17*\Settings\CurrentSettings-*.vssettings"
    If (Test-Path "$Config1") {
        $Configs = (Get-Item "$Config1").FullName
        [Xml] $Content = Get-Content "$Configs"
        $Content.SelectSingleNode("//*[@name='HighlightCurrentLine']").InnerText = "false"
        $Content.Save("$Configs")
    }
    If (Test-Path "$Config2") {
        $Configs = (Get-Item "$Config2").FullName
        [Xml] $Content = Get-Content "$Configs"
        $Content.SelectSingleNode("//*[@name='HighlightCurrentLine']").InnerText = "false"
        $Content.Save("$Configs")
    }

    If (Test-Path "$Config1") {
        $Configs = (Get-Item "$Config1").FullName
        [Xml] $Content = Get-Content "$Configs"
        $Content.SelectSingleNode("//*[@name='LineSpacing']").InnerText = "1.5"
        $Content.Save($Configs)
    }
    If (Test-Path "$Config2") {
        $Configs = (Get-Item "$Config2").FullName
        [Xml] $Content = Get-Content "$Configs"
        $Content.SelectSingleNode("//*[@name='LineSpacing']").InnerText = "1.5"
        $Content.Save($Configs)
    }

    Remove-Item "$Env:UserProfile\source" -Recurse -EA SI
    New-Item "$Deposit" -ItemType Directory -EA SI | Out-Null
    Invoke-Gsudo { Add-MpPreference -ExclusionPath "$Using:Deposit" *> $Null }
    If (Test-Path "$Config1") {
        $Configs = (Get-Item "$Config1").FullName
        [Xml] $Content = Get-Content "$Configs"
        $Payload = $Deposit.Replace("${Env:UserProfile}", '%vsspv_user_appdata%') + "\"
        $Content.SelectSingleNode("//*[@name='ProjectsLocation']").InnerText = "$Payload"
        $Content.Save($Configs)
    }
    If (Test-Path "$Config2") {
        $Configs = (Get-Item "$Config2").FullName
        [Xml] $Content = Get-Content "$Configs"
        $Payload = $Deposit.Replace("${Env:UserProfile}", '%vsspv_user_appdata%') + "\"
        $Content.SelectSingleNode("//*[@name='ProjectsLocation']").InnerText = "$Payload"
        $Content.Save($Configs)
    }

}

Function Update-VisualStudio2022Extension {

    Param (
        [String] $Payload,
        [Switch] $Preview
    )

    $Website = "https://marketplace.visualstudio.com/items?itemName=$Payload"
    $Content = Invoke-WebRequest -Uri $Website -UseBasicParsing -SessionVariable Session
    $Address = $Content.Links | Where-Object { $_.class -Eq "install-button-container" } | Select-Object -ExpandProperty href
    $Address = "https://marketplace.visualstudio.com" + "$Address"
    $Package = "$Env:Temp\$([Guid]::NewGuid()).vsix"
    Invoke-WebRequest "$Address" -OutFile "$Package" -WebSession $Session
    $Adjunct = If ($Preview) { "Preview" } Else { "Professional" }
    $Updater = "$Env:ProgramFiles\Microsoft Visual Studio\2022\$Adjunct\Common7\IDE\VSIXInstaller.exe"
    Invoke-Gsudo { Start-Process "$Using:Updater" "/q /a `"$Using:Package`"" -WindowStyle Hidden -Wait }

}

Function Update-VisualStudio2022Workload {

    Param (
        [String] $Payload,
        [Switch] $Preview
    )

    $Address = "https://aka.ms/vs/17/release/vs_professional.exe"
    If ($Preview) { $Address = "https://c2rsetup.officeapps.live.com/c2r/downloadVS.aspx?sku=professional&channel=Preview&version=VS2022" }
    $Fetched = Invoke-Fetcher "Webclient" "$Address" "$Env:Temp\VisualStudioSetup.exe"
    Invoke-Gsudo {
        Start-Process "$Using:Fetched" "update --wait --quiet --norestart" -WindowStyle Hidden -Wait
        Start-Process "$Using:Fetched" "install --wait --quiet --norestart --add $Using:Payload" -WindowStyle Hidden -Wait
        Start-Sleep 2 ; Start-Process "cmd" "/c taskkill /f /im devenv.exe /t 2>nul 1>nul" -WindowStyle Hidden -Wait
    }
    
}

Function Update-VisualStudioCode {

    $Starter = "$Env:LocalAppData\Programs\Microsoft VS Code\Code.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://code.visualstudio.com/sha?build=stable"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").products[1].name , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 6)

    If (-Not $Updated -And "$Env:TERM_PROGRAM" -Ne "Vscode") {
        $Address = "https://aka.ms/win32-x64-user-stable"
        $Fetched = Invoke-Fetcher "Webclient" "$Address" "$Env:Temp\VSCodeUserSetup-x64-Latest.exe"
        $ArgList = "/VERYSILENT /MERGETASKS=`"!runcode`""
        Invoke-Gsudo { Stop-Process -Name "Code" -EA SI ; Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
    }

    Update-SysPath "$Env:LocalAppData\Programs\Microsoft VS Code\bin" "User"
    Update-VisualStudioCodeExtension "github.github-vscode-theme"
    Update-VisualStudioCodeExtension "ms-vscode.powershell"

    $Configs = "$Env:AppData\Code\User\settings.json"
    New-Item "$(Split-Path "$Configs")" -ItemType Directory -EA SI
    New-Item "$Configs" -ItemType File -EA SI
    $NewJson = New-Object PSObject
    $NewJson | Add-Member -Type NoteProperty -Name "editor.bracketPairColorization.enabled" -Value $True -Force
    $NewJson | Add-Member -Type NoteProperty -Name "editor.fontSize" -Value 14 -Force
    $NewJson | Add-Member -Type NoteProperty -Name "editor.lineHeight" -Value 28 -Force
    $NewJson | Add-Member -Type NoteProperty -Name "security.workspace.trust.enabled" -Value $False -Force
    $NewJson | Add-Member -Type NoteProperty -Name "telemetry.telemetryLevel" -Value "crash" -Force
    $NewJson | Add-Member -Type NoteProperty -Name "update.mode" -Value "none" -Force
    $NewJson | Add-Member -Type NoteProperty -Name "workbench.colorTheme" -Value "Default Dark+ Experimental" -Force
    $NewJson | ConvertTo-Json | Set-Content "$Configs"

}

Function Update-VisualStudioCodeExtension {

    Param(
        [String] $Payload
    )

    Start-Process "code" "--install-extension $Payload --force" -WindowStyle Hidden -Wait

}

Function Update-VmwareWorkstation {

    Param (
        [String] $Leading = "17",
        [String] $Deposit = "$Env:UserProfile\Machines",
        [String] $Serials = "MC60H-DWHD5-H80U9-6V85M-8280D"
    )

    $Starter = "${Env:ProgramFiles(x86)}\VMware\VMware Workstation\vmware.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://softwareupdate.vmware.com/cds/vmw-desktop/ws-windows.xml"
    $Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "url>ws/($Leading.[\d.]+)/(\d+)/windows/core").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 4)

    If (-Not $Updated) {
        If (Assert-Pending -Eq $True) { Invoke-Restart }
        $Address = "https://www.vmware.com/go/getworkstation-win"
        $Fetched = Invoke-Fetcher "Webclient" "$Address" "$Env:Temp\vmware-workstation-full.exe"
        $ArgList = "/s /v/qn EULAS_AGREED=1 AUTOSOFTWAREUPDATE=0 DATACOLLECTION=0 ADDLOCAL=ALL REBOOT=ReallySuppress SERIALNUMBER=$Serials"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait } ; Start-Sleep 4
        Start-Process "$Starter" -WindowStyle Hidden ; Start-Sleep 10 ; Stop-Process -Name "vmware" -EA SI ; Start-Sleep 2
        Set-ItemProperty -Path "HKCU:\Software\VMware, Inc.\VMware Tray" -Name "TrayBehavior" -Type DWord -Value 2
        Remove-Desktop "VMware*.lnk"
    }

    If (-Not $Present) {
        $Address = "https://api.github.com/repos/DrDonk/unlocker/releases/latest"
        $Results = (Invoke-Scraper "Json" "$Address").assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*.zip" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $Extract = Invoke-Extract "$Fetched"
        # Update-Nanazip ; $Extract = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName
        # Start-Process "7z.exe" "x `"$Fetched`" -o`"$Extract`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
        Start-Sleep 4 ; $Program = Join-Path "$Extract" "windows\unlock.exe"
        Invoke-Gsudo {
            [Environment]::SetEnvironmentVariable("UNLOCK_QUIET", "1", "Process")
            Start-Process "$Using:Program" -WindowStyle Hidden
        }
    }

    If ($Deposit) {
        New-Item -Path "$Deposit" -ItemType Directory -EA SI
        $Configs = "$Env:AppData\VMware\preferences.ini"
        If (-Not ((Get-Content "$Configs") -Match "prefvmx.defaultVMPath")) { Add-Content -Path "$Configs" -Value "prefvmx.defaultVMPath = `"$Deposit`"" }
    }

}

Function Update-Windows {

    Param (
        [String] $Country = "Romance Standard Time",
        [String] $Machine = "WINHOGEN"
    )

    Update-Element "Computer" "$Machine"
    Update-Element "Timezone" "$Country"
    Update-Element "Volume" 40

    Enable-Feature "Activation"
    Enable-Feature "NightLight"
    Enable-Feature "RemoteDesktop"

}

Function Update-Wsl {

    Enable-Feature "Wsl"

    $Program = "$Env:Windir\System32\wsl.exe"
    If (Test-Path "$Program") {
        & "$Program" --update
        & "$Program" --shutdown
        & "$Program" --install ubuntu --no-launch
    }

    $Program = "$Env:LocalAppData\Microsoft\WindowsApps\ubuntu.exe"
    If (Test-Path "$Program") {
        Start-Process "$Program" "install --root" -WindowStyle Hidden -Wait
        Start-Process "$Program" "run sudo dpkg --configure -a" -WindowStyle Hidden -Wait
        Start-Process "$Program" "run sudo apt update" -WindowStyle Hidden -Wait
        Start-Process "$Program" "run sudo apt upgrade -y" -WindowStyle Hidden -Wait
        Start-Process "$Program" "run sudo apt full-upgrade -y" -WindowStyle Hidden -Wait
        Start-Process "$Program" "run sudo apt autoremove -y" -WindowStyle Hidden -Wait
        Start-Process "$Program" "run sudo apt install -y x11-apps" -WindowStyle Hidden -Wait
    }

}

Function Update-YtDlg {

    $Deposit = "$Env:LocalAppData\Programs\YtDlp"
    $Starter = "$Deposit\yt-dlp.exe"
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-10)

    If (-Not $Updated) {
        $Address = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        New-Item "$Deposit" -ItemType Directory -EA SI
        Invoke-Fetcher "Webclient" "$Address" "$Starter"
    }

    Update-SysPath "$Deposit" "Machine"

}

If ($MyInvocation.InvocationName -Ne "." -Or "$Env:TERM_PROGRAM" -Eq "Vscode") {

    $Current = $Script:MyInvocation.MyCommand.Path
    $Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName.ToUpper()

    Clear-Host ; $ProgressPreference = "SilentlyContinue"
    Write-Output "+---------------------------------------------------------------+"
    Write-Output "|                                                               |"
    Write-Output "|  > WINHOGEN                                                   |"
    Write-Output "|                                                               |"
    Write-Output "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                        |"
    Write-Output "|                                                               |"
    Write-Output "+---------------------------------------------------------------+"

    $Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
    $Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
    Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Feature "Uac" ; Remove-Feature "Sleeping"
    $Correct = (Update-Gsudo) -And ! (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
    If (-Not $Correct) { Write-Host "$Failure`n" -FO Red ; Exit }
    Update-Powershell ; Enable-Feature "Uac"

    Update-Element "Timezone" "Romance Standard Time"
    $Members = Export-Members -Variant "Laptop"

    $Bigness = (65 - 19) * -1
    $Shaping = "`r{0,$Bigness}{1,-3}{2,-5}{3,-3}{4,-8}"
    $Heading = "$Shaping" -F "FUNCTION", " ", "ITEMS", " ", "DURATION"
    Write-Host "$Heading"
    $Minimum = 0 ; $Maximum = $Members.Count
    Foreach ($Element In $Members) {
        $Minimum++ ; $Started = Get-Date
        $Running = $Element.Split(' ')[0].ToUpper()
        $Shaping = "`n{0,$Bigness}{1,-3}{2,-5}{3,-3}{4,-8}"
        $Advance = "$("{0:d2}" -F [Int] $Minimum)/$("{0:d2}" -F [Int] $Maximum)"
        $Loading = "$Shaping" -F "$Running", "", "$Advance", "", "--:--:--"
        Write-Host "$Loading" -ForegroundColor DarkYellow -NoNewline
        Try {
            Invoke-Expression $Element *> $Null
            $Elapsed = "{0:hh}:{0:mm}:{0:ss}" -F ($(Get-Date) - $Started)
            $Shaping = "`r{0,$Bigness}{1,-3}{2,-5}{3,-3}{4,-8}"
            $Success = "$Shaping" -F "$Running", "", "$Advance", "", "$Elapsed"
            Write-Host "$Success" -ForegroundColor Green -NoNewLine
        }
        Catch {
            $Elapsed = "{0:hh}:{0:mm}:{0:ss}" -F ($(Get-Date) - $Started)
            $Shaping = "`r{0,$Bigness}{1,-3}{2,-5}{3,-3}{4,-8}"
            $Failure = "$Shaping" -F "$Running", "", "$Advance", "", "$Elapsed"
            Write-Host "$Failure" -ForegroundColor Red -NoNewLine
        }
    }

    Enable-Feature "Sleeping" ; gsudo -k *> $Null
    Write-Host "`n"

}