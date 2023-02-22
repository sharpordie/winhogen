# <samp>OVERVIEW</samp>

Opinionated post-installation script for Windows 11.

<img src="assets/img1.png" width="49.25%"/><img src="assets/img0.png" width="1.5%"/><img src="assets/img2.png" width="49.25%"/>

# <samp>GUIDANCE</samp>

```powershell
iwr https://raw.githubusercontent.com/sharpordie/winhogen/main/winhogen.ps1 -o (ni $env:temp\winhogen.ps1 -f)
try { pwsh -ep bypass $env:temp\winhogen.ps1 } catch { powershell -ep bypass $env:temp\winhogen.ps1 }
```