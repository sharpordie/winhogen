Function Invoke-Browser {

    Param(
        [String] $Startup = "https://www.bing.com",
        [String] $Factors
    )

    $Members = @("Microsoft.Bcl.AsyncInterfaces", "Microsoft.CodeAnalysis", "Microsoft.Playwright", "System.Text.Json")
    Foreach ($Element In $Members) {
        If (-Not (Get-Package -Name "$Element" -EA SI)) {
            Install-Package "$Element" -Scope "CurrentUser" -Source "https://www.nuget.org/api/v2" -Force -SkipDependencies
        }
    }

    $Members = @("System.Text.Json", "Microsoft.Bcl.AsyncInterfaces", "Microsoft.Playwright")
    Foreach ($Element In $Members) {
        If (-Not ([System.Management.Automation.PSTypeName]"$Element").Type ) {
            $X = (Get-ChildItem -Filter "*.dll" -Recurse (Split-Path (Get-Package -Name "$Element").Source)).FullName | Where-Object { $_ -Like "*standard2.0*" } | Select-Object -Last 1
            Try { Add-Type -Path "$X" -EA SI } Catch { $_.Exception.LoaderExceptions ; Return 1 }
        }
    }

    [Microsoft.Playwright.Program]::Main(@("install", "chromium"))
    $Handler = [Microsoft.Playwright.Playwright]::CreateAsync().GetAwaiter().GetResult()
    $Browser = $Handler.Chromium.LaunchAsync(@{ "Headless" = $False }).GetAwaiter().GetResult()
    $WebPage = $Browser.NewPageAsync().GetAwaiter().GetResult()
    $WebPage.GoToAsync("http://www.bing.com").GetAwaiter().GetResult()
    $WebPage.CloseAsync().GetAwaiter().GetResult()
    $Browser.CloseAsync().GetAwaiter().GetResult()

}

Invoke-Browser