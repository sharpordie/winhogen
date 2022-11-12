Function Main {

    # Import modules
    Import-Module -Name "$PSScriptRoot\Modules.psm1" -Force

    # Change title
    $Current = "$($Script:MyInvocation.MyCommand.Path)"
    $Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName

    # Output welcome
    Clear-Host ; $ProgressPreference = "SilentlyContinue"
    Write-Host "+----------------------------------------------------------+"
    Write-Host "|                                                          |"
    Write-Host "|  > WINHOGEN                                              |"
    Write-Host "|                                                          |"
    Write-Host "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                   |"
    Write-Host "|                                                          |"
    Write-Host "+----------------------------------------------------------+"
    
    # Remove restrictions
    $Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
    $Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
    Write-Host "$Loading" -FO DarkYellow -NoNewline ; Enable-PowPlan "Ultimate"
    $Correct = (Update-Gsudo) -And -Not (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
    If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

    # Handle functions
    $Factors = @(
        "Update-Git -GitMail sharpordie@outlook.com -GitUser sharpordie"
        "Update-NvidiaDriver"
        "Update-NvidiaGeforceExperience"
        "Update-AndroidStudio"
        "Update-Chromium"
        "Update-Vscode"
        "Update-Bluestacks"
        "Update-Flutter"
        "Update-Jdownloader"
        "Update-Keepassxc"
        "Update-Mpv"
        "Update-Python"
        "Update-Qbittorrent"
        "Update-Sizer"
        "Update-Spotify"
        "Update-Wsl"
        "Update-YtDlg"
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
    
    # Revert restrictions
    Invoke-Expression "gsudo -k" *> $Null
    
    # Output newline
    Write-Host "`n"

}

Main