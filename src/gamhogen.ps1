#!/usr/bin/env pwsh

# Change headline
Clear-Host ; $Current = $Script:MyInvocation.MyCommand.Path
$Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName.ToUpper()

# Output greeting
Write-Output "+-------------------------------------------------------------------------+"
Write-Output "|                                                                         |"
Write-Output "|  > GAMHOGEN                                                             |"
Write-Output "|                                                                         |"
Write-Output "|  > CONFIGURATION SCRIPT FOR GAMING PURPOSE                              |"
Write-Output "|                                                                         |"
Write-Output "+-------------------------------------------------------------------------+"

# Import winhogen
Import-Module "$(Split-Path "$Current")\winhogen.psm1" -Force

# Handle security
$Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
$Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Feature "Uac" ; Update-PowPlan "Ultimate"
$Correct = (Update-Gsudo) -And ! (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

# Handle elements
$Members = @(
    "Update-Windows 'Romance Standard Time' 'GAMHOGEN'"
    "Update-Ldplayer"
)

# Output progress
$Maximum = (75 - 20) * -1
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
Enable-Feature "Uac" ; gsudo -k *> $Null

# Output new line
Write-Host "`n"