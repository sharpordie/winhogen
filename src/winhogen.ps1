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

Function Deploy-Browser {

    Param(
        [ValidateSet("Chromium", "Firefox")] [String] $Browser = "Chromium"
    )

    Import-Library "System.Text.Json"
    Import-Library "Microsoft.Bcl.AsyncInterfaces"
    Import-Library "Microsoft.CodeAnalysis"
    Import-Library "Microsoft.Playwright"
    $Current = $Script:MyInvocation.MyCommand.Path
    Invoke-Gsudo {
        . $Using:Current ; Start-Sleep 4
        Import-Library "System.Text.Json"
        Import-Library "Microsoft.Bcl.AsyncInterfaces"
        Import-Library "Microsoft.CodeAnalysis"
        Import-Library "Microsoft.Playwright"
        [Microsoft.Playwright.Program]::Main(@("install", "$Using:Browser".ToLower()))
    }
    Return [Microsoft.Playwright.Playwright]::CreateAsync().GetAwaiter().GetResult()

}

Function Enable-Feature {

    Param(
        [ValidateSet("Activation", "HyperV", "RemoteDesktop", "Sleeping", "Uac", "Wsl")] [String] $Feature
    )

    Switch ($Feature) {
        "Activation" {
            $Content = (Write-Output ((cscript /nologo "C:\Windows\System32\slmgr.vbs" /xpr) -Join ""))
            If (-Not $Content.Contains("permanently activated")) {
                $Fetched = Invoke-Fetcher "Webclient" "https://massgrave.dev/get.ps1"
                Start-Process "powershell" "-f `"$Fetched`"" -WindowStyle Hidden
                Add-Type -AssemblyName System.Windows.Forms
                Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("4")
                Start-Sleep 12 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
            }
        }
        "HyperV" {
            $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Hyper-V-All" -Online).State }
            If ($Content.Value -Ne "Enabled") {
                $Address = "https://cdn3.bluestacks.com/support_files/HD-EnableHyperV.exe"
                $Fetched = Invoke-Fetcher "Webclient" "$Address"
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
                "Update-Pycharm"
                "Update-Antidote"
                "Update-Noxplayer"
                "Update-Scrcpy"
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
        If (-Not (Get-Package "$Library" -EA SI)) { Install-Package "$Library" -Scope "CurrentUser" -Source "https://www.nuget.org/api/v2" -Force -SkipDependencies }
        $Results = (Get-ChildItem -Filter "*.dll" -Recurse (Split-Path (Get-Package -Name "$Library").Source)).FullName
        $Content = $Results | Where-Object { $_ -Like "*standard2.0*" } | Select-Object -Last 1
        If ($Testing) { Try { Add-Type -Path "$Content" -EA SI } Catch { $_.Exception.LoaderExceptions } }
        Else { Try { Add-Type -Path "$Content" -EA SI } Catch {} }
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
            $Handler = Deploy-Browser
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
            $Handler = Deploy-Browser
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $Waiting = $WebPage.WaitForDownloadAsync()
            $WebPage.SetViewportSizeAsync(1400, 400).GetAwaiter().GetResult() | Out-Null
            $WebPage.GoToAsync("$Payload").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForSelectorAsync("#sh_pdf_download-2 > form > a").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(2000).GetAwaiter().GetResult() | Out-Null
            $WebPage.EvaluateAsync("document.querySelector('#sh_pdf_download-2 > form > a').click()", "").GetAwaiter().GetResult() | Out-Null
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
            $Handler = Deploy-Browser
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
    Start-Sleep 4 ; Restart-Computer -Force

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
            $Handler = Deploy-Browser
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
            $Handler = Deploy-Browser
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
            $Handler = Deploy-Browser
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
        [ValidateSet("HyperV", "Sleeping", "Uac")] [String] $Feature
    )

    Switch ($Feature) {
        "HyperV" {
            $Content = Invoke-Gsudo { (Get-WindowsOptionalFeature -FE "Microsoft-Hyper-V-All" -Online).State }
            If ($Content.Value -Eq "Enabled") {
                $Address = "https://cdn3.bluestacks.com/support_files/HD-DisableHyperV_native_v2.exe"
                $Fetched = Invoke-Fetcher "Webclient" "$Address"
                # $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
                # (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
                Invoke-Gsudo { Start-Process "$Using:Fetched" ; Start-Sleep 10 ; Stop-Process -Name "HD-DisableHyperV" }
                If (Assert-Pending -Eq $True) { Invoke-Restart }
            }
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
            Try { Start-Process "powershell" "-ep bypass -file `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait } Catch { }
            Remove-Item "$Created" -Force
        }
    }

}

Function Update-Element {

    Param(
        [ValidateSet("Computer", "Plan", "Timezzone")] [String] $Element,
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
        "Timezzone" {
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

Function Update-Antidote {

    Param(
        [Switch] $Autorun
    )

    $Starter = (Get-Item "$Env:ProgramFiles\Drui*\Anti*\Appl*\Bin6*\Antidote.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"
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
        Import-Library "Interop.UIAutomationClient"
        Import-Library "FlaUI.Core"
        Import-Library "FlaUI.UIA3"
        Import-Library "System.Drawing.Common"
        Import-Library "System.Security.Permissions"
        $Handler = [FlaUI.UIA3.UIA3Automation]::New()
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
    }

    If (-Not $Autorun) {
        Invoke-Gsudo { Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "AgentConnectix64" -EA SI }
    }

}

Function Update-Bluestacks {

    Param(
        [ValidateSet("7", "9", "11")] [String] $Android = "11"
    )

    $Starter = (Get-Item "$Env:ProgramFiles\BlueStacks*\HD-Player.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Address = "https://support.bluestacks.com/hc/en-us/articles/4402611273485-BlueStacks-5-offline-installer"
    $Results = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "windows/nxt/([\d.]+)/(?<sha>[0-9a-f]+)/")
    $Version = $Results.Groups[1].Value
    $Hashing = $Results.Groups[2].Value
    $Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 6))

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
        $Altered = (Get-Item "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs\BlueStacks*.lnk" -EA SI).FullName
        If ($Null -Ne $Altered) {
            $Content = [IO.File]::ReadAllBytes("$Altered")
            $Content[0x15] = $Content[0x15] -Bor 0x20
            Invoke-Gsudo { [IO.File]::WriteAllBytes("$Using:Altered", $Using:Content) }
        }
    }

}

Function Update-DbeaverUltimate {

    Update-MicrosoftOpenjdk
    $BaseDir = "$Env:ProgramFiles\DBeaverUltimate"
    $Starter = (Get-Item "$BaseDir\Uninstall.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"
    $Address = "https://filecr.com/windows/dbeaver-ultimate"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "<title>DBeaver ([\d.]+) .*</title>").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated -Or $True) {
        $Fetched = Invoke-Fetcher "Filecr" "$Address"
        $Deposit = Invoke-Extract -Archive "$Fetched" -Secrets "123"
        $RootDir = (Get-Item "$Deposit\D*").FullName
        $Program = (Get-Item "$RootDir\dbeaver*.exe").FullName
        Invoke-Gsudo { Start-Process "$Using:Program" "/S /allusers" -Wait }
        If (-Not $Present -Or $True) {
            # Handle archives
            $RarFile = (Get-Item "$RootDir\*.rar").FullName
            $Extract = Invoke-Extract -Archive "$RarFile"
            $RarFile = (Get-Item "$Extract\*.rar").FullName
            $Extract = Invoke-Extract -Archive "$RarFile"
            $JarFile = (Get-Item "$Extract\*.jar").FullName
            # $JarFile = "C:\Users\Admin\AppData\Local\Temp\acfdbf21-ec3c-4458-b29d-583623ccd9a0\dvt-DBeaver-KeyMaker.jar"
            # Launch jar file
            $Current = $Script:MyInvocation.MyCommand.Path
            Invoke-Gsudo {
                . $Using:Current ; Start-Sleep 4
                Import-Library "Interop.UIAutomationClient"
                Import-Library "FlaUI.Core"
                Import-Library "FlaUI.UIA3"
                Import-Library "System.Drawing.Common"
                Import-Library "System.Security.Permissions"
                Start-Process "java" "-jar `"$Using:JarFile`"" 
                $Handler = [FlaUI.UIA3.UIA3Automation]::New()
                Start-Sleep 8 ; $Desktop = $Handler.GetDesktop()
                $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByClassName("SunAwtFrame"))
                $Window1.Focus()
                # Insert name
                $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::CONTROL
                $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::KEY_A
                Start-Sleep 4 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type("$Env:Username")
                # Insert company
                [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type(" ")
                # Insert email
                [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
                Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type(" ")
                # Gather license
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                Start-Sleep 1 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
                # Invoke patch
                [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
                [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
                # Handle patching
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
                # Invoke exit
                Start-Sleep 2 ; Stop-Process -Name "java" -EA SI ; Start-Sleep 2
                # Handle windows security alert dialog
                Try {
                    Start-Process "$Using:BaseDir\dbeaver.exe" ; Start-Sleep 20
                    $Desktop = $Handler.GetDesktop()
                    $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByName("Windows Security Alert"))
                    $Button1 = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Allow access"))
                    $Button1.Click()
                }
                Catch {}
                Start-Sleep 4 ; Stop-Process -Name "dbeaver" -EA SI
                # Import license
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
                # Finish process
                Stop-Process -Name "dbeaver" -EA SI
            }
        }
    }

}

Function Update-Gsudo {

    $Starter = "${Env:ProgramFiles(x86)}\gsudo\gsudo.exe"
    $Current = Try { (Get-Item "$Starter" -EA SI).VersionInfo.FileVersion.ToString() } Catch { "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"
    $Address = "https://api.github.com/repos/gerardog/gsudo/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    Try {
        If (-Not $Updated) {
            $Results = (Invoke-Scraper "Json" "$Address").assets
            $Address = $Results.Where( { $_.browser_download_url -Like "*.msi" } ).browser_download_url
            # $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
            # (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
            $Fetched = Invoke-Fetcher "Webclient" "$Address"
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

Function Update-Ldplayer {

    $Starter = (Get-Item "C:\LDPlayer\LDPlayer*\dnplayer.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Address = "https://www.ldplayer.net/other/version-history-and-release-notes.html"
    $Version = [Regex]::Matches((Invoke-Scraper "Html" "$Address"), "LDPlayer_([\d.]+).exe").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 6)

    If (-Not $Updated) {
        $Address = "https://encdn.ldmnq.com/download/package/LDPlayer_$Version.exe"
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        $Current = $Script:MyInvocation.MyCommand.Path
        Invoke-Gsudo {
            . $Using:Current ; Start-Sleep 4
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
            Start-Sleep 4 ; $Started.Dispose() | Out-Null ; $Handler.Dispose() | Out-Null
        }
        Remove-Desktop "LDM*.lnk" ; Remove-Desktop "LDP*.lnk"
    }

}

Function Update-MicrosoftOpenjdk {

    $Starter = (Get-Item "$Env:ProgramFiles\Microsoft\jdk-*\bin\java.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    # $Present = $Current -Ne "0.0.0.0"
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

Function Update-Nanazip {

    $Starter = "$Env:LocalAppData\Microsoft\WindowsApps\7z.exe"
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Address = "https://api.github.com/repos/m2team/nanazip/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-Scraper "Json" "$Address").assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*.msixbundle" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Webclient" "$Address"
        Add-AppxPackage -Path "$Fetched" -DeferRegistrationWhenPackagesAreInUse -ForceUpdateFromAnyVersion
    }

}

Function Update-Noxplayer {

    $Starter = "${Env:ProgramFiles(x86)}\Nox\bin\Nox.exe"
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Address = "https://support.bignox.com/en/win-release"
    $Version = [Regex]::Matches((Invoke-Scraper "BrowserHtml" "$Address"), ".*V([\d.]+) Release Note").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://www.bignox.com/en/download/fullPackage/win_64_9?formal"
        $Fetched = Invoke-Fetcher "Browser" "$Address"
        $Current = $Script:MyInvocation.MyCommand.Path
        Invoke-Gsudo {
            . $Using:Current ; Start-Sleep 4
            Import-Library "Interop.UIAutomationClient"
            Import-Library "FlaUI.Core"
            Import-Library "FlaUI.UIA3"
            Import-Library "System.Drawing.Common"
            Import-Library "System.Security.Permissions"
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

Function Update-Powershell {

    $Starter = (Get-Item "$Env:ProgramFiles\PowerShell\*\pwsh.exe" -EA SI).FullName
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Address = "https://api.github.com/repos/powershell/powershell/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        Invoke-Gsudo {
            $ProgressPreference = "SilentlyContinue"
            Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet" *> $Null
        }
    }

    If ($PSVersionTable.PSVersion -Lt [Version] "7.0.0.0") { Invoke-Restart }

}

Function Update-Pycharm {

    Param (
        [String] $Deposit = "$Env:userProfile\Projects",
        [String] $Margins = 140
    )

    Update-Jetbra
    $Starter = "$Env:ProgramFiles\JetBrains\PyCharm\bin\pycharm64.exe"
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"
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
        # Gather activation code
        $License = Invoke-Scraper "Jetbra" "PyCharm"
        $License = $License.Substring(0, 1) + "$License"
        # Launch pycharm application
        Import-Library "Interop.UIAutomationClient"
        Import-Library "FlaUI.Core"
        Import-Library "FlaUI.UIA3"
        Import-Library "System.Drawing.Common"
        Import-Library "System.Security.Permissions"
        $Handler = [FlaUI.UIA3.UIA3Automation]::New()
        $Started = [FlaUI.Core.Application]::Launch("$Starter")
        $Window1 = $Started.GetMainWindow($Handler)
        $Window1.Focus()
        # Handle first dialog
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        # Handle second dialog
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        # Select activation code
        $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
        $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::KEY_C
        Start-Sleep 8 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
        # Insert activation code
        Start-Sleep 8 ; [FlaUI.Core.Input.Keyboard]::Type("$License")
        Start-Sleep 4 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE)
        # Handle windows security alert dialog
        Start-Sleep 8 ; $Desktop = $Handler.GetDesktop()
        $Window1 = $Desktop.FindFirstDescendant($Handler.ConditionFactory.ByName("Windows Security Alert"))
        $Button1 = $Window1.FindFirstDescendant($Handler.ConditionFactory.ByName("Allow access"))
        $Button1.Click()
        # Finish pycharm window
        $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::ALT
        $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::F4
        Start-Sleep 2 ; [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
        # Finish pycharm process
        Start-Sleep 4 ; Stop-Process -Name "pycharm64" -EA SI
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

    # Handle security
    $Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
    $Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
    Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Feature "Uac" ; Remove-Feature "Sleeping"
    $Correct = (Update-Gsudo) -And ! (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
    If (-Not $Correct) { Write-Host "$Failure`n" -FO Red ; Exit } ; Update-Powershell

    Update-DbeaverUltimate ; Exit

    # Handle elements
    $Members = Export-Members -Variant "Development" -Machine "WINHOGEN"

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
    Enable-Feature "Uac" ; Enable-Feature "Sleeping" ; gsudo -k *> $Null

    # Output new line
    Write-Host "`n"

}