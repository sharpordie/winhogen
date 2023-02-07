# <samp>OVERVIEW</samp>

Opinionated post-installation scripts for Windows 11.

# <samp>GUIDANCE</samp>

## For coding purpose

<img src="https://fakeimg.pl/852x480/43d6b5/43d6b5" width="49.25%"/><img src="assets/img0.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/43d6b5/43d6b5" width="49.25%"/>

### Features

- Update and configure windows
- Update and configure gpu driver
- ...

### Launcher

```powershell
iwr https://github.com/sharpordie/winhogen/archive/refs/heads/main.zip -o $env:temp\main.zip
expand-archive $env:temp\main.zip -destinationpath $env:temp -force
powershell -ep bypass $env:temp\winhogen-main\src\codhogen.ps1
```

## For gaming purpose

<img src="https://fakeimg.pl/852x480/ffa154/ffa154" width="49.25%"/><img src="assets/img0.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/ffa154/ffa154" width="49.25%"/>

### Features

- Update and configure windows
- Update and configure gpu driver
- ...

### Launcher

```powershell
iwr https://github.com/sharpordie/winhogen/archive/refs/heads/main.zip -o $env:temp\main.zip
expand-archive $env:temp\main.zip -destinationpath $env:temp -force
powershell -ep bypass $env:temp\winhogen-main\src\gamhogen.ps1
```

## For stream purpose

<img src="https://fakeimg.pl/852x480/9bdb4d/9bdb4d" width="49.25%"/><img src="assets/img0.png" width="1.5%"/><img src="https://fakeimg.pl/852x480/9bdb4d/9bdb4d" width="49.25%"/>

### Features

- Update and configure windows
- Update and configure gpu driver
- Update and configure sunshine
- ...

### Launcher

```powershell
iwr https://github.com/sharpordie/winhogen/archive/refs/heads/main.zip -o $env:temp\main.zip
expand-archive $env:temp\main.zip -destinationpath $env:temp -force
powershell -ep bypass $env:temp\winhogen-main\src\strhogen.ps1
```

## For custom purpose

Copy the generic template and make it yours.

```powershell
git clone https://github.com/sharpordie/winhogen.git
cp winhogen\src\template.ps1 winhogen\src\cushogen.ps1
```