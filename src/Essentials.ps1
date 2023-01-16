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

    $Starter = "7z.exe"
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

    $Version = (Get-Package "$Payload" -EA SI).Version
    If ($Null -Eq $Version) { $Version = (Get-AppxPackage "$Payload" -EA SI).Version }
    If ($Null -Eq $Version) { $Version = "0.0.0.0" }

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

    Param(
        [Switch] $Forcing
    )

    $Current = "$($Script:MyInvocation.MyCommand.Path)"
    $Heading = (Get-Item "$Current").BaseName
    Invoke-Gsudo { Unregister-ScheduledTask -TaskName "$Using:Heading" -Confirm:$False -EA SI }

    If ($Forcing -Or (Assert-Pending) -Eq $True) {
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

}

Function Invoke-Scraper {

    Param(
        [ValidateSet("HtmlContent", "JsonContent", "GithubRelease", "GithubVersion")] [String] $Scraper,
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
            Invoke-Gsudo {
                Start-Process "$Using:Fetched"
                Start-Sleep 10 ; Stop-Process -Name "HD-DisableHyperV"
            }
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
        [ValidateSet("Balanced", "High", "Power", "Ultimate")] [String] $Element = "Balanced"
    )

    $Picking = (powercfg /L | ForEach-Object { If ($_.Contains("($Element")) { $_.Split()[3] } })
    If ([String]::IsNullOrEmpty("$Picking")) { Start-Process "powercfg.exe" "/DUPLICATESCHEME e9a42b02-d5df-448d-aa00-03f14749eb61" -NoNewWindow -Wait }
    $Picking = (powercfg /L | ForEach-Object { If ($_.Contains("($Element")) { $_.Split()[3] } })
    Start-Process "powercfg.exe" "/S $Picking" -NoNewWindow -Wait

    If ($Element -Eq "Ultimate") {
        $Desktop = $Null -Eq (Get-WmiObject Win32_SystemEnclosure -ComputerName "localhost" | Where-Object ChassisTypes -In "{9}", "{10}", "{14}")
        $Desktop = $Desktop -Or $Null -Eq (Get-WmiObject Win32_Battery -ComputerName "localhost")
        If (-Not $Desktop) { Start-Process "powercfg.exe" "/SETACVALUEINDEX $Picking SUB_BUTTONS LIDACTION 000" -NoNewWindow -Wait }
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

Function Update-NvidiaCuda {

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

Function Update-NvidiaDriver {

    $Current = Expand-Version "NVIDIA Graphics Driver*"

    $Address = "https://community.chocolatey.org/packages/nvidia-display-driver"
    $Version = Invoke-Scraper "HtmlContent" "$Address" "NVidia Display Driver ([\d.]+)</title>"
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Address = "https://us.download.nvidia.com/Windows/$Version/$Version-desktop-win10-win11-64bit-international-dch-whql.exe"
        $Fetched = Invoke-Fetcher "$Address"
        $Deposit = Expand-Archive "$Fetched"
        Invoke-Gsudo { Start-Process "$Using:Deposit\setup.exe" "Display.Driver HDAudio.Driver -clean -s -noreboot" -Wait }
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

    # Handle elements
    $Factors = @(
        "Update-NvidiaDriver"
        "Update-NvidiaCuda"

        "Update-Nanazip"
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
    Invoke-Expression "gsudo -k" *> $Null ; Enable-Feature "Uac"
    
    # Output new line
    Write-Host "`n"

}

Main