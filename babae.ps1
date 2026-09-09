<#
.SYNOPSIS
    babae - The Zero-Lag, SSH-Safe, TUI Editor
.DESCRIPTION
    Pure PowerShell TUI editor. No dependencies, no NuGet, no DLLs.
    ANSI rendering, dark/light themes, cross-platform clipboard, .editorconfig support,
    syntax highlighting, horizontal scrolling, autocomplete.
.NOTES
    PS installation: https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu?view=powershell-7.6
    babae installation: winget install simwai.babae (Windows) or curl -O https://gitlab.com/simwai/babae/-/raw/main/babae.ps1
.PARAMETER Path
    Optional file to open on launch.
.PARAMETER Theme
    Starting theme: dark (default) | mocha | frappe | github-dark | latte
.EXAMPLE
    pwsh ./babae.ps1
    pwsh ./babae.ps1 myfile.txt -Theme mocha
#>
param(
  [Parameter(Position = 0)][string]$Path,
  [ValidateSet("dark", "mocha", "frappe", "github-dark", "latte")]
  [string]$Theme = "dark"
)

$ErrorActionPreference = "Stop"
$script:currentThemeIndex = [Math]::Max(0, @("dark", "mocha", "frappe", "github-dark", "latte").IndexOf($Theme))

$moduleRoot = Join-Path (Split-Path $PSCommandPath) "src\Editor"
. (Join-Path $moduleRoot "Themes.ps1")
. (Join-Path $moduleRoot "Input.ps1")
. (Join-Path $moduleRoot "State.ps1")
. (Join-Path $moduleRoot "Clipboard.ps1")
. (Join-Path $moduleRoot "Config.ps1")
. (Join-Path $moduleRoot "Syntax.ps1")
. (Join-Path $moduleRoot "Renderer.ps1")
. (Join-Path $moduleRoot "Keys.ps1")
. (Join-Path $moduleRoot "Dialogs.ps1")
. (Join-Path $moduleRoot "Platform.ps1")
. (Join-Path $moduleRoot "Install.ps1")
. (Join-Path $moduleRoot "Main.ps1")
Start-BabaeEditor -Path $Path