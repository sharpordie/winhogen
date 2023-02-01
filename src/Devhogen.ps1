#!/usr/bin/env pwsh

# Output greeting
Clear-Host ; $ProgressPreference = "SilentlyContinue"
Write-Host "+-----------------------------------------------------------------+"
Write-Host "|  > DEVHOGEN                                                     |"
Write-Host "|  > CONFIGURATION SCRIPT FOR DEVELOPERS                          |"
Write-Host "+-----------------------------------------------------------------+"

# Change headline
$Current = "$($Script:MyInvocation.MyCommand.Path)"
$Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName

# Import winhogen
If (Test-Path "$(Split-Path "$Current")\Winhogen.psm1") {
    Import-Module "$(Split-Path "$Current")\Winhogen.psm1" -Force
}
Else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $BaseUrl = "https://raw.githubusercontent.com"
    $Address = "$BaseUrl/sharpordie/winhogen/HEAD/src/Winhogen.psm1"
    Invoke-Expression ((New-Object Net.WebClient).DownloadString("$Address"))
}

# Handle security
$Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
$Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Feature "Uac" ; Update-PowPlan "Ultimate"
$Correct = (Update-Gsudo) -And ! (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

# Remove schedule
$Payload = (Get-Item "$Current").BaseName
Invoke-Gsudo { Unregister-ScheduledTask "$Using:Payload" -Confirm:$False -EA SI }

# Handle elements
$Members = @(
    "Update-System 'Romance Standard Time' 'DEVHOGEN'"
    # "Update-NvidiaCudaDriver"
    "Update-Wsl"
    "Update-AndroidStudio"
    "Update-Chromium"
    "Update-Git 'main' '72373746+sharpordie@users.noreply.github.com' 'sharpordie'"
    # "Update-Pycharm"
    # "Update-VisualStudio2022"
    "Update-VisualStudioCode"
    # "Update-Bluestacks"
    # "Update-DockerDesktop"
    "Update-Flutter"
    "Update-Figma"
    "Update-Jdownloader"
    "Update-Joal"
    "Update-Keepassxc"
    "Update-Mambaforge"
    # "Update-Maui"
    "Update-Mpv"
    "Update-Python"
    "Update-Qbittorrent"
    # "Update-VmwareWorkstation"
    "Update-YtDlg"
)

# Output progress
$Maximum = (67 - 20) * -1
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
Enable-Feature "Uac" ; Invoke-Expression "gsudo -k" *> $Null

# Output new line
Write-Host "`n"