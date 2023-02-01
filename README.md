# <samp>OVERVIEW</samp>

Opinionated post-installation scripts for Windows 11.

# <samp>GUIDANCE</samp>

## For development purpose

<img src="https://fakeimg.pl/852x480/000/fff" width="49.25%"/><img src="https://upload.wikimedia.org/wikipedia/commons/c/ca/1x1.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/000/fff" width="49.25%"/>

### One-command execution

Running this blindly is strongly discouraged.

```powershell
iwr https://raw.githubusercontent.com/sharpordie/winhogen/HEAD/src/Devhogen.ps1 -o $env:temp\Devhogen.ps1 | powershell -ep bypass $env:temp\Devhogen.ps1
```

## For gaming purpose

<img src="https://fakeimg.pl/852x480/000/fff" width="49.25%"/><img src="https://upload.wikimedia.org/wikipedia/commons/c/ca/1x1.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/000/fff" width="49.25%"/>

### One-command execution

Running this blindly is strongly discouraged.

```powershell
iwr https://raw.githubusercontent.com/sharpordie/winhogen/HEAD/src/Gamhogen.ps1 -o $env:temp\Gamhogen.ps1 | powershell -ep bypass $env:temp\Gamhogen.ps1
```