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

# ---------------------------------------------------------------------------
# Global Installation / Update (kept as originally requested)
# ---------------------------------------------------------------------------
if (-not [Console]::IsInputRedirected -and -not $Env:BABAE_SKIP_INSTALL) {
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
$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$script:frameDelayMilliseconds = 16

# ---------------------------------------------------------------------------
# Themes - built from a base template to eliminate duplication
# ---------------------------------------------------------------------------
$script:baseTheme = @{
  background                  = "48;2;17;15;26"
  backgroundLine              = "48;2;24;21;36"
  backgroundGutter            = "48;2;20;18;30"
  backgroundStatusBar         = "48;2;30;26;48"
  backgroundSelection         = "48;2;80;50;140"
  backgroundHeader            = "48;2;80;50;140"
  foregroundNormal            = "38;2;220;215;240"
  foregroundMuted             = "38;2;110;100;150"
  foregroundAccent            = "38;2;189;147;249"
  foregroundLineNumber        = "38;2;80;70;110"
  foregroundCurrentLineNumber = "38;2;189;147;249"
  foregroundHeader            = "38;2;255;255;255"
  foregroundSearch            = "38;2;255;184;108"
  foregroundDirty             = "38;2;255;121;198"
  foregroundSaved             = "38;2;80;250;123"
  foregroundTilde             = "38;2;60;50;90"
  foregroundSelection         = "38;2;255;255;255"
  foregroundRuler             = "38;2;110;100;150"
  foregroundKeyword           = "38;2;203;166;247"
  foregroundString            = "38;2;166;227;161"
  foregroundComment           = "38;2;166;173;200"
  foregroundNumber            = "38;2;250;179;135"
  foregroundType              = "38;2;245;194;231"
  foregroundVariable          = "38;2;205;214;244"
  foregroundFunction          = "38;2;137;180;250"
  foregroundOperator          = "38;2;148;226;213"
  foregroundPunctuation       = "38;2;166;173;200"
  foregroundConstant          = "38;2;235;160;172"
  displayName                 = ""
}

function New-ThemeFromOverride([hashtable]$overrides, [string]$displayName) {
  $theme = $script:baseTheme.Clone()
  foreach ($key in $overrides.Keys) { $theme[$key] = $overrides[$key] }
  $theme.displayName = $displayName
  return $theme
}

$script:availableThemeNames = @("dark", "mocha", "frappe", "github-dark", "latte")
$script:themeDefinitions = @{
  "dark"           = New-ThemeFromOverride @{} "babae dark"
  "mocha"          = New-ThemeFromOverride @{
    background                  = "48;2;30;30;46"
    backgroundLine              = "48;2;40;38;53"
    backgroundGutter            = "48;2;24;24;37"
    backgroundStatusBar         = "48;2;17;17;27"
    backgroundSelection         = "48;2;88;91;112"
    backgroundHeader            = "48;2;17;17;27"
    foregroundNormal            = "38;2;205;214;244"
    foregroundMuted             = "38;2;88;91;112"
    foregroundAccent            = "38;2;203;166;247"
    foregroundLineNumber        = "38;2;88;91;112"
    foregroundCurrentLineNumber = "38;2;203;166;247"
    foregroundHeader            = "38;2;205;214;244"
    foregroundSearch            = "38;2;249;226;175"
    foregroundDirty             = "38;2;243;139;168"
    foregroundSaved             = "38;2;166;227;161"
    foregroundTilde             = "38;2;49;50;68"
    foregroundRuler             = "38;2;88;91;112"
    displayName                 = "Catppuccin Mocha"
  } "Catppuccin Mocha"
  "frappe"         = New-ThemeFromOverride @{
    background                  = "48;2;48;52;70"
    backgroundLine              = "48;2;65;69;89"
    backgroundGutter            = "48;2;41;44;60"
    backgroundStatusBar         = "48;2;35;38;52"
    backgroundSelection         = "48;2;98;104;128"
    backgroundHeader            = "48;2;35;38;52"
    foregroundNormal            = "38;2;198;208;245"
    foregroundMuted             = "38;2;98;104;128"
    foregroundAccent            = "38;2;202;158;230"
    foregroundLineNumber        = "38;2;98;104;128"
    foregroundCurrentLineNumber = "38;2;202;158;230"
    foregroundHeader            = "38;2;198;208;245"
    foregroundSearch            = "38;2;229;200;144"
    foregroundDirty             = "38;2;231;130;132"
    foregroundSaved             = "38;2;166;209;137"
    foregroundTilde             = "38;2;65;69;89"
    foregroundRuler             = "38;2;98;104;128"
    displayName                 = "Catppuccin Frappe"
  } "Catppuccin Frappe"
  "github-dark"    = New-ThemeFromOverride @{
    background                  = "48;2;13;17;23"
    backgroundLine              = "48;2;22;27;34"
    backgroundGutter            = "48;2;13;17;23"
    backgroundStatusBar         = "48;2;22;27;34"
    backgroundSelection         = "48;2;33;68;118"
    backgroundHeader            = "48;2;22;27;34"
    foregroundNormal            = "38;2;230;237;243"
    foregroundMuted             = "38;2;110;118;129"
    foregroundAccent            = "38;2;210;153;255"
    foregroundLineNumber        = "38;2;110;118;129"
    foregroundCurrentLineNumber = "38;2;210;153;255"
    foregroundHeader            = "38;2;230;237;243"
    foregroundSearch            = "38;2;255;212;0"
    foregroundDirty             = "38;2;248;81;73"
    foregroundSaved             = "38;2;63;185;80"
    foregroundTilde             = "38;2;33;38;45"
    foregroundRuler             = "38;2;110;118;129"
    displayName                 = "GitHub Dark"
  } "GitHub Dark"
  "latte" = New-ThemeFromOverride @{
    background                  = "48;2;239;241;245"
    backgroundLine              = "48;2;228;230;237"
    backgroundGutter            = "48;2;220;224;232"
    backgroundStatusBar         = "48;2;204;208;218"
    backgroundSelection         = "48;2;188;192;204"
    backgroundHeader            = "48;2;204;208;218"
    foregroundNormal            = "38;2;76;79;105"
    foregroundMuted             = "38;2;108;111;133"
    foregroundAccent            = "38;2;136;57;239"
    foregroundLineNumber        = "38;2;156;160;176"
    foregroundCurrentLineNumber = "38;2;136;57;239"
    foregroundHeader            = "38;2;76;79;105"
    foregroundSearch            = "38;2;254;100;11"
    foregroundDirty             = "38;2;210;15;57"
    foregroundSaved             = "38;2;64;160;43"
    foregroundTilde             = "38;2;188;192;204"
    foregroundRuler             = "38;2;108;111;133"
    foregroundKeyword           = "38;2;108;45;181"
    foregroundString            = "38;2;42;107;27"
    foregroundComment           = "38;2;67;71;80"
    foregroundNumber            = "38;2;196;77;0"
    foregroundType              = "38;2;194;82;163"
    foregroundVariable          = "38;2;60;63;86"
    foregroundFunction          = "38;2;20;73;196"
    foregroundOperator          = "38;2;14;110;114"
    foregroundPunctuation       = "38;2;85;88;104"
    foregroundConstant          = "38;2;178;36;54"
    displayName                 = "Catppuccin Latte"
  } "Catppuccin Latte"
}
$script:currentThemeIndex = [Math]::Max(0, $script:availableThemeNames.IndexOf($Theme))
function Get-ThemeColor([string]$key) {
  $currentTheme = $script:themeDefinitions[$script:availableThemeNames[$script:currentThemeIndex]]
  return "`e[$($currentTheme[$key])m"
}
$script:RESET_SEQUENCE = "`e[0m"
# $script:BOLD_SEQUENCE = "`e[1m"

$script:SEQ_MOUSE_TRACKING_OFF = "`e[?1000l`e[?1002l`e[?1003l"
$script:SEQ_AUTOWRAP_OFF = "`e[?7l"
$script:SEQ_AUTOWRAP_ON = "`e[?7h"

# ---------------------------------------------------------------------------
# Output & Input infrastructure
# ---------------------------------------------------------------------------
$script:outputWriter = [System.IO.StreamWriter]::new([Console]::OpenStandardOutput())
$script:outputWriter.AutoFlush = $false

$script:inputStream = [Console]::OpenStandardInput()
$script:inputReadBuffer = [byte[]]::new(4096)
$script:pendingByteQueue = [System.Collections.Generic.Queue[byte]]::new()
$script:isInteractiveConsole = $true
try { [void][Console]::KeyAvailable } catch { $script:isInteractiveConsole = $false }
$script:currentReadTask = $null

function Start-AsyncInputRead {
  if ($null -eq $script:currentReadTask) {
    $script:currentReadTask = $script:inputStream.ReadAsync($script:inputReadBuffer, 0, $script:inputReadBuffer.Length)
  }
}
function Complete-AsyncInputRead {
  $bytesRead = $script:currentReadTask.GetAwaiter().GetResult()
  $script:currentReadTask = $null
  for ($i = 0; $i -lt $bytesRead; $i++) {
    $script:pendingByteQueue.Enqueue($script:inputReadBuffer[$i])
  }
  return $bytesRead
}
function Try-DrainInputQueue {
  if ($script:pendingByteQueue.Count -gt 0) { return $true }
  if ($script:isInteractiveConsole) {
    try { return [Console]::KeyAvailable } catch { $script:isInteractiveConsole = $false }
  }
  Start-AsyncInputRead
  if (-not $script:currentReadTask.IsCompleted) { return $false }
  [void](Complete-AsyncInputRead)
  return $true
}
function Test-InputDataAvailable { return Try-DrainInputQueue }

function Read-ByteFromInput {
  while ($script:pendingByteQueue.Count -eq 0) {
    Start-AsyncInputRead
    $bytesRead = Complete-AsyncInputRead
    if ($bytesRead -le 0) { return -1 }
  }
  return [int]$script:pendingByteQueue.Dequeue()
}
function Drain-OsPipeBuffers {
  if ($null -ne $script:currentReadTask -and $script:currentReadTask.IsCompleted) {
    $bytesRead = Complete-AsyncInputRead
    if ($bytesRead -le 0) { return }
  }
  while ($true) {
    Start-AsyncInputRead
    if (-not $script:currentReadTask.Wait(1)) { break }
    $bytesRead = Complete-AsyncInputRead
    if ($bytesRead -le 0) { break }
  }
}
function Read-AllAvailableText {
  if ($null -ne $script:currentReadTask) {
    if ($script:currentReadTask.IsCompleted) {
      [void]$script:currentReadTask.GetAwaiter().GetResult()
    }
    $script:currentReadTask = $null
  }

  Drain-OsPipeBuffers

  $deadline = [System.Diagnostics.Stopwatch]::StartNew()
  while ($deadline.ElapsedMilliseconds -lt 15) {
    Start-AsyncInputRead
    if ($script:currentReadTask.Wait(5)) {
      $read = Complete-AsyncInputRead
      if ($read -le 0) { break }
    } else { break }
  }

  Drain-OsPipeBuffers
  $count = $script:pendingByteQueue.Count
  if ($count -eq 0) { return [string]::Empty }

  $allBytes = [byte[]]::new($count)
  $script:pendingByteQueue.CopyTo($allBytes, 0)
  $script:pendingByteQueue.Clear()

  if ($null -ne $script:currentReadTask) {
    if ($script:currentReadTask.IsCompleted) {
      [void]$script:currentReadTask.GetAwaiter().GetResult()
    }
    $script:currentReadTask = $null
  }

  $text = [System.Text.Encoding]::UTF8.GetString($allBytes)
  return $text
}

function Read-PastedText {
  Drain-OsPipeBuffers
  $count = $script:pendingByteQueue.Count
  if ($count -eq 0) { return [string]::Empty }

  $allBytes = [byte[]]::new($count)
  $script:pendingByteQueue.CopyTo($allBytes, 0)
  $script:pendingByteQueue.Clear()
  $text = [System.Text.Encoding]::UTF8.GetString($allBytes) -replace "`r`n", "`n" -replace "`r", "`n"
  return $text
}

function Build-ConsoleKeyInfo([char]$ch, [System.ConsoleKey]$key, [System.ConsoleModifiers]$modifiers) {
  return [System.ConsoleKeyInfo]::new($ch, $key,
    ($modifiers -band [System.ConsoleModifiers]::Shift) -ne 0,
    ($modifiers -band [System.ConsoleModifiers]::Alt) -ne 0,
    ($modifiers -band [System.ConsoleModifiers]::Control) -ne 0)
}

function Parse-EscapeSequence([string]$sequence) {
  if ($sequence.StartsWith('[')) {
    $param = $sequence.Substring(1)
    switch ($param) {
      'A' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    0 }
      'B' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  0 }
      'C' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) 0 }
      'D' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  0 }
      'H' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Home)       0 }
      'F' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::End)        0 }
      '1~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Home)       0 }
      '4~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::End)        0 }
      '5~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::PageUp)     0 }
      '6~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::PageDown)   0 }
      '2~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Insert)     0 }
      '3~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Delete)     0 }
      '1;2A' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    ([System.ConsoleModifiers]::Shift) }
      '1;2B' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  ([System.ConsoleModifiers]::Shift) }
      '1;2C' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) ([System.ConsoleModifiers]::Shift) }
      '1;2D' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  ([System.ConsoleModifiers]::Shift) }
      '1;2H' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Home)       ([System.ConsoleModifiers]::Shift) }
      '1;2F' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::End)        ([System.ConsoleModifiers]::Shift) }
      '1;5P' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::F1) ([System.ConsoleModifiers]::Control) }
      '49;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D1) ([System.ConsoleModifiers]::Control) }
      '50;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D2) ([System.ConsoleModifiers]::Control) }
      '51;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D3) ([System.ConsoleModifiers]::Control) }
      '52;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D4) ([System.ConsoleModifiers]::Control) }
      '53;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D5) ([System.ConsoleModifiers]::Control) }
      '54;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D6) ([System.ConsoleModifiers]::Control) }
      '55;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D7) ([System.ConsoleModifiers]::Control) }
      '56;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D8) ([System.ConsoleModifiers]::Control) }
      '57;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D9) ([System.ConsoleModifiers]::Control) }
      '48;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D0) ([System.ConsoleModifiers]::Control) }
    }
  }
  if ($sequence.StartsWith('O')) {
    switch ($sequence.Substring(1)) {
      'A' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    0 }
      'B' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  0 }
      'C' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) 0 }
      'D' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  0 }
      'H' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Home)       0 }
      'F' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::End)        0 }
      'P' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::F1)         0 }
    }
  }
  return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::NoName) 0
}

# --- FIX #3: escape-sequence reassembly now actively waits for late-arriving
#     bytes instead of abandoning a partial sequence the instant the queue
#     empties. This is what was causing dead arrow keys over SSH / laggy pipes,
#     per https://learn.microsoft.com/en-us/windows/console/classic-vs-vt
function Read-InputEvent {
  $firstByte = Read-ByteFromInput
  if ($firstByte -eq -1) {
    return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]26) ([System.ConsoleKey]::Z) ([System.ConsoleModifiers]::Control)) }
  }

  if ($firstByte -eq 27) {
    Drain-OsPipeBuffers
    if ($script:pendingByteQueue.Count -eq 0) {
      $w = 0
      while ($script:pendingByteQueue.Count -eq 0 -and $w -lt 5) { Start-Sleep -Milliseconds 2; $w++; Drain-OsPipeBuffers }
      if ($script:pendingByteQueue.Count -eq 0) { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) } }
    }
    $peekChar = [char]$script:pendingByteQueue.Peek()
    if ($peekChar -ne '[' -and $peekChar -ne 'O') {
      return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
    }
    $seqBuilder = [System.Text.StringBuilder]::new()
    $maxSeqLen = 24   # widened slightly to comfortably fit SGR mouse reports
    $maxWaitIterations = 40
    while ($seqBuilder.Length -lt $maxSeqLen) {
      if ($script:pendingByteQueue.Count -eq 0) {
        $waited = 0
        while ($script:pendingByteQueue.Count -eq 0 -and $waited -lt $maxWaitIterations) {
          Start-Sleep -Milliseconds 2
          Drain-OsPipeBuffers
          $waited++
        }
        if ($script:pendingByteQueue.Count -eq 0) { break }
      }
      $nb = $script:pendingByteQueue.Peek()
      if ($nb -eq 27) { break }
      $nc = [char]$nb
      [void]$seqBuilder.Append($nc)
      $script:pendingByteQueue.Dequeue() | Out-Null
      $seq = $seqBuilder.ToString()

      if ($seq -eq '[200~') {
        $paste = Read-PastedText
        return [PSCustomObject]@{ Kind = 'Paste'; Text = $paste }
      }

      # SGR mouse report: ESC [ < params M-or-m — babae has no mouse handling, discard silently
      if ($seq -match '^\[<[0-9;]+[Mm]$') {
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::NoName) 0) }
      }

      $ki = Parse-EscapeSequence $seq
      if ($ki.Key -ne [System.ConsoleKey]::NoName) {
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = $ki }
      }

      $couldContinue = ($seq.Length -eq 1 -and ($seq -eq '[' -or $seq -eq 'O')) `
        -or ($seq.Length -eq 2 -and $seq -eq '[<') `
        -or ($seq.Length -gt 2 -and $seq.StartsWith('[<') -and ($nc -match '[0-9;Mm]')) `
        -or ($seq.Length -gt 1 -and $seq[0] -eq '[' -and -not $seq.StartsWith('[<') -and ($nc -match '[0-9;]'))
      if (-not $couldContinue) { break }
    }
    $seqStr = $seqBuilder.ToString()
    if ($script:debugMode) {
      $raw = [System.Text.Encoding]::UTF8.GetBytes($seqStr)
      $tmpQueue = [System.Collections.Generic.Queue[byte]]::new()
      foreach ($b in $raw) { $tmpQueue.Enqueue($b) }
      foreach ($b in $script:pendingByteQueue) { $tmpQueue.Enqueue($b) }
      $script:pendingByteQueue = $tmpQueue
    }
    return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
  }

  if ($firstByte -ge 32 -and $firstByte -le 126) {
    Drain-OsPipeBuffers
    if ($script:pendingByteQueue.Count -gt 8) {
      $paste = [char]$firstByte + (Read-PastedText)
      return [PSCustomObject]@{ Kind = 'Paste'; Text = $paste }
    }
  }

  switch ($firstByte) {
    0 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]0)  ([System.ConsoleKey]::D2)        ([System.ConsoleModifiers]::Control)) } }
    13 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]13) ([System.ConsoleKey]::Enter)     0) } }
    127 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }
    8 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]8)   ([System.ConsoleKey]::Backspace) 0) } }
    9 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]9)  ([System.ConsoleKey]::Tab)       0) } }
    27 { }
    28 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]28) ([System.ConsoleKey]::D4)        ([System.ConsoleModifiers]::Control)) } }
    29 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]29) ([System.ConsoleKey]::D5)        ([System.ConsoleModifiers]::Control)) } }
    30 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]30) ([System.ConsoleKey]::D6)        ([System.ConsoleModifiers]::Control)) } }
    31 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]31) ([System.ConsoleKey]::D7)        ([System.ConsoleModifiers]::Control)) } }
    default {
      if ($firstByte -ge 1 -and $firstByte -le 26) {
        $letter = [char]($firstByte + [int][char]'A' - 1)
        $ck = [System.ConsoleKey]$letter.ToString()
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]$firstByte) $ck ([System.ConsoleModifiers]::Control)) }
      }
    }
  }

  [byte[]]$utf8Bytes = @($firstByte)
  if ($firstByte -ge 0xC0) {
    $extra = if ($firstByte -ge 0xF0) { 3 } elseif ($firstByte -ge 0xE0) { 2 } else { 1 }
    for ($i = 0; $i -lt $extra; $i++) { $utf8Bytes += Read-ByteFromInput }
  }
  $char = [System.Text.Encoding]::UTF8.GetString($utf8Bytes)[0]
  $ck = try { [System.ConsoleKey]$char.ToString().ToUpper() } catch { [System.ConsoleKey]::NoName }
  return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo $char $ck 0) }
}

$script:cachedRenderRows = [System.Collections.Generic.List[string]]::new()
$script:cachedCursorRow = -1
$script:cachedCursorColumn = -1

function Write-OutputBuffer([string]$text) {
  $script:outputWriter.Write($text)
  $script:outputWriter.Flush()
}
function Clear-RenderCache {
  $script:cachedRenderRows.Clear()
  $script:cachedCursorRow = -1
  $script:cachedCursorColumn = -1
}

# ---------------------------------------------------------------------------
# Clipboard helper (deduplicated platform detection)
# ---------------------------------------------------------------------------
function Find-ClipboardTool {
  if ($IsWindows -or $env:OS -eq 'Windows_NT') { return 'WinForms' }
  if ($IsMacOS) { return 'pbcopy' }
  if (Get-Command wl-copy -ErrorAction SilentlyContinue) { return 'wl-copy' }
  if (Get-Command xclip -ErrorAction SilentlyContinue) { return 'xclip' }
  if (Get-Command xsel -ErrorAction SilentlyContinue) { return 'xsel' }
  return $null
}

function Get-ClipboardContent {
  $tool = Find-ClipboardTool
  try {
    switch ($tool) {
      'WinForms' { return [System.Windows.Forms.Clipboard]::GetText() }
      'pbcopy' { return & pbpaste 2>$null }
      'wl-copy' { return & wl-paste 2>$null }
      'xclip' { return & xclip -selection clipboard -o 2>$null }
      'xsel' { return & xsel --clipboard --output 2>$null }
      default { return [string]::Empty }
    }
  } catch { return [string]::Empty }
}

function Set-ClipboardContent([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return }
  $tool = Find-ClipboardTool
  try {
    switch ($tool) {
      'WinForms' { [System.Windows.Forms.Clipboard]::SetText($text); return }
      'pbcopy' { $text | & pbcopy; return }
      'wl-copy' { $text | & wl-copy; return }
      'xclip' { $text | & xclip -selection clipboard; return }
      'xsel' { $text | & xsel --clipboard --input; return }
    }
  } catch {}
}
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Editor state (inline trivial getters)
# ---------------------------------------------------------------------------
$editorState = [PSCustomObject]@{
  TextBuffer             = [System.Text.StringBuilder]::new()
  CursorOffset           = 0
  PreferredColumn        = 0
  VerticalScrollRow      = 0
  HorizontalScrollOffset = 0
  FilePath               = ''
  Language               = 'Plain Text'
  IsDirty                = $false
  StatusMessage          = ''
  LastSearchTerm         = ''
  UndoStack              = [System.Collections.Generic.Stack[object]]::new()
  RedoStack              = [System.Collections.Generic.Stack[object]]::new()
  EditorMode             = 'edit'
  SaveAsBuffer           = ''
  SearchBuffer           = ''
  IsSelectionActive      = $false
  SelectionAnchor        = 0
  SyntaxTokenCache       = @{}
  AutocompleteMatches    = $null
  AutocompleteIndex      = 0
  AutocompleteBaseOffset = 0
}

function Get-BufferText { $editorState.TextBuffer.ToString() }
function Set-BufferContent([string]$text) {
  $editorState.TextBuffer.Clear() | Out-Null
  if ($text) { $editorState.TextBuffer.Append($text) | Out-Null }
  $editorState.SyntaxTokenCache = @{}
}
function Clamp-CursorOffset {
  $editorState.CursorOffset = [Math]::Max(0, [Math]::Min($editorState.CursorOffset, $editorState.TextBuffer.Length))
}

function Convert-OffsetToRowCol([int]$offset) {
  $text = $editorState.TextBuffer.ToString()
  $clamped = [Math]::Max(0, [Math]::Min($offset, $text.Length))
  $row = 0; $lineStart = 0
  for ($i = 0; $i -lt $clamped; $i++) {
    if ($text[$i] -eq "`n") { $row++; $lineStart = $i + 1 }
  }
  return $row, ($clamped - $lineStart)
}

function Get-LineStartOffset([int]$offset) {
  $text = $editorState.TextBuffer.ToString()
  while ($offset -gt 0 -and $text[$offset - 1] -ne "`n") { $offset-- }
  return $offset
}

function Get-LineEndOffset([int]$offset) {
  $text = $editorState.TextBuffer.ToString()
  while ($offset -lt $text.Length -and $text[$offset] -ne "`n") { $offset++ }
  return $offset
}

function Get-LineByNumber([int]$lineNum) {
  $text = $editorState.TextBuffer.ToString()
  $row = 0; $start = 0
  for ($i = 0; $i -le $text.Length; $i++) {
    if ($i -eq $text.Length -or $text[$i] -eq "`n") {
      if ($row -eq $lineNum) { return $text.Substring($start, $i - $start) }
      $row++; $start = $i + 1
    }
  }
  return $null
}

function Convert-RowColToOffset([int]$row, [int]$col) {
  $text = $editorState.TextBuffer.ToString()
  $r = 0; $start = 0
  for ($i = 0; $i -le $text.Length; $i++) {
    if ($i -eq $text.Length -or $text[$i] -eq "`n") {
      if ($r -eq $row) { return $start + [Math]::Max(0, [Math]::Min($col, $i - $start)) }
      $r++; $start = $i + 1
    }
  }
  return $text.Length
}

function Get-SelectionBoundaries {
  return [Math]::Min($editorState.SelectionAnchor, $editorState.CursorOffset),
  [Math]::Max($editorState.SelectionAnchor, $editorState.CursorOffset)
}

function Reset-EditorState {
  Set-BufferContent ''
  $editorState.CursorOffset = 0; $editorState.PreferredColumn = 0
  $editorState.VerticalScrollRow = 0; $editorState.HorizontalScrollOffset = 0
  $editorState.FilePath = ''; $editorState.Language = 'Plain Text'
  $editorState.IsDirty = $false; $editorState.StatusMessage = ''; $editorState.LastSearchTerm = ''
  $editorState.UndoStack.Clear(); $editorState.RedoStack.Clear()
  $editorState.EditorMode = 'edit'; $editorState.SearchBuffer = ''
  $editorState.IsSelectionActive = $false; $editorState.SelectionAnchor = 0
  $editorState.SyntaxTokenCache = @{}
  $editorState.AutocompleteMatches = $null
}

function Load-FileIntoEditor([string]$path) {
  $editorState.FilePath = $path
  $editorState.Language = Get-LanguageFromPath $path
  $raw = if (Test-Path $path) {
    [IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  } else { '' }
  Set-BufferContent $raw
  $editorState.CursorOffset = 0; $editorState.PreferredColumn = 0
  $editorState.VerticalScrollRow = 0; $editorState.HorizontalScrollOffset = 0
}

function Save-EditorFile {
  if ([string]::IsNullOrWhiteSpace($editorState.FilePath)) { $editorState.StatusMessage = ' No path '; return }
  $content = Get-BufferText
  if ($script:editorConfigSettings.trim_trailing_whitespace) {
    $content = ($content -split "`n", -1 | ForEach-Object { $_.TrimEnd() }) -join "`n"
  }
  if ($script:editorConfigSettings.insert_final_newline -and -not $content.EndsWith("`n")) { $content += "`n" }
  switch ($script:editorConfigSettings.end_of_line) {
    'crlf' { $content = $content -replace "`n", "`r`n" }
    'cr' { $content = $content -replace "`n", "`r" }
  }
  $enc = switch ($script:editorConfigSettings.charset) {
    'utf-8-bom' { [Text.UTF8Encoding]::new($true) }
    'latin1' { [Text.Encoding]::Latin1 }
    default { [Text.UTF8Encoding]::new($false) }
  }
  [IO.File]::WriteAllText($editorState.FilePath, $content, $enc)
  $editorState.IsDirty = $false; $editorState.StatusMessage = ' Saved '
}

function Push-UndoSnapshot {
  if ($editorState.UndoStack.Count -ge 200) {
    $arr = $editorState.UndoStack.ToArray()
    $editorState.UndoStack.Clear()
    for ($i = 0; $i -lt ($arr.Count - 100); $i++) {
      $editorState.UndoStack.Push($arr[$arr.Count - 1 - $i])
    }
  }
  $editorState.UndoStack.Push([PSCustomObject]@{
      Buffer = Get-BufferText; Cursor = $editorState.CursorOffset; Preferred = $editorState.PreferredColumn
    })
  $editorState.RedoStack.Clear()
  $editorState.SyntaxTokenCache = @{}
}

function Apply-Snapshot($snap, $targetStack) {
  $targetStack.Push([PSCustomObject]@{
      Buffer = Get-BufferText; Cursor = $editorState.CursorOffset; Preferred = $editorState.PreferredColumn
    })
  Set-BufferContent $snap.Buffer
  $editorState.CursorOffset = [Math]::Min($snap.Cursor, $editorState.TextBuffer.Length)
  $editorState.PreferredColumn = $snap.Preferred
  $editorState.VerticalScrollRow = 0
  $editorState.HorizontalScrollOffset = 0
  $editorState.IsDirty = $true
  Clear-RenderCache
}

function Undo-LastChange {
  if ($editorState.UndoStack.Count -eq 0) { $editorState.StatusMessage = ' Nothing to undo '; return }
  Apply-Snapshot $editorState.UndoStack.Pop() $editorState.RedoStack
}
function Redo-LastChange {
  if ($editorState.RedoStack.Count -eq 0) { $editorState.StatusMessage = ' Nothing to redo '; return }
  Apply-Snapshot $editorState.RedoStack.Pop() $editorState.UndoStack
}

function Get-SelectedText {
  if (-not $editorState.IsSelectionActive) { return [string]::Empty }
  $s, $e = Get-SelectionBoundaries
  (Get-BufferText).Substring($s, $e - $s)
}

function Remove-SelectedText {
  if (-not $editorState.IsSelectionActive) { return }
  $s, $e = Get-SelectionBoundaries
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $s) + $t.Substring($e))
  $editorState.CursorOffset = $s
  $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
  $editorState.IsSelectionActive = $false; $editorState.IsDirty = $true
}

function Start-Selection {
  if (-not $editorState.IsSelectionActive) {
    $editorState.IsSelectionActive = $true
    $editorState.SelectionAnchor = $editorState.CursorOffset
  }
}

# --- FIX #1: bracketed-paste markers now stripped with explicit replacement args
function Paste-TextFromClipboard([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { $editorState.StatusMessage = ' Clipboard empty '; return }
  Push-UndoSnapshot
  if ($editorState.IsSelectionActive) { Remove-SelectedText }
  $norm = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $norm = $norm -replace "`e\[200~", '' -replace "`e\[201~", ''
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $editorState.CursorOffset) + $norm + $t.Substring($editorState.CursorOffset))
  $editorState.CursorOffset += $norm.Length
  $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
  $editorState.IsDirty = $true; $editorState.StatusMessage = ' Pasted (clipboard) '
  Clear-RenderCache
}

function Update-ScrollPosition {
  # Vertical scroll
  $height = [Console]::WindowHeight - 2
  if ($height -lt 1) { $height = 1 }
  $cursorRow = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]
  if ($cursorRow -lt $editorState.VerticalScrollRow) { $editorState.VerticalScrollRow = $cursorRow }
  elseif ($cursorRow -gt $editorState.VerticalScrollRow + $height - 1) { $editorState.VerticalScrollRow = $cursorRow - $height + 1 }
  $editorState.VerticalScrollRow = [Math]::Max(0, $editorState.VerticalScrollRow)

  # Horizontal scroll
  $textWidth = [Console]::WindowWidth - 5
  $cursorCol = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
  if ($cursorCol -lt $editorState.HorizontalScrollOffset) { $editorState.HorizontalScrollOffset = $cursorCol }
  elseif ($cursorCol -ge $editorState.HorizontalScrollOffset + $textWidth) { $editorState.HorizontalScrollOffset = $cursorCol - $textWidth + 1 }
  $editorState.HorizontalScrollOffset = [Math]::Max(0, $editorState.HorizontalScrollOffset)
}

function Move-CursorToScreenCoordinate([int]$r, [int]$c) { "`e[$r;${c}H" }

# --- FIX #5 (additive): DECSTBM scroll-margin helpers
function Set-ScrollMargins([int]$top, [int]$bottom) {
  Write-OutputBuffer "`e[$top;${bottom}r"
}
function Reset-ScrollMargins() {
  Write-OutputBuffer "`e[r"
}

# ---------------------------------------------------------------------------
# .editorconfig (unchanged except variable name)
# ---------------------------------------------------------------------------
$script:editorConfigSettings = @{
  indent_style             = "space"
  indent_size              = 4
  tab_width                = 4
  end_of_line              = "lf"
  trim_trailing_whitespace = $false
  insert_final_newline     = $false
  charset                  = "utf-8"
  max_line_length          = 0
}
$script:commandBindingDefinitions = @(
  [PSCustomObject]@{ Key = '^T'; Label = 'Theme' }
  [PSCustomObject]@{ Key = '^S'; Label = 'Save' }
  [PSCustomObject]@{ Key = '^Q'; Label = 'Quit' }
  [PSCustomObject]@{ Key = '^F'; Label = 'Find' }
  [PSCustomObject]@{ Key = '^Z'; Label = 'Undo' }
  [PSCustomObject]@{ Key = '^Y'; Label = 'Redo' }
  [PSCustomObject]@{ Key = '^A'; Label = 'Select all' }
  [PSCustomObject]@{ Key = '^C'; Label = 'Copy' }
  [PSCustomObject]@{ Key = '^V'; Label = 'Paste' }
  [PSCustomObject]@{ Key = '^F1'; Label = 'Help' }
)

function Convert-EditorConfigGlobToRegex([string]$glob) {
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append('^')
  for ($i = 0; $i -lt $glob.Length; $i++) {
    $ch = $glob[$i]
    if ($ch -eq '*') {
      if ($i + 1 -lt $glob.Length -and $glob[$i + 1] -eq '*') {
        [void]$sb.Append('.*'); $i++
      } else { [void]$sb.Append('[^/]*') }
      continue
    }
    if ($ch -eq '?') { [void]$sb.Append('[^/]'); continue }
    if ($ch -eq '.') { [void]$sb.Append('\.'); continue }
    if ('+()^$|{}'.Contains([string]$ch)) { [void]$sb.Append('\' + $ch); continue }
    if ($ch -eq '\\') {
      if ($i + 1 -lt $glob.Length) { $i++; [void]$sb.Append([Regex]::Escape([string]$glob[$i])) }
      continue
    }
    [void]$sb.Append($ch)
  }
  [void]$sb.Append('$')
  return $sb.ToString()
}

function Test-EditorConfigSectionMatch([string]$pattern, [string]$relativePath) {
  $norm = $relativePath -replace '\\', '/'
  $rx = Convert-EditorConfigGlobToRegex $pattern
  if ($pattern.Contains('/')) { return $norm -match $rx }
  return $norm -match $rx -or ([IO.Path]::GetFileName($norm) -match $rx)
}

function Load-EditorConfig([string]$filePath) {
  $script:editorConfigSettings.indent_style = "space"
  $script:editorConfigSettings.indent_size = 4
  $script:editorConfigSettings.tab_width = 4
  $script:editorConfigSettings.end_of_line = "lf"
  $script:editorConfigSettings.trim_trailing_whitespace = $false
  $script:editorConfigSettings.insert_final_newline = $false
  $script:editorConfigSettings.charset = "utf-8"
  $script:editorConfigSettings.max_line_length = 0

  $dir = if ($filePath) { [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($filePath)) } else { $PWD.Path }
  $fileName = if ($filePath) { [IO.Path]::GetFileName([IO.Path]::GetFullPath($filePath)) } else { "" }
  $stack = [System.Collections.Generic.List[string]]::new()
  $current = $dir
  while ($current) {
    $candidate = Join-Path $current '.editorconfig'
    if (Test-Path $candidate) { $stack.Insert(0, $candidate) }
    $parent = [IO.Path]::GetDirectoryName($current)
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { break }
    $current = $parent
  }
  foreach ($configPath in $stack) {
    $baseDir = [IO.Path]::GetDirectoryName($configPath)
    $rel = if ($filePath) {
      [IO.Path]::GetRelativePath($baseDir, [IO.Path]::GetFullPath($filePath)) -replace '\\', '/'
    } else { $fileName }
    $active = $false
    foreach ($raw in [IO.File]::ReadAllLines($configPath)) {
      $line = $raw.Trim()
      if ($line -eq '' -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
      if ($line -match '^\[(.*)\]$') { $active = Test-EditorConfigSectionMatch $Matches[1].Trim() $rel; continue }
      if ($line -match '^([^=]+)=(.*)$') {
        $k = $Matches[1].Trim().ToLowerInvariant()
        $v = $Matches[2].Trim().ToLowerInvariant()
        if (-not $active) { continue }
        switch ($k) {
          'indent_style' { $script:editorConfigSettings.indent_style = $v }
          'indent_size' { if ($v -match '^\d+$') { $script:editorConfigSettings.indent_size = [int]$v } }
          'tab_width' { if ($v -match '^\d+$') { $script:editorConfigSettings.tab_width = [int]$v } }
          'end_of_line' { $script:editorConfigSettings.end_of_line = $v }
          'trim_trailing_whitespace' { $script:editorConfigSettings.trim_trailing_whitespace = ($v -eq 'true') }
          'insert_final_newline' { $script:editorConfigSettings.insert_final_newline = ($v -eq 'true') }
          'charset' { $script:editorConfigSettings.charset = $v }
          'max_line_length' { if ($v -match '^\d+$') { $script:editorConfigSettings.max_line_length = [int]$v } }
        }
      }
    }
  }
  $editorState.StatusMessage = ' .editorconfig loaded '
}

function Get-IndentationString {
  if ($script:editorConfigSettings.indent_style -eq 'tab') { return "`t" }
  return ' ' * [Math]::Max(1, $script:editorConfigSettings.indent_size)
}

# ---------------------------------------------------------------------------
# Syntax highlighting engine (unchanged)
# ---------------------------------------------------------------------------
function Get-LanguageFromPath([string]$path) {
  if ([string]::IsNullOrEmpty($path)) { return 'Plain Text' }
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    '.ps1' { 'PowerShell' } '.psm1' { 'PowerShell' } '.psd1' { 'PowerShell' }
    '.cs' { 'C#' }
    '.ts' { 'TypeScript' } '.tsx' { 'TypeScript' }
    '.js' { 'JavaScript' } '.jsx' { 'JavaScript' }
    '.py' { 'Python' }
    '.json' { 'JSON' } '.jsonc' { 'JSONC' } '.jsonl' { 'JSON' }
    '.md' { 'Markdown' }
    '.sh' { 'Bash' } '.bash' { 'Bash' }
    '.html' { 'HTML' } '.htm' { 'HTML' }
    '.css' { 'CSS' }
    '.svg' { 'SVG' }
    '.yaml' { 'YAML' } '.yml' { 'YAML' }
    '.toml' { 'TOML' }
    '.java' { 'Java' }
    default {
      if ($path -match '\.env') { 'dotenv' }
      elseif ($path -match 'Dockerfile') { 'Dockerfile' }
      else { 'Plain Text' }
    }
  }
}

$script:languageSyntaxRules = @{
  "JavaScript" = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new("'(?:[^'\\]|\\.)*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('`(?:[^`\\]|\\.)*`', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|for|while|do|switch|case|break|continue|return|function|var|let|const|class|extends|new|this|super|import|export|default|from|as|async|await|try|catch|finally|throw)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null|undefined)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_$][\w$]*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[\+\-\*\/%<>=!&|^~?:]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "TypeScript" = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new("'(?:[^'\\]|\\.)*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('`(?:[^`\\]|\\.)*`', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|for|while|do|switch|case|break|continue|return|function|var|let|const|class|extends|new|this|super|import|export|default|from|as|async|await|try|catch|finally|throw|interface|type|enum)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null|undefined)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_$][\w$]*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[\+\-\*\/%<>=!&|^~?:]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "Python"     = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('(''[\s\S]*?''|"""[\s\S]*?""")', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'(?:[^'\\]|\\.)*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|elif|else|for|while|def|class|import|from|as|return|yield|with|try|except|finally|raise|break|continue|pass|and|or|not|in|is|None|True|False)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_]\w*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[\+\-\*\/%<>=!&|^~]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "PowerShell" = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('<#[\s\S]*?#>', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new("'(?:[^']|'')*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|elseif|foreach|for|while|do|switch|case|default|return|break|continue|function|filter|param|begin|process|end|throw|try|catch|finally|trap|class|enum|using|namespace|in|and|or|not)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\$\w+', 'Compiled'); TokenType = 'variable' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[\+\-\*\/%<>=!&|^~]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "Bash"       = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'(?:[^']|'')*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|return|exit|source|export|local|readonly|declare|shift|trap|break|continue)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\$\{?\w+', 'Compiled'); TokenType = 'variable' }
    @{ CompiledRegex = [regex]::new('\b\d+\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[+\-*/%<>=!&|^~]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "HTML"       = @(
    @{ CompiledRegex = [regex]::new('<!--[\s\S]*?-->', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"[^"]*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'[^']*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('</?[a-zA-Z0-9]+', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('[{}>]', 'Compiled'); TokenType = 'punctuation' }
  )
  "CSS"        = @(
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"[^"]*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'[^']*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('#[0-9a-fA-F]{3,8}', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?(px|em|rem|%|vw|vh)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[{};:]', 'Compiled'); TokenType = 'punctuation' }
  )
  "SVG"        = @(
    @{ CompiledRegex = [regex]::new('<!--[\s\S]*?-->', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"[^"]*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'[^']*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('</?[a-zA-Z_:][\w:.-]*', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('[{}><]', 'Compiled'); TokenType = 'punctuation' }
  )
  "JSON"       = @(
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[{}[\],:]', 'Compiled'); TokenType = 'punctuation' }
  )
  "JSONC"      = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[{}[\],:]', 'Compiled'); TokenType = 'punctuation' }
  )
  "YAML"       = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'(?:[^']|'')*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('-?\b\d+(\.\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[\[\]{}:>|]', 'Compiled'); TokenType = 'punctuation' }
  )
  "TOML"       = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'(?:[^'\\]|'')*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(true|false)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('-?\b\d+(\.\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[\[\]{}.,=]', 'Compiled'); TokenType = 'punctuation' }
  )
  "dotenv"     = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"[^"]*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'[^']*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[=]', 'Compiled'); TokenType = 'operator' }
  )
  "Java"       = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|for|while|do|switch|case|break|continue|return|class|interface|extends|implements|new|this|super|import|package|try|catch|finally|throw|throws|public|private|protected|static|final|void|int|long|double|boolean|char|byte|short|float|String)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_]\w*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[+\-*/%<>=!&|^~?:]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "C#"         = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|for|foreach|while|do|switch|case|break|continue|return|class|struct|interface|enum|namespace|using|new|this|base|public|private|protected|internal|static|readonly|virtual|override|abstract|sealed|async|await|try|catch|finally|throw|int|long|float|double|decimal|bool|char|string|var|void|object|dynamic)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_]\w*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[+\-*/%<>=!&|^~?:]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "Markdown"   = @(
    @{ CompiledRegex = [regex]::new('^#{1,6}.*$', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\[.*?\]\(.*?\)', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('`{1,3}[^`]*`{1,3}', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('^[*-+]\s.*$', 'Compiled'); TokenType = 'punctuation' }
  )
  "Dockerfile" = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|SHELL)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\$\{?\w+\}?', 'Compiled'); TokenType = 'variable' }
    @{ CompiledRegex = [regex]::new('\b\d+\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[=]', 'Compiled'); TokenType = 'operator' }
  )
}

function Get-TokensForLine([string]$line, [string]$language) {
  if (-not $script:languageSyntaxRules.ContainsKey($language)) { return @() }
  $rules = $script:languageSyntaxRules[$language]
  $tokenList = [System.Collections.Generic.List[object]]::new()
  $pos = 0
  while ($pos -lt $line.Length) {
    $best = $null
    foreach ($rule in $rules) {
      $m = $rule.CompiledRegex.Match($line, $pos)
      if ($m.Success -and $m.Index -eq $pos -and ($null -eq $best -or $m.Length -gt $best.Length)) {
        $best = @{ Start = $pos; Length = $m.Length; Type = $rule.TokenType }
      }
    }
    if ($best) { $tokenList.Add([PSCustomObject]$best); $pos += $best.Length }
    else { $pos++ }
  }
  return $tokenList
}

function Build-EditorRowContent([int]$rowIndex, [int]$screenWidth, [int]$textWidth) {
  $cursorRow, $cursorCol = Convert-OffsetToRowCol $editorState.CursorOffset
  $selStart = 0; $selEnd = 0
  if ($editorState.IsSelectionActive) { $selStart, $selEnd = Get-SelectionBoundaries }

  if ($rowIndex -eq 0) {
    $themeName = $script:themeDefinitions[$script:availableThemeNames[$script:currentThemeIndex]].displayName
    $fileName = if ($editorState.FilePath) { [IO.Path]::GetFileName($editorState.FilePath) } else { 'new file' }
    $dirty = if ($editorState.IsDirty) { "$(Get-ThemeColor 'foregroundDirty')●$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader') " } else { '  ' }
    $plain = " babae | $fileName [$($editorState.Language)] | $themeName "
    $pad = [Math]::Max(0, $screenWidth - $plain.Length)
    return "$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')${BOLD_SEQUENCE} babae $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundMuted')| $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$dirty$fileName [$($editorState.Language)] $(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundMuted')| $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$themeName$(' ' * $pad)$script:RESET_SEQUENCE"
  }

  if ($rowIndex -eq ([Console]::WindowHeight - 1)) {
    $msg = $editorState.StatusMessage
    $pos = " $($cursorRow + 1):$($cursorCol + 1) "
    $ecHint = if ($script:editorConfigSettings.indent_style -eq 'tab') { 'tab' } else { "$($script:editorConfigSettings.indent_size)sp" }
    $eol = $script:editorConfigSettings.end_of_line.ToUpperInvariant()
    if ($editorState.EditorMode -eq 'search') {
      $plain = " Search: $($editorState.SearchBuffer)_ (Enter=jump Esc=cancel) "
      $pad = [Math]::Max(0, $screenWidth - $plain.Length)
      return "$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundAccent')${BOLD_SEQUENCE} Search:$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundNormal') $($editorState.SearchBuffer)_ $(Get-ThemeColor 'foregroundMuted')(Enter=jump Esc=cancel)$(' ' * $pad)$script:RESET_SEQUENCE"
    }
    if ($editorState.EditorMode -eq 'save-as') {
      $plain = " Save as: $($editorState.SaveAsBuffer) (Enter=save Esc=cancel) "
      $pad = [Math]::Max(0, $screenWidth - $plain.Length)
      return "$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundAccent')${BOLD_SEQUENCE} Save as:$RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundNormal') $($editorState.SaveAsBuffer) $(Get-ThemeColor 'foregroundMuted')(Enter=save Esc=cancel)$(' ' * $pad)$RESET_SEQUENCE"
    }
    $displayOrder = @('^F1', '^T', '^S', '^Q', '^F', '^Z')
    $barCmds = foreach ($k in $displayOrder) { $script:commandBindingDefinitions | Where-Object { $_.Key -eq $k } }
    $leftPlain = ' ' + (($barCmds | ForEach-Object { "$($_.Key) $($_.Label)" }) -join ' ') + ' '
    $rightPlain = " $eol | $ecHint |$pos"
    if ($msg) { $rightPlain = " $msg |" + $rightPlain }
    if ($editorState.IsSelectionActive) { $rightPlain = " SEL |" + $rightPlain }
    $pad = [Math]::Max(0, $screenWidth - $leftPlain.Length - $rightPlain.Length)
    $right = ''
    if ($msg) { $right += "$(Get-ThemeColor 'foregroundSaved') $msg $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundMuted')│" }
    if ($editorState.IsSelectionActive) { $right += "$(Get-ThemeColor 'foregroundAccent') SEL $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundMuted')│" }
    $right += "$(Get-ThemeColor 'foregroundMuted') $eol $(Get-ThemeColor 'foregroundMuted')│ $(Get-ThemeColor 'foregroundMuted')$ecHint $(Get-ThemeColor 'foregroundMuted')│$(Get-ThemeColor 'foregroundAccent')$pos$script:RESET_SEQUENCE"
    $barLeft = "$(Get-ThemeColor 'backgroundStatusBar')"
    foreach ($cmd in $barCmds) {
      $barLeft += "$(Get-ThemeColor 'foregroundAccent')${BOLD_SEQUENCE}$($cmd.Key)$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundMuted') $($cmd.Label) "
    }
    return "$barLeft$(' ' * $pad)$right"
  }

  $lineIndex = $rowIndex - 1 + $editorState.VerticalScrollRow
  $lineText = Get-LineByNumber $lineIndex
  if ($null -eq $lineText) {
    return "$(Get-ThemeColor 'backgroundGutter')$(Get-ThemeColor 'foregroundTilde')   ~ $script:RESET_SEQUENCE$(Get-ThemeColor 'background')$(' ' * $textWidth)$script:RESET_SEQUENCE"
  }

  $isCurrent = ($lineIndex -eq $cursorRow)
  $lineNum = ($lineIndex + 1).ToString().PadLeft(4)
  $gutter = if ($isCurrent) {
    "$(Get-ThemeColor 'backgroundGutter')$(Get-ThemeColor 'foregroundCurrentLineNumber')${BOLD_SEQUENCE}$lineNum$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundGutter') $script:RESET_SEQUENCE"
  } else {
    "$(Get-ThemeColor 'backgroundGutter')$(Get-ThemeColor 'foregroundLineNumber')$lineNum$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundGutter') $script:RESET_SEQUENCE"
  }

  $hScroll = $editorState.HorizontalScrollOffset
  $fullLine = $lineText
  $visibleStart = $hScroll
  $visibleLen = [Math]::Min($textWidth, $fullLine.Length - $visibleStart)
  if ($visibleLen -lt 0) { $visibleLen = 0 }
  $slice = if ($fullLine.Length -gt $visibleStart) { $fullLine.Substring($visibleStart, $visibleLen) } else { '' }
  $slice = $slice -replace [char]0x1B, '?'

  $cacheKey = "$lineIndex`:$fullLine"
  if (-not $editorState.SyntaxTokenCache.ContainsKey($cacheKey)) {
    $editorState.SyntaxTokenCache[$cacheKey] = Get-TokensForLine $fullLine $editorState.Language
  }
  $tokens = $editorState.SyntaxTokenCache[$cacheKey]

  $bg = if ($isCurrent) { Get-ThemeColor 'backgroundLine' } else { Get-ThemeColor 'background' }
  $lineOff = Convert-RowColToOffset $lineIndex 0
  $rulerCol = if ($script:editorConfigSettings.max_line_length -gt 0) { $script:editorConfigSettings.max_line_length } else { -1 }

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append($gutter)
  [void]$sb.Append($bg)
  $lineHasBreak = ($lineOff + $fullLine.Length -lt $editorState.TextBuffer.Length -and $editorState.TextBuffer[$lineOff + $fullLine.Length] -eq "`n")
  for ($ci = 0; $ci -lt $textWidth; $ci++) {
    $lineCharOffset = $ci + $visibleStart
    $hasTextCharacter = $lineCharOffset -lt $fullLine.Length
    $absOff = $lineOff + $lineCharOffset
    $ch = if ($ci -lt $slice.Length) { [string]$slice[$ci] } else { ' ' }
    $isLineBreakCell = -not $hasTextCharacter -and $lineCharOffset -eq $fullLine.Length -and $lineHasBreak
    $selectionOffset = if ($isLineBreakCell) { $lineOff + $fullLine.Length } else { $absOff }
    $inSel = ($hasTextCharacter -or $isLineBreakCell) -and $editorState.IsSelectionActive -and $selectionOffset -ge $selStart -and $selectionOffset -lt $selEnd
    $rulerHere = ($rulerCol -ge 0 -and ($ci + $visibleStart) -eq $rulerCol)

    $tokenType = $null
    foreach ($tok in $tokens) {
      if ($tok.Start -le $absOff - $lineOff -and ($tok.Start + $tok.Length) -gt $absOff - $lineOff) {
        $tokenType = $tok.Type; break
      }
    }
    $fgKey = 'foregroundNormal'
    if ($tokenType) { $fgKey = "foreground$tokenType" }

    if ($inSel) {
      [void]$sb.Append("$(Get-ThemeColor 'backgroundSelection')$(Get-ThemeColor $fgKey)$ch$bg")
    } elseif ($rulerHere) {
      [void]$sb.Append("$(Get-ThemeColor 'foregroundRuler')│$(Get-ThemeColor $fgKey)$ch")
    } else {
      [void]$sb.Append("$(Get-ThemeColor $fgKey)$ch")
    }
  }
  [void]$sb.Append($script:RESET_SEQUENCE)
  return $sb.ToString()
}

# --- FIX #2: cursor hide/show now brackets every single frame (DECTCEM)
#     instead of relying on a one-shot cache flag that never reset.
function Render-EditorFrame {
  $width = [Console]::WindowWidth
  $height = [Console]::WindowHeight
  $textWidth = $width - 5

  if ($script:cachedRenderRows.Count -ne $height) {
    Clear-RenderCache
    for ($i = 0; $i -lt $height; $i++) { $script:cachedRenderRows.Add('') }
    Write-OutputBuffer("`e[2J`e[3J")
  }

  $dirty = [System.Text.StringBuilder]::new()
  [void]$dirty.Append("`e[?25l")

  $anyRowChanged = $false
  for ($row = 0; $row -lt $height; $row++) {
    $rendered = Build-EditorRowContent $row $width $textWidth
    if ($script:cachedRenderRows[$row] -ne $rendered) {
      $script:cachedRenderRows[$row] = $rendered
      [void]$dirty.Append((Move-CursorToScreenCoordinate ($row + 1) 1))
      [void]$dirty.Append($rendered)
      $anyRowChanged = $true
    }
  }

  $cr, $cc = Convert-OffsetToRowCol $editorState.CursorOffset
  $maxTextRow = [Console]::WindowHeight - 1
  $screenRow = [Math]::Min($maxTextRow, [Math]::Max(2, $cr - $editorState.VerticalScrollRow + 2))
  $screenCol = [Math]::Max(6, $cc - $editorState.HorizontalScrollOffset + 6)

  if ($anyRowChanged -or $screenRow -ne $script:cachedCursorRow -or $screenCol -ne $script:cachedCursorColumn) {
    [void]$dirty.Append((Move-CursorToScreenCoordinate $screenRow $screenCol))
    $script:cachedCursorRow = $screenRow
    $script:cachedCursorColumn = $screenCol
  }

  [void]$dirty.Append("`e[?25h")
  Write-OutputBuffer($dirty.ToString())
  $editorState.StatusMessage = ''
}

function Show-HelpDialog {
  $width = [Console]::WindowWidth
  $height = [Console]::WindowHeight
  $themeName = $script:themeDefinitions[$script:availableThemeNames[$script:currentThemeIndex]].displayName
  $cmdLines = $script:commandBindingDefinitions | ForEach-Object {
    $pad = ' ' * ([Math]::Max(1, 10 - $_.Key.Length))
    "  $($_.Key)$pad$($_.Label)"
  }
  $lines = @(
    '', '  babae  —  keybindings', '  ────────────────────────────────────',
    "  Theme now: $themeName", ''
  ) + $cmdLines + @(
    '', '  Shift+Arrows  Extend selection',
    '  RightClick    Paste from clipboard',
    '  Esc           Cancel search / clear selection',
    '  Tab           Indent / autocomplete',
    '', '  Press any key to close...', ''
  )
  $boxW = 52
  $boxH = $lines.Count + 2
  $top = [int](($height - $boxH) / 2)
  $left = [int](($width - $boxW) / 2)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("`e[?25l")
  for ($i = 0; $i -lt $boxH; $i++) {
    [void]$sb.Append((Move-CursorToScreenCoordinate ($top + $i) $left))
    if ($i -eq 0 -or $i -eq ($boxH - 1)) {
      [void]$sb.Append("$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$(' ' * $boxW)$script:RESET_SEQUENCE")
      continue
    }
    $text = $lines[$i - 1]
    $pad = [Math]::Max(0, $boxW - $text.Length)
    [void]$sb.Append("$(Get-ThemeColor 'backgroundLine')$(Get-ThemeColor 'foregroundNormal')$text$(' ' * $pad)$script:RESET_SEQUENCE")
  }
  $cr, $cc = Convert-OffsetToRowCol $editorState.CursorOffset
  [void]$sb.Append((Move-CursorToScreenCoordinate ($cr - $editorState.VerticalScrollRow + 2) ($cc - $editorState.HorizontalScrollOffset + 6)))
  [void]$sb.Append("`e[?25h")
  Write-OutputBuffer($sb.ToString())
  Read-InputEvent | Out-Null
  Clear-RenderCache
}

function Search-ForTerm([string]$term) {
  if ([string]::IsNullOrWhiteSpace($term)) { return }
  $editorState.LastSearchTerm = $term
  $editorState.IsSelectionActive = $false
  $t = Get-BufferText
  $ix = $t.IndexOf($term, [Math]::Min($editorState.CursorOffset + 1, $t.Length), [StringComparison]::OrdinalIgnoreCase)
  if ($ix -lt 0) { $ix = $t.IndexOf($term, 0, [StringComparison]::OrdinalIgnoreCase) }
  if ($ix -lt 0) { $editorState.StatusMessage = ' Not found '; return }
  $editorState.IsSelectionActive = $true
  $editorState.SelectionAnchor = $ix
  $editorState.CursorOffset = $ix + $term.Length
  $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
  $editorState.StatusMessage = ' Found '
}

# --- FIX #4: Enter no longer carries indentation from the current line.
function Handle-EditingKey([ConsoleKeyInfo]$ki) {
  $key = $ki.Key
  $ctrl = ($ki.Modifiers -band [ConsoleModifiers]::Control) -ne 0
  $shift = ($ki.Modifiers -band [ConsoleModifiers]::Shift) -ne 0
  $ch = $ki.KeyChar

  if ($ctrl) {
    switch ($key) {
      'T' { $script:currentThemeIndex = ($script:currentThemeIndex + 1) % $script:availableThemeNames.Count; $editorState.StatusMessage = " Theme: $($script:themeDefinitions[$script:availableThemeNames[$script:currentThemeIndex]].displayName) "; Clear-RenderCache; return }
      'S' {
        if ([string]::IsNullOrWhiteSpace($editorState.FilePath)) {
          $editorState.EditorMode = 'save-as'; $editorState.SaveAsBuffer = ''
        } else { Save-EditorFile }
        return
      }
      'Q' { $editorState.EditorMode = 'confirm-quit'; return }
      'Z' { Undo-LastChange; return }
      'Y' { Redo-LastChange; return }
      'F' { $editorState.EditorMode = 'search'; $editorState.SearchBuffer = ''; return }
      'A' { $editorState.IsSelectionActive = $true; $editorState.SelectionAnchor = 0; $editorState.CursorOffset = $editorState.TextBuffer.Length; $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; return }
      'C' { $selected = Get-SelectedText; if ([string]::IsNullOrEmpty($selected)) { $selected = Get-LineByNumber (Convert-OffsetToRowCol $editorState.CursorOffset)[0] }; Set-ClipboardContent $selected; $editorState.StatusMessage = ' Copied to clipboard '; return }
      'V' { Paste-TextFromClipboard (Get-ClipboardContent); return }
      'F1' { Show-HelpDialog; return }
    }
    return
  }

  switch ($key) {
    'LeftArrow' {
      if ($editorState.IsSelectionActive -and -not $shift) { $editorState.CursorOffset = (Get-SelectionBoundaries)[0] }
      elseif ($editorState.CursorOffset -gt 0) {
        if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
        $editorState.CursorOffset--
      }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; $editorState.AutocompleteMatches = $null
      return
    }
    'RightArrow' {
      if ($editorState.IsSelectionActive -and -not $shift) { $editorState.CursorOffset = (Get-SelectionBoundaries)[1] }
      elseif ($editorState.CursorOffset -lt $editorState.TextBuffer.Length) {
        if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
        $editorState.CursorOffset++
      }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; $editorState.AutocompleteMatches = $null
      return
    }
    'UpArrow' {
      if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $row = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]
      if ($row -gt 0) { $editorState.CursorOffset = Convert-RowColToOffset ($row - 1) $editorState.PreferredColumn }
      $editorState.AutocompleteMatches = $null
      return
    }
    'DownArrow' {
      if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $row = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]
      $editorState.CursorOffset = Convert-RowColToOffset ($row + 1) $editorState.PreferredColumn
      $editorState.AutocompleteMatches = $null
      return
    }
    'Home' {
      if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $editorState.CursorOffset = Get-LineStartOffset $editorState.CursorOffset; $editorState.PreferredColumn = 0; $editorState.AutocompleteMatches = $null
      return
    }
    'End' {
      if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $editorState.CursorOffset = Get-LineEndOffset $editorState.CursorOffset
      $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; $editorState.AutocompleteMatches = $null
      return
    }
    'PageUp' { $editorState.IsSelectionActive = $false; $editorState.AutocompleteMatches = $null; $page = [Console]::WindowHeight - 2; $row = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]; $editorState.CursorOffset = Convert-RowColToOffset ([Math]::Max(0, $row - $page)) $editorState.PreferredColumn; return }
    'PageDown' { $editorState.IsSelectionActive = $false; $editorState.AutocompleteMatches = $null; $page = [Console]::WindowHeight - 2; $row = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]; $editorState.CursorOffset = Convert-RowColToOffset ($row + $page) $editorState.PreferredColumn; return }
    'Enter' {
      Push-UndoSnapshot
      if ($editorState.IsSelectionActive) { Remove-SelectedText }
      $t = Get-BufferText
      Set-BufferContent ($t.Substring(0, $editorState.CursorOffset) + "`n" + $t.Substring($editorState.CursorOffset))
      $editorState.CursorOffset++
      $editorState.PreferredColumn = 0; $editorState.IsDirty = $true; $editorState.AutocompleteMatches = $null; return
    }
    'Backspace' {
      if ($editorState.IsSelectionActive) { Push-UndoSnapshot; Remove-SelectedText; $editorState.AutocompleteMatches = $null; return }
      if ($editorState.CursorOffset -gt 0) {
        Push-UndoSnapshot
        $t = Get-BufferText
        Set-BufferContent ($t.Substring(0, $editorState.CursorOffset - 1) + $t.Substring($editorState.CursorOffset))
        $editorState.CursorOffset--
        $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; $editorState.IsDirty = $true
      }
      $editorState.AutocompleteMatches = $null; return
    }
    'Delete' {
      if ($editorState.IsSelectionActive) { Push-UndoSnapshot; Remove-SelectedText; $editorState.AutocompleteMatches = $null; return }
      if ($editorState.CursorOffset -lt $editorState.TextBuffer.Length) {
        Push-UndoSnapshot
        $t = Get-BufferText
        Set-BufferContent ($t.Substring(0, $editorState.CursorOffset) + $t.Substring($editorState.CursorOffset + 1))
        $editorState.IsDirty = $true
      }
      $editorState.AutocompleteMatches = $null; return
    }
    'Tab' {
      $prefix = Get-WordPrefixAtCursor
      if ($prefix -ne '' -and ($null -eq $editorState.AutocompleteMatches)) {
        $words = Get-AllWordsInBuffer
        $matchedWords = @($words | Where-Object { $_ -like "$prefix*" } | Sort-Object -Unique)
        if ($matchedWords.Count -eq 1) {
          Push-UndoSnapshot
          Insert-TextAtCursor ([string]$matchedWords[0]).Substring($prefix.Length)
          $editorState.AutocompleteMatches = $null
        } elseif ($matchedWords.Count -gt 1) {
          $editorState.AutocompleteMatches = $matchedWords
          $editorState.AutocompleteIndex = 0
          $editorState.AutocompleteBaseOffset = $editorState.CursorOffset - $prefix.Length
          Push-UndoSnapshot
          Replace-CurrentWord [string]$matchedWords[0]
        } else { Push-UndoSnapshot; Insert-TextAtCursor (Get-IndentationString) }
      } elseif ($null -ne $editorState.AutocompleteMatches) {
        $editorState.AutocompleteIndex = ($editorState.AutocompleteIndex + 1) % $editorState.AutocompleteMatches.Count
        $t = Get-BufferText
        $before = $t.Substring(0, $editorState.AutocompleteBaseOffset)
        $after = $t.Substring($editorState.CursorOffset)
        $newWord = $editorState.AutocompleteMatches[$editorState.AutocompleteIndex]
        Set-BufferContent ($before + $newWord + $after)
        $editorState.CursorOffset = $editorState.AutocompleteBaseOffset + $newWord.Length
        $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
        $editorState.IsDirty = $true
        Clear-RenderCache
      } else { Push-UndoSnapshot; Insert-TextAtCursor (Get-IndentationString) }
      return
    }
    'Escape' { $editorState.EditorMode = 'edit'; $editorState.SearchBuffer = ''; $editorState.IsSelectionActive = $false; $editorState.AutocompleteMatches = $null; return }
  }

  if ([int]$ch -ge 32 -and [int]$ch -ne 127) {
    Push-UndoSnapshot
    if ($editorState.IsSelectionActive) { Remove-SelectedText }
    $t = Get-BufferText
    Set-BufferContent ($t.Substring(0, $editorState.CursorOffset) + $ch + $t.Substring($editorState.CursorOffset))
    $editorState.CursorOffset++
    $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
    $editorState.IsDirty = $true
    $editorState.AutocompleteMatches = $null
  }
}

function Get-WordPrefixAtCursor {
  $t = Get-BufferText
  $end = $editorState.CursorOffset
  $start = $end
  while ($start -gt 0 -and $t[$start - 1] -match '[\w]') { $start-- }
  return $t.Substring($start, $end - $start)
}

function Get-AllWordsInBuffer {
  $t = Get-BufferText
  return $t -split '\W+' | Where-Object { $_.Length -gt 1 } | Sort-Object -Unique
}

function Insert-TextAtCursor([string]$s) {
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $editorState.CursorOffset) + $s + $t.Substring($editorState.CursorOffset))
  $editorState.CursorOffset += $s.Length
  $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
  $editorState.IsDirty = $true
  Clear-RenderCache
}

function Replace-CurrentWord([string]$newWord) {
  $t = Get-BufferText
  $prefix = Get-WordPrefixAtCursor
  $start = $editorState.CursorOffset - $prefix.Length
  $before = $t.Substring(0, $start)
  $after = $t.Substring($editorState.CursorOffset)
  Set-BufferContent ($before + $newWord + $after)
  $editorState.CursorOffset = $start + $newWord.Length
  $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
  $editorState.IsDirty = $true
  Clear-RenderCache
}

function Handle-SearchKey([ConsoleKeyInfo]$ki) {
  switch ($ki.Key) {
    'Escape' { $editorState.EditorMode = 'edit'; $editorState.SearchBuffer = ''; return }
    'Enter' { $editorState.EditorMode = 'edit'; Search-ForTerm $editorState.SearchBuffer; return }
    'Backspace' { if ($editorState.SearchBuffer.Length -gt 0) { $editorState.SearchBuffer = $editorState.SearchBuffer.Substring(0, $editorState.SearchBuffer.Length - 1) }; return }
    default { if ($ki.KeyChar -ne [char]0 -and -not [char]::IsControl($ki.KeyChar)) { $editorState.SearchBuffer += [string]$ki.KeyChar } }
  }
}

function Handle-SaveAsKey([ConsoleKeyInfo]$ki) {
  switch ($ki.Key) {
    'Escape' { $editorState.EditorMode = 'edit'; $editorState.SaveAsBuffer = ''; return }
    'Enter' {
      if ([string]::IsNullOrWhiteSpace($editorState.SaveAsBuffer)) { return }
      $editorState.FilePath = Join-Path $PWD $editorState.SaveAsBuffer
      $editorState.Language = Get-LanguageFromPath $editorState.FilePath
      Load-EditorConfig $editorState.FilePath
      Save-EditorFile
      $editorState.EditorMode = 'edit'; $editorState.SaveAsBuffer = ''
      return
    }
    'Backspace' { if ($editorState.SaveAsBuffer.Length -gt 0) { $editorState.SaveAsBuffer = $editorState.SaveAsBuffer.Substring(0, $editorState.SaveAsBuffer.Length - 1) }; return }
    default { if ($ki.KeyChar -ne [char]0 -and -not [char]::IsControl($ki.KeyChar)) { $editorState.SaveAsBuffer += [string]$ki.KeyChar } }
  }
}

function Show-ConfirmQuitDialog {
  $width = [Console]::WindowWidth
  $height = [Console]::WindowHeight
  $msg = '  Unsaved changes — quit anyway?  [y / N]  '
  $boxW = $msg.Length + 2
  $top = [int](($height - 3) / 2)
  $left = [int](($width - $boxW) / 2)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("`e[?25l")
  [void]$sb.Append((Move-CursorToScreenCoordinate $top $left))
  [void]$sb.Append("$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$(' ' * $boxW)$script:RESET_SEQUENCE")
  [void]$sb.Append((Move-CursorToScreenCoordinate ($top + 1) $left))
  [void]$sb.Append("$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$msg$(' ' * ($boxW - $msg.Length))$script:RESET_SEQUENCE")
  [void]$sb.Append((Move-CursorToScreenCoordinate ($top + 2) $left))
  [void]$sb.Append("$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$(' ' * $boxW)$script:RESET_SEQUENCE")
  Write-OutputBuffer($sb.ToString())
  while ($true) {
    $ev = Read-InputEvent
    if ($ev.Kind -ne 'Key') { continue }
    if ($ev.KeyInfo.Key -eq 'Y') { $script:shouldExitApplication = $true; return }
    if ($ev.KeyInfo.Key -in 'N', 'Escape', 'Enter') { $editorState.EditorMode = 'edit'; $editorState.StatusMessage = ' Quit cancelled '; Clear-RenderCache; return }
  }
}

$script:isWindowsPlatform = $IsWindows -or $env:OS -eq 'Windows_NT'

function Enter-RawInputMode {
  $script:isUnixPlatform = $IsLinux -or $IsMacOS
  $script:originalSttySettings = $null
  $script:originalConsoleMode = $null

  if ($script:isUnixPlatform -and -not [Console]::IsInputRedirected) {
    $script:originalSttySettings = stty -g 2>/dev/null
    stty raw -echo 2>/dev/null
    return
  }
  if (-not $script:isWindowsPlatform) { return }

  Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public static class ConsoleRaw {
        [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
        [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint mode);
        public const int STD_INPUT_HANDLE = -10;
        public const uint ENABLE_ECHO_INPUT = 0x0004;
        public const uint ENABLE_LINE_INPUT = 0x0002;
        public const uint ENABLE_PROCESSED_INPUT = 0x0001;
        public const uint ENABLE_EXTENDED_FLAGS = 0x0080;
        public const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
        public const uint ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
    }
'@ -ErrorAction SilentlyContinue

  $handle = [ConsoleRaw]::GetStdHandle([ConsoleRaw]::STD_INPUT_HANDLE)
  [uint]$mode = 0
  [void][ConsoleRaw]::GetConsoleMode($handle, [ref]$mode)
  $script:originalConsoleMode = $mode
  $newMode = ($mode -band (-bnot ([ConsoleRaw]::ENABLE_ECHO_INPUT -bor [ConsoleRaw]::ENABLE_LINE_INPUT -bor [ConsoleRaw]::ENABLE_PROCESSED_INPUT -bor [ConsoleRaw]::ENABLE_QUICK_EDIT_MODE))) `
    -bor [ConsoleRaw]::ENABLE_EXTENDED_FLAGS -bor [ConsoleRaw]::ENABLE_VIRTUAL_TERMINAL_INPUT
  [void][ConsoleRaw]::SetConsoleMode($handle, $newMode)
}

function Exit-RawInputMode {
  if ($null -ne $script:originalConsoleMode) {
    try {
      $handle = [ConsoleRaw]::GetStdHandle([ConsoleRaw]::STD_INPUT_HANDLE)
      [ConsoleRaw]::SetConsoleMode($handle, $script:originalConsoleMode)
    } catch {}
  }
  if ($script:originalSttySettings -and -not [Console]::IsInputRedirected) {
    try { stty $script:originalSttySettings 2>/dev/null } catch {}
  }
}

function Start-BabaeEditor {
  [CmdletBinding()]
  param([Parameter(Position = 0)][string]$Path)

  if ([Console]::IsOutputRedirected) { Write-Error "babae cannot run with redirected output."; return }

  Reset-EditorState
  Clear-RenderCache

  if ($Path) {
    $resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
    $editorState.FilePath = if ($resolved) { $resolved.Path } else { Join-Path $PWD $Path }
    Load-FileIntoEditor $editorState.FilePath
    Load-EditorConfig $editorState.FilePath
  } else {
    Set-BufferContent ''
    Load-EditorConfig ''
  }

  $prevW = 0; $prevH = 0
  $script:shouldExitApplication = $false

  try {
    [Console]::TreatControlCAsInput = $true
    Enter-RawInputMode
    Write-OutputBuffer("`e[?1049h`e[?2004h`e[?25l`e[2J`e[3J`e[H")
    Write-OutputBuffer($script:SEQ_MOUSE_TRACKING_OFF)
    Write-OutputBuffer($script:SEQ_AUTOWRAP_OFF)

    while (-not $script:shouldExitApplication) {
      $w = [Console]::WindowWidth; $h = [Console]::WindowHeight
      if ($w -ne $prevW -or $h -ne $prevH) {
        $prevW = $w; $prevH = $h; Clear-RenderCache
        Set-ScrollMargins 2 ($h - 1)
      }

      Update-ScrollPosition

      if ($editorState.EditorMode -eq 'confirm-quit') {
        if ($editorState.IsDirty) { Show-ConfirmQuitDialog } else { $script:shouldExitApplication = $true }
        continue
      }

      Render-EditorFrame

      $ev = Read-InputEvent
      if ($ev.Kind -eq 'Paste') { Paste-TextFromClipboard $ev.Text }
      else {
        switch ($editorState.EditorMode) {
          'edit' { Handle-EditingKey $ev.KeyInfo }
          'search' { Handle-SearchKey $ev.KeyInfo }
          'save-as' { Handle-SaveAsKey $ev.KeyInfo }
        }
      }
      Clamp-CursorOffset
    }
  } finally {
    Exit-RawInputMode
    [Console]::TreatControlCAsInput = $true
    Reset-ScrollMargins
    Write-OutputBuffer($script:SEQ_MOUSE_TRACKING_OFF)
    Write-OutputBuffer("`e[?2004l`e[?1049l`e[?25h`e[0m")
    Write-OutputBuffer($script:SEQ_AUTOWRAP_ON)
    Write-Host 'babae: session ended.' -ForegroundColor Cyan
    if ($editorState.FilePath) { Write-Host "File : $($editorState.FilePath)" -ForegroundColor DarkGray }
  }
}

Set-Alias -Name babae -Value Start-BabaeEditor -Scope Global
Start-BabaeEditor @PSBoundParameters
