#!/usr/bin/env pwsh

# Output greeting
Clear-Host ; $Global:ProgressPreference = "SilentlyContinue"
Write-Host "+-----------------------------------------------------------------+"
Write-Host "|                                                                 |"
Write-Host "|  > GAMHOGEN                                                     |"
Write-Host "|                                                                 |"
Write-Host "|  > CONFIGURATION SCRIPT FOR GAMERS                              |"
Write-Host "|                                                                 |"
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
Write-Host "$Loading" -NoNewline ; Remove-Feature "Uac" ; Update-PowPlan "Ultimate"
$Correct = (Update-Gsudo) -And ! (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

# Remove schedule
$Payload = (Get-Item "$Current").BaseName
Invoke-Gsudo { Unregister-ScheduledTask "$Using:Payload" -Confirm:$False -EA SI }

# Handle members
$Members = @(
    "Update-System 'Romance Standard Time' 'GAMHOGEN'"
    "Update-NvidiaGameDriver"
    "Update-Qbittorrent"
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