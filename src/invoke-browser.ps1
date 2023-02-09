

Function Invoke-Restart {

    Update-Powershell
    $Current = $Script:MyInvocation.MyCommand.Path
    $Heading = (Get-Item "$Current").BaseName
    $Deposit = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    $Program = "$Env:LocalAppData\Microsoft\WindowsApps\wt.exe"
    $Command = "$Program --title `"$Heading`" pwsh -ep bypass -noexit -nologo -file `"$Current`""
    New-ItemProperty "$Deposit" "$Heading" -Value "$Command"
    Invoke-Gsudo { Get-LocalUser -Name "$Env:Username" | Set-LocalUser -Password ([SecureString]::New()) }
    Start-Sleep 4 ; Restart-Computer -Force

}

Function Update-Powershell {

    $Current = $PSVersionTable.PSVersion.ToString()

    $Address = "https://api.github.com/repos/powershell/powershell/releases/latest"
    $Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        Invoke-Gsudo { Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet" }
        Invoke-Restart
    }

}

Invoke-Browser