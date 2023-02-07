# <samp>OVERVIEW</samp>

Opinionated post-installation scripts for Windows 11.

| <samp>AND</samp> | <samp>IOS</samp> | <samp>LIN</samp> | <samp>MAC</samp> | <samp>WIN</samp> | <samp>WEB</samp> |
| :-: | :-: | :-: | :-: | :-: | :-: |
| <br>🟥<br><br> | <br>🟥<br><br> | <br>🟥<br><br> | <br>🟥<br><br> | <br>🟩<br><br> | <br>🟥<br><br> |

# <samp>GUIDANCE</samp>

## For coding purpose

<img src="https://fakeimg.pl/852x480/43d6b5/43d6b5" width="49.25%"/><img src="https://upload.wikimedia.org/wikipedia/commons/c/ca/1x1.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/43d6b5/43d6b5" width="49.25%"/>

### Features

- Update and configure windows
- Update and configure gpu driver
- ...

### Launcher

```powershell
iwr https://github.com/sharpordie/winhogen/archive/refs/heads/main.zip -o $env:temp\main.zip
expand-archive $env:temp\main.zip -destinationpath $env:temp -force
powershell -ep bypass $env:temp\winhogen-main\codhogen.ps1
```

## For gaming purpose

<img src="https://fakeimg.pl/852x480/ffa154/ffa154" width="49.25%"/><img src="https://upload.wikimedia.org/wikipedia/commons/c/ca/1x1.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/ffa154/ffa154" width="49.25%"/>

### Features

- Update and configure windows
- Update and configure gpu driver
- ...

### Launcher

```powershell
iwr https://github.com/sharpordie/winhogen/archive/refs/heads/main.zip -o $env:temp\main.zip
expand-archive $env:temp\main.zip -destinationpath $env:temp -force
powershell -ep bypass $env:temp\winhogen-main\gamhogen.ps1
```

## For shield purpose

<img src="https://fakeimg.pl/852x480/9bdb4d/9bdb4d" width="49.25%"/><img src="https://upload.wikimedia.org/wikipedia/commons/c/ca/1x1.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/9bdb4d/9bdb4d" width="49.25%"/>

### Features

- Update and configure windows
- Update and configure gpu driver
- Update and configure sunshine
- ...

### Launcher

```powershell
iwr https://github.com/sharpordie/winhogen/archive/refs/heads/main.zip -o $env:temp\main.zip
expand-archive $env:temp\main.zip -destinationpath $env:temp -force
powershell -ep bypass $env:temp\winhogen-main\shihogen.ps1
```

## For custom purpose

Copy the generic template and make it yours.

```powershell
git clone https://github.com/sharpordie/winhogen.git
cd winhogen
cp template.ps1 ownhogen.ps1
```