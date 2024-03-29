#Region Services

Function Assert-Pending {

    $Operations = (Get-Item "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\").GetValue("PendingFileRenameOperations")
    If ($Null -Eq $Operations) { $False }
    Else {
        $TrueOperationsCount = $Operations.Length / 2
        $TrueRenames = [Collections.Generic.Dictionary[String, String]]::New($TrueOperationsCount)
        For ($I = 0; $I -Ne $TrueOperationsCount; $I++) {
            $OperationSource = $Operations[$I * 2]
            $OperationDestination = $Operations[$I * 2 + 1]
            If ($OperationDestination.Length -eq 0) { Write-Verbose "Ignoring pending file delete '$OperationSource'" }
            Else {
                Write-Host "Found a true pending file rename (as opposed to delete). Source '$OperationSource'; Dest '$OperationDestination'"
                $TrueRenames[$OperationSource] = $OperationDestination
            }
        }
        $TrueRenames.Count -Gt 0
    }
    
}

Function Enable-PowPlan {

    Param (
        [ValidateSet("Balanced", "High", "Power", "Ultimate")] [String] $Element = "Balanced"
    )

    # Remove dummies
    # $Factors = (powercfg /L | ForEach-Object { If ($_.Contains("(Ultimate")) { $_.Split()[3] } })
    # foreach($Segment in $Factors) { Invoke-Expression "powercfg.exe /DELETE $Segment" }

    # Active ultimate
    $Picking = (powercfg /L | ForEach-Object { If ($_.Contains("($Element")) { $_.Split()[3] } })
    If ([String]::IsNullOrEmpty("$Picking")) { Start-Process "powercfg.exe" "/DUPLICATESCHEME e9a42b02-d5df-448d-aa00-03f14749eb61" -NoNewWindow -Wait }
    
    # Enable plan
    $Picking = (powercfg /L | ForEach-Object { If ($_.Contains("($Element")) { $_.Split()[3] } })
    Start-Process "powercfg.exe" "/S $Picking" -NoNewWindow -Wait
    
    # Change lidaction
    If ($Element -Eq "Ultimate") {
        $Desktop = $Null -Eq (Get-WmiObject Win32_SystemEnclosure -ComputerName "localhost" | Where-Object ChassisTypes -In "{9}", "{10}", "{14}")
        $Desktop = $Desktop -Or $Null -Eq (Get-WmiObject Win32_Battery -ComputerName "localhost")
        If (-Not $Desktop) { Start-Process "powercfg.exe" "/SETACVALUEINDEX $Picking SUB_BUTTONS LIDACTION 000" -NoNewWindow -Wait }
    }

}

Function Enable-Prompts {

    $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
    [IO.File]::WriteAllText("$Created", @(
            '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
            'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 5'
            'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 1'
        ) -Join "`n")
    Start-Process "powershell" "-ExecutionPolicy Bypass -File `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait
    Remove-Item "$Created" -Force

}

Function Expand-Archive {

    Param (
        [String] $Archive,
        [String] $Deposit,
        [String] $Secrets
    )

    $Starter = "$Env:ProgramFiles\7-Zip\7z.exe"
    If (-Not (Test-Path "$Starter")) { Update-SevenZip }
    If (-Not $Deposit) { $Deposit = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName }
    If (-Not (Test-Path "$Deposit")) { New-Item "$Deposit" -ItemType Directory -EA SI }
    $ArgList = "x `"$Archive`" -o`"$Deposit`""
    $ArgList = If ($Secrets) { "$ArgList -p`"$Secrets`"" } Else { "$ArgList" }
    $ArgList = "$ArgList -y -bso0 -bsp0"
    Start-Process "$Starter" "$ArgList" -WindowStyle Hidden -Wait
    Return "$Deposit"

}

Function Expand-Version {

    Param (
        [String] $Starter
    )

    $Version = "0.0.0.0"
    If ($Version -Eq "0.0.0.0") { $Version = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { $Version } }
    If ($Version -Eq "0.0.0.0") { $Version = Try { (Get-Item "$Starter" -EA SI).VersionInfo.FileVersion.ToString() } Catch { $Version } }
    If ($Version -Eq "0.0.0.0") { $Version = Try { Invoke-Expression "& '$Starter' --version" -EA SI } Catch { $Version } }
    Return [Regex]::Matches($Version, "([\d.]+)").Groups[1].Value

}

Function Invoke-Fetcher {

    Param (
        [String] $Address,
        [String] $Fetched
    )

    $Fetched = If (-Not $Fetched) { Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)" } Else { $Fetched }
    (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
    Return "$Fetched"

}

Function Invoke-Restart {

    Param(
        [Switch] $Removed
    )

    $Current = "$($Script:MyInvocation.MyCommand.Path)"
    $Heading = (Get-Item "$Current").BaseName
    Invoke-Gsudo { Unregister-ScheduledTask -TaskName "$Using:Heading" -Confirm:$False }
    If (-Not $Removed) {
        $ArgList = "/c start /b wt --title `"$Heading`" powershell -ExecutionPolicy Bypass -NoExit -NoLogo -File `"$Current`""
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

}

Function Invoke-Scraper {

    Param(
        [ValidateSet("Html", "Json")] [String] $Scraper,
        [String] $Address,
        [String] $Pattern
    )
    
    Add-Type -AssemblyName "System.Net.Http"
    $Manager = [Net.Http.HttpClient]::New()
    $UsAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/500.0 (KHTML, like Gecko) Chrome/100.0.0.0 Safari/500.0"
    $Manager.DefaultRequestHeaders.Add("User-Agent", "$UsAgent")

    If ($Scraper -Eq "Html") {
        $Scraped = $Manager.GetStringAsync("$Address").GetAwaiter().GetResult().ToString()
        Return [Regex]::Matches("$Scraped", "$Pattern")
    }

    If ($Scraper -Eq "Json") {
        Return $Manager.GetStringAsync("$Address").GetAwaiter().GetResult().ToString() | ConvertFrom-Json
    }
    
}

Function Invoke-Syspin {

    Param(
        [ValidateSet("PinToStart", "PinToTaskbar", "UnpinFromStart", "UnpinFromTaskbar")] [String] $Command,
        [String] $Starter
    )

    $Content = Switch ($Command) {
        PinToTaskbar { "5386" }
        UnpinFromTaskbar { "5387" }
        PinToStart { "51261" }
        UnpinFromStart { "51394" }
        Default { "5386" }
    }

    $Address = "http://www.technosys.net/download.aspx?file=syspin.exe"
    $Fetched = Join-Path "$Env:Temp" "syspin.exe"
    If ((Test-Path "$Fetched") -Eq $False) { Invoke-Fetcher "$Address" "$Fetched" }
    Invoke-Expression "& `"$Fetched`" `"$Starter`" `"$Content`"" | Out-Null

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
        [ValidateSet("HyperV")] [String] $Feature
    )

    Switch ($Feature) {
        HyperV { 
            $Address = "https://cdn3.bluestacks.com/support_files/HD-DisableHyperV_native_v2.exe"
            $Fetched = Invoke-Fetcher "$Address"
            Invoke-Gsudo {
                Start-Process "$Using:Fetched"
                Start-Sleep 10 ; Stop-Process -Name "HD-DisableHyperV"
            }
        }
        Default { Return 0 }
    }

    # Reboot computer
    Invoke-Restart -Removed ; If (Assert-Pending -Eq $True) { Invoke-Restart }

}

Function Remove-Prompts {

    $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
    [IO.File]::WriteAllText("$Created", @(
            '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
            'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 0'
            'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 0'
        ) -Join "`n")
    Start-Process "powershell" "-ExecutionPolicy Bypass -File `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait
    Remove-Item "$Created" -Force

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

    # Gather current
    $SdkHome = "$Env:LocalAppData\Android\Sdk"
    $Starter = "$SdkHome\cmdline-tools\latest\bin\sdkmanager.bat"

    # Update package
    $Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-90)
    If (-Not $Updated) {
        $Address = "https://developer.android.com/studio#command-tools"
        $Pattern = "commandlinetools-win-(\d+)"
        $Results = Invoke-Scraper "Html" "$Address" "$Pattern"
        $Release = $Results.Groups[1].Value
        $Address = "https://dl.google.com/android/repository/commandlinetools-win-${Release}_latest.zip"
        $Fetched = Invoke-Fetcher "$Address"
        $Deposit = Expand-Archive "$Fetched"
        New-Item "$SdkHome" -ItemType Directory -EA SI
        Update-Temurin ; $Manager = "$Deposit\cmdline-tools\bin\sdkmanager.bat"
        Invoke-Expression "echo $("yes " * 10) | & `"$Manager`" --sdk_root=`"$SdkHome`" `"cmdline-tools;latest`""
    }

    # Change environ
    Invoke-Gsudo { [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$Using:SdkHome", "Machine") }
    [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$SdkHome", "Process")
    Update-SysPath "$SdkHome\cmdline-tools\latest\bin" "Machine"
    Update-SysPath "$SdkHome\emulator" "Machine"
    Update-SysPath "$SdkHome\platform-tools" "Machine"

}

Function Update-AndroidStudio {

    # Update package
    $Address = "https://raw.githubusercontent.com/ScoopInstaller/extras/master/bucket/android-studio.json"
    # $Address = "https://raw.githubusercontent.com/scoopinstaller/versions/master/bucket/android-studio-beta.json"
    $Version = (Invoke-Scraper "Json" "$Address").version
    $Starter = "$Env:ProgramFiles\Android\Android Studio\bin\studio64.exe"
    $Present = Test-Path "$Starter"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 6))
    If (-Not $Updated) {
        $Address = "https://redirector.gvt1.com/edgedl/android/studio/install/$Version/android-studio-$Version-windows.exe"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
    }

    # Finish install
    If (-Not $Present) {
        Update-AndroidCmdline
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'build-tools;33.0.1'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'emulator'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'extras;intel;Hardware_Accelerated_Execution_Manager'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'platform-tools'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'platforms;android-33'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'sources;android-33'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager 'system-images;android-33;google_apis;x86_64'"
        Invoke-Expression "echo $("yes " * 10) | sdkmanager --licenses"
        Invoke-Expression "avdmanager create avd -n 'Pixel_3_API_33' -d 'pixel_3' -k 'system-images;android-33;google_apis;x86_64'"
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

Function Update-Appearance {

    # Change pinned elements
    $shell = New-Object -ComObject Shell.Application
    $shell.Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}").Items() | ForEach-Object { $_.InvokeVerb("unpinfromhome") }
    $shell.Namespace("$Env:Temp").Self.InvokeVerb("pintohome")
    $shell.Namespace("$Env:UserProfile").Self.InvokeVerb("pintohome")
    # $shell.Namespace("$Env:UserProfile\Downloads").Self.InvokeVerb("pintohome")
    New-Item -Path "$Env:UserProfile\Projects" -ItemType Directory -EA SI ; $shell.Namespace("$Env:UserProfile\Projects").Self.InvokeVerb("pintohome")
    New-Item -Path "$Env:UserProfile\Machines" -ItemType Directory -EA SI ; $shell.Namespace("$Env:UserProfile\Machines").Self.InvokeVerb("pintohome")

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

    # Change pinned applications
    Get-Item "$Env:AppData\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\*.lnk" | Remove-Item -Force -EA SI
    $Folder1 = "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    $Folder2 = "$Env:AppData\Microsoft\Windows\Start Menu\Programs"
    $Factors = @(
        "$Folder2\JDownloader\JDownloader 2.lnk"
        "$Folder1\qBittorrent\qBittorrent.lnk"
        "$Folder2\Visual Studio Code\Visual Studio Code.lnk"
        "$Folder1\Visual Studio 2022.lnk"
        "$Folder1\VMware\VMware Workstation Pro.lnk"
        "$Folder2\Spotify.lnk"
        "$Folder2\Mpv.lnk"
        "$Folder2\Figma.lnk"
    )
    Foreach ($Element In $Factors) { Invoke-Syspin "UnpinFromTaskbar" "$Element" }
    Foreach ($Element In $Factors) { Invoke-Syspin "PinToTaskbar" "$Element" }

    # Reboot explorer
    Stop-Process -Name "explorer"

}

Function Update-Bluestacks {

    # Update package
    $Address = "https://webcache.googleusercontent.com/search?q=cache:https://support.bluestacks.com"
    $Address = "$Address/hc/en-us/articles/4402611273485-BlueStacks-5-offline-installer"
    $Pattern = "windows/nxt/([\d.]+)/(?<sha>[0-9a-f]+)/"
    $Results = Invoke-Scraper "Html" "$Address" "$Pattern"
    $Version = $Results.Groups[1].Value
    $Hashing = $Results.Groups[2].Value
    $Starter = (Get-Item "$Env:ProgramFiles\BlueStacks*\HD-Player.exe").FullName
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 6))
    If (-Not $Updated) {
        $Address = "https://cdn3.bluestacks.com/downloads/windows/nxt/$Version/$Hashing/FullInstaller/x64/BlueStacksFullInstaller_${Version}_amd64_native.exe"
        $Fetched = Invoke-Fetcher "$Address"
        # $ArgList = "-s --defaultImageName Nougat64 --imageToLaunch Nougat64 --defaultImageName Nougat64 --imageToLaunch Nougat64"
        $ArgList = "-s --defaultImageName Nougat64 --imageToLaunch Nougat64 --defaultImageName Pie64 --imageToLaunch Pie64"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Remove-Desktop "BlueStacks*.lnk"
    }

    # Update shortcut
    # $Altered = (Get-Item "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs\BlueStacks 5.lnk").FullName
    # If ($Null -Ne $Altered) {
    #     $Content = [IO.File]::ReadAllBytes("$Altered")
    #     $Content[0x15] = $Content[0x15] -Bor 0x20
    #     Invoke-Gsudo { [IO.File]::WriteAllBytes("$Using:Altered", $Using:Content) }
    # }

}

Function Update-Chromium {

    Param (
        [String] $Deposit = "$Env:UserProfile\Downloads\DDL",
        [String] $Startup = "about:blank"
    )

    # Update package
    $Address = "https://api.github.com/repos/macchrome/winchrome/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address")[0].tag_name, "[\d.]+").Value
    $Starter = "$Env:ProgramFiles\Chromium\Application\chrome.exe"
    $Present = Test-Path "$Starter"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 3) + ".0")
    If (-Not $Updated) {
        $Address = (Invoke-Scraper "Json" "$Address")[0].assets[0].browser_download_url
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "--system-level --do-not-launch-chrome" -Wait }
    }

    # Finish install
    If (-Not $Present) {
        # Change deposit
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

        # Change custom-ntp
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

        # Change search engine
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

        # Change extension-mime-request-handling
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

        # Change hide-sidepanel-button
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

        # Change remove-tabsearch-button
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

        # Change win-10-tab-search-caption-button
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

        # Change show-avatar-button
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

        # Update chromium-web-store
        $Address = "https://api.github.com/repos/NeverDecaf/chromium-web-store/releases/latest"
        $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address")[0].tag_name, "[\d.]+").Value
        Update-ChromiumExtension "https://github.com/NeverDecaf/chromium-web-store/releases/download/v$Version/Chromium.Web.Store.crx"

        # Update extensions
        Update-ChromiumExtension "omoinegiohhgbikclijaniebjpkeopip" # clickbait-remover-for-you
        Update-ChromiumExtension "ibplnjkanclpjokhdolnendpplpjiace" # simple-translate
        Update-ChromiumExtension "mnjggcdmjocbbbhaepdhchncahnbgone" # sponsorblock-for-youtube
        Update-ChromiumExtension "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock-origin
    }

    # Update bypass-paywalls-chrome
    Update-ChromiumExtension "https://github.com/iamadamdev/bypass-paywalls-chrome/archive/master.zip"

}

Function Update-ChromiumExtension {

    Param (
        [String] $Payload
    )

    # Update extension
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

Function Update-DockerDesktop {

    # Update package
    $Starter = "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://community.chocolatey.org/packages/docker-desktop"
    $Version = Invoke-Scraper "HtmlContent" "$Address" "Docker Desktop ([\d.]+)</title>"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://desktop.docker.com/win/stable/Docker Desktop Installer.exe"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "install --quiet" -Wait } ; Start-Sleep 10
        Remove-Desktop "*Docker*.lnk" ; Invoke-Restart -Forcing
    }

    # Change settings
    $Configs = "$Env:AppData\Docker\settings.json"
    $Content = Get-Content "$Configs" | ConvertFrom-Json
    $Content.analyticsEnabled = $False
    $Content.autoStart = $False
    $Content.disableTips = $True
    $Content.disableUpdate = $True
    $Content.licenseTermsVersion = 2
    $Content.openUIOnStartupDisabled = $True
    $Content | ConvertTo-Json | Set-Content "$Configs"

}

Function Update-DotnetMaui {

    # Update package
    Update-VisualStudio2022
    Update-VisualStudio2022Workload "Microsoft.VisualStudio.Workload.NetCrossPlat"

    # Finish install
    Invoke-Gsudo {
        $SdkHome = "${Env:ProgramFiles(x86)}\Android\android-sdk"
        $Creator = (Get-Item "$SdkHome\cmdline-tools\*\bin\avdmanager*").FullName
        $Starter = (Get-Item "$SdkHome\cmdline-tools\*\bin\sdkmanager*").FullName
        & "$Starter" --list_available
        If ($Null -Ne $Starter) {
            Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"build-tools;31.0.0`""
            Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"cmdline-tools;7.0`""
            Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"emulator`""
            Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"extras;intel;Hardware_Accelerated_Execution_Manager`""
            Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"platform-tools`""
            Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"platforms;android-31`""
            Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"system-images;android-31;google_apis;x86_64`""
            Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" --licenses"
            Invoke-Expression "echo $("yes " * 10) | & `"$Creator`" create avd -n `"Pixel_3_API_31`" -d `"pixel_3`" -k `"system-images;android-31;google_apis;x86_64`""

            # # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"build-tools;30.0.3`""
            # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"build-tools;32.0.0`""
            # # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"build-tools;33.0.1`""
            # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"cmdline-tools;7.0`""
            # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"emulator`""
            # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"extras;intel;Hardware_Accelerated_Execution_Manager`""
            # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"platform-tools`""
            # # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"platforms;android-30`""
            # # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"platforms;android-33`""
            # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"platforms;android-32`""
            # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --sdk_root=`"$SdkHome`" `"system-images;android-32;google_apis;x86_64`""
            # Invoke-Expression "echo $("yes " * 10) | & `"$Starter`" --licenses"
            # Invoke-Expression "echo $("yes " * 10) | & `"$Creator`" create avd -n `"Pixel_3_API_32`" -d `"pixel_3`" -k `"system-images;android-32;google_apis;x86_64`""
            # $Configs = "$Env:UserProfile\.android\avd\Pixel_5_API_30.avd\config.ini"
            # If (-Not (Test-Path $Configs)) {
            #     Write-Output $("yes " * 10) | & "$Creator" create avd -n "Pixel_5_API_30" -d "pixel_5" -k "system-images;android-30;google_apis;x86_64"
            #     $Altered = (Get-Content "$Configs" | ForEach-Object { $_ -Match "displayname" }) -Contains $True
            #     If (-Not $Altered) { Add-Content "$Configs" "avd.ini.displayname=Pixel 5 - API 30" }
            # }
            # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "build-tools;30.0.3"
            # # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "build-tools;32.0.0"
            # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "build-tools;33.0.1"
            # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "platform-tools"
            # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "platforms;android-30"
            # # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "platforms;android-31"
            # # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "platforms;android-32"
            # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "platforms;android-33"
            # Write-Output $("yes " * 10) | & "$Starter" --sdk_root="$SdkHome" "system-images;android-30;google_apis_playstore;x86_64"
            # Write-Output $("yes`n" * 9) | & "$Starter" --licenses
            # $Configs = "$Env:UserProfile\.android\avd\Pixel_5_API_30.avd\config.ini"
            # If (-Not (Test-Path $Configs)) {
            #     Write-Output $("yes " * 10) | & "$Creator" create avd -n "Pixel_5_API_30" -d "pixel_5" -k "system-images;android-30;google_apis_playstore;x86_64"
            #     $Altered = (Get-Content "$Configs" | ForEach-Object { $_ -Match "displayname" }) -Contains $True
            #     If (-Not $Altered) { Add-Content "$Configs" "avd.ini.displayname=Pixel 5 - API 30" }
            # }
        }
    }

    # Update visual studio
    Update-VisualStudio2022Extension "MattLaceyLtd.MauiAppAccelerator"
    Update-VisualStudio2022Extension "TeamXavalon.XAMLStyler2022"

}

Function Update-Figma {

    # Update package
    $Address = "https://desktop.figma.com/win/RELEASE.json"
    $Version = (Invoke-Scraper "Json" "$Address").version
    $Starter = "$Env:LocalAppData\Figma\Figma.exe"
    $Present = Test-Path "$Starter"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://desktop.figma.com/win/FigmaSetup.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $ArgList = "/s /S /q /Q /quiet /silent /SILENT /VERYSILENT"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        If (-Not $Present) {
            $Started = Get-Date
            $LnkFile = "$Env:UserProfile\Desktop\Figma*.lnk"
            While (-Not (Test-Path $LnkFile) -And $Started.AddSeconds(30) -Gt (Get-Date)) { Start-Sleep 2 }
            Remove-Item -Path $LnkFile
        }
    }

    # Remove tray
    Start-Process "$Starter" ; Start-Sleep 5 ; Stop-Process -Name "Figma" ; Stop-Process -Name "figma_agent" ; Start-Sleep 5
    $Configs = Get-Content "$Env:AppData\Figma\settings.json" | ConvertFrom-Json
    Try { $Configs.showFigmaInMenuBar = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "showFigmaInMenuBar" -Value $False }
    $Configs | ConvertTo-Json | Set-Content "$Env:AppData\Figma\settings.json"

}

Function Update-Flutter {

    # Update package
    $Deposit = "$Env:LocalAppData\Android\Flutter"
    $Starter = "$Deposit\bin\flutter"
    $Present = Test-Path "$Starter"
    Update-Git ; Invoke-Expression "git clone https://github.com/flutter/flutter.git -b stable $Deposit"
    Update-SysPath "$Deposit\bin" "Machine"
    # If (-Not $Present) {
    #     New-Item "$Deposit" -ItemType Directory -EA SI
    #     $Address = "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
    #     $Address = (Invoke-Scraper "Json" "$Address")[0].releases[0].archive
    #     $Address = "https://storage.googleapis.com/flutter_infra_release/releases/$Address"
    #     $Fetched = Invoke-Fetcher "$Address"        
    #     $Extract = Expand-Archive "$Fetched"
    #     $Topmost = (Get-ChildItem "$Extract" -Directory | Select-Object -First 1).FullName
    #     Copy-Item "$Topmost\*" -Destination "$Deposit" -Recurse -Force
    #     Update-SysPath "$Deposit\bin" "Machine"
    # }

    # Change settings
    Invoke-Expression "flutter channel stable"
    Invoke-Expression "flutter precache" ; Invoke-Expression "flutter upgrade"
    Invoke-Expression "echo $("yes " * 10) | flutter doctor --android-licenses"
    Invoke-Expression "dart --disable-analytics"
    Invoke-Expression "flutter config --no-analytics"

    # Update android studio
    $Present = Test-Path "$Env:ProgramFiles\Android\Android Studio\bin\studio64.exe"
    # If ($Present) {
    #     Update-JetbrainsPlugin "AndroidStudio" "6351"  # Dart
    #     Update-JetbrainsPlugin "AndroidStudio" "9212"  # Flutter
    # }

    # Update visual studio 2022
    # $Present = Test-Path "$Env:ProgramFiles\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe"
    # If ($Present) {
    #     Update-VisualStudio2022Workload "Microsoft.VisualStudio.Workload.NativeDesktop"
    # }

    # Update visual studio code
    If ($Null -Ne (Get-Command "code" -EA SI)) {
        Start-Process "code" "--install-extension Dart-Code.flutter --force" -WindowStyle Hidden -Wait
        Start-Process "code" "--install-extension alexisvt.flutter-snippets --force" -WindowStyle Hidden -Wait
        Start-Process "code" "--install-extension pflannery.vscode-versionlens --force" -WindowStyle Hidden -Wait
        Start-Process "code" "--install-extension robert-brunhage.flutter-riverpod-snippets --force" -WindowStyle Hidden -Wait
        Start-Process "code" "--install-extension usernamehw.errorlens --force" -WindowStyle Hidden -Wait
    }

}

Function Update-Git {

    Param (
        [String] $Default = "main",
        [String] $GitMail,
        [String] $GitUser
    )
    
    # Update package
    $Address = "https://git-scm.com/download/win"
    $Pattern = "<strong>([\d.]+)</strong>"
    $Version = (Invoke-Scraper "Html" "$Address" "$Pattern").Groups[1].Value
    $Starter = "$Env:ProgramFiles\Git\git-bash.exe"
    $Current = Expand-Version "$Starter"
    $Updated = [System.Version] "$Current" -Ge [System.Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://github.com/git-for-windows/git/releases/download"
        $Address = "$Address/v$Version.windows.1/Git-$Version-64-bit.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $ArgList = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART, /NOCANCEL, /SP- /COMPONENTS=`"`""
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
    }
    
    # Change settings
    Update-SysPath "$Env:ProgramFiles\Git\cmd" "Process"
    If ($Null -Ne $GitMail) { Invoke-Expression "git config --global user.email '$GitMail'" }
    If ($Null -Ne $GitUser) { Invoke-Expression "git config --global user.name '$GitUser'" }
    Invoke-Expression "git config --global http.postBuffer 1048576000"
    Invoke-Expression "git config --global init.defaultBranch '$Default'"
    
}

Function Update-Gsudo {
    
    # Update package
    $Address = "https://raw.githubusercontent.com/scoopinstaller/main/master/bucket/gsudo.json"
    $Version = (Invoke-Scraper "Json" "$Address").version
    $Starter = "${Env:ProgramFiles(x86)}\gsudo\gsudo.exe"
    $Present = Test-Path "$Starter"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    Try {
        Update-SysPath "$(Split-Path "$Starter" -Parent)" "Process"
        If (-Not $Updated) {
            $Address = "https://github.com/gerardog/gsudo/releases/download/v$Version/gsudoSetup.msi"
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

Function Update-IntelHaxm {

    # Remove hyper-v
    Remove-Feature -Feature HyperV

    # Gather current
    $Current = (Get-Package "Inte*Hard*Acce*" -EA SI).Version

    # Update package
    $Address = "https://api.github.com/repos/intel/haxm/releases"
    $Version = (Invoke-Scraper "Json" "$Address")[0].tag_name.Replace("v", "")
    # $Version = [Regex]::Matches("$Address", "v([\d.]+)").Groups[1].Value
    $Updated = $Null -Ne $Current -And [Version] ($Current.SubString(0, 1)) -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = (Invoke-Scraper "Json" "$Address")[0].assets.Where( { $_.browser_download_url -like "*windows*" } ).browser_download_url
        $Fetched = Invoke-Fetcher "$Address"
        $Deposit = Expand-Archive "$Fetched"
        Invoke-Gsudo { Start-Process "$Using:Deposit\silent_install.bat" -WindowStyle Hidden -Wait }
    }

}

Function Update-Jdownloader {

    Param (
        [String] $Deposit = "$Env:UserProfile\Downloads\JD2"
    )

    # Update package
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

    # Update settings
    If (-Not $Present) {
        $Config1 = "$Env:ProgramFiles\JDownloader\cfg\org.jdownloader.settings.GeneralSettings.json"
        $Config2 = "$Env:ProgramFiles\JDownloader\cfg\org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
        Start-Process "$Starter" ; Start-Sleep 12 ; While (-Not (Test-Path -Path "$Config1")) { Start-Sleep 2 }
        Stop-Process -Name "JDownloader2" ; Start-Sleep 2
        $Configs = Get-Content "$Config1" | ConvertFrom-Json
        Try { $Configs.defaultdownloadfolder = "$Deposit" } Catch { $Configs | Add-Member -Type NoteProperty -Name "defaultdownloadfolder" -Value "$Deposit" }
        Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config1" }
        $Configs = Get-Content "$Config2" | ConvertFrom-Json
        Try { $Configs.premiumalerttaskcolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalerttaskcolumnenabled" -Value $False }
        Try { $Configs.premiumalertspeedcolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalertspeedcolumnenabled" -Value $False }
        Try { $Configs.premiumalertetacolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalertetacolumnenabled" -Value $False }
        Try { $Configs.specialdealoboomdialogvisibleonstartup = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "specialdealoboomdialogvisibleonstartup" -Value $False }
        Try { $Configs.specialdealsenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "specialdealsenabled" -Value $False }
        Try { $Configs.donatebuttonstate = "AUTO_HIDDEN" } Catch { $Configs | Add-Member -Type NoteProperty -Name "donatebuttonstate" -Value "AUTO_HIDDEN" }
        Try { $Configs.donatebuttonlatestautochange = 4102444800000 } Catch { $Configs | Add-Member -Type NoteProperty -Name "donatebuttonlatestautochange" -Value 4102444800000 }
        Try { $Configs.bannerenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "bannerenabled" -Value $False }
        Try { $Configs.myjdownloaderviewvisible = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "myjdownloaderviewvisible" -Value $False }
        Try { $Configs.speedmetervisible = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "speedmetervisible" -Value $False }
        Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config2" }
    }

}

Function Update-JoalDesktop {

    # Gather current
    $Starter = "$Env:LocalAppData\Programs\joal-desktop\JoalDesktop.exe"
    $Current = Expand-Version "$Starter"

    # Update package
    $Address = "https://api.github.com/repos/anthonyraymond/joal-desktop/releases"
    $Version = (Invoke-Scraper "Json" "$Address")[0].tag_name.Replace("v", "")
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = (Invoke-Scraper "Json" "$Address")[0].assets.Where( { $_.browser_download_url -like "*win-x64.exe" } ).browser_download_url
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
        Remove-Desktop "*Joal*.lnk"
    }

}

Function Update-Keepassxc {

    # Update package
    $Address = "https://raw.githubusercontent.com/scoopinstaller/extras/master/bucket/keepassxc.json"
    $Version = (Invoke-Scraper "Json" "$Address").version
    $Starter = "$Env:ProgramFiles\KeePassXC\KeePassXC.exe"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://github.com/keepassxreboot/keepassxc/releases/download/$Version/KeePassXC-$Version-Win64.msi"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" /qn" -Wait }
    }

    # Remove autorun
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "KeePassXC" -EA SI

}

Function Update-Mambaforge {

    # Gather current
    $Present = $Null -Ne (Get-Command "mamba" -EA SI)

    # Update package
    If (-Not $Present) {
        $Address = "https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Windows-x86_64.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $Deposit = "$Env:localAppData\Programs\Mambaforge"
        $ArgList = "/S /InstallationType=JustMe /RegisterPython=0 /AddToPath=1 /NoRegistry=1 /D=$Deposit"
        Start-Process "$Fetched" "$ArgList" -Wait
        Update-SysPath -Deposit "" -Section "User"
    }

    # Change settings
    Invoke-Expression "conda config --set auto_activate_base false"
    # Invoke-Expression "conda update --all -y"

}

Function Update-Miniconda {

    # Gather current
    $Present = $Null -Ne (Get-Command "conda" -EA SI)

    # Update package
    If (-Not $Present) {
        $Address = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $Deposit = "$Env:localAppData\Programs\Miniconda"
        $ArgList = "/S /InstallationType=JustMe /RegisterPython=0 /AddToPath=1 /NoRegistry=1 /D=$Deposit"
        Start-Process "$Fetched" "$ArgList" -Wait
        Update-SysPath -Deposit "" -Section "User"
    }

    # Change settings
    Invoke-Expression "conda config --set auto_activate_base false"
    # Invoke-Expression "conda update --all -y"
    
}

Function Update-Mpv {

    # Update package
    $Address = "https://sourceforge.net/projects/mpv-player-windows/files/64bit"
    $Pattern = "mpv-x86_64-([\d]{8})-git-([\a-z]{7})\.7z"
    $Results = Invoke-Scraper "Html" "$Address" "$Pattern"
    $Version = $Results.Groups[1].Value
    $Release = $results.Groups[2].Value
    $Starter = "$Env:LocalAppData\Programs\Mpv\mpv.exe"
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

    # Update shaders
    $Deposit = Join-Path "$(Split-Path "$Starter")" "shaders"
    New-Item "$Deposit" -ItemType Directory -EA SI
    $Address = "https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl"
    $Fetched = Invoke-Fetcher "$Address" ; Move-Item "$Fetched" "$Deposit" -Force
    $Address = "https://gist.githubusercontent.com/igv/36508af3ffc84410fe39761d6969be10/raw/6998ff663a135376dbaeb6f038e944d806a9b9d9/SSimDownscaler.glsl"
    $Fetched = Invoke-Fetcher "$Address" ; Move-Item "$Fetched" "$Deposit" -Force

    # Change settings
    $Configs = Join-Path "$(Split-Path "$starter")" "mpv\mpv.conf"
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

    # Adjust association
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Address = "https://raw.githubusercontent.com/DanysysTeam/PS-SFTA/master/SFTA.ps1"
    Invoke-Expression ((New-Object Net.WebClient).DownloadString("$Address"))
    Register-FTA "$Starter" -Extension ".mkv"
    Register-FTA "$Starter" -Extension ".mp4"

}

Function Update-Nanazip {

    # Gather current
    $Current = (Get-AppxPackage "*Nanazip*" -EA SI).Version

    # Update package
    $Address = "https://api.github.com/repos/M2Team/NanaZip/releases"
    $Version = (Invoke-Scraper "Json" "$Address")[0].tag_name.Replace("v", "")
    $Updated = $Null -Ne $Current -And [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = (Invoke-Scraper "Json" "$Address")[0].assets.Where( { $_.browser_download_url -like "*.msixbundle" } ).browser_download_url
        $Fetched = Invoke-Fetcher "$Address"
        Add-AppxPackage -DeferRegistrationWhenPackagesAreInUse -ForceUpdateFromAnyVersion -Path "$Fetched"
        # $Deposit = Expand-Archive "$Fetched"
        # Invoke-Gsudo { Start-Process "$Using:Deposit\silent_install.bat" -WindowStyle Hidden -Wait }
    }

}

Function Update-NvidiaDriver {

    # Update package
    $Address = "https://community.chocolatey.org/packages/nvidia-display-driver"
    $Pattern = "NVidia Display Driver ([\d.]+)</title>"
    $Version = (Invoke-Scraper "Html" "$Address" "$Pattern").Groups[1].Value
    $Current = (Get-Package "NVIDIA Graphics Driver*" -EA SI).Version
    $Updated = $Null -Ne $Current -And [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://us.download.nvidia.com/Windows/$Version/$Version-desktop-win10-win11-64bit-international-dch-whql.exe"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "-s -noreboot" -Wait }
        Remove-Desktop "GeForce*.lnk"
    }

}

Function Update-PaintNet {

    # Update package
    $Address = "https://api.github.com/repos/paintdotnet/release/releases"
    $Version = [Regex]::Matches((Invoke-Scraper "Json" "$Address")[0].tag_name, "([\d.]+)").Groups[1].Value
    $Starter = "$Env:ProgramFiles\paint.net\paintdotnet.exe"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = (Invoke-Scraper "Json" "$Address")[0].assets.Where( { $_.browser_download_url -like "*x64.msi" } ).browser_download_url
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" /qn" -Wait }
        Remove-Desktop "paint*.lnk"
    }

}

Function Update-Postgresql {

    Param (
        [Int] $Leading = 14
    )

    # Gather current
    $Starter = "$Env:ProgramFiles\PostgreSQL\$Leading\bin\psql.exe"
    $Current = Expand-Version "$Starter"

    # Update package
    $Address = "https://raw.githubusercontent.com/scoopinstaller/versions/master/bucket/postgresql$Leading.json"
    $Version = (Invoke-Scraper "Json" "$Address").version
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

    # Update package
    $Address = "https://www.python.org/downloads/windows/"
    $Pattern = "python-($Leading\.$Backing\.[\d.]+)-"
    $Version = (Invoke-Scraper "Html" "$Address" "$Pattern").Groups[1].Value
    $Current = "0.0.0.0"
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

    # Update poetry
    New-Item "$Env:AppData\Python\Scripts" -ItemType Directory -EA SI
    $Address = "https://install.python-poetry.org/"
    $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "install-poetry.py")
    Start-Process "python" "`"$Fetched`" --uninstall" -WindowStyle Hidden -Wait
    Start-Process "python" "$Fetched" -WindowStyle Hidden -Wait
    Update-SysPath "$Env:AppData\Python\Scripts" "Machine"
    Start-Process "poetry" "self update" -WindowStyle Hidden -Wait
    Start-Process "poetry" "config virtualenvs.in-project true" -WindowStyle Hidden -Wait

    # # Update visual studio code
    # If ($Null -Ne (Get-Command "code" -EA SI)) {
    #     Start-Process "code" "--install-extension ms-python.python" -WindowStyle Hidden -Wait
    #     Start-Process "code" "--install-extension njpwerner.autodocstring" -WindowStyle Hidden -Wait
    #     Start-Process "code" "--install-extension visualstudioexptteam.vscodeintellicode" -WindowStyle Hidden -Wait
    # }

}

Function Update-Qbittorrent {

    Param (
        [String] $Deposit = "$Env:UserProfile\Downloads\P2P",
        [String] $Loading = "$Env:UserProfile\Downloads\P2P\Incompleted"
    )

    # Update package
    $Address = "https://www.qbittorrent.org/download.php"
    $Pattern = "Latest:\s+v([\d.]+)"
    $Version = (Invoke-Scraper "Html" "$Address" "$Pattern").Groups[1].Value
    $Starter = "$Env:ProgramFiles\qBittorrent\qbittorrent.exe"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://downloads.sourceforge.net/project/qbittorrent/qbittorrent-win32/qbittorrent-$Version/qbittorrent_${Version}_x64_setup.exe"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
    }

    # Create directories
    New-Item "$Deposit" -ItemType Directory -EA SI
    New-Item "$Loading" -ItemType Directory -EA SI

    # Change settings
    $Configs = "$Env:AppData\qBittorrent\qBittorrent.ini"
    New-Item "$(Split-Path "$Configs")" -ItemType Directory -EA SI
    Set-Content -Path "$Configs" -Value "[LegalNotice]"
    Add-Content -Path "$Configs" -Value "Accepted=true"
    Add-Content -Path "$Configs" -Value "[Preferences]"
    Add-Content -Path "$Configs" -Value "Bittorrent\MaxRatio=0"
    Add-Content -Path "$Configs" -Value "Downloads\SavePath=$($Deposit.Replace("\", "/"))"
    Add-Content -Path "$Configs" -Value "Downloads\TempPath=$($Loading.Replace("\", "/"))"
    Add-Content -Path "$Configs" -Value "Downloads\TempPathEnabled=true"

}

Function Update-SevenZip {

    # Update package
    $Address = "https://www.7-zip.org/download.html"
    $Pattern = "Download 7-Zip ([\d.]+)"
    $Version = (Invoke-Scraper "Html" "$Address" "$Pattern").Groups[1].Value
    $Starter = "$Env:ProgramFiles\7-Zip\7zFM.exe"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Version = $Version.Replace(".", "")
        $Address = "https://7-zip.org/a/7z$Version-x64.exe"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
    }
    
    # Adjust association
    # Replaced by NanaZip
    # [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # $Address = "https://raw.githubusercontent.com/DanysysTeam/PS-SFTA/master/SFTA.ps1"
    # Invoke-Expression ((New-Object Net.WebClient).DownloadString("$Address"))
    # Register-FTA "$Starter" -Extension ".7z"

}

Function Update-Sizer {

    # Update package
    $Address = "https://community.chocolatey.org/packages/sizer"
    $Pattern = "Sizer ([\d.]+)</title>"
    $Version = (Invoke-Scraper "Html" "$Address" "$Pattern").Groups[1].Value
    $Starter = "${Env:ProgramFiles(x86)}\Sizer\sizer.exe"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] ($Current.Remove(1, 2)) -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "http://brianapps.net/sizer4/"
        $Pattern = "(sizer4_dev[\d]+.msi)"
        $Address = (Invoke-Scraper "Html" "$Address" "$Pattern").Groups[1].Value
        $Address = "http://brianapps.net/sizer4/$Address"
        $Fetched = Invoke-Fetcher "$Address"
        Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" /qn" -Wait }
        Remove-Desktop "Sizer*.lnk"
    }

}

Function Update-Spotify {

    # Update package
    $Address = "https://raw.githack.com/SpotX-CLI/SpotX-Win/main/scripts/Install_Auto.bat"
    $Fetched = Invoke-Fetcher "$Address"
    Invoke-Gsudo { Invoke-Expression "echo ``n | cmd /c '$Using:Fetched'" }
    Invoke-Gsudo { Start-Sleep 2 ; Stop-Process -Name "Spotify" }
    Remove-Desktop "Spotify*.lnk"

    # Remove autorun
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Spotify" -EA SI

}

Function Update-Temurin {

    # Gather current
    $Current = (Get-Package "*Temurin*" -EA SI).Version

    # Update package
    $Address = "https://api.github.com/repos/adoptium/temurin19-binaries/releases/latest"
    $Results = (Invoke-Scraper "Json" "$Address")[0].assets
    $Address = $Results.Where( { $_.browser_download_url -Like "*jdk_x64_windows*.msi" } ).browser_download_url
    $Version = [Regex]::Matches("$Address", ".*jdk-([\d.]+)").Groups[1].Value
    $Updated = $Null -Ne $Current -And [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Fetched = Invoke-Fetcher "$Address"
        $Adjunct = If ($Present) { "REINSTALL=ALL REINSTALLMODE=amus" } Else { "INSTALLLEVEL=1" }
        Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" $Using:Adjunct /quiet" -Wait }
        Update-SysPath -Deposit "" -Section "Machine"
    }

}

Function Update-VisualStudio2022 {

    Param(
        [String] $Deposit = "$Env:UserProfile\Projects",
        [String] $Serials = "TD244-P4NB7-YQ6XK-Y8MMM-YWV2J",
        [Switch] $Preview
    )

    # Update package
    $Adjunct = If ($Preview) { "Preview" } Else { "Professional" }
    $Storage = "$Env:ProgramFiles\Microsoft Visual Studio\2022\$Adjunct"
    $Starter = "$Storage\Common7\IDE\devenv.exe"
    $Present = Test-Path "$Starter"
    Update-VisualStudio2022Workload "Microsoft.VisualStudio.Workload.CoreEditor" -Preview:$Preview

    # Finish install
    If (-Not $Present) {
        Invoke-Gsudo { Start-Process "$Using:Starter" "/ResetUserData" -Wait }
        Add-Type -AssemblyName "System.Windows.Forms"
        Start-Process -FilePath "$Starter"
        Start-Sleep 15 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 4)
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}") ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep 20 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
    }

    # Change serials
    $Program = "$Storage\Common7\IDE\StorePID.exe"
    Invoke-Gsudo { Start-Process "$Using:Program" "$Using:Serials 09662" -WindowStyle Hidden -Wait }

    # Change highlightcurrentline
    $Config1 = "$Env:LocalAppData\Microsoft\VisualStudio\17*\Settings\CurrentSettings.vssettings"
    $Config2 = "$Env:LocalAppData\Microsoft\VisualStudio\17*\Settings\CurrentSettings-*.vssettings"
    If (Test-Path "$Config1") {
        $Configs = Get-Item "$Config1"
        [Xml] $Content = Get-Content "$Configs"
        $Content.SelectSingleNode("//*[@name='HighlightCurrentLine']").InnerText = "false"
        $Content.Save("$Configs")
    }
    If (Test-Path "$Config2") {
        $Configs = Get-Item "$Config2"
        [Xml] $Content = Get-Content "$Configs"
        $Content.SelectSingleNode("//*[@name='HighlightCurrentLine']").InnerText = "false"
        $Content.Save("$Configs")
    }

    # Change linespacing
    If (Test-Path "$Config1") {
        $Configs = Get-Item "$Config1"
        [Xml] $Content = Get-Content "$Configs"
        $Content.SelectSingleNode("//*[@name='LineSpacing']").InnerText = "1.5"
        $Content.Save($Configs)
    }
    If (Test-Path "$Config2") {
        $Configs = Get-Item "$Config2"
        [Xml] $Content = Get-Content "$Configs"
        $Content.SelectSingleNode("//*[@name='LineSpacing']").InnerText = "1.5"
        $Content.Save($Configs)
    }

    # Change directory
    Remove-Item "$Env:UserProfile\source" -Recurse -EA SI
    New-Item "$Deposit" -ItemType Directory -EA SI | Out-Null
    Invoke-Gsudo { Add-MpPreference -ExclusionPath "$Using:Deposit" *> $Null }
    If (Test-Path "$Config1") {
        $Configs = Get-Item "$Config1"
        [Xml] $Content = Get-Content "$Configs"
        $Payload = $Deposit.Replace("${Env:UserProfile}", '%vsspv_user_appdata%') + "\"
        $Content.SelectSingleNode("//*[@name='ProjectsLocation']").InnerText = "$Payload"
        $Content.Save($Configs)
    }
    If (Test-Path "$Config2") {
        $Configs = Get-Item "$Config2"
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
    $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "VisualStudioSetup.exe")
    Invoke-Gsudo {
        Start-Process "$Using:Fetched" "update --wait --quiet --norestart" -WindowStyle Hidden -Wait
        Start-Process "$Using:Fetched" "install --wait --quiet --norestart --add $Using:Payload" -WindowStyle Hidden -Wait
        Start-Sleep 2 ; Start-Process "cmd" "/c taskkill /f /im devenv.exe /t 2>nul 1>nul" -WindowStyle Hidden -Wait
    }
    
}

# Function Update-VisualStudio2022Preview {

#     Param(
#         [String] $Deposit = "$Env:UserProfile\Projects",
#         [String] $Serials = "TD244-P4NB7-YQ6XK-Y8MMM-YWV2J"
#     )

#     # Update software
#     $Starter = "$Env:ProgramFiles\Microsoft Visual Studio\2022\Preview\Common7\IDE\devenv.exe"
#     $Present = Test-Path "$Starter"
#     Update-VisualStudio2022PreviewWorkload "Microsoft.VisualStudio.Workload.CoreEditor"

#     # Finish installation
#     If (-Not $Present) {
#         Invoke-Gsudo { Start-Process "$Using:Starter" "/ResetUserData" -Wait }
#         Add-Type -AssemblyName "System.Windows.Forms"
#         Start-Process -FilePath "$Starter"
#         Start-Sleep 15 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 4)
#         Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
#         Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}") ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
#         Start-Sleep 20 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 10
#     }

#     # Change serials
#     $Program = "$Env:ProgramFiles\Microsoft Visual Studio\2022\Preview\Common7\IDE\StorePID.exe"
#     Invoke-Gsudo { Start-Process "$Using:Program" "$Using:Serials 09662" -WindowStyle Hidden -Wait } ; Start-Sleep 8

# }

# Function Update-VisualStudio2022PreviewExtension {

#     Param (
#         [String] $Payload
#     )

#     $Website = "https://marketplace.visualstudio.com/items?itemName=$Payload"
#     $Content = Invoke-WebRequest -Uri $Website -UseBasicParsing -SessionVariable Session
#     $Address = $Content.Links | Where-Object { $_.class -Eq "install-button-container" } | Select-Object -ExpandProperty href
#     $Address = "https://marketplace.visualstudio.com" + "$Address"
#     $Package = "$Env:Temp\$([Guid]::NewGuid()).vsix"
#     Invoke-WebRequest "$Address" -OutFile "$Package" -WebSession $Session
#     $Updater = "$Env:ProgramFiles\Microsoft Visual Studio\2022\Preview\Common7\IDE\VSIXInstaller.exe"
#     Invoke-Gsudo { Start-Process "$Using:Updater" "/q /a `"$Using:Package`"" -WindowStyle Hidden -Wait }

# }

# Function Update-VisualStudio2022PreviewWorkload {

#     Param (
#         [String] $Payload
#     )

#     $Address = "https://c2rsetup.officeapps.live.com/c2r/downloadVS.aspx?sku=professional&channel=Preview&version=VS2022"
#     $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "VisualStudioSetup.exe")
#     Invoke-Gsudo {
#         Start-Process "$Using:Fetched" "update --wait --quiet --norestart" -WindowStyle Hidden -Wait
#         Start-Process "$Using:Fetched" "install --wait --quiet --norestart --add $Using:Payload" -WindowStyle Hidden -Wait
#         Start-Sleep 2 ; Start-Process "cmd" "/c taskkill /f /im devenv.exe /t 2>nul 1>nul" -WindowStyle Hidden -Wait
#     }
    
# }

Function Update-VmwareWorkstation {

    Param (
        [String] $Leading = "17",
        [String] $Deposit = "$Env:UserProfile\Machines",
        [String] $Serials = "MC60H-DWHD5-H80U9-6V85M-8280D"
    )

    # Update software
    $Address = "https://softwareupdate.vmware.com/cds/vmw-desktop/ws-windows.xml"
    $Pattern = "url>ws/($Leading.[\d.]+)/(\d+)/windows/core"
    $Version = (Invoke-Scraper "Html" "$Address" "$Pattern").Groups[1].Value
    $Starter = "${Env:ProgramFiles(x86)}\VMware\VMware Workstation\vmware.exe"
    $Present = Test-Path "$Starter"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated) {
        $Address = "https://www.vmware.com/go/getworkstation-win"
        $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "vmware-workstation-full.exe")
        $ArgList = "/s /v`"/qn EULAS_AGREED=1 SERIALNUMBER=$Serials"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Remove-Desktop "VMware*.lnk"
        Start-Process "$Starter" -WindowStyle Hidden ; Start-Sleep 10
        Stop-Process -Name "vmware" ; Start-Sleep 2
    }

    # Update unlocker
    If (-Not $Present -Or $True) {
        $Address = "https://api.github.com/repos/DrDonk/unlocker/releases/latest"
        $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address")[0].tag_name, "[\d.]+").Value
        $Address = "https://github.com/DrDonk/unlocker/releases/download/v$Version/unlocker$($Version.Replace('.', '')).zip"
        $Fetched = Invoke-Fetcher "$Address"
        $Extract = Expand-Archive "$Fetched"
        $Program = Join-Path "$Extract" "windows\unlock.exe"
        Invoke-Gsudo {
            [Environment]::SetEnvironmentVariable("UNLOCK_QUIET", "1", "Process")
            Start-Process "$Using:Program" -WindowStyle Hidden
        }
    }

    # Change directory
    If ($Deposit) {
        New-Item -Path "$Deposit" -ItemType Directory -EA SI | Out-Null
        $Configs = "$Env:AppData\VMware\preferences.ini"
        If (-Not ((Get-Content "$Configs") -Match "prefvmx.defaultVMPath")) { Add-Content -Path "$Configs" -Value "prefvmx.defaultVMPath = `"$Deposit`"" }
    }

    # Remove tray
    Set-ItemProperty -Path "HKCU:\Software\VMware, Inc.\VMware Tray" -Name "TrayBehavior" -Type DWord -Value 2

}

Function Update-Vscode {

    # Update package
    $Address = "https://code.visualstudio.com/sha?build=stable"
    $Version = (Invoke-Scraper "Json" "$Address").products[1].name
    $Starter = "$Env:LocalAppData\Programs\Microsoft VS Code\Code.exe"
    $Current = Expand-Version "$Starter"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"
    If (-Not $Updated -And "$Env:TERM_PROGRAM" -Ne "Vscode") {
        $Address = "https://aka.ms/win32-x64-user-stable"
        $Fetched = Invoke-Fetcher "$Address" (Join-Path "$Env:Temp" "VSCodeUserSetup-x64-Latest.exe")
        $ArgList = "/VERYSILENT /MERGETASKS=`"!runcode`""
        Invoke-Gsudo { Stop-Process -Name "Code" ; Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
        Update-SysPath "$Env:LocalAppData\Programs\Microsoft VS Code\bin" "Machine"
    }

    # Update extensions
    Start-Process "code" "--install-extension github.github-vscode-theme --force" -WindowStyle Hidden -Wait
    Start-Process "code" "--install-extension ms-vscode.powershell --force" -WindowStyle Hidden -Wait

    # Change settings
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
    $NewJson | Add-Member -Type NoteProperty -Name "workbench.colorTheme" -Value "GitHub Dark Default" -Force
    $NewJson | ConvertTo-Json | Set-Content "$Configs"

}

Function Update-Windows {

    # Change hostname
    Rename-Computer -NewName "WINHOGEN" -EA SI

    # Change timezone
    Set-TimeZone -Name "Romance Standard Time"
    Invoke-Gsudo {
        Start-Process "w32tm" "/unregister" -WindowStyle Hidden -Wait
        Start-Process "w32tm" "/register" -WindowStyle Hidden -Wait
        Start-Process "net" "start w32time" -WindowStyle Hidden -Wait
        Start-Process "w32tm" "/resync /force" -WindowStyle Hidden -Wait
    }

    # Enable remove desktop
    Invoke-Gsudo { 
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    }

}

Function Update-Wsl {

    # Enable feature
    Invoke-Restart -Removed
    $Present = Invoke-Gsudo { (Get-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux -Online).State -Eq "Enabled" }
    If (-Not $Present) {
        Invoke-Gsudo { Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart }
        Invoke-Gsudo { Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart }
        Invoke-Restart
    }

    # Update wsl
    Start-Process "wsl" "--update" -WindowStyle Hidden -Wait
    Start-Process "wsl" "--shutdown" -WindowStyle Hidden -Wait
    Start-Process "wsl" "--install ubuntu --no-launch" -WindowStyle Hidden -Wait

    # Update ubuntu
    $Program = "$Env:LocalAppData\Microsoft\WindowsApps\ubuntu.exe"
    Start-Process "$Program" "install --root" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run sudo dpkg --configure -a" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run sudo apt update -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run sudo apt update" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run sudo apt upgrade -y" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run sudo apt full-upgrade -y" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run sudo apt autoremove -y" -WindowStyle Hidden -Wait
    Start-Process "$Program" "run sudo apt install -y x11-apps" -WindowStyle Hidden -Wait

}

Function Update-YtDlg {

    # Update package
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
    Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Prompts ; Enable-PowPlan "Ultimate"
    $Correct = (Update-Gsudo) -And -Not (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
    If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

    # Handle elements
    $Factors = @(
        "Update-NvidiaDriver"
        "Update-IntelHaxm"
        "Update-Windows"

        "Update-AndroidCmdline"
        "Update-AndroidStudio"
        "Update-Chromium"
        "Update-VisualStudio2022"
        "Update-Vscode"

        "Update-Git -GitMail sharpordie@outlook.com -GitUser sharpordie"
        "Update-Bluestacks"
        "Update-Nanazip"
        "Update-DotnetMaui"
        "Update-Figma"
        "Update-Flutter"
        "Update-Jdownloader"
        "Update-JoalDesktop"
        "Update-Keepassxc"
        "Update-Mambaforge"
        # "Update-Miniconda"
        "Update-Mpv"
        # "Update-PaintNet"
        "Update-Postgresql"
        "Update-Python"
        "Update-Qbittorrent"
        # "Update-Sizer"
        # "Update-Spotify"
        # "Update-VmwareWorkstation"
        "Update-YtDlg"

        "Update-Appearance"
    )
    
    # Output progress
    $Maximum = (60 - 20) * -1
    $Shaping = "`r{0,$Maximum}{1,-3}{2,-6}{3,-3}{4,-8}"
    $Heading = "$Shaping" -F "FUNCTION", " ", "STATUS", " ", "DURATION"
    Write-Host "$heading"
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
    Invoke-Expression "gsudo -k" *> $Null ; Enable-Prompts
    
    # Output new line
    Write-Host "`n"

}

Main