# <samp>OVERVIEW</samp>

Opinionated post-installation scripts for Windows 11.

<img src="assets/img1.png" width="49.25%"/><img src="assets/img0.png" width="1.5%"/><img src="assets/img2.png" width="49.25%"/>

# <samp>GUIDANCE</samp>

## For development purpose

Check out [line number 37](src/Devhogen.ps1#L37) to get an idea of what the script does.

```powershell
iwr https://raw.githubusercontent.com/sharpordie/winhogen/HEAD/src/Devhogen.ps1 -o $env:temp\Devhogen.ps1
powershell -ep bypass $env:temp\Devhogen.ps1
```

## For gaming purpose

Check out [line number 37](src/Gamhogen.ps1#L37) to get an idea of what the script does.

```powershell
iwr https://raw.githubusercontent.com/sharpordie/winhogen/HEAD/src/Gamhogen.ps1 -o $env:temp\Gamhogen.ps1
powershell -ep bypass $env:temp\Gamhogen.ps1
```

## For your own purpose

Copy the generic template and modify the list of functions to execute.

```powershell
git clone https://github.com/sharpordie/winhogen.git
cd winhogen ; cp ./src/Template.ps1 ./src/Newhogen.ps1
```