#Region Services

Function Assert-Pending {

    $Session = Get-Item "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $Factors = $Session.GetValue("PendingFileRenameOperations")
    If ($Null -Eq $Factors) { $False }
    Else {
        $Maximum = $Factors.Length / 2
        $Renames = [Collections.Generic.Dictionary[String, String]]::New($Maximum)
        For ($I = 0; $I -Ne $Maximum; $I++) {
            $Current = $Factors[$I * 2]
            $Deposit = $Factors[$I * 2 + 1]
            If ($Deposit.Length -Ne 0) { $Renames[$Current] = $Deposit }
        }
        $Renames.Count -Gt 0
    }
    
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
    If ($Version -Eq "0.0.0.0") { $Version = Try { (Get-Command "$Payload" -EA SI).Version.ToString() } Catch { $Version } }
    If ($Version -Eq "0.0.0.0") { $Version = Try { (Get-Item "$Payload" -EA SI).VersionInfo.FileVersion.ToString() } Catch { $Version } }
    If ($Version -Eq "0.0.0.0") { $Version = Try { Invoke-Expression "& `"$Payload`" --version" -EA SI } Catch { $Version } }
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
        "Update-Wsa"
        "Update-AndroidStudio"
        "Update-Git -GitMail 72373746+sharpordie@users.noreply.github.com -GitUser sharpordie"
        "Update-Flutter"
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