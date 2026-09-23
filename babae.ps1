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
. (Join-Path $moduleRoot "themes.ps1")
. (Join-Path $moduleRoot "input.ps1")
. (Join-Path $moduleRoot "state.ps1")
. (Join-Path $moduleRoot "clipboard.ps1")
. (Join-Path $moduleRoot "config.ps1")
. (Join-Path $moduleRoot "syntax.ps1")
. (Join-Path $moduleRoot "renderer.ps1")
. (Join-Path $moduleRoot "keys.ps1")
. (Join-Path $moduleRoot "dialogs.ps1")
. (Join-Path $moduleRoot "platform.ps1")
. (Join-Path $moduleRoot "install.ps1")
. (Join-Path $moduleRoot "main.ps1")
Start-BabaeEditor -Path $Path