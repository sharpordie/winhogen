Function Update-SysPath {

    Param (
        [String] $Payload,
        [ValidateSet("Machine", "Process", "User")] [String] $Section,
        [Switch] $Prepend
    )

    If ($Section -Ne "Process" ) {
        $OldPath = [Environment]::GetEnvironmentVariable("PATH", "$Section")
        $OldPath = $OldPath -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Payload))\\?" }
        $NewPath = If ($Prepend) { ($Payload + $OldPath) -Join ";" } Else { ($OldPath + $Payload) -Join ";" }
        Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PATH", "$Using:NewPath", "$Using:Section") }
    }

    $OldPath = $Env:Path -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Payload))\\?" }
    $NewPath = If ($Prepend) { ($Payload + $OldPath) -Join ";" } Else { ($OldPath + $Payload) -Join ";" }
    $Env:Path = $NewPath -Join ";"

}

Function Update-AndroidCmdline {

    $SdkHome = "$Env:LocalAppData\Android\Sdk"
    $Starter = "$SdkHome\cmdline-tools\latest\bin\sdkmanager.bat"
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-90)

    If (-Not $Updated) {
        $Address = "https://developer.android.com/studio#command-tools"
        $Release = ([Regex]::Matches((Invoke-WebRequest "$Address"), "commandlinetools-win-(\d+)")).Groups[1].Value
        $Address = "https://dl.google.com/android/repository/commandlinetools-win-${Release}_latest.zip"
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        Update-Nanazip ; $Extract = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName
        Start-Process "7z.exe" "x `"$Fetched`" -o`"$Extract`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
        Start-Sleep 4 ; New-Item "$SdkHome" -ItemType Directory -EA SI
        Update-Temurin ; $Manager = "$Extract\cmdline-tools\bin\sdkmanager.bat"
        Invoke-Expression "echo $("yes " * 10) | & `"$Manager`" --sdk_root=`"$SdkHome`" `"cmdline-tools;latest`""
    }

    Invoke-Gsudo { [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$Using:SdkHome", "Machine") }
    [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$SdkHome", "Process")
    Update-SysPath -Payload "$SdkHome\cmdline-tools\latest\bin" -Section "Machine"
    Update-SysPath -Payload "$SdkHome\emulator" -Section "Machine"
    Update-SysPath -Payload "$SdkHome\platform-tools" -Section "Machine"

    # $Factors = @("$SdkHome\cmdline-tools\latest\bin",  , "$SdkHome\platform-tools")
    # Foreach ($Deposit In $Factors) {
    #     $OldPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    #     $OldPath = $OldPath -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Deposit))\\?" }
    #     $NewPath = ($OldPath + $Deposit) -Join ";"
    #     Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PATH", "$Using:NewPath", "Machine") }
    #     $OldPath = $Env:Path -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Deposit))\\?" }
    #     $Env:Path = ($OldPath + $Deposit) -Join ";"
    # }

}

Function Update-AndroidStudio {

    $Starter = "$Env:ProgramFiles\Android\Android Studio\bin\studio64.exe"
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    $Address = "https://raw.githubusercontent.com/scoopinstaller/extras/master/bucket/android-studio.json"
    $Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).version, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 6))

    If (-Not $Updated) {
        $Address = "https://redirector.gvt1.com/edgedl/android/studio/install/$Version/android-studio-$Version-windows.exe"
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
        Start-Sleep 4
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

Function Update-Figma {

    $Starter = "$Env:LocalAppData\Figma\Figma.exe"
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    $Address = "https://desktop.figma.com/win/RELEASE.json"
    $Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).version, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://desktop.figma.com/win/FigmaSetup.exe"
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
        $ArgList = "/s /S /q /Q /quiet /silent /SILENT /VERYSILENT"
        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Start-Sleep 4
    }

    If (-Not $Present) {
        Start-Sleep 4 ; Start-Process "$Starter" ; Start-Sleep 8
        Stop-Process -Name "Figma" -EA SI ; Stop-Process -Name "figma_agent" -EA SI ; Start-Sleep 4
        $Configs = Get-Content "$Env:AppData\Figma\settings.json" | ConvertFrom-Json
        Try { $Configs.showFigmaInMenuBar = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "showFigmaInMenuBar" -Value $False }
        $Configs | ConvertTo-Json | Set-Content "$Env:AppData\Figma\settings.json"
    }

}

Function Update-Flutter {

    $Deposit = "$Env:LocalAppData\Android\Flutter"
    Update-Git ; git clone "https://github.com/flutter/flutter.git" -b stable "$Deposit"
    Start-Sleep 4

    Update-SysPath "$Deposit\bin" "Machine"
    flutter channel stable ; flutter precache ; flutter upgrade
    Write-Output $("yes " * 10) | flutter doctor --android-licenses
    dart --disable-analytics ; flutter config --no-analytics

    $Product = "$Env:ProgramFiles\Android\Android Studio"
    Update-JetbrainsPlugin "$Product" "6351"  # dart
    Update-JetbrainsPlugin "$Product" "9212"  # flutter
    Update-JetbrainsPlugin "$Product" "13666" # flutter-intl
    Update-JetbrainsPlugin "$Product" "14641" # flutter-riverpod-snippets

    # Start-Process "code" "--install-extension Dart-Code.flutter --force" -WindowStyle Hidden -Wait
    # Start-Process "code" "--install-extension alexisvt.flutter-snippets --force" -WindowStyle Hidden -Wait
    # Start-Process "code" "--install-extension pflannery.vscode-versionlens --force" -WindowStyle Hidden -Wait
    # Start-Process "code" "--install-extension robert-brunhage.flutter-riverpod-snippets --force" -WindowStyle Hidden -Wait
    # Start-Process "code" "--install-extension usernamehw.errorlens --force" -WindowStyle Hidden -Wait

}

Function Update-Git {

    Param (
        [String] $Default = "main",
        [String] $GitMail,
        [String] $GitUser
    )

    $Starter = "$Env:ProgramFiles\Git\git-bash.exe"
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    $Address = "https://api.github.com/repos/git-for-windows/git/releases/latest"
    $Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name.Replace("windows.", ""), "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*64-bit.exe" } ).browser_download_url
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        $ArgList = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART, /NOCANCEL, /SP- /COMPONENTS=`"`""
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Start-Sleep 4
    }

    Update-SysPath "$Env:ProgramFiles\Git\cmd" "Process"
    If (-Not [String]::IsNullOrWhiteSpace($GitMail)) { git config --global user.email "$GitMail" }
    If (-not [String]::IsNullOrWhiteSpace($GitUser)) { git config --global user.name "$GitUser" }
    git config --global http.postBuffer 1048576000
    git config --global init.defaultBranch "$Default"
    
}

Function Update-Gsudo {

    $Current = (Get-Package "*gsudo*" -EA SI).Version
    If ($Null -Eq $Current) { $Current = "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

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
            Else { Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" /qn" -Wait } }
            Start-Sleep 4
        }
        # $Deposit = "${Env:ProgramFiles(x86)}\gsudo"
        # $OldPath = $Env:Path -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Deposit))\\?" }
        # $Env:Path = ($OldPath + $Deposit) -Join ";"
        Update-SysPath -Payload "${Env:ProgramFiles(x86)}\gsudo" -Section "Process"
        Return $True
    }
    Catch { 
        Return $False
    }
    
}

Function Update-JetbrainsPlugin {

    Param(
        [String] $Deposit,
        [String] $Element
    )

    If (-Not (Test-Path "$Deposit") -Or ([String]::IsNullOrWhiteSpace($Element))) { Return 0 }
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
                $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
                (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
                Update-Nanazip ; Start-Process "7z.exe" "x `"$Fetched`" -o`"$Plugins`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
                Break Outer
            }
        }
        Start-Sleep 1
    }

}

Function Update-Nanazip {

    $Current = (Get-Package "*nanazip*" -EA SI).Version
    If ($Null -Eq $Current) { $Current = "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    $Address = "https://api.github.com/repos/m2team/nanazip/releases/latest"
    $Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*.msixbundle" } ).browser_download_url
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        Add-AppxPackage -DeferRegistrationWhenPackagesAreInUse -ForceUpdateFromAnyVersion -Path "$Fetched"
        Start-Sleep 4
    }

}

Function Update-Temurin {

    $Current = (Get-Package "*temurin*" -EA SI).Version
    If ($Null -Eq $Current) { $Current = "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    $Address = "https://api.github.com/repos/adoptium/temurin19-binaries/releases/latest"
    $Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*jdk_x64_windows*.msi" } ).browser_download_url
        $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
        (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        $ArgList = If ($Present) { "REINSTALL=ALL REINSTALLMODE=amus /quiet" } Else { "INSTALLLEVEL=1 /quiet" }
        Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" $Using:ArgList" -Wait }
        Start-Sleep 4
    }

    # $Deposit = (Get-Item "$Env:ProgramFiles\Eclipse Adoptium\jdk-*\bin").FullName
    # $OldPath = $Env:Path -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Deposit))\\?" }
    # $Env:Path = ($OldPath + $Deposit) -Join ";"
    $Deposit = (Get-Item "$Env:ProgramFiles\Eclipse Adoptium\jdk-*\bin").FullName
    Update-SysPath -Payload "$Deposit" -Section "Process"

}

# Change headline
$Current = "$($Script:MyInvocation.MyCommand.Path)"
$Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName

# Output greeting
Clear-Host ; $ProgressPreference = "SilentlyContinue"
Write-Host "+----------------------------------------------------------+"
Write-Host "|                                                          |"
Write-Host "|  > WINHOGEN (NEW)                                        |"
Write-Host "|                                                          |"
Write-Host "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                   |"
Write-Host "|                                                          |"
Write-Host "+----------------------------------------------------------+"

# Remove security
$Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
$Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
Write-Host "$Loading" -FO DarkYellow -NoNewline
$Correct = (Update-Gsudo) -And -Not (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

# Handle elements
$Factors = @(
    "Update-AndroidStudio"
    "Update-Git -GitMail 72373746+sharpordie@users.noreply.github.com -GitUser sharpordie"
    "Update-Flutter"
    "Update-Figma"
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
Invoke-Expression "gsudo -k" *> $Null

# Output new line
Write-Host "`n"

