# <samp>OVERVIEW</samp>

Opinionated post-installation script for Windows 11.

<img src="assets/img1.png" width="49.25%"/><img src="assets/img0.png" width="1.5%"/><img src="assets/img2.png" width="49.25%"/>

# <samp>GUIDANCE</samp>

Blindly executing this is strongly discouraged.

```powershell
$address = "https://raw.githubusercontent.com/sharpordie/winhogen/main/src/winhogen.ps1"
$fetched = ni $env:temp\winhogen.ps1 -f ; iwr $address -o $fetched
try { pwsh -ep bypass $fetched } catch { powershell -ep bypass $fetched }
```

# <samp>FUNDINGS</samp>

You can support my work by sending me some crypto.

```txt
ADA: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
BAT: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
BCH: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
BTC: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ETH: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
LTC: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
XMR: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ZEC: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```
