# <samp>OVERVIEW</samp>

Opinionated post-installation scripts for Windows 11.

<img src="https://fakeimg.pl/852x480/000/fff/?text=DEVHOGEN" width="49.25%"/><img src="https://upload.wikimedia.org/wikipedia/commons/c/ca/1x1.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/000/fff/?text=GAMHOGEN" width="49.25%"/>

# <samp>GUIDANCE</samp>

## For development purpose

Check out [line number 37](src/Devhogen.ps1#L37) to get an idea of what the script does.

```powershell
iwr https://raw.githubusercontent.com/sharpordie/winhogen/HEAD/src/Devhogen.ps1 -o $env:temp\Devhogen.ps1 | powershell -ep bypass $env:temp\Devhogen.ps1
```

## For gaming purpose

Check out [line number 37](src/Gamhogen.ps1#L37) to get an idea of what the script does.

```powershell
iwr https://raw.githubusercontent.com/sharpordie/winhogen/HEAD/src/Gamhogen.ps1 -o $env:temp\Gamhogen.ps1 | powershell -ep bypass $env:temp\Gamhogen.ps1
```