<#[
.SYNOPSIS
    Builds the portable babae package used by WinGet.
#>
[CmdletBinding()]
param(
  [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $repoRoot "dist"
$stagingDir = Join-Path $distDir "staging"
$launcherDir = Join-Path $distDir "launcher"
$zipPath = Join-Path $distDir "babae-$Version.zip"
$csprojPath = Join-Path $repoRoot "src\Launcher\Launcher.csproj"
$editorRoot = Join-Path $repoRoot "src\Editor"

function Write-Step([string]$Message) {
  Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Merge-Modules {
  Write-Step "Merging editor modules into single-file distribution"

  $moduleFiles = @(
    "Themes.ps1"
    "Input.ps1"
    "State.ps1"
    "Clipboard.ps1"
    "Config.ps1"
    "Syntax.ps1"
    "Renderer.ps1"
    "Keys.ps1"
    "Dialogs.ps1"
    "Platform.ps1"
    "Install.ps1"
    "Main.ps1"
  )

  $merged = @()
  $merged += "<#"
  $merged += ".SYNOPSIS"
  $merged += "    babae - The Zero-Lag, SSH-Safe, TUI Editor"
  $merged += ".DESCRIPTION"
  $merged += "    Pure PowerShell TUI editor. No dependencies, no NuGet, no DLLs."
  $merged += "    ANSI rendering, dark/light themes, cross-platform clipboard, .editorconfig support,"
  $merged += "    syntax highlighting, horizontal scrolling, autocomplete."
  $merged += ".NOTES"
  $merged += "    PS installation: https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu?view=powershell-7.6"
  $merged += "    babae installation: winget install simwai.babae (Windows) or curl -O https://gitlab.com/simwai/babae/-/raw/main/babae.ps1"
  $merged += ".PARAMETER Path"
  $merged += "    Optional file to open on launch."
  $merged += ".PARAMETER Theme"
  $merged += "    Starting theme: dark (default) | mocha | frappe | github-dark | latte"
  $merged += ".EXAMPLE"
  $merged += "    pwsh ./babae.ps1"
  $merged += "    pwsh ./babae.ps1 myfile.txt -Theme mocha"
  $merged += "#>"
  $merged += "param("
  $merged += "  [Parameter(Position = 0)][string]`$Path,"
  $merged += "  [ValidateSet(`"dark`", `"mocha`", `"frappe`", `"github-dark`", `"latte`")]"
  $merged += "  [string]`$Theme = `"dark`""
  $merged += ")"
  $merged += ""
  $merged += "`$ErrorActionPreference = `"Stop`""
  $merged += ""

  $merged += "`$script:currentThemeIndex = [Math]::Max(0, @(`"dark`", `"mocha`", `"frappe`", `"github-dark`", `"latte`").IndexOf(`$Theme))"
  $merged += ""

  foreach ($module in $moduleFiles) {
    $path = Join-Path $editorRoot $module
    if (-not (Test-Path $path)) {
      throw "Module not found: $path"
    }
    $content = Get-Content $path -Raw

    # Remove the param block from Main.ps1 since we handle params in the merged file
    if ($module -eq "Main.ps1") {
      $content = $content -replace '(?s)^param\(.*?\n\)\n\s*\n', ''
    }

    # Remove duplicate $ErrorActionPreference = "Stop" from modules (keep first)
    if ($module -ne "Themes.ps1") {
      $content = $content -replace '^\$ErrorActionPreference = "Stop"\s*\n', ''
    }

    $merged += $content
    $merged += ""
  }

  $merged += "Start-BabaeEditor `@PSBoundParameters"

  $outputPath = Join-Path $stagingDir "babae.ps1"
  Set-Content -Path $outputPath -Value ($merged -join "`n") -Encoding UTF8
  Write-Host "  Merged $(($merged -join "`n").Split("`n").Count) lines -> $outputPath"
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
  throw "The .NET SDK is required to build the launcher."
}

Write-Step "Building babae.exe launcher"
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Remove-Item $launcherDir, $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
& dotnet publish $csprojPath -c Release -r win-x64 --self-contained false -o $launcherDir
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $launcherDir "babae.exe"))) {
  throw "dotnet publish failed."
}

Write-Step "Packaging zip"
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
Copy-Item (Join-Path $launcherDir "babae.exe") $stagingDir
Merge-Modules
Copy-Item (Join-Path $repoRoot "LICENSE") $stagingDir
Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -Force

$sha256 = (Get-FileHash $zipPath -Algorithm SHA256).Hash
$manifestDir = Join-Path $repoRoot "manifests\s\simwai\babae\$Version"
$installerManifest = Join-Path $manifestDir "simwai.babae.installer.yaml"
if (Test-Path $installerManifest) {
  $content = Get-Content $installerManifest -Raw
  $updated = $content -replace 'InstallerSha256: [0-9A-Fa-f]{64}', "InstallerSha256: $sha256"
  if ($updated -ne $content) {
    Set-Content $installerManifest -Value $updated -NoNewline -Encoding UTF8
  }
}

Write-Host "Created: $zipPath"
Write-Host "SHA256: $sha256"