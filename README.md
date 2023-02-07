# <samp>OVERVIEW</samp>

Opinionated post-installation script for Windows 11.

| <samp>AND</samp> | <samp>IOS</samp> | <samp>LIN</samp> | <samp>MAC</samp> | <samp>WIN</samp> | <samp>WEB</samp> |
| :-: | :-: | :-: | :-: | :-: | :-: |
| <br>🟥<br><br> | <br>🟥<br><br> | <br>🟥<br><br> | <br>🟥<br><br> | <br>🟩<br><br> | <br>🟥<br><br> |

# <samp>GUIDANCE</samp>

## 1 Gather project archive

```powershell
iwr https://github.com/sharpordie/winhogen/archive/refs/heads/main.zip -o $env:temp\main.zip
```

## 2. Expand fetched archive

```powershell
expand-archive $env:temp\main.zip -destinationpath $env:temp -force
```

## 3. Launch expanded script

### Winhogen for casual purpose

```powershell
powershell -ep bypass $env:temp\winhogen-main\winhogen.ps1
```

### Gamhogen for gaming purpose

```powershell
powershell -ep bypass $env:temp\winhogen-main\gamhogen.ps1
```

<!-- 
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

## For personal purpose

Copy the generic template and modify the list of functions to execute.

```powershell
git clone https://github.com/sharpordie/winhogen.git
cd winhogen ; cp ./src/Template.ps1 ./src/Ownhogen.ps1
``` -->