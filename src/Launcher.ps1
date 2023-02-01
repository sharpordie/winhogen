[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Address = "hhttps://raw.githubusercontent.com/sharpordie/winhogen/main/src/Winhogen.psm1"
Invoke-Expression ((New-Object Net.WebClient).DownloadString("$Address"))

Clear-Host ; $ProgressPreference = "SilentlyContinue"
Write-Host "+----------------------------------------------------------+"
Write-Host "|                                                          |"
Write-Host "|  > WINHOGEN (NEW)                                        |"
Write-Host "|                                                          |"
Write-Host "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                   |"
Write-Host "|                                                          |"
Write-Host "+----------------------------------------------------------+"

$Current = "$($Script:MyInvocation.MyCommand.Path)"
$Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName

$Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
$Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Feature "Uac" ; Update-PowPlan "Ultimate"
$Correct = (Update-Gsudo) -And -Not (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

$Payload = (Get-Item "$Current").BaseName
Invoke-Gsudo { Unregister-ScheduledTask -TaskName "$Using:Payload" -Confirm:$False -EA SI }

$Factors = @(
    "Update-Windows"
    # "Update-Cuda"
    # "Update-Wsa"
    # "Update-Wsl"

    "Update-AndroidStudio"
    "Update-Chromium"
    "Update-Git -GitMail 72373746+sharpordie@users.noreply.github.com -GitUser sharpordie"
    # "Update-Pycharm"
    "Update-VisualStudio2022"
    "Update-Vscode"
		
    # "Update-Bluestacks"
    "Update-Docker"
    "Update-Flutter"
    "Update-Figma"
    # "Update-Jdownloader"
    # "Update-Joal"
    # "Update-Keepassxc"
    # "Update-Mambaforge"
    # "Update-Maui"
    "Update-Mpv"
    # "Update-Python"
    # "Update-Qbittorrent"
    "Update-VmwareWorkstation"
    "Update-YtDlg"
)

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

Enable-Feature "Uac" ; Invoke-Expression "gsudo -k" *> $Null
	
Write-Host "`n"