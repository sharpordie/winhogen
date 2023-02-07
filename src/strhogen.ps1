#!/usr/bin/env pwsh

Clear-Host ; $Current = $Script:MyInvocation.MyCommand.Path
$Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName.ToUpper()
Import-Module "$(Split-Path "$Current")\winhogen.psm1" -Force

Write-Output "+-------------------------------------------------------------------------+"
Write-Output "|                                                                         |"
Write-Output "|  > STRHOGEN                                                             |"
Write-Output "|                                                                         |"
Write-Output "|  > CONFIGURATION SCRIPT FOR STREAM PURPOSE                              |"
Write-Output "|                                                                         |"
Write-Output "+-------------------------------------------------------------------------+"