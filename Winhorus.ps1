#!/usr/bin/env pwsh

Function Deploy-Library {

    Param(
        [ValidateSet("Flaui", "Playwright")] [String] $Library
    )

    Switch ($Library) {
        "Flaui" {
            Import-Library "Interop.UIAutomationClient" | Out-Null
            Import-Library "FlaUI.Core" | Out-Null
            Import-Library "FlaUI.UIA3" | Out-Null
            Import-Library "System.Drawing.Common" | Out-Null
            Import-Library "System.Security.Permissions" | Out-Null
            [FlaUI.UIA3.UIA3Automation]::New()
        }
        "Playwright" {
            $Current = $Script:MyInvocation.MyCommand.Path
            $Command = "-ep bypass -c '. $Current ; Deploy-Library Playwright | Out-Null'"
            If ($Null -Ne $Current) { Start-Process "powershell" "$Command" -WindowStyle Hidden -Wait }
            Import-Library "System.Text.Json" | Out-Null
            Import-Library "Microsoft.Bcl.AsyncInterfaces" | Out-Null
            Import-Library "Microsoft.CodeAnalysis" | Out-Null
            Import-Library "Microsoft.Playwright" | Out-Null
            [Microsoft.Playwright.Program]::Main(@("install", "chromium"))
            [Microsoft.Playwright.Playwright]::CreateAsync().GetAwaiter().GetResult()
            # $Current = $Script:MyInvocation.MyCommand.Path
            # Invoke-Command {
            #     . $Current
            #     Import-Library "System.Text.Json" | Out-Null
            #     Import-Library "Microsoft.Bcl.AsyncInterfaces" | Out-Null
            #     Import-Library "Microsoft.CodeAnalysis" | Out-Null
            #     Import-Library "Microsoft.Playwright" | Out-Null
            #     Invoke-Expression '[Microsoft.Playwright.Program]::Main(@("install", "chromium"))' >$null 2>&1
            # } -NoNewScope
            # [Microsoft.Playwright.Playwright]::CreateAsync().GetAwaiter().GetResult()
        }
    }

}

Function Expand-Version {

    Param (
        [String] $Payload
    )

    If ([String]::IsNullOrWhiteSpace($Payload)) { Return "0.0.0.0" }
    $Version = $(powershell -Command "(Get-Package `"$Payload`" -EA SI).Version")
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = (Get-AppxPackage "$Payload" -EA SI).Version }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = Try { (Get-Command "$Payload" -EA SI).Version } Catch { $Null } }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = Try { (Get-Item "$Payload" -EA SI).VersionInfo.FileVersion } Catch { $Null } }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = Try { Invoke-Expression "& `"$Payload`" --version" -EA SI } Catch { $Null } }
    If ([String]::IsNullOrWhiteSpace($Version)) { $Version = "0.0.0.0" }
    Return [Regex]::Match($Version, "[\d.]+").Value.Trim(".")

}

Function Import-Library {

    Param(
        [String] $Library,
        [Switch] $Testing
    )

    If (-Not ([Management.Automation.PSTypeName]"$Library").Type ) {
        If (-Not (Get-Package "$Library" -EA SI)) { Install-Package "$Library" -Scope "CurrentUser" -Source "https://www.nuget.org/api/v2" -Force -SkipDependencies | Out-Null }
        $Results = (Get-ChildItem -Filter "*.dll" -Recurse (Split-Path (Get-Package -Name "$Library").Source)).FullName
        $Content = $Results | Where-Object { $_ -Like "*standard2.0*" } | Select-Object -Last 1
        If ($Testing) { Try { Add-Type -Path "$Content" -EA SI | Out-Null } Catch { $_.Exception.LoaderExceptions } }
        Else { Try { Add-Type -Path "$Content" -EA SI | Out-Null } Catch {} }
    }

}

Function Invoke-Fetcher {

    Param(
        [String] $Variant,
        [String] $Address,
        [String] $Fetched
    )

    Switch ($Variant) {
        Address {
            If (-Not $Fetched) { $Fetched = Join-Path "$Env:Temp" "$(Split-Path "$Address" -Leaf)" }
            (New-Object Net.WebClient).DownloadFile("$Address", "$Fetched") ; Return "$Fetched"
        }
        Browser {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $WebPage.GoToAsync("about:blank").GetAwaiter().GetResult() | Out-Null
            $Waiting = $WebPage.WaitForDownloadAsync()
            $WebPage.GoToAsync("$Address") | Out-Null
            $Attempt = $Waiting.GetAwaiter().GetResult()
            $Attempt.PathAsync().GetAwaiter().GetResult() | Out-Null
            $Suggest = $Attempt.SuggestedFilename
            $Fetched = Join-Path "$Env:Temp" "$Suggest"
            $Attempt.SaveAsAsync("$Fetched").GetAwaiter().GetResult() | Out-Null
            $WebPage.CloseAsync().GetAwaiter().GetResult() | Out-Null
            $Browser.CloseAsync().GetAwaiter().GetResult() | Out-Null
            Return "$Fetched"
        }
        Filecr { }
        Torrent { }
    }

}

Function Invoke-NoAdmin {

    Param(
        [String] $Starter,
        [String] $ArgList,
        [String] $WorkDir = "",
        [Switch] $Visible
    )

    $Content = '
    using System;
    using System.Runtime.InteropServices;
    namespace Winhogen
    {
        public class SystemUtility
        {
            public static void ExecuteProcessUnElevated(string starter, string arglist, string workdir = "", bool visible = false)
            {
                var shellWindows = (IShellWindows)new CShellWindows();
                object loc = CSIDL_Desktop;
                object unused = new object();
                int hwnd;
                var serviceProvider = (IServiceProvider)shellWindows.FindWindowSW(ref loc, ref unused, SWC_DESKTOP, out hwnd, SWFO_NEEDDISPATCH);
                var serviceGuid = SID_STopLevelBrowser;
                var interfaceGuid = typeof(IShellBrowser).GUID;
                var shellBrowser = (IShellBrowser)serviceProvider.QueryService(ref serviceGuid, ref interfaceGuid);
                var dispatch = typeof(IDispatch).GUID;
                var folderView = (IShellFolderViewDual)shellBrowser.QueryActiveShellView().GetItemObject(SVGIO_BACKGROUND, ref dispatch);
                var shellDispatch = (IShellDispatch2)folderView.Application;
                shellDispatch.ShellExecute(starter, arglist, workdir, string.Empty, visible ? SW_SHOWNORMAL : SW_HIDE);
            }
            private const int CSIDL_Desktop = 0;
            private const int SWC_DESKTOP = 8;
            private const int SWFO_NEEDDISPATCH = 1;
            private const int SW_HIDE = 0;
            private const int SW_SHOWNORMAL = 1;
            private const int SVGIO_BACKGROUND = 0;
            private readonly static Guid SID_STopLevelBrowser = new Guid("4C96BE40-915C-11CF-99D3-00AA004AE837");
            [ComImport]
            [Guid("9BA05972-F6A8-11CF-A442-00A0C90A8F39")]
            [ClassInterfaceAttribute(ClassInterfaceType.None)]
            private class CShellWindows
            {
            }
            [ComImport]
            [Guid("85CB6900-4D95-11CF-960C-0080C7F4EE85")]
            [InterfaceType(ComInterfaceType.InterfaceIsIDispatch)]
            private interface IShellWindows
            {
                [return: MarshalAs(UnmanagedType.IDispatch)]
                object FindWindowSW([MarshalAs(UnmanagedType.Struct)] ref object pvarloc, [MarshalAs(UnmanagedType.Struct)] ref object pvarlocRoot, int swClass, out int pHWND, int swfwOptions);
            }
            [ComImport]
            [Guid("6d5140c1-7436-11ce-8034-00aa006009fa")]
            [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
            private interface IServiceProvider
            {
                [return: MarshalAs(UnmanagedType.Interface)]
                object QueryService(ref Guid guidService, ref Guid riid);
            }
            [ComImport]
            [Guid("000214E2-0000-0000-C000-000000000046")]
            [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
            private interface IShellBrowser
            {
                void VTableGap01(); // GetWindow
                void VTableGap02(); // ContextSensitiveHelp
                void VTableGap03(); // InsertMenusSB
                void VTableGap04(); // SetMenuSB
                void VTableGap05(); // RemoveMenusSB
                void VTableGap06(); // SetStatusTextSB
                void VTableGap07(); // EnableModelessSB
                void VTableGap08(); // TranslateAcceleratorSB
                void VTableGap09(); // BrowseObject
                void VTableGap10(); // GetViewStateStream
                void VTableGap11(); // GetControlWindow
                void VTableGap12(); // SendControlMsg
                IShellView QueryActiveShellView();
            }
            [ComImport]
            [Guid("000214E3-0000-0000-C000-000000000046")]
            [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
            private interface IShellView
            {
                void VTableGap01(); // GetWindow
                void VTableGap02(); // ContextSensitiveHelp
                void VTableGap03(); // TranslateAcceleratorA
                void VTableGap04(); // EnableModeless
                void VTableGap05(); // UIActivate
                void VTableGap06(); // Refresh
                void VTableGap07(); // CreateViewWindow
                void VTableGap08(); // DestroyViewWindow
                void VTableGap09(); // GetCurrentInfo
                void VTableGap10(); // AddPropertySheetPages
                void VTableGap11(); // SaveViewState
                void VTableGap12(); // SelectItem
                [return: MarshalAs(UnmanagedType.Interface)]
                object GetItemObject(UInt32 aspectOfView, ref Guid riid);
            }
            [ComImport]
            [Guid("00020400-0000-0000-C000-000000000046")]
            [InterfaceType(ComInterfaceType.InterfaceIsIDispatch)]
            private interface IDispatch
            {
            }
            [ComImport]
            [Guid("E7A1AF80-4D96-11CF-960C-0080C7F4EE85")]
            [InterfaceType(ComInterfaceType.InterfaceIsIDispatch)]
            private interface IShellFolderViewDual
            {
                object Application { [return: MarshalAs(UnmanagedType.IDispatch)] get; }
            }
            [ComImport]
            [Guid("A4C6892C-3BA9-11D2-9DEA-00C04FB16162")]
            [InterfaceType(ComInterfaceType.InterfaceIsIDispatch)]
            public interface IShellDispatch2
            {
                void ShellExecute([MarshalAs(UnmanagedType.BStr)] string File, [MarshalAs(UnmanagedType.Struct)] object vArgs, [MarshalAs(UnmanagedType.Struct)] object vDir, [MarshalAs(UnmanagedType.Struct)] object vOperation, [MarshalAs(UnmanagedType.Struct)] object vShow);
            }
        }
    }'
    Add-Type -ReferencedAssemblies ("System", "System.Runtime.InteropServices") -TypeDefinition $Content -Language CSharp
    [Winhogen.SystemUtility]::ExecuteProcessUnElevated($Starter, $ArgList, $WorkDir, $Visible.IsPresent)

}

Function Invoke-Restart {

    Get-LocalUser -Name "$Env:Username" | Set-LocalUser -Password ([SecureString]::New())
    $Current = $Script:MyInvocation.MyCommand.Path
    $Heading = (Get-Item "$Current").BaseName
    $Present = $Null -Ne (Get-Item "$Env:ProgramFiles\PowerShell\*\pwsh.exe" -EA SI).FullName
    $Program = If ($Present) { "pwsh" } Else { "powershell" }
    $ArgList = "/c start /b wt --title `"$Heading`" $Program -ep bypass -noexit -nologo -f `"$Current`""
    Register-ScheduledTask `
        -TaskName "$Heading" `
        -Trigger (New-ScheduledTaskTrigger -AtLogOn) `
        -User ($Env:Username) `
        -Action (New-ScheduledTaskAction -Execute "cmd" -Argument "$ArgList") `
        -RunLevel Highest `
        -Force *> $Null
    Restart-Computer -Force

}

Function Invoke-Scraper {

    Param(
        [ValidateSet("Html", "Json", "BrowserHtml", "BrowserJson", "Jetbra")] [String] $Scraper,
        [String] $Payload
    )

    Switch ($Scraper) {
        "Html" {
            Return Invoke-WebRequest "$Payload"
        }
        "Json" {
            Return Invoke-WebRequest "$Payload" | ConvertFrom-Json
        }
        "BrowserHtml" {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $WebPage.GoToAsync("$Payload").GetAwaiter().GetResult() | Out-Null
            $Scraped = $WebPage.QuerySelectorAsync("body").GetAwaiter().GetResult()
            $Scraped = $Scraped.InnerHtmlAsync().GetAwaiter().GetResult()
            $WebPage.CloseAsync().GetAwaiter().GetResult() | Out-Null
            $Browser.CloseAsync().GetAwaiter().GetResult() | Out-Null
            Return $Scraped.ToString()
        }
        "BrowserJson" {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $WebPage.GoToAsync("$Payload").GetAwaiter().GetResult() | Out-Null
            $Scraped = $WebPage.QuerySelectorAsync("body > :first-child").GetAwaiter().GetResult()
            $Scraped = $Scraped.InnerHtmlAsync().GetAwaiter().GetResult()
            $WebPage.CloseAsync().GetAwaiter().GetResult()
            $Browser.CloseAsync().GetAwaiter().GetResult()
            Return $Scraped.ToString() | ConvertFrom-Json
        }
        "Jetbra" {
            $Handler = Deploy-Library "Playwright"
            $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
            $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
            $WebPage.GoToAsync("https://jetbra.in/s").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(10000).GetAwaiter().GetResult() | Out-Null
            $Address = $WebPage.EvaluateAsync("document.querySelectorAll('#checker\\.results a')[0].href", "").GetAwaiter().GetResult()
            $WebPage.GoToAsync("$Address").GetAwaiter().GetResult() | Out-Null
            $WebPage.WaitForTimeoutAsync(2000).GetAwaiter().GetResult() | Out-Null
            $WebPage.Locator(":has-text('$Payload') ~ p").ClickAsync().GetAwaiter().GetResult() | Out-Null
            $WebPage.CloseAsync().GetAwaiter().GetResult() | Out-Null
            $Browser.CloseAsync().GetAwaiter().GetResult() | Out-Null
            Return "$(Get-Clipboard)".Trim()
        }
    }

}

Function Update-Oneself {
    
    $Granted = [Security.Principal.WindowsIdentity]::GetCurrent().Groups -Contains "S-1-5-32-544"
    If (-Not $Granted) {
        $Current = $Script:MyInvocation.MyCommand.Path
        $Heading = (Get-Item "$Current").BaseName
        $ArgList = "-ep bypass -noexit -nologo -f `"$Current`""
        $Present = $Null -Ne (Get-Item "$Env:ProgramFiles\PowerShell\*\pwsh.exe" -EA SI).FullName
        $Program = If ($Present) { "pwsh" } Else { "powershell" }
        $ArgList = "nt -d `"$PSScriptRoot`" --title `"$Heading`" $Program $ArgList"
        Start-Process "wt" "$ArgList" -Verb RunAs ; Exit
    }
    If ($PSVersionTable.PSVersion -Lt [Version] "7.0.0.0") {
        $Address = "https://aka.ms/install-powershell.ps1"
        Invoke-Expression "& { $(Invoke-RestMethod "$Address") } -UseMSI -Quiet" *> $Null
        Invoke-Restart
    }
    $Handler = Deploy-Library Flaui
    $Factor1 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::LWIN
    $Factor2 = [FlaUI.Core.WindowsAPI.VirtualKeyShort]::KEY_D
    [FlaUI.Core.Input.Keyboard]::TypeSimultaneously($Factor1, $Factor2)
    $Handler.Dispose() | Out-Null

}

Function Update-SysPath {
    
    Param (
        [String] $Deposit,
        [ValidateSet("Machine", "Process", "User")] [String] $Section,
        [Switch] $Prepend
    )

    $Changed = [Environment]::GetEnvironmentVariable("PATH", "$Section")
    $Changed = If ($Changed.Contains(";;")) { $Changed.Replace(";;", ";") } Else { $Changed }
    $Changed = If ($Changed.EndsWith(";")) { $Changed } Else { "${Changed};" }
    $Changed = If ($Changed.Contains($Deposit)) { $Changed } Else { If ($Prepend) { "${Deposit};${Changed}" } Else { "${Changed}${Deposit};" } }
    [Environment]::SetEnvironmentVariable("PATH", "$Changed", "$Section")
    [Environment]::SetEnvironmentVariable("PATH", "$Changed", "Process")

}

Function Update-Git {

    Param (
        [String] $Default = "main",
        [String] $GitMail,
        [String] $GitUser
    )

    $Starter = "$Env:ProgramFiles\Git\git-bash.exe"
    $Current = Expand-Version "$Starter"
    $Address = "https://api.github.com/repos/git-for-windows/git/releases/latest"
    $Version = [Regex]::Match((Invoke-Scraper "Json" "$Address").tag_name.Replace("windows.", "") , "[\d.]+").Value
    $Updated = [Version] "$Current" -Ge [Version] "$Version"

    If (-Not $Updated) {
        $Results = (Invoke-Scraper "Json" "$Address").assets
        $Address = $Results.Where( { $_.browser_download_url -Like "*64-bit.exe" } ).browser_download_url
        $Fetched = Invoke-Fetcher "Address" "$Address"
        $ArgList = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART, /NOCANCEL, /SP- /COMPONENTS=`"`""
        Start-Process "$Fetched" "$ArgList" -Verb RunAs -Wait
    }

    Update-SysPath "$Env:ProgramFiles\Git\cmd" "Process"
    If (-Not [String]::IsNullOrWhiteSpace($GitMail)) { git config --global user.email "$GitMail" }
    If (-Not [String]::IsNullOrWhiteSpace($GitUser)) { git config --global user.name "$GitUser" }
    git config --global http.postBuffer 1048576000
    git config --global init.defaultBranch "$Default"
    
}

If ($MyInvocation.InvocationName -Ne ".") {

    $Current = $Script:MyInvocation.MyCommand.Path
    $Host.UI.RawUI.WindowTitle = (Get-Item "$Current").BaseName.ToUpper()

    Clear-Host ; $ProgressPreference = "SilentlyContinue"
    Write-Output "+---------------------------------------------------------------+"
    Write-Output "|                                                               |"
    Write-Output "|  > WINHOGEN                                                   |"
    Write-Output "|                                                               |"
    Write-Output "|  > CONFIGURATION SCRIPT FOR WINDOWS 11                        |"
    Write-Output "|                                                               |"
    Write-Output "+---------------------------------------------------------------+"

    Update-Oneself
    # Update-Git 'main' '72373746+sharpordie@users.noreply.github.com' 'sharpordie'
    # Try { Invoke-Expression '$ProgressPreference = "SilentlyContinue" ; Invoke-Fetcher "Browser" "https://www.bignox.com/en/download/fullPackage/win_64?beta"' *> $Null } Catch {}
    Invoke-Fetcher "Browser" "https://www.bignox.com/en/download/fullPackage/win_64?beta"

    # Invoke-NoAdmin "powershell" "-ep bypass -c md $Env:UserProfile\Desktop\TADAMNOADMIN"
    # Start-Process "powershell" "-ep bypass -c md $Env:UserProfile\Desktop\TADAM" -Verb RunAs -WindowStyle Hidden

    $Granted = [Security.Principal.WindowsIdentity]::GetCurrent().Groups -Contains "S-1-5-32-544"
    Write-Output $Granted

}