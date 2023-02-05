#!/usr/bin/env pwsh

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
        [ValidateSet("HyperV", "Uac", "Wsl")] [String] $Feature
    )

    Switch ($Feature) {
        "HyperV" {
            $Enabled = Invoke-Gsudo { (Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online).State -Eq "Enabled" }
            If (-Not $Enabled) {
                $Address = "https://cdn3.bluestacks.com/support_files/HD-EnableHyperV.exe"
                $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
				(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
                Invoke-Gsudo {
                    Start-Process "$Using:Fetched"
                    Start-Sleep 10
                    Stop-Process -Name "HD-EnableHyperV"
                }
                If (Assert-Pending -Eq $True) { Invoke-Restart }
            }
        }
        "Uac" {
            $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
            [IO.File]::WriteAllText("$Created", @(
                    '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
                    'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 5'
                    'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 1'
                ) -Join "`n")
            Try { Start-Process "powershell" "-ep bypass -file `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait } Catch { }
            Remove-Item "$Created" -Force
        }
        "Wsl" {
            $Enabled = Invoke-Gsudo { (Get-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux -Online).State -Eq "Enabled" }
            If (-Not $Enabled) {
                Invoke-Gsudo {
                    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart *> $Null
                    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart *> $Null
                }
                If (Assert-Pending -Eq $True) { Invoke-Restart }
            }
        }
    }

}

Function Invoke-Restart {

    $Current = $Script:MyInvocation.MyCommand.Path
    $Deposit = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    $Command = "wt powershell -ep bypass -noexit -nologo -file `"$Current`""
    New-ItemProperty "$Deposit" "." -Value "$Command"
    Update-Account "$Env:Username" ([SecureString]::New())
    Restart-Computer -Force

}

Function Remove-Feature {

    Param(
        [ValidateSet("HyperV", "Uac")] [String] $Feature
    )

    Switch ($Feature) {
        "HyperV" {
            $Enabled = Invoke-Gsudo { (Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online).State -Eq "Enabled" }
            If ($Enabled) {
                $Address = "https://cdn3.bluestacks.com/support_files/HD-DisableHyperV_native_v2.exe"
                $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
				(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
                Invoke-Gsudo {
                    Start-Process "$Using:Fetched"
                    Start-Sleep 10
                    Stop-Process -Name "HD-DisableHyperV"
                }
                If (Assert-Pending -Eq $True) { Invoke-Restart }
            }
        }
        "Uac" {
            $Created = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), "ps1")
            [IO.File]::WriteAllText("$Created", @(
                    '$KeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"'
                    'Set-ItemProperty -Path "$KeyPath" -Name ConsentPromptBehaviorAdmin -Value 0'
                    'Set-ItemProperty -Path "$KeyPath" -Name PromptOnSecureDesktop -Value 0'
                ) -Join "`n")
            Try { Start-Process "powershell" "-ep bypass -file `"$Created`"" -Verb RunAs -WindowStyle Hidden -Wait } Catch { }
            Remove-Item "$Created" -Force
        }
    }

}

Function Rename-Machine {

    Param(
        [String] $Machine,
        [Switch] $Restart
    )

    If ((Hostname) -Ne "$Machine") {
        Invoke-Gsudo { Rename-Computer "$Using:Machine" -Force -Passthru *> $Null }
        If ($Restart) { Invoke-Restart }
    }

}

Function Update-Account {

    Param(
        [String] $Account = "$Env:Username",
        [SecureString] $Private
    )

    Invoke-Gsudo {
        $Current = Get-LocalUser -Name "$Using:Account"
        $Current | Set-LocalUser -Password $Using:Private
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

#Region Updaters

Function Update-Gsudo {

    $Current = (Get-Package "*gsudo*" -EA SI).Version
    If ($Null -Eq $Current) { $Current = "0.0.0.0" }
    $Present = $Current -Ne "0.0.0.0"

    If ($Present) { Return $True }

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
        Update-SysPath "${Env:ProgramFiles(x86)}\gsudo" "Process"
        Return $True
    }
    Catch { 
        Return $False
    }

}

#EndRegion

Function Main {

    $Current = $Script:MyInvocation.MyCommand.Path
    $Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName
    $ProgressPreference = "SilentlyContinue"

    Clear-Host
    Write-Host "+-------------------------------------------------------------+"
    Write-Host "|                                                             |"
    Write-Host "|  > WINHOGEN                                                 |"
    Write-Host "|  > CONFIGURATION SCRIPT FOR DEVELOPERS                      |"
    Write-Host "|                                                             |"
    Write-Host "+-------------------------------------------------------------+"

    $Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
    $Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
    Write-Host "$Loading" -FO DarkYellow -NoNewline
    Remove-Feature "Uac"
    Update-PowPlan "Ultimate"
    $Correct = (Update-Gsudo) -And ! (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
    If (-Not $Correct) {
        Write-Host "$Failure" -FO Red
        Write-Host
        Exit
    }

    $Members = @(
        "Rename-Machine 'WINHOGEN' -Restart"
    )

    $Maximum = (63 - 20) * -1
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

    Enable-Feature "Uac"
    Invoke-Expression "gsudo -k" *> $Null
    Write-Host "`n"

}

Main