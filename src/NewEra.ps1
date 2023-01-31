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
		[ValidateSet("Uac", "Wsl")] [String] $Feature
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
		"Wsl" {
			$Present = Invoke-Gsudo { (Get-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux -Online).State -Eq "Enabled" }
			If (-Not $Present) {
				Invoke-Gsudo { Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart }
				Invoke-Gsudo { Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart }
			}
		}
	}

	If (Assert-Pending -Eq $True) { Invoke-Restart }

}

Function Invoke-Restart {

	$Current = "$($Script:MyInvocation.MyCommand.Path)"
	$Heading = (Get-Item "$Current").BaseName
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
	Start-Sleep 2 ; Restart-Computer -Force

}

Function Remove-Feature {

	Param(
		[ValidateSet("HyperV", "Uac")] [String] $Feature
	)

	Switch ($Feature) {
		"HyperV" { 
			$Address = "https://cdn3.bluestacks.com/support_files/HD-DisableHyperV_native_v2.exe"
			$Fetched = Invoke-Fetcher "$Address"
			Invoke-Gsudo { Start-Process "$Using:Fetched" ; Start-Sleep 10 ; Stop-Process -Name "HD-DisableHyperV" }
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

Function Update-SysPath {

	Param (
		[String] $Payload,
		[ValidateSet("Machine", "Process", "User")] [String] $Section
	)

	If ($Section -Ne "Process" ) {
		$OldPath = [Environment]::GetEnvironmentVariable("PATH", "$Section")
		$OldPath = $OldPath -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Payload))\\?" }
		$NewPath = ($OldPath + $Payload) -Join ";"
		Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PATH", "$Using:NewPath", "$Using:Section") }
	}

	$OldPath = $Env:Path -Split ";" | Where-Object { $_ -NotMatch "^$([Regex]::Escape($Payload))\\?" }
	$NewPath = ($OldPath + $Payload) -Join ";" ; $Env:Path = $NewPath -Join ";"

}

Function Update-AndroidCmdline {

	$SdkHome = "$Env:LocalAppData\Android\Sdk"
	$Starter = "$SdkHome\cmdline-tools\latest\bin\sdkmanager.bat"
	$Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-90)

	If (-Not $Updated) {
		$Address = "https://developer.android.com/studio#command-tools"
		$Release = ([Regex]::Matches((Invoke-WebRequest "$Address"), "commandlinetools-win-(\d+)")).Groups[1].Value
		$Address = "https://dl.google.com/android/repository/commandlinetools-win-${Release}_latest.zip"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Update-Nanazip ; $Extract = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName
		Start-Process "7z.exe" "x `"$Fetched`" -o`"$Extract`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
		Start-Sleep 4 ; New-Item "$SdkHome" -ItemType Directory -EA SI
		Update-Openjdk ; $Manager = "$Extract\cmdline-tools\bin\sdkmanager.bat"
		Write-Output yes | & "$Manager" --sdk_root="$SdkHome" "cmdline-tools;latest"
		Start-Sleep 4
	}

	Invoke-Gsudo { [Environment]::SetEnvironmentVariable("ANDROID_HOME", "$Using:SdkHome", "Machine") }
	[Environment]::SetEnvironmentVariable("ANDROID_HOME", "$SdkHome", "Process")
	Update-SysPath "$SdkHome\cmdline-tools\latest\bin" "Machine"
	Update-SysPath "$SdkHome\emulator" "Machine"
	Update-SysPath "$SdkHome\platform-tools" "Machine"

}

Function Update-AndroidStudio {

	$Starter = "$Env:ProgramFiles\Android\Android Studio\bin\studio64.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	$Present = $Current -Ne "0.0.0.0"

	$Address = "https://raw.githubusercontent.com/scoopinstaller/extras/master/bucket/android-studio.json"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).version, "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 6))

	If (-Not $Updated) {
		$Address = "https://redirector.gvt1.com/edgedl/android/studio/install/$Version/android-studio-$Version-windows.exe"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
		Start-Sleep 4
	}

	If (-Not $Present) {
		Update-AndroidCmdline
		Write-Output yes | sdkmanager "build-tools;33.0.1"
		Write-Output yes | sdkmanager "emulator"
		Write-Output yes | sdkmanager "extras;intel;Hardware_Accelerated_Execution_Manager"
		Write-Output yes | sdkmanager "platform-tools"
		Write-Output yes | sdkmanager "platforms;android-33"
		Write-Output yes | sdkmanager "platforms;android-33-ext4"
		Write-Output yes | sdkmanager "sources;android-33"
		Write-Output yes | sdkmanager "system-images;android-33;google_apis;x86_64"
		Write-Output yes | sdkmanager --licenses
		avdmanager create avd -n "Pixel_3_API_33" -d "pixel_3" -k "system-images;android-33;google_apis;x86_64"
	}

	If (-Not $Present) {
		Add-Type -AssemblyName System.Windows.Forms
		Start-Process "$Starter" ; Start-Sleep 10
		[Windows.Forms.SendKeys]::SendWait("{TAB}") ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 20
		[Windows.Forms.SendKeys]::SendWait("{TAB}" * 2) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
		[Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
		[Windows.Forms.SendKeys]::SendWait("{TAB}" * 2) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
		[Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
		[Windows.Forms.SendKeys]::SendWait("{TAB}" * 3) ; Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 2
		[Windows.Forms.SendKeys]::SendWait("{ENTER}") ; Start-Sleep 6
		[Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
	}

}

Function Update-Chromium {

	Param (
		[String] $Deposit = "$Env:UserProfile\Downloads\DDL",
		[String] $Startup = "about:blank"
	)

	$Starter = "$Env:ProgramFiles\Chromium\Application\chrome.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString().Replace(".0", "") } Catch { "0.0.0.0" }
	$Present = $Current -Ne "0.0.0.0"

	$Address = "https://api.github.com/repos/macchrome/winchrome/releases/latest"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"
	
	If (-Not $Updated) {
		$Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
		$Address = $Results.Where( { $_.browser_download_url -Like "*installer.exe" } ).browser_download_url
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "$Using:Fetched" "--system-level --do-not-launch-chrome" -Wait }
		Start-Sleep 4
	}

	If (-Not $Present) {
		Add-Type -AssemblyName System.Windows.Forms
		New-Item "$Deposit" -ItemType Directory -EA SI
		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://settings/")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("before downloading")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 3)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("$Deposit")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("custom-ntp")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 5)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("^a")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("$Startup")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 2)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://settings/")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("search engines")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 3)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("duckduckgo")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("extension-mime-request-handling")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 2)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("hide-sidepanel-button")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("remove-tabsearch-button")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("win-10-tab-search-caption-button")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 2)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://flags/")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("show-avatar-button")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}" * 6)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}" * 3)
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Start-Process "$Starter" "--lang=en --start-maximized"
		Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("^+b")
		Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2

		Remove-Item "$Env:Public\Desktop\Chromium*.lnk" -EA SI
		Remove-Item "$Env:UserProfile\Desktop\Chromium*.lnk" -EA SI

		$Address = "https://api.github.com/repos/NeverDecaf/chromium-web-store/releases/latest"
		$Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
		$Address = $Results.Where( { $_.browser_download_url -Like "*.crx" } ).browser_download_url
		Update-ChromiumExtension "$Address"

		Update-ChromiumExtension "omoinegiohhgbikclijaniebjpkeopip" # clickbait-remover-for-you
		Update-ChromiumExtension "bcjindcccaagfpapjjmafapmmgkkhgoa" # json-formatter
		Update-ChromiumExtension "ibplnjkanclpjokhdolnendpplpjiace" # simple-translate
		Update-ChromiumExtension "mnjggcdmjocbbbhaepdhchncahnbgone" # sponsorblock-for-youtube
		Update-ChromiumExtension "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock-origin
	}

	Update-ChromiumExtension "https://github.com/iamadamdev/bypass-paywalls-chrome/archive/master.zip"

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$Address = "https://raw.githubusercontent.com/DanysysTeam/PS-SFTA/master/SFTA.ps1"
	Invoke-Expression ((New-Object Net.WebClient).DownloadString("$Address"))
	$FtaList = @(".htm", ".html", ".pdf", ".shtml", ".svg", ".xht", ".xhtml")
	Foreach ($Element In $FtaList) { Set-FTA "ChromiumHTM" "$Element" }
	$PtaList = @("ftp", "http", "https")
	Foreach ($Element In $PtaList) { Set-PTA "ChromiumHTM" "$Element" }

}

Function Update-ChromiumExtension {

	Param (
		[String] $Payload
	)

	$Package = $Null
	$Starter = "$Env:ProgramFiles\Chromium\Application\chrome.exe"
	If (Test-path "$Starter") {
		If ($Payload -Like "http*") {
			$Address = "$Payload"
			$Package = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
			(New-Object Net.WebClient).DownloadFile("$Address", "$Package")
		}
		Else {
			$Version = Try { (Get-Item "$Starter" -EA SI).VersionInfo.FileVersion.ToString() } Catch { "0.0.0.0" }
			$Address = "https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3"
			$Address = "${Address}&prodversion=${Version}&x=id%3D${Payload}%26installsource%3Dondemand%26uc"
			$Package = Join-Path "$Env:Temp" "$Payload.crx"
			(New-Object Net.WebClient).DownloadFile("$Address", "$Package")
		}
		If ($Null -Ne $Package -And (Test-Path "$Package")) {
			Add-Type -AssemblyName System.Windows.Forms
			If ($Package -Like "*.zip") {
				$Deposit = "$Env:ProgramFiles\Chromium\Unpacked\$($Payload.Split("/")[4])"
				$Present = Test-Path "$Deposit"
				Invoke-Gsudo { New-Item "$Using:Deposit" -ItemType Directory -EA SI }
				Update-Nanazip ; $Extract = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName
				Start-Process "7z.exe" "x `"$Package`" -o`"$Extract`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
				$Topmost = (Get-ChildItem -Path "$Extract" -Directory | Select-Object -First 1).FullName
				Invoke-Gsudo { Copy-Item -Path "$Using:Topmost\*" -Destination "$Using:Deposit" -Recurse -Force }
				If ($Present) { Return }
				Start-Process "$Starter" "--lang=en --start-maximized"
				Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://extensions/")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("$Deposit")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
				Start-Process "$Starter" "--lang=en --start-maximized"
				Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("^l")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("chrome://extensions/")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{TAB}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
			}
			Else {
				Start-Process "$Starter" "`"$Package`" --start-maximized --lang=en"
				Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("{DOWN}")
				Start-Sleep 2 ; [Windows.Forms.SendKeys]::SendWait("{ENTER}")
				Start-Sleep 4 ; [Windows.Forms.SendKeys]::SendWait("%{F4}") ; Start-Sleep 2
			}
		}
	}

}

Function Update-Cuda {

	$Current = (Get-Package "*cuda*runtime*" -EA SI).Version
	If ($Null -Eq $Current) { $Current = "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://raw.githubusercontent.com/scoopinstaller/main/master/bucket/cuda.json"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).version, "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] $Version.SubString(0, 4)

	If (-Not $Updated) {
		$Address = (Invoke-WebRequest "$Address" | ConvertFrom-Json).architecture."64bit".url.Replace("#/dl.7z", "")
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "$Using:Fetched" "/s /noreboot" -Wait }
		Remove-Item "$Env:Public\Desktop\GeForce*.lnk" -EA SI
		Remove-Item "$Env:UserProfile\Desktop\GeForce*.lnk" -EA SI
	}

}

Function Update-DockerDesktop {

	$Starter = "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://community.chocolatey.org/packages/docker-desktop"
	$Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "Docker Desktop ([\d.]+)</title>").Groups[1].Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Address = "https://desktop.docker.com/win/stable/Docker Desktop Installer.exe"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "$Using:Fetched" "install --quiet --accept-license" -Wait }
		Start-Sleep 4
		Remove-Item "$Env:Public\Desktop\Docker*.lnk" -EA SI
		Remove-Item "$Env:UserProfile\Desktop\Docker*.lnk" -EA SI
	}

}

Function Update-Figma {

	$Starter = "$Env:LocalAppData\Figma\Figma.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	$Present = $Current -Ne "0.0.0.0"

	$Address = "https://desktop.figma.com/win/RELEASE.json"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).version, "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Address = "https://desktop.figma.com/win/FigmaSetup.exe"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		$ArgList = "/s /S /q /Q /quiet /silent /SILENT /VERYSILENT"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
		Start-Sleep 4
	}

	If (-Not $Present) {
		Start-Sleep 4 ; Start-Process "$Starter" ; Start-Sleep 8
		Stop-Process -Name "Figma" -EA SI ; Stop-Process -Name "figma_agent" -EA SI ; Start-Sleep 4
		$Configs = Get-Content "$Env:AppData\Figma\settings.json" | ConvertFrom-Json
		Try { $Configs.showFigmaInMenuBar = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "showFigmaInMenuBar" -Value $False }
		$Configs | ConvertTo-Json | Set-Content "$Env:AppData\Figma\settings.json"
	}

}

Function Update-Flutter {

	$Deposit = "$Env:LocalAppData\Android\Flutter"
	Update-Git ; git clone "https://github.com/flutter/flutter.git" -b stable "$Deposit"
	Start-Sleep 4

	Update-SysPath "$Deposit\bin" "Machine"
	flutter channel stable ; flutter precache ; flutter upgrade
	Write-Output $("yes " * 10) | flutter doctor --android-licenses
	dart --disable-analytics ; flutter config --no-analytics

	$Browser = "$Env:ProgramFiles\Chromium\Application\chrome.exe"
	If (Test-Path "$Browser") {
		Invoke-Gsudo { [Environment]::SetEnvironmentVariable("CHROME_EXECUTABLE", "$Using:Browser", "Machine") }
		[Environment]::SetEnvironmentVariable("CHROME_EXECUTABLE", "$Browser", "Process")
	}

	$Product = "$Env:ProgramFiles\Android\Android Studio"
	Update-JetbrainsPlugin "$Product" "6351"  # dart
	Update-JetbrainsPlugin "$Product" "9212"  # flutter
	Update-JetbrainsPlugin "$Product" "13666" # flutter-intl
	Update-JetbrainsPlugin "$Product" "14641" # flutter-riverpod-snippets

	Update-VscodeExtension "Dart-Code.flutter"
	Update-VscodeExtension "alexisvt.flutter-snippets"
	Update-VscodeExtension "pflannery.vscode-versionlens"
	Update-VscodeExtension "robert-brunhage.flutter-riverpod-snippets"
	Update-VscodeExtension "usernamehw.errorlens"

}

Function Update-Git {

	Param (
		[String] $Default = "main",
		[String] $GitMail,
		[String] $GitUser
	)

	$Starter = "$Env:ProgramFiles\Git\git-bash.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://api.github.com/repos/git-for-windows/git/releases/latest"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name.Replace("windows.", ""), "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
		$Address = $Results.Where( { $_.browser_download_url -Like "*64-bit.exe" } ).browser_download_url
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		$ArgList = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART, /NOCANCEL, /SP- /COMPONENTS=`"`""
		Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
		Start-Sleep 4
	}

	Update-SysPath "$Env:ProgramFiles\Git\cmd" "Process"
	If (-Not [String]::IsNullOrWhiteSpace($GitMail)) { git config --global user.email "$GitMail" }
	If (-Not [String]::IsNullOrWhiteSpace($GitUser)) { git config --global user.name "$GitUser" }
	git config --global http.postBuffer 1048576000
	git config --global init.defaultBranch "$Default"
	
}

Function Update-Gsudo {

	$Current = (Get-Package "*gsudo*" -EA SI).Version
	If ($Null -Eq $Current) { $Current = "0.0.0.0" }
	$Present = $Current -Ne "0.0.0.0"

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

Function Update-Jdownloader {

	Param (
		[String] $Deposit = "$Env:UserProfile\Downloads\JD2"
	)

	$Starter = "$Env:ProgramFiles\JDownloader\JDownloader2.exe"
	$Present = Test-Path "$Starter"

	If (-Not $Present) {
		$Address = "http://installer.jdownloader.org/clean/JD2SilentSetup_x64.exe"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "$Using:Fetched" "-q" -Wait }
		Start-Sleep 4
		Remove-Item "$Env:Public\Desktop\JDownloader*.lnk" -EA SI
		Remove-Item "$Env:UserProfile\Desktop\JDownloader*.lnk" -EA SI
	}

	If (-Not $Present) {
		New-Item "$Deposit" -ItemType Directory -EA SI
		$AppData = "$Env:ProgramFiles\JDownloader\cfg"
		$Config1 = "$AppData\org.jdownloader.settings.GeneralSettings.json"
		$Config2 = "$AppData\org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
		$Config3 = "$AppData\org.jdownloader.extensions.extraction.ExtractionExtension.json"
		Start-Process "$Starter" ; While (-Not (Test-Path "$Config1")) { Start-Sleep 2 }
		Stop-Process -Name "JDownloader2" -EA SI ; Start-Sleep 2
		$Configs = Get-Content "$Config1" | ConvertFrom-Json
		Try { $Configs.defaultdownloadfolder = "$Deposit" } Catch { $Configs | Add-Member -Type NoteProperty -Name "defaultdownloadfolder" -Value "$Deposit" }
		Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config1" }
		$Configs = Get-Content "$Config2" | ConvertFrom-Json
		Try { $Configs.bannerenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "bannerenabled" -Value $False }
		Try { $Configs.clipboardmonitored = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "clipboardmonitored" -Value $False }
		Try { $Configs.donatebuttonlatestautochange = 4102444800000 } Catch { $Configs | Add-Member -Type NoteProperty -Name "donatebuttonlatestautochange" -Value 4102444800000 }
		Try { $Configs.donatebuttonstate = "AUTO_HIDDEN" } Catch { $Configs | Add-Member -Type NoteProperty -Name "donatebuttonstate" -Value "AUTO_HIDDEN" }
		Try { $Configs.myjdownloaderviewvisible = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "myjdownloaderviewvisible" -Value $False }
		Try { $Configs.premiumalertetacolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalertetacolumnenabled" -Value $False }
		Try { $Configs.premiumalertspeedcolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalertspeedcolumnenabled" -Value $False }
		Try { $Configs.premiumalerttaskcolumnenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "premiumalerttaskcolumnenabled" -Value $False }
		Try { $Configs.specialdealoboomdialogvisibleonstartup = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "specialdealoboomdialogvisibleonstartup" -Value $False }
		Try { $Configs.specialdealsenabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "specialdealsenabled" -Value $False }
		Try { $Configs.speedmetervisible = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "speedmetervisible" -Value $False }
		Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config2" }
		$Configs = Get-Content "$Config3" | ConvertFrom-Json
		Try { $Configs.enabled = $False } Catch { $Configs | Add-Member -Type NoteProperty -Name "enabled" -Value $False }
		Invoke-Gsudo { $Using:Configs | ConvertTo-Json | Set-Content "$Using:Config3" }
		Update-ChromiumExtension "fbcohnmimjicjdomonkcbcpbpnhggkip" # myjdownloader-browser-ext
	}

}

Function Update-JetbrainsPlugin {

	Param(
		[String] $Deposit,
		[String] $Element
	)

	If (-Not (Test-Path "$Deposit") -Or ([String]::IsNullOrWhiteSpace($Element))) { Return 0 }
	$Release = (Get-Content "$Deposit\product-info.json" | ConvertFrom-Json).buildNumber
	$Release = [Regex]::Matches("$Release", "([\d.]+)\.").Groups[1].Value
	$DataDir = (Get-Content "$Deposit\product-info.json" | ConvertFrom-Json).dataDirectoryName
	$Adjunct = If ("$DataDir" -Like "AndroidStudio*") { "Google\$DataDir" } Else { "JetBrains\$DataDir" }
	$Plugins = "$Env:AppData\$Adjunct\plugins" ; New-Item "$Plugins" -ItemType Directory -EA SI
	:Outer For ($I = 1; $I -Le 3; $I++) {
		$Address = "https://plugins.jetbrains.com/api/plugins/$Element/updates?page=$I"
		$Content = Invoke-WebRequest "$Address" | ConvertFrom-Json
		For ($J = 0; $J -Le 19; $J++) {
			$Maximum = $Content["$J"].until.Replace("`"", "").Replace("*", "9999")
			$Minimum = $Content["$J"].since.Replace("`"", "").Replace("*", "9999")
			If ([String]::IsNullOrWhiteSpace($Maximum)) { $Maximum = "9999.0" }
			If ([String]::IsNullOrWhiteSpace($Minimum)) { $Maximum = "0000.0" }
			If ([Version] "$Minimum" -Le "$Release" -And "$Release" -Le "$Maximum") {
				$Address = $Content["$J"].file.Replace("`"", "")
				$Address = "https://plugins.jetbrains.com/files/$Address"
				$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
				(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
				Update-Nanazip ; Start-Process "7z.exe" "x `"$Fetched`" -o`"$Plugins`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
				Break Outer
			}
		}
		Start-Sleep 1
	}

}

Function Update-JoalDesktop {

	$Starter = "$Env:LocalAppData\Programs\joal-desktop\JoalDesktop.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://api.github.com/repos/anthonyraymond/joal-desktop/releases/latest"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
		$Address = $Results.Where( { $_.browser_download_url -Like "*win-x64.exe" } ).browser_download_url
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
		Start-Sleep 4
		Remove-Item "$Env:Public\Desktop\Joal*.lnk" -EA SI
		Remove-Item "$Env:UserProfile\Desktop\Joal*.lnk" -EA SI
	}

}

Function Update-Keepassxc {

	$Starter = "$Env:ProgramFiles\KeePassXC\KeePassXC.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://api.github.com/repos/keepassxreboot/keepassxc/releases/latest"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
		$Address = $Results.Where( { $_.browser_download_url -Like "*Win64.msi" } ).browser_download_url
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" /qn" -Wait }
		Start-Sleep 4
		Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "KeePassXC" -EA SI
	}

}

Function Update-Mambaforge {

	$Deposit = "$Env:LocalAppData\Programs\Mambaforge"
	$Present = Test-Path "$Deposit\Scripts\mamba.exe"

	If (-Not $Present) {
		$Address = "https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Windows-x86_64.exe"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		$ArgList = "/S /InstallationType=JustMe /RegisterPython=0 /AddToPath=1 /NoRegistry=1 /D=$Deposit"
		Start-Process "$Fetched" "$ArgList" -Wait
		Start-Sleep 4
	}

	Update-SysPath "$Deposit\Scripts" "User"
	conda config --set auto_activate_base false
	conda update --all -y

}

Function Update-Mpv {

	$Starter = "$Env:LocalAppData\Programs\Mpv\mpv.exe"

	$Address = "https://sourceforge.net/projects/mpv-player-windows/files/64bit"
	$Results = [Regex]::Matches((Invoke-WebRequest "$Address"), "mpv-x86_64-([\d]{8})-git-([\a-z]{7})\.7z")
	$Version = $Results.Groups[1].Value
	$Release = $results.Groups[2].Value
	$Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-10)
    
	If (-Not $Updated) {
		$Address = "https://sourceforge.net/projects/mpv-player-windows/files/64bit/mpv-x86_64-$Version-git-$Release.7z"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Update-Nanazip ; $Deposit = Split-Path "$Starter" ; New-Item "$Deposit" -ItemType Directory -EA SI
		Start-Process "7z.exe" "x `"$Fetched`" -o`"$Deposit`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait ; Start-Sleep 4
		$LnkFile = "$Env:AppData\Microsoft\Windows\Start Menu\Programs\Mpv.lnk"
		Update-LnkFile -LnkFile "$LnkFile" -Starter "$Starter"
		Start-Sleep 4 ; Invoke-Gsudo { & "$Using:Deposit\installer\mpv-install.bat" }
		Start-Sleep 4 ; Stop-Process -Name "SystemSettings" -EA SI
	}

	$Configs = Join-Path "$(Split-Path "$Starter")" "mpv\mpv.conf"
	Set-Content -Path "$Configs" -Value "profile=gpu-hq"
	Add-Content -Path "$Configs" -Value "vo=gpu-next"
	Add-Content -Path "$Configs" -Value "hwdec=auto-copy"
	Add-Content -Path "$Configs" -Value "keep-open=yes"
	Add-Content -Path "$Configs" -Value "ytdl-format=`"bestvideo[height<=?2160]+bestaudio/best`""
	Add-Content -Path "$Configs" -Value "[protocol.http]"
	Add-Content -Path "$Configs" -Value "force-window=immediate"
	Add-Content -Path "$Configs" -Value "hls-bitrate=max"
	Add-Content -Path "$Configs" -Value "cache=yes"
	Add-Content -Path "$Configs" -Value "[protocol.https]"
	Add-Content -Path "$Configs" -Value "profile=protocol.http"
	Add-Content -Path "$Configs" -Value "[protocol.ytdl]"
	Add-Content -Path "$Configs" -Value "profile=protocol.http"

}

Function Update-Nanazip {

	$Current = (Get-Package "*nanazip*" -EA SI).Version
	If ($Null -Eq $Current) { $Current = "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://api.github.com/repos/m2team/nanazip/releases/latest"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).tag_name, "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
		$Address = $Results.Where( { $_.browser_download_url -Like "*.msixbundle" } ).browser_download_url
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Add-AppxPackage -DeferRegistrationWhenPackagesAreInUse -ForceUpdateFromAnyVersion -Path "$Fetched"
		Start-Sleep 4
	}

}

Function Update-Openjdk {

	$Current = (Get-Package "*microsoft*openjdk*" -EA SI).Version
	If ($Null -Eq $Current) { $Current = "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://learn.microsoft.com/en-us/java/openjdk/download"
	$Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "OpenJDK ([\d.]+) LTS").Groups[1].Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Address = "https://aka.ms/download-jdk/microsoft-jdk-$Version-windows-x64.msi"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "msiexec" "/i `"$Using:Fetched`" INSTALLLEVEL=3 /quiet" -Wait }
		Start-Sleep 4
	}

	$Deposit = (Get-Item "$Env:ProgramFiles\Microsoft\jdk-*\bin").FullName
	Update-SysPath "$Deposit" "Process"

}

Function Update-Python {

	Param (
		[Int] $Leading = 3,
		[Int] $Backing = 10
	)

	$Current = (Get-Package "*python*evelopment*" -EA SI).Version
	If ($Null -Eq $Current) { $Current = "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://www.python.org/downloads/windows/"
	$Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "python-($Leading\.$Backing\.[\d.]+)-").Groups[1].Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Ongoing = Invoke-Gsudo { [Environment]::GetEnvironmentVariable("PATH", "Machine") }
		$Changed = "$Ongoing" -Replace "C:\\Program Files\\Python[\d]+\\Scripts\\;" -Replace "C:\\Program Files\\Python[\d]+\\;"
		Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PATH", "$Using:Changed", "Machine") }
		$Address = "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		$ArgList = "/quiet InstallAllUsers=1 AssociateFiles=0 PrependPath=1 Shortcuts=0 Include_launcher=0 InstallLauncherAllUsers=0"
		Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait } ; Start-Sleep 4
		Update-SysPath "$Env:ProgramFiles\Python$Leading$Backing\" "Machine"
		Update-SysPath "$Env:ProgramFiles\Python$Leading$Backing\Scripts\" "Machine"
		Invoke-Gsudo { Start-Process "python" "-m pip install --upgrade pip" -WindowStyle Hidden -Wait }
		Invoke-Gsudo { [Environment]::SetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "1", "Machine") }
	}

	New-Item "$Env:AppData\Python\Scripts" -ItemType Directory -EA SI
	$Address = "https://install.python-poetry.org/"
	$Fetched = Join-Path "$Env:Temp" "install-poetry.py"
	(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
	Start-Process "python" "`"$Fetched`" --uninstall" -WindowStyle Hidden -Wait
	Start-Process "python" "$Fetched" -WindowStyle Hidden -Wait
	Update-SysPath "$Env:AppData\Python\Scripts" "Machine"
	Start-Process "poetry" "config virtualenvs.in-project true" -WindowStyle Hidden -Wait
	Start-Process "poetry" "self update" -WindowStyle Hidden -Wait

}

Function Update-Qbittorrent {

	Param (
		[String] $Deposit = "$Env:UserProfile\Downloads\P2P",
		[String] $Loading = "$Env:UserProfile\Downloads\P2P\Incompleted"
	)

	$Starter = "$Env:ProgramFiles\qBittorrent\qbittorrent.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://www.qbittorrent.org/download.php"
	$Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "Latest:\s+v([\d.]+)").Groups[1].Value
	$Updated = [Version] "$Current" -Ge [Version] "$Version"

	If (-Not $Updated) {
		$Address = "https://downloads.sourceforge.net/project/qbittorrent/qbittorrent-win32/qbittorrent-$Version/qbittorrent_${Version}_x64_setup.exe"
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Start-Process "$Using:Fetched" "/S" -Wait }
	}

	$Configs = "$Env:AppData\qBittorrent\qBittorrent.ini"
	New-Item "$Deposit" -ItemType Directory -EA SI
	New-Item "$Loading" -ItemType Directory -EA SI
	New-Item "$(Split-Path "$Configs")" -ItemType Directory -EA SI
	Set-Content -Path "$Configs" -Value "[LegalNotice]"
	Add-Content -Path "$Configs" -Value "Accepted=true"
	Add-Content -Path "$Configs" -Value "[Preferences]"
	Add-Content -Path "$Configs" -Value "Bittorrent\MaxRatio=0"
	Add-Content -Path "$Configs" -Value "Downloads\SavePath=$($Deposit.Replace("\", "/"))"
	Add-Content -Path "$Configs" -Value "Downloads\TempPath=$($Loading.Replace("\", "/"))"
	Add-Content -Path "$Configs" -Value "Downloads\TempPathEnabled=true"

}

Function Update-VmwareWorkstation {

    Param (
        [String] $Leading = "17",
        [String] $Deposit = "$Env:UserProfile\Machines",
        [String] $Serials = "MC60H-DWHD5-H80U9-6V85M-8280D"
    )

    $Starter = "${Env:ProgramFiles(x86)}\VMware\VMware Workstation\vmware.exe"
    $Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	$Present = $Current -Ne "0.0.0.0"

    $Address = "https://softwareupdate.vmware.com/cds/vmw-desktop/ws-windows.xml"
	$Version = [Regex]::Matches((Invoke-WebRequest "$Address"), "url>ws/($Leading.[\d.]+)/(\d+)/windows/core").Groups[1].Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
		If (Assert-Pending -Eq $True) { Invoke-Restart }
        $Address = "https://www.vmware.com/go/getworkstation-win"
        $Fetched = Join-Path "$Env:Temp" "vmware-workstation-full.exe"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
        $ArgList = "/s /v/qn EULAS_AGREED=1 AUTOSOFTWAREUPDATE=0 DATACOLLECTION=0 ADDLOCAL=ALL REBOOT=ReallySuppress SERIALNUMBER=$Serials"
        Invoke-Gsudo { Start-Process "$Using:Fetched" "$Using:ArgList" -Wait } ; Start-Sleep 4
        Start-Process "$Starter" -WindowStyle Hidden ; Start-Sleep 10 ; Stop-Process -Name "vmware" -EA SI ; Start-Sleep 2
        Set-ItemProperty -Path "HKCU:\Software\VMware, Inc.\VMware Tray" -Name "TrayBehavior" -Type DWord -Value 2
		Remove-Item "$Env:Public\Desktop\VMware*.lnk" -EA SI
		Remove-Item "$Env:UserProfile\Desktop\VMware*.lnk" -EA SI
    }

    If (-Not $Present) {
        $Address = "https://api.github.com/repos/DrDonk/unlocker/releases/latest"
		$Results = (Invoke-WebRequest "$Address" | ConvertFrom-Json).assets
		$Address = $Results.Where( { $_.browser_download_url -Like "*.zip" } ).browser_download_url
		$Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Update-Nanazip ; $Extract = [IO.Directory]::CreateDirectory("$Env:Temp\$([Guid]::NewGuid().Guid)").FullName
		Start-Process "7z.exe" "x `"$Fetched`" -o`"$Extract`" -y -bso0 -bsp0" -WindowStyle Hidden -Wait
        Start-Sleep 4 ; $Program = Join-Path "$Extract" "windows\unlock.exe"
        Invoke-Gsudo {
            [Environment]::SetEnvironmentVariable("UNLOCK_QUIET", "1", "Process")
            Start-Process "$Using:Program" -WindowStyle Hidden
        }
    }

    If ($Deposit) {
        New-Item -Path "$Deposit" -ItemType Directory -EA SI
        $Configs = "$Env:AppData\VMware\preferences.ini"
        If (-Not ((Get-Content "$Configs") -Match "prefvmx.defaultVMPath")) { Add-Content -Path "$Configs" -Value "prefvmx.defaultVMPath = `"$Deposit`"" }
    }

}

Function Update-Vscode {

	$Starter = "$Env:LocalAppData\Programs\Microsoft VS Code\Code.exe"
	$Current = Try { (Get-Command "$Starter" -EA SI).Version.ToString() } Catch { "0.0.0.0" }
	# $Present = $Current -Ne "0.0.0.0"

	$Address = "https://code.visualstudio.com/sha?build=stable"
	$Version = [Regex]::Match((Invoke-WebRequest "$Address" | ConvertFrom-Json).products[1].name, "[\d.]+").Value
	$Updated = [Version] "$Current" -Ge [Version] ($Version.SubString(0, 6))

	If (-Not $Updated -And "$Env:TERM_PROGRAM" -Ne "Vscode") {
		$Address = "https://aka.ms/win32-x64-user-stable"
		$Fetched = Join-Path "$Env:Temp" "VSCodeUserSetup-x64-Latest.exe"
		$ArgList = "/VERYSILENT /MERGETASKS=`"!runcode`""
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Stop-Process -Name "Code" -EA SI ; Start-Process "$Using:Fetched" "$Using:ArgList" -Wait }
		Start-Sleep 4
	}

	Update-SysPath "$Env:LocalAppData\Programs\Microsoft VS Code\bin" "Machine"
	Update-VscodeExtension "github.github-vscode-theme"
	Update-VscodeExtension "ms-vscode.powershell"

	$Configs = "$Env:AppData\Code\User\settings.json"
	New-Item "$(Split-Path "$Configs")" -ItemType Directory -EA SI
	New-Item "$Configs" -ItemType File -EA SI
	$NewJson = New-Object PSObject
	$NewJson | Add-Member -Type NoteProperty -Name "editor.bracketPairColorization.enabled" -Value $True -Force
	$NewJson | Add-Member -Type NoteProperty -Name "editor.fontSize" -Value 14 -Force
	$NewJson | Add-Member -Type NoteProperty -Name "editor.lineHeight" -Value 28 -Force
	$NewJson | Add-Member -Type NoteProperty -Name "security.workspace.trust.enabled" -Value $False -Force
	$NewJson | Add-Member -Type NoteProperty -Name "telemetry.telemetryLevel" -Value "crash" -Force
	$NewJson | Add-Member -Type NoteProperty -Name "update.mode" -Value "none" -Force
	$NewJson | Add-Member -Type NoteProperty -Name "workbench.colorTheme" -Value "GitHub Dark Default" -Force
	$NewJson | ConvertTo-Json | Set-Content "$Configs"

}

Function Update-VscodeExtension {

	Param(
		[String] $Payload
	)

	Start-Process "code" "--install-extension $Payload --force" -WindowStyle Hidden -Wait

}

Function Update-Wsa {

	Function Local:Invoke-Scraper {
		Param(
			[String] $Address,
			[String] $Pattern
		)
		$Content = Invoke-WebRequest `
			-UseBasicParsing `
			-Uri "https://store.rg-adguard.net/api/GetFiles" `
			-Method "POST" `
			-ContentType "application/x-www-form-urlencoded" `
			-Body "type=url&url=$Address&ring=RP&lang=en-US"
		Return [Regex]::Matches($Content.Links.Where({ $_ -Like "$Pattern" }).OuterHTML, "href=`"(.*)(?=`"\s)").Groups[1].Value
	}

	$Current = (Get-AppxPackage "*microsoft*ui*xaml*" -EA SI).Version
	If ($Null -Eq $Current) { $Current = "0.0.0.0" }
	$Present = "$Current" -Ne "0.0.0.0"
	If (-Not $Present) {
		$Address = Invoke-Scraper "www.microsoft.com/en-us/p/windows-subsystem-for-android/9p3395vx91nr" "*Microsoft.UI.Xaml*x64*appx*"
		$Fetched = Join-Path "$Env:Temp" "9p3395vx91nr.appx"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Add-AppxPackage -Path "$Fetched"
	}

	$Current = (Get-AppxPackage "*windowssubsystemforandroid*" -EA SI).Version
	If ($Null -Eq $Current) { $Current = "0.0.0.0" }
	$Present = "$Current" -Ne "0.0.0.0"
	If (-Not $Present) {
		$Address = Invoke-Scraper "www.microsoft.com/en-us/p/windows-subsystem-for-android/9p3395vx91nr" "*msixbundle*"
		$Fetched = Join-Path "$Env:Temp" "9p3395vx91nr.msixbundle"
		(New-Object Net.WebClient).DownloadFile("$Address", "$Fetched")
		Invoke-Gsudo { Add-AppxPackage -Path "$Using:Fetched" }
	}

}

Function Update-Wsl {

	Enable-Feature "Wsl" ; Start-Process "wsl" "--update" -WindowStyle Hidden -Wait
	Start-Process "wsl" "--shutdown" -WindowStyle Hidden -Wait
	Start-Process "wsl" "--install ubuntu --no-launch" -WindowStyle Hidden -Wait

	$Program = "$Env:LocalAppData\Microsoft\WindowsApps\ubuntu.exe"
	Start-Process "$Program" "install --root" -WindowStyle Hidden -Wait
	Start-Process "$Program" "run sudo dpkg --configure -a" -WindowStyle Hidden -Wait
	Start-Process "$Program" "run sudo apt update -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false" -WindowStyle Hidden -Wait
	Start-Process "$Program" "run sudo apt update" -WindowStyle Hidden -Wait
	Start-Process "$Program" "run sudo apt upgrade -y" -WindowStyle Hidden -Wait
	Start-Process "$Program" "run sudo apt full-upgrade -y" -WindowStyle Hidden -Wait
	Start-Process "$Program" "run sudo apt autoremove -y" -WindowStyle Hidden -Wait
	Start-Process "$Program" "run sudo apt install -y x11-apps" -WindowStyle Hidden -Wait

}

Function Update-YtDlg {

	$Deposit = "$Env:LocalAppData\Programs\YtDlp"
	$Starter = "$Deposit\yt-dlp.exe"
	$Updated = Test-Path "$Starter" -NewerThan (Get-Date).AddDays(-10)

	If (-Not $Updated) {
		$Address = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
		New-Item "$Deposit" -ItemType Directory -EA SI
		(New-Object Net.WebClient).DownloadFile("$Address", "$Starter")
	}

	Update-SysPath "$Deposit" "Machine"

}

Function Main {

	# Change headline
	$Current = "$($Script:MyInvocation.MyCommand.Path)"
	$Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName

	# Output greeting
	Clear-Host ; $ProgressPreference = "SilentlyContinue"
	Write-Host "+----------------------------------------------------------+"
	Write-Host "|                                                          |"
	Write-Host "|  > WINHOGEN (NEW)                                        |"
	Write-Host "|                                                          |"
	Write-Host "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                   |"
	Write-Host "|                                                          |"
	Write-Host "+----------------------------------------------------------+"

	# Remove security
	$Loading = "`nTHE UPDATING DEPENDENCIES PROCESS HAS LAUNCHED"
	$Failure = "`rTHE UPDATING DEPENDENCIES PROCESS WAS CANCELED"
	# Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Feature "Uac" ; Update-PowPlan "Ultimate"
	Write-Host "$Loading" -FO DarkYellow -NoNewline ; Remove-Feature "Uac"
	$Correct = (Update-Gsudo) -And -Not (gsudo cache on -d -1 2>&1).ToString().Contains("Error")
	If (-Not $Correct) { Write-Host "$Failure" -FO Red ; Write-Host ; Exit }

	# Remove schedule
	$Payload = (Get-Item "$Current").BaseName
	Invoke-Gsudo { Unregister-ScheduledTask -TaskName "$Using:Payload" -Confirm:$False -EA SI }

	# Handle elements
	$Factors = @(
		"Update-Cuda"
		"Update-DockerDesktop"
		"Update-VmwareWorkstation"
		"Update-Wsl"
		"Update-Wsa"

		"Update-AndroidStudio"
		"Update-Chromium"
		"Update-Git -GitMail 72373746+sharpordie@users.noreply.github.com -GitUser sharpordie"
		"Update-Vscode"
		
		"Update-Flutter"
		"Update-Figma"
		"Update-Jdownloader"
		"Update-JoalDesktop"
		"Update-Keepassxc"
		"Update-Mambaforge"
		"Update-Mpv"
		"Update-Python"
		"Update-Qbittorrent"
		"Update-YtDlg"
	)

	# Output progress
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

	# Revert security
	Enable-Feature "Uac" ; Invoke-Expression "gsudo -k" *> $Null

	# Output new line
	Write-Host "`n"

}

Main