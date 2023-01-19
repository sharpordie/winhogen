#Region Services

Function Assert-Pending {

    If (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -EA Ignore) { Return $True }
    If (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -EA Ignore) { Return $True }
    If (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -EA Ignore) { Return $True }
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
        [ValidateSet("Uac")] [String] $Feature
    )

    Switch ($Feature) {
        "Uac" {
            $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
            [IO.File]::WriteAllText("$Created", @(
                    '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
                    'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 5'
                    'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 1'
                ) -Join "`n")
            Start-Process "powershell" "-ep bypass -f `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait
            Remove-Item "$Created" -Force
        }
    }

    If (Assert-Pending -Eq $True) { Invoke-Restart }

}

Function Expand-Archive {

    Param (
        [String] $Archive,
        [String] $Deposit,
        [String] $Secrets
    )

    $Starter = "$Env:LocalAppData\Microsoft\WindowsApps\7z.exe"
    If (-Not (Test-Path "$Starter")) { Update-Nanazip }
    If (-Not $Deposit) { $Deposit = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName }
    If (-Not (Test-Path "$Deposit")) { New-Item "$Deposit" -ItemType Directory -EA SI }
    Start-Process "$Starter" "x `"$Archive`" -o`"$Deposit`" -p`"$Secrets`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
    Return "$Deposit"

}

Function Expand-Version {

    Param (
        [String] $Payload
    )

    If ([String]::IsNullOrWhiteSpace($Payload)) { Return "0.0.0.0" }

    $Version = (Get-Package "$Payload" -EA SI).Version
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = (Get-AppxPackage "$Payload" -EA SI).Version }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = "0.0.0.0" }
    # If ($Version -Eq "0.0.0.0") { $Version = Try { (Get-Command "$Payload" -EA SI).Version.ToString() } Catch { $Version } }
    If ($Version -Eq "0.0.0.0") { $Version = Try { (Get-Item "$Payload" -EA SI).VersionInfo.FileVersion.ToString() } Catch { $Version } }
    Return [Regex]::Matches($Version, "([\d.]+)").Groups[1].Value

}

Function Invoke-Fetcher {

    Param (
        [String] $Address,
        [String] $Fetched
    )

    If (-Not $Fetched) { $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)" }
    (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched") ; Return "$Fetched"

}

Function Invoke-Restart {

    $Current = "$($Script:MyInvocation.MyCommand.Path)"
    $Heading = (Get-Item "$Current").BaseName
    $ArgList = "/c start /b wt --title `"$Heading`" powershell -ep bypass -noexit -nologo -f `"$Current`""
    Invoke-Gsudo {
        Register-ScheduledTask `
            -TaskName "$Using:Heading" `
            -Trigger (New-ScheduledTaskTrigger -AtLogOn) `
            -User ($Env:Username) `
            -Action (New-ScheduledTaskAction -Execute "cmd" -Argument "$Using:ArgList") `
            -RunLevel Limited `
            -Force *> $Null            
    }
    Restart-Computer -Force

}

Function Invoke-Scraper {

    Param(
        [ValidateSet("HtmlContent", "JsonContent", "GithubRelease", "GithubVersion", "MicrosoftStore")] [String] $Scraper,
        [String] $Address,
        [String] $Pattern
    )

    Add-Type -AssemblyName "System.Net.Http"
    $Manager = [Net.Http.HttpClient]::New()
    $UsAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/500.0 (KHTML, like Gecko) Chrome/100.0.0.0 Safari/500.0"
    $Manager.DefaultRequestHeaders.Add("User-Agent", "$UsAgent")

    Switch ($Scraper) {
        "HtmlContent" {
            $Content = $Manager.GetStringAsync("$Address").GetAwaiter().GetResult().ToString()
            If (-Not [String]::IsNullOrWhiteSpace($Pattern)) { $Content = ([Regex]::Matches("$Content", "$Pattern")).Groups[1].Value }
            Return $Content
        }
        "JsonContent" {
            Return Invoke-Scraper "HtmlContent" "$Address" | ConvertFrom-Json
        }
        "GithubRelease" {
            $Factors = (Invoke-Scraper "JsonContent" "$Address")[0].assets
            Return $Factors.Where( { $_.browser_download_url -Like "$Pattern" } ).browser_download_url
        }
        "GithubVersion" {
            Return [Regex]::Match((Invoke-Scraper "JsonContent" "$Address")[0].tag_name, "[\d.]+").Value
        }
        "MicrosoftStore" {
            $Content = Invoke-WebRequest `
                -UseBasicParsing `
                -Uri "https://store.rg-adguard.net/api/GetFiles" `
                -Method "POST" `
                -ContentType "application/x-www-form-urlencoded" `
                -Body "type=url&url=$Address&ring=RP&lang=en-US"
            Return [Regex]::Matches($Content.Links.Where({ $_ -Like "$Pattern" }).OuterHTML, "href=`"(.*)(?=`"\s)").Groups[1].Value
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
        [ValidateSet("HyperV", "Uac")] [String] $Feature
    )

    Switch ($Feature) {
        "HyperV" { 
            $Address = "https://cdn3.bluestacks.com/support_files/HD-DisableHyperV_native_v2.exe"
            $Fetched = Invoke-Fetcher "$Address"
            Invoke-Gsudo { Start-Process "$Using:Fetched" ; Start-Sleep 10 ; Stop-Process -Name "HD-DisableHyperV" }
        }
        "Uac" {
            $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
            [IO.File]::WriteAllText("$Created", @(
                    '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
                    'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 0'
                    'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 0'
                ) -Join "`n")
            Start-Process "powershell" "-ep bypass -f `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait
            Remove-Item "$Created" -Force
        }
    }

    If (Assert-Pending -Eq $True) { Invoke-Restart }

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

Function Update-PowPlan {

    Param (
        [ValidateSet("Balanced", "High", "Power", "Ultimate")] [String] $Payload = "Balanced"
    )

    $Program = "C:\Windows\System32\powercfg.exe"
    $Picking = (Invoke-Expression "$Program /l" | ForEach-Object { If ($_.Contains("($Payload")) { $_.Split()[3] } })
    If ([String]::IsNullOrEmpty("$Picking")) { Start-Process "$Program" "/duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61" -NoNewWindow -Wait }
    $Picking = (Invoke-Expression "$Program /l" | ForEach-Object { If ($_.Contains("($Payload")) { $_.Split()[3] } })
    Start-Process "$Program" "/s $Picking" -NoNewWindow -Wait

    If ($Payload -Eq "Ultimate") {
        $Desktop = $Null -Eq (Get-WmiObject Win32_SystemEnclosure -ComputerName "localhost" | Where-Object ChassisTypes -In "{9}", "{10}", "{14}")
        $Desktop = $Desktop -Or $Null -Eq (Get-WmiObject Win32_Battery -ComputerName "localhost")
        If (-Not $Desktop) { Start-Process "$Program" "/setacvalueindex $Picking sub_buttons lidaction 000" -NoNewWindow -Wait }
    }

}

Function Update-SysPath {
    
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

    $SdkHome = "$Env:LocalAppData\Android\Sdk"
    $Starter = "$SdkHome\cmdline-tools\latest\bin\sdkmanager.bat"
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-90)
    If (-Not $Updated) {
        $Address = "https://developer.android.com/studio#command-tools"
        $Release = Invoke-Scraper "HtmlContent" "$Address" "commandlinetools-win-(\d+)"
        $Address = "https://dl.google.com/android/repository/commandlinetools-win-${Release}_latest.zip"
        $Fetched = Invoke-Fetcher "$Address"
        $Deposit = Expand-Archive "$Fetched"
        New-Item "$SdkHome" -ItemType Directory -EA SI
        Update-Temurin ; $Manager = "$Deposit\cmdline-tools\bin\sdkmanager.bat"
        Invoke-Expression "echo $("yes " * 10) | & `"$Manager`" --sdk_root=`"$SdkHome`" `"cmdline-tools;latest`""
    }

    Invoke-Gsudo { [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$Using:SdkHome", "Machine") }
    [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$SdkHome", "Process")
    Update-SysPath "$SdkHome\cmdline-tools\latest\bin" "Machine"
    Update-SysPath "$SdkHome\emulator" "Machine"
    Update-SysPath "$SdkHome\platform-tools" "Machine"

}

Function Update-AndroidStudio {

    $Starter = "$Env:ProgramFiles\Android\Android Studio\bin\studio64.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://raw.githubusercontent.com/scoopinstaller/extras/master/bucket/android-studio.json"
    $Version = (Invoke-Scraper "JsonContent" "$Address").version
    $Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 6))
    If (-Not $Updated) {
        $Address = "https://redirector.gvt1.com/edgedl/android/studio/install/$Version/android-studio-$Version-windows.exe"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
    }

    If (-Not $Present) {
        Update-AndroidCmdline
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'build-tools;33.0.1'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'emulator'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'extras;intel;Hardware_Accelerated_Execution_Manager'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'platform-tools'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'platforms;android-33'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'platforms;android-33-ext4'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'sources;android-33'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'system-images;android-33;google_apis;x86_64'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager --licenses"
        Invoke-Expression "avdmanager create avd -n 'Pixel_3_API_33' -d 'pixel_3' -k 'system-images;android-33;google_apis;x86_64'"
    }

    If (-Not $Present) {
        Add-Type -AssemblyName System.Windows.Forms
        Start-Process "$Starter" ; Start-Sleep 10
        [Windows.Forms.SendKeys]::SendWait("{TAB}") ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 20
        [Windows.Forms.SendKeys]::SendWait("{TAB}" * 2) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
        [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
        [Windows.Forms.SendKeys]::SendWait("{TAB}" * 2) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
        [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
        [Windows.Forms.SendKeys]::SendWait("{TAB}" * 3) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
        [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 6
        [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
    }
    
}

Function Update-Chromium {

    Param (
        [String] $Deposit = "$Env:UserProfile\Downloads\DDL",
        [String] $Startup = "about:blank"
    )

    $Starter = "$Env:ProgramFiles\Chromium\Application\chrome.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://api.github.com/repos/macchrome/winchrome/releases/latest"
    $Version = Invoke-Scraper "GithubVersion" "$Address"
    $Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 3) + ".0")
    If (-Not $Updated) {
        $Address = Invoke-Scraper "GithubRelease" "$Address" "*installer.exe"
        $Fetched = Invoke-Fetcher "$Address"
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
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

        Start-Process "$Starter" "--lang=en --start-maximized"
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
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

        Start-Process "$Starter" "--lang=en --start-maximized"
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://settings/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("search engines")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 3)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("duckduckgo")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

        Start-Process "$Starter" "--lang=en --start-maximized"
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("extension-mime-request-handling")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 2)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

        Start-Process "$Starter" "--lang=en --start-maximized"
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("hide-sidepanel-button")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

        Start-Process "$Starter" "--lang=en --start-maximized"
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("remove-tabsearch-button")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

        Start-Process "$Starter" "--lang=en --start-maximized"
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("win-10-tab-search-caption-button")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 2)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

        Start-Process "$Starter" "--lang=en --start-maximized"
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("show-avatar-button")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 3)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
        Start-Process "$Starter" "--lang=en --start-maximized"
        Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("^+b")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
        Remove-Desktop "Chromium*.lnk"

        $Address = "https://api.github.com/repos/NeverDecaf/chromium-web-store/releases/latest"
        Update-ChromiumExtension (Invoke-Scraper "GithubRelease" "$Address" "*.crx")

        Update-ChromiumExtension "omoinegiohhgbikclijaniebjpkeopip" # clickbait-remover-for-you
        Update-ChromiumExtension "bcjindcccaagfpapjjmafapmmgkkhgoa" # json-formatter
        Update-ChromiumExtension "ibplnjkanclpjokhdolnendpplpjiace" # simple-translate
        Update-ChromiumExtension "mnjggcdmjocbbbhaepdhchncahnbgone" # sponsorblock-for-youtube
        Update-ChromiumExtension "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock-origin
    }

    Update-ChromiumExtension "https://github.com/iamadamdev/bypass-paywalls-chrome/archive/master.zip"

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
            $Package = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
            Invoke-Fetcher "$Address" "$Package"
        }
        Else {
            $Version = Try { (Get-Item "$Starter" -EA SI).VersionInfo.FileVersion.ToString() } Catch { "0.0.0.0" }
            $Address = "https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3"
            $Address = "${Address}&prodversion=${Version}&x=id%3D${Payload}%26installsource%3Dondemand%26uc"
            $Package = Join-Path "$Env:Temp" "$Payload.crx"
            Invoke-Fetcher "$Address" "$Package"
        }
        If ($Null -Ne $Package -And (Test-path "$Package")) {
            Add-Type -AssemblyName System.Windows.Forms
            If ($Package -Like "*.zip") {
                $Deposit = "$Env:ProgramFiles\Chromium\Unpacked\$($Payload.Split("/")[4])"
                $Present = Test-Path "$Deposit"
                Invoke-Gsudo { New-Item "$Using:Deposit" -ItemType Directory -EA SI }
                $Extract = Expand-Archive "$Package"
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

Function Update-Figma {

    $Starter = "$Env:LocalAppData\Figma\Figma.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://desktop.figma.com/win/RELEASE.json"
    $Version = (Invoke-Scraper "JsonContent" "$Address").version
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://desktop.figma.com/win/FigmaSetup.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $ArgList = "/s /S /q /Q /quiet /silent /SILENT /VERYSILENT"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
    }

    If (-Not $Present) {
        Start-Process "$Starter" ; Start-Sleep 8 ; Stop-Process -Name "Figma" ; Stop-Process -Name "figma_agent" ; Start-Sleep 5
        $Configs = Get-Content "$Env:AppData\Figma\settings.json" | ConvertFrom-Json
        Try { $Configs.showFigmaInMenuBar = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "showFigmaInMenuBar" -Value $False }
        $Configs | ConvertTo-Json | Set-Content "$Env:AppData\Figma\settings.json"
    }

}

Function Update-Flutter {

    $Deposit = "$Env:LocalAppData\Android\Flutter"
    Update-Git ; Invoke-Expression "git clone https://github.com/flutter/flutter.git -b stable $Deposit"
    Update-SysPath "$Deposit\bin" "Machine"

    Invoke-Expression "flutter channel stable"
    Invoke-Expression "flutter precache" ; Invoke-Expression "flutter upgrade"
    Invoke-Expression "echo $("yes " * 10) | flutter doctor --android-licenses"
    Invoke-Expression "dart --disable-analytics"
    Invoke-Expression "flutter config --no-analytics"

    $Product = "$Env:ProgramFiles\Android\Android Studio"
    Update-JetbrainsPlugin "$Product" "6351"  # dart
    Update-JetbrainsPlugin "$Product" "9212"  # flutter
    Update-JetbrainsPlugin "$Product" "13666" # flutter-intl
    Update-JetbrainsPlugin "$Product" "14641" # flutter-riverpod-snippets

    Start-Process "code" "--install-extension Dart-Code.flutter --force" -WindowStyle Hidden -Wait
    Start-Process "code" "--install-extension alexisvt.flutter-snippets --force" -WindowStyle Hidden -Wait
    Start-Process "code" "--install-extension pflannery.vscode-versionlens --force" -WindowStyle Hidden -Wait
    Start-Process "code" "--install-extension robert-brunhage.flutter-riverpod-snippets --force" -WindowStyle Hidden -Wait
    Start-Process "code" "--install-extension usernamehw.errorlens --force" -WindowStyle Hidden -Wait

}

Function Update-Git {

    Param (
        [String] $Default = "main",
        [String] $GitMail,
        [String] $GitUser
    )
    
    $Starter = "$Env:ProgramFiles\Git\git-bash.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://git-scm.com/download/win"
    $Version = Invoke-Scraper "HtmlContent" "$Address" "<strong>([\d.]+)</strong>"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://github.com/git-for-windows/git/releases/download"
        $Address = "$Address/v$Version.windows.1/Git-$Version-64-bit.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $ArgList = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART, /NOCANCEL, /SP- /COMPONENTS=`"`""
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
    }
    
    Update-SysPath "$Env:ProgramFiles\Git\cmd" "Process"
    If ($Null -Ne $GitMail) { Invoke-Expression "git config --global user.email '$GitMail'" }
    If ($Null -Ne $GitUser) { Invoke-Expression "git config --global user.name '$GitUser'" }
    Invoke-Expression "git config --global http.postBuffer 1048576000"
    Invoke-Expression "git config --global init.defaultBranch '$Default'"
    
}

Function Update-Gsudo {

    $Starter = "${Env:ProgramFiles(x86)}\gsudo\gsudo.exe"
    $Current = Expand-Version "$Starter"
    $Present = Test-Path "$Starter"
    $Address = "https://api.github.com/repos/gerardog/gsudo/releases/latest"
    $Version = Invoke-Scraper "GithubVersion" "$Address"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    Try {
        Update-SysPath "$(Split-Path "$Starter" -Parent)" "Process"
        If (-Not $Updated) {
            $Address = Invoke-Scraper "GithubRelease" "$Address" "*.msi"
            $Fetched = Invoke-Fetcher "$Address"
            If (-Not $Present) { Start-Process "msiexec" "/i `"$Fetched`" /qn" -Verb RunAs -Wait }
            Else { Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" /qn" -Wait } }
        }
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
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "-q" -Wait }
        Remove-Desktop "JDownloader*.lnk"
        New-Item "$Deposit" -ItemType Directory -EA SI
        Update-ChromiumExtension "fbcohnmimjicjdomonkcbcpbpnhggkip"
    }

    If (-Not $Present) {
        $AppData = "$Env:ProgramFiles\JDownloader\cfg"
        $Config1 = "$AppData\org.jdownloader.settings.GeneralSettings.json"
        $Config2 = "$AppData\org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
        $Config3 = "$AppData\org.jdownloader.gui.jdtrayicon.TrayExtension.json"
        $Config4 = "$AppData\org.jdownloader.extensions.extraction.ExtractionExtension.json"
        Start-Process "$Starter" ; Start-Sleep 12 ; While (-Not (Test-Path -Path "$Config1")) { Start-Sleep 2 }
        Stop-Process -Name "JDownloader2" ; Start-Sleep 2
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
        Try { $Configs.enabled = "$Deposit" } Catch { $Configs | Add-Member -Type NoteProperty -Name "enabled" -Value "$Deposit" }
        Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config3" }
        $Configs = Get-Content "$Config4" | ConvertFrom-Json
        Try { $Configs.enabled = "$Deposit" } Catch { $Configs | Add-Member -Type NoteProperty -Name "enabled" -Value "$Deposit" }
        Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config4" }
    }

}

Function Update-JetbrainsPlugin {

    Param(
        [String] $Deposit = "$Env:ProgramFiles\Android\Android Studio",
        [String] $Element
    )

    If (-Not (Test-Path "$Deposit") -Or ([String]::IsNullOrWhiteSpace($Element))) { Return 0 }
    $Release = (Get-Content "$Deposit\product-info.json" | ConvertFrom-Json).buildNumber
    $Release = [Regex]::Matches("$Release", "([\d.]+)\.").Groups[1].Value
    $DataDir = (Get-Content "$Deposit\product-info.json" | ConvertFrom-Json).dataDirectoryName
    $Adjunct = If ("$DataDir" -Like "AndroidStudio*") { "Google\$DataDir" } Else { "JetBrains\$DataDir" }
    $Plugins = "$Env:AppData\$Adjunct\plugins" ; New-Item "$Plugins" -ItemType Directory -EA SI
    For ($I = 0; $I -Le 3; $I++) {
        For ($J = 0; $J -Le 19; $J++) {
            $Address = "https://plugins.jetbrains.com/api/plugins/$Element/updates?page=$I"
            $Content = Invoke-Scraper "JsonContent" "$Address"
            $Maximum = $Content["$J"].until.Replace("`"", "").Replace("*", "9999")
            $Minimum = $Content["$J"].since.Replace("`"", "").Replace("*", "9999")
            If ([Version] "$Minimum" -Le "$Release" -And "$Release" -Le "$Maximum") {
                $Address = $Content["$J"].file.Replace("`"", "")
                $Address = "https://plugins.jetbrains.com/files/$Address"
                $Fetched = Invoke-Fetcher "$Address"
                Expand-Archive "$Fetched" "$Plugins"
                Break 2
            }
            Start-Sleep 1
        }
    }

}

Function Update-Mambaforge {

    If ($Null -Eq (Get-Command "mamba" -EA SI)) {
        $Address = "https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Windows-x86_64.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $Deposit = "$Env:LocalAppData\Programs\Mambaforge"
        $ArgList = "/S /InstallationType=JustMe /RegisterPython=0 /AddToPath=1 /NoRegistry=1 /D=$Deposit"
        Start-Process "$Fetched" "$ArgList" -Wait
        Update-SysPath -Section "User"
    }

    Invoke-Expression "conda config --set auto_activate_base false"
    Invoke-Expression "conda update --all -y"

}

Function Update-Mpv {

    $Starter = "$Env:LocalAppData\Programs\Mpv\mpv.exe"
    $Address = "https://sourceforge.net/projects/mpv-player-windows/files/64bit"
    $Version = Invoke-Scraper "HtmlContent" "$Address" "mpv-x86_64-([\d]{8})-git-([\a-z]{7})\.7z"
    $Release = Invoke-Scraper "HtmlContent" "$Address" "mpv-x86_64-[\d]{8}-git-([\a-z]{7})\.7z"
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-10)
    If (-Not $Updated) {
        $Address = "https://sourceforge.net/projects/mpv-player-windows/files/64bit/mpv-x86_64-$Version-git-$Release.7z"
        $Fetched = Invoke-Fetcher "$Address"
        $Deposit = Split-Path "$Starter"
        New-Item "$Deposit" -ItemType Directory -EA SI
        Expand-Archive "$Fetched" "$Deposit"
        $LnkFile = "$Env:AppData\Microsoft\Windows\Start Menu\Programs\Mpv.lnk"
        $Picture = Invoke-Fetcher "https://github.com/mpvnet-player/mpv.net/raw/master/src/mpvnet.ico" "$Deposit\mpv.ico"
        Update-LnkFile -LnkFile "$LnkFile" -Starter "$Starter" -Picture "$Picture"
    }

    $Shaders = Join-Path "$(Split-Path "$Starter")" "shaders"
    New-Item "$Shaders" -ItemType Directory -EA SI
    $Address = "https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl"
    $Fetched = Invoke-Fetcher "$Address" ; Move-Item "$Fetched" "$Shaders" -Force
    $Address = "https://gist.githubusercontent.com/igv/36508af3ffc84410fe39761d6969be10/raw/6998ff663a135376dbaeb6f038e944d806a9b9d9/SSimDownscaler.glsl"
    $Fetched = Invoke-Fetcher "$Address" ; Move-Item "$Fetched" "$Shaders" -Force

    $Configs = Join-Path "$(Split-Path "$Starter")" "mpv\mpv.conf"
    Set-Content -Path "$Configs" -Value "profile=gpu-hq"
    Add-Content -Path "$Configs" -Value "vo=gpu-next"
    Add-Content -Path "$Configs" -Value "hwdec=auto-copy"
    Add-Content -Path "$Configs" -Value "keep-open=yes"
    Add-Content -Path "$Configs" -Value "ytdl-format=`"bestvideo[height<=?2160]+bestaudio/best`""
    Add-Content -Path "$Configs" -Value "glsl-shaders-clr"
    Add-Content -Path "$Configs" -Value "glsl-shaders=`"~~/shaders/FSRCNNX_x2_8-0-4-1.glsl`""
    Add-Content -Path "$Configs" -Value "scale=ewa_lanczos"
    Add-Content -Path "$Configs" -Value "glsl-shaders-append=`"~~/shaders/SSimDownscaler.glsl`""
    Add-Content -Path "$Configs" -Value "dscale=mitchell"
    Add-Content -Path "$Configs" -Value "linear-downscaling=no"
    Add-Content -Path "$Configs" -Value "[protocol.http]"
    Add-Content -Path "$Configs" -Value "force-window=immediate"
    Add-Content -Path "$Configs" -Value "hls-bitrate=max"
    Add-Content -Path "$Configs" -Value "cache=yes"
    Add-Content -Path "$Configs" -Value "[protocol.https]"
    Add-Content -Path "$Configs" -Value "profile=protocol.http"
    Add-Content -Path "$Configs" -Value "[protocol.ytdl]"
    Add-Content -Path "$Configs" -Value "profile=protocol.http"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Address = "https://raw.githubusercontent.com/DanysysTeam/PS-SFTA/master/SFTA.ps1"
    Invoke-Expression ((New-Object Net.WebClient).DownloadString("$Address"))
    Register-FTA "$Starter" -Extension ".mkv"
    Register-FTA "$Starter" -Extension ".mp4"

}

Function Update-Nanazip {

    $Current = Expand-Version "*NanaZip*"
    $Address = "https://api.github.com/repos/M2Team/NanaZip/releases/latest"
    $Version = Invoke-Scraper "GithubVersion" "$Address"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = Invoke-Scraper "GithubRelease" "$Address" "*.msixbundle"
        $Fetched = Invoke-Fetcher "$Address"
        Add-AppxPackage -DeferRegistrationWhenPackagesAreInUse -ForceUpdateFromAnyVersion -Path "$Fetched"
    }

}

Function Update-Nvidia {

    Param(
        [ValidateSet("Cuda", "Game")] [String] $Variety
    )

    Switch ($Variety) {
        "Cuda" {
            $Current = Expand-Version "*CUDA Runtime*"
            $Address = "https://raw.githubusercontent.com/scoopinstaller/main/master/bucket/cuda.json"
            $Version = (Invoke-Scraper "JsonContent" "$Address").version
            $Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 4)
            If (-Not $Updated) {
                $Address = (Invoke-Scraper "JsonContent" "$Address").architecture."64bit".url.Replace("#/dl.7z", "")
                $Fetched = Invoke-Fetcher "$Address"
                Invoke-Gsudo { Start-Process "$Using:Fetched" "/s" -Wait }
                Remove-Desktop "GeForce*.lnk"
            }
        }
        "Game" {
            $Current = Expand-Version "*NVIDIA Graphics Driver*"
            $Address = "https://community.chocolatey.org/packages/geforce-game-ready-driver"
            $Version = Invoke-Scraper "HtmlContent" "$Address" "Geforce Game Ready Driver ([\d.]+)</title>"
            $Updated = [Version] "$Current" -Ge [Version] "$Version"
            If (-Not $Updated) {
                $Address = "https://us.download.nvidia.com/Windows/$Version/$Version-desktop-win10-win11-64bit-international-dch-whql.exe"
                $Fetched = Invoke-Fetcher "$Address"
                $Deposit = Expand-Archive "$Fetched"
                Invoke-Gsudo { Start-Process "$Using:Deposit\setup.exe" "Display.Driver HDAudio.Driver -clean -s -noreboot" -Wait }
            }
        }
    }

}

Function Update-Postgresql {

    Param (
        [Int] $Leading = 14
    )

    $Starter = "$Env:ProgramFiles\PostgreSQL\$Leading\bin\psql.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://raw.githubusercontent.com/scoopinstaller/versions/master/bucket/postgresql$Leading.json"
    $Version = (Invoke-Scraper "JsonContent" "$Address").version
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://get.enterprisedb.com/postgresql/postgresql-$Version-1-windows-x64.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $ArgList = '--unattendedmodeui none --mode unattended --superpassword "password" --servicename "PostgreSQL" --servicepassword "password" --serverport 5432'
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
    }

}

Function Update-Python {

    Param (
        [Int] $Leading = 3,
        [Int] $Backing = 10
    )

    $Current = Expand-Version "*python*"
    $Address = "https://www.python.org/downloads/windows/"
    $Version = Invoke-Scraper "HtmlContent" "$Address" "python-($Leading\.$Backing\.[\d.]+)-"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Ongoing = Invoke-Gsudo { [Environment]::GetEnvironmentVariable("PATH", "Machine") }
        $Changed = "$Ongoing" -Replace "C:\\Program Files\\Python[\d]+\\Scripts\\;" -Replace "C:\\Program Files\\Python[\d]+\\;"
        Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PATH", "$Using:Changed", "Machine") }
        $Address = "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe"
        $ArgList = "/quiet InstallAllUsers=1 AssociateFiles=0 PrependPath=1 Shortcuts=0 Include_launcher=0 InstallLauncherAllUsers=0"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Update-SysPath "$Env:ProgramFiles\Python$Leading$Backing\" "Machine" -Prepend
        Update-SysPath "$Env:ProgramFiles\Python$Leading$Backing\Scripts\" "Machine" -Prepend
        Invoke-Gsudo { Start-Process "python" "-m pip install --upgrade pip" -WindowStyle Hidden -Wait }
        Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "1", "Machine") }
    }

    If ($Null -Eq (Get-Command "poetry" -EA SI)) {
        New-Item "$Env:AppData\Python\Scripts" -ItemType Directory -EA SI
        $Address = "https://install.python-poetry.org/"
        $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "install-poetry.py")
        Start-Process "python" "`"$Fetched`" --uninstall" -WindowStyle Hidden -Wait
        Start-Process "python" "$Fetched" -WindowStyle Hidden -Wait
        Update-SysPath "$Env:AppData\Python\Scripts" "Machine"
        Start-Process "poetry" "config virtualenvs.in-project true" -WindowStyle Hidden -Wait
    }
    Else {
        Start-Process "poetry" "self update" -WindowStyle Hidden -Wait
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
    $Version = Invoke-Scraper "HtmlContent" "$Address" "Latest:\s+v([\d.]+)"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://downloads.sourceforge.net/project/qbittorrent/qbittorrent-win32/qbittorrent-$Version/qbittorrent_${Version}_x64_setup.exe"
        $Fetched = Invoke-Fetcher "$Address"
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

Function Update-Temurin {

    $Current = Expand-Version "*Temurin*"
    $Present = "$Current" -Ne "0.0.0.0"
    $Address = "https://api.github.com/repos/adoptium/temurin19-binaries/releases/latest"
    $Version = Invoke-Scraper "GithubVersion" "$Address"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = Invoke-Scraper "GithubRelease" "$Address" "*jdk_x64_windows*.msi"
        $Fetched = Invoke-Fetcher "$Address"
        $Adjunct = If ($Present) { "REINSTALL=ALL REINSTALLMODE=amus" } Else { "INSTALLLEVEL=1" }
        Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" $Using:Adjunct /quiet" -Wait }
        Update-SysPath -Deposit "" -Section "Machine"
    }

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
    $Version = Invoke-Scraper "HtmlContent" "$Address" "url>ws/($Leading.[\d.]+)/(\d+)/windows/core"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://www.vmware.com/go/getworkstation-win"
        # $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "vmware-workstation-full.exe")
        $Fetched = Join-Path "$Env:Temp" "vmware-workstation-full.exe"
        $ArgList = "/s /v/qn EULAS_AGREED=1 AUTOSOFTWAREUPDATE=0 DATACOLLECTION=0 ADDLOCAL=ALL REBOOT=ReallySuppress SERIALNUMBER=$Serials"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Remove-Desktop "VMware*.lnk"
        Start-Process "$Starter" -WindowStyle Hidden ; Start-Sleep 10
        Stop-Process -Name "vmware" ; Start-Sleep 2
        Set-ItemProperty -Path "HKCU:\Software\VMware, Inc.\VMware Tray" -Name "TrayBehavior" -Type DWord -Value 2
    }

    If (-Not $Present) {
        $Address = "https://api.github.com/repos/DrDonk/unlocker/releases/latest"
        $Address = Invoke-Scraper "GithubRelease" "$Address" "*.zip"
        $Fetched = Invoke-Fetcher "$Address"
        $Extract = Expand-Archive "$Fetched"
        $Program = Join-Path "$Extract" "windows\unlock.exe"
        Invoke-Gsudo {
            [Environment]::SetEnvironmentVariable("UNLOCK_QUIET", "1", "Process")
            Start-Process "$Using:Program" -WindowStyle Hidden
        }
    }

    If ($Deposit) {
        New-Item -Path "$Deposit" -ItemType Directory -EA SI | Out-Null
        $Configs = "$Env:AppData\VMware\preferences.ini"
        If (-Not ((Get-Content "$Configs") -Match "prefvmx.defaultVMPath")) { Add-Content -Path "$Configs" -Value "prefvmx.defaultVMPath = `"$Deposit`"" }
    }

}

Function Update-Wsa {

    $Current = Expand-Version "*WindowsSubsystemForAndroid*"
    $Present = "$Current" -Ne "0.0.0.0"
    If (-Not $Present) {
        $Address = Invoke-Scraper "MicrosoftStore" "www.microsoft.com/en-us/p/windows-subsystem-for-android/9p3395vx91nr" "*Microsoft.UI.Xaml*x64*appx*"
        $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "9p3395vx91nr.appx")
        Add-AppxPackage -Path "$Fetched"
        $Address = Invoke-Scraper "MicrosoftStore" "www.microsoft.com/en-us/p/windows-subsystem-for-android/9p3395vx91nr" "*msixbundle*"
        $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "9p3395vx91nr.msixbundle")
        Invoke-Gsudo { Add-AppxPackage -Path "$Using:Fetched" }
    }

}

Function Update-YtDlg {

    $Starter = "$Env:LocalAppData\Programs\YtDlp\yt-dlp.exe"
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-10)
    If (-Not $Updated) {
        $Address = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        $Deposit = Split-Path "$Starter"
        New-Item "$Deposit" -ItemType Directory -EA SI
        Invoke-Fetcher "$Address" "$Starter"
        Update-SysPath "$Deposit" "Machine"
    }

}

Function Main {

    # Change headline
    $Current = "$($Script:MyInvocation.MyCommand.Path)"
    $Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName

    # Output greeting
    Clear-Host ; $ProgressPreference = "SilentlyContinue"
    Write-Host "+----------------------------------------------------------+"
    Write-Host "|                                                          |"
    Write-Host "|  > WINHOGEN                                              |"
    Write-Host "|                                                          |"
    Write-Host "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                   |"
    Write-Host "|                                                          |"
    Write-Host "+----------------------------------------------------------+"
    
    # Remove security
    $Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
    $Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
    Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Feature "Uac" ; Update-PowPlan "Ultimate"
    $Correct = (Update-Gsudo) -And -Not (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
    If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

    # Remove schedule
    $Payload = (Get-Item "$Current").BaseName
    Invoke-Gsudo { Unregister-ScheduledTask -TaskName "$Using:Payload" -Confirm:$False -EA SI }

    # Handle elements
    $Factors = @(
        "Update-Nvidia Cuda"
        "Update-AndroidStudio"
        "Update-Chromium"
        "Update-Git -GitMail 72373746+sharpordie@users.noreply.github.com -GitUser sharpordie"

        "Update-Flutter"
        "Update-Postgresql"
        "Update-Python"
        "Update-Wsa"

        "Update-Figma"
        "Update-Jdownloader"
        "Update-Mambaforge"
        "Update-Mpv"
        "Update-Qbittorrent"
        "Update-VmwareWorkstation"
        "Update-YtDlg"
    )
    
    # Output progress
    $Maximum = (60 - 20) * -1
    $Shaping = "`r{0,$Maximum}{1,-3}{2,-6}{3,-3}{4,-8}"
    $Heading = "$Shaping" -F "FUNCTION", " ", "STATUS", " ", "DURATION"
    Write-Host "$Heading"
    Foreach ($Element In $Factors) {
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
    Invoke-Expression "gsudo -k" *> $Null ; Enable-Feature "Uac"
    
    # Output new line
    Write-Host "`n"

}

Main