#!/usr/bin/env pwsh

Clear-Host

$Current = $Script:MyInvocation.MyCommand.Path
$Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName
echo "(Split-Path "$Current")\winhogen.psm1"
Import-Module "(Split-Path "$Current")\winhogen.psm1" -Force

Write-Output "+-------------------------------------------------------------------------+"
Write-Output "|                                                                         |"
Write-Output "|  > GAMHOGEN                                                             |"
Write-Output "|                                                                         |"
Write-Output "|  > CONFIGURATION SCRIPT FOR GAMING PURPOSE                              |"
Write-Output "|                                                                         |"
Write-Output "+-------------------------------------------------------------------------+"

Update-Ldplayer