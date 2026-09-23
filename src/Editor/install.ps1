<#
.SYNOPSIS
    Installation check and global profile setup for babae.
.DESCRIPTION
    Detects whether babae is installed globally, prompts for install or
    update, and adds a profile function when needed.
#>

$ErrorActionPreference = 'Stop'

function Invoke-InstallCheck {
  <#
  .SYNOPSIS
      Ensures the running babae script matches the globally installed copy.
  .DESCRIPTION
      Skips entirely in redirected or test environments. When running from
      a non-installed copy, prompts the user to copy the script into
      ~/.babae and add a profile function.
  #>
  if ([Console]::IsInputRedirected -or $Env:BABAE_SKIP_INSTALL) { return }

  $installDirectory = Join-Path $HOME ".babae"
  $installedScriptPath = Join-Path $installDirectory "babae.ps1"
  $currentScriptPath = $PSCommandPath

  $isRunningFromInstalledCopy = $false
  if ($currentScriptPath) {
    if (Test-Path $currentScriptPath) {
      $resolvedCurrent = (Resolve-Path $currentScriptPath).Path
      if ($resolvedCurrent -eq $installedScriptPath) {
        $isRunningFromInstalledCopy = $true
      }
    }
  }

  if ($currentScriptPath -and -not $isRunningFromInstalledCopy) {
    $shouldUpdate = $false
    $message = ""
    if (-not (Test-Path $installedScriptPath)) {
      $shouldUpdate = $true
      $message = " babae is not installed globally. Install to $installedScriptPath and add to profile? (y/n): "
    } else {
      try {
        $currentHash = (Get-FileHash $currentScriptPath -Algorithm SHA256).Hash
        $installedHash = (Get-FileHash $installedScriptPath -Algorithm SHA256).Hash
        if ($currentHash -ne $installedHash) {
          $shouldUpdate = $true
          $message = " A different version of babae is installed globally. Update it? (Y/n): "
        }
      } catch {}
    }

    if ($shouldUpdate) {
      Write-Host "`n$message" -NoNewline -ForegroundColor Cyan
      $choice = Read-Host
      if ([string]::IsNullOrWhiteSpace($choice) -or $choice -match '^[Yy]') {
        if (-not (Test-Path $installDirectory)) { New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null }
        Copy-Item -Path $currentScriptPath -Destination $installedScriptPath -Force

        $profileDirectory = Split-Path $PROFILE
        if (-not (Test-Path $profileDirectory)) { New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null }
        if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }

        $functionName = "babae"
        $functionDefinition = "`nfunction $functionName { pwsh -NoProfile -File `"$installedScriptPath`" @args }`n"
        $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($null -eq $profileContent -or $profileContent -notlike "*function $functionName {*") {
          Add-Content -Path $PROFILE -Value $functionDefinition
          Write-Host " Added 'babae' function to $PROFILE" -ForegroundColor Green
        } else {
          Write-Host " Global 'babae' command updated." -ForegroundColor Green
        }
        Write-Host " babae installed/updated successfully at $installedScriptPath" -ForegroundColor Green
        Start-Sleep -Seconds 1
      }
    }
  }
}

