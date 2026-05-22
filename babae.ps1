<#
.SYNOPSIS
    babae - The Zero-Lag, SSH-Safe, TUI Editor
.DESCRIPTION
    Pure PowerShell TUI editor. No dependencies, no NuGet, no DLLs.
    ANSI rendering, dark themes, cross-platform clipboard, .editorconfig support.
.NOTES
    PS installation: https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu?view=powershell-7.6
    babae installation: curl https://raw.githubusercontent.com/BabaDeluxe/babadeluxe-scripts/refs/heads/master/babae.ps1 > babae.ps1
.PARAMETER Path
    Optional file to open on launch.
.PARAMETER Theme
    Starting theme: dark (default) | mocha | frappe | github-dark
.PARAMETER DiagPane
    Show the in-TUI diagnose pane (Ctrl+D toggles at runtime).
.PARAMETER DebugLog
    Write a debug log file (babae-debug.log) in the current directory.
.EXAMPLE
    pwsh ./babae.ps1
    pwsh ./babae.ps1 myfile.txt -Theme mocha
    pwsh ./babae.ps1 myfile.txt -DiagPane
#>
param(
  [Parameter(Position = 0)][string]$Path,
  [ValidateSet("dark", "mocha", "frappe", "github-dark")]
  [string]$Theme = "dark",
  [switch]$DiagPane,
  [switch]$DebugLog
)

# ---------------------------------------------------------------------------
# Global Installation / Update
# ---------------------------------------------------------------------------
if (-not [Console]::IsInputRedirected -and -not $Env:BABAE_SKIP_INSTALL) {
  $installDir = Join-Path $HOME ".babae"
  $installPath = Join-Path $installDir "babae.ps1"
  $currentPath = $PSCommandPath

  if ($currentPath -and (Test-Path $currentPath) -and (Resolve-Path $currentPath).Path -ne $installPath) {
    $shouldUpdate = $false
    $msg = ""
    if (-not (Test-Path $installPath)) {
      $shouldUpdate = $true
      $msg = " babae is not installed globally. Install to $installPath and add to profile? (y/n): "
    } else {
      try {
        $currentHash = (Get-FileHash $currentPath -Algorithm SHA256).Hash
        $installHash = (Get-FileHash $installPath -Algorithm SHA256).Hash
        if ($currentHash -ne $installHash) {
          $shouldUpdate = $true
          $msg = " A different version of babae is installed globally. Update it? (y/n): "
        }
      } catch {}
    }

    if ($shouldUpdate) {
      Write-Host "`n$msg" -NoNewline -ForegroundColor Cyan
      $choice = Read-Host
      if ($choice -eq 'y') {
        if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }
        Copy-Item -Path $currentPath -Destination $installPath -Force

        # Update Profile
        $profileDir = Split-Path $PROFILE
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }

        $funcName = "babae"
        $funcDef = "`nfunction $funcName { pwsh -NoProfile -File `"$installPath`" @args }`n"
        $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($null -eq $profileContent -or $profileContent -notlike "*function $funcName {*") {
          Add-Content -Path $PROFILE -Value $funcDef
          Write-Host " Added 'babae' function to $PROFILE" -ForegroundColor Green
        } else {
          Write-Host " Global 'babae' command updated." -ForegroundColor Green
        }
        Write-Host " babae installed/updated successfully at $installPath" -ForegroundColor Green
        Start-Sleep -Seconds 1
      }
    }
  }
}
$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$script:frameDelayMs = 33

# ---------------------------------------------------------------------------
# Diagnose / Debug infrastructure
# ---------------------------------------------------------------------------
# Ring-buffer for the in-TUI diag pane. Max 120 entries; oldest dropped.
$script:diagRing        = [System.Collections.Generic.Queue[string]]::new()
$script:diagRingMax     = 120
$script:diagPaneVisible = $DiagPane.IsPresent
$script:diagPaneHeight  = 6   # rows reserved for the pane (excl. separator bar)

# File log path — $null when -DebugLog not supplied.
$script:debugLogPath = $null
if ($DebugLog.IsPresent) {
  $script:debugLogPath = Join-Path . 'babae-debug.log'
}

# Write-DiagLog: single call site used throughout the script.
# Routes to the ring-buffer (always) and to the file (when -DebugLog).
function Write-DiagLog([string]$message) {
  $ts  = [DateTimeOffset]::UtcNow.ToString('HH:mm:ss.fff')
  $line = "[$ts] $message"
  $script:diagRing.Enqueue($line)
  while ($script:diagRing.Count -gt $script:diagRingMax) { [void]$script:diagRing.Dequeue() }
  if ($null -ne $script:debugLogPath) {
    try { Add-Content -LiteralPath $script:debugLogPath -Value $line -Encoding UTF8 } catch {}
  }
}

# Keep the old name as an alias so nothing breaks if it's called elsewhere.
function Write-DebugLog([string]$message) { Write-DiagLog $message }

# ---------------------------------------------------------------------------
# Themes
# ---------------------------------------------------------------------------
$script:themeNames = @("dark", "mocha", "frappe", "github-dark")
$script:themes = @{
  "dark"        = @{
    bg = "48;2;17;15;26"; bgLine = "48;2;24;21;36"; bgGutter = "48;2;20;18;30"; bgBar = "48;2;30;26;48"; bgSelect = "48;2;80;50;140"; bgHeader = "48;2;80;50;140"
    fgNorm = "38;2;220;215;240"; fgMuted = "38;2;110;100;150"; fgAccent = "38;2;189;147;249"; fgLineNum = "38;2;80;70;110"; fgCurNum = "38;2;189;147;249"; fgHeader = "38;2;255;255;255"
    fgSearch = "38;2;255;184;108"; fgDirty = "38;2;255;121;198"; fgSaved = "38;2;80;250;123"; fgTilde = "38;2;60;50;90"; name = "babae dark"
  }
  "mocha"       = @{
    bg = "48;2;30;30;46"; bgLine = "48;2;40;38;53"; bgGutter = "48;2;24;24;37"; bgBar = "48;2;17;17;27"; bgSelect = "48;2;88;91;112"; bgHeader = "48;2;17;17;27"
    fgNorm = "38;2;205;214;244"; fgMuted = "38;2;88;91;112"; fgAccent = "38;2;203;166;247"; fgLineNum = "38;2;88;91;112"; fgCurNum = "38;2;203;166;247"; fgHeader = "38;2;205;214;244"
    fgSearch = "38;2;249;226;175"; fgDirty = "38;2;243;139;168"; fgSaved = "38;2;166;227;161"; fgTilde = "38;2;49;50;68"; name = "Catppuccin Mocha"
  }
  "frappe"      = @{
    bg = "48;2;48;52;70"; bgLine = "48;2;65;69;89"; bgGutter = "48;2;41;44;60"; bgBar = "48;2;35;38;52"; bgSelect = "48;2;98;104;128"; bgHeader = "48;2;35;38;52"
    fgNorm = "38;2;198;208;245"; fgMuted = "38;2;98;104;128"; fgAccent = "38;2;202;158;230"; fgLineNum = "38;2;98;104;128"; fgCurNum = "38;2;202;158;230"; fgHeader = "38;2;198;208;245"
    fgSearch = "38;2;229;200;144"; fgDirty = "38;2;231;130;132"; fgSaved = "38;2;166;209;137"; fgTilde = "38;2;65;69;89"; name = "Catppuccin Frappe"
  }
  "github-dark" = @{
    bg = "48;2;13;17;23"; bgLine = "48;2;22;27;34"; bgGutter = "48;2;13;17;23"; bgBar = "48;2;22;27;34"; bgSelect = "48;2;33;68;118"; bgHeader = "48;2;22;27;34"
    fgNorm = "38;2;230;237;243"; fgMuted = "38;2;110;118;129"; fgAccent = "38;2;210;153;255"; fgLineNum = "38;2;110;118;129"; fgCurNum = "38;2;210;153;255"; fgHeader = "38;2;230;237;243"
    fgSearch = "38;2;255;212;0"; fgDirty = "38;2;248;81;73"; fgSaved = "38;2;63;185;80"; fgTilde = "38;2;33;38;45"; name = "GitHub Dark"
  }
}
$script:themeIdx = [Math]::Max(0, $script:themeNames.IndexOf($Theme))
function T([string]$key) { "`e[$($script:themes[$script:themeNames[$script:themeIdx]][$key])m" }
$RESET = "`e[0m"
$BOLD = "`e[1m"

# ---------------------------------------------------------------------------
# Low-flicker output: direct stdout stream + row shadow buffer
# ---------------------------------------------------------------------------
$script:stdoutWriter = [System.IO.StreamWriter]::new([Console]::OpenStandardOutput())
# Native PowerShell input queue
$script:inputQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:inputPendingKeys = [System.Collections.Generic.Queue[object]]::new()
$script:inputThread = $null
$script:stdoutWriter.AutoFlush = $false

# ---------------------------------------------------------------------------
# Raw stdin reader
# ---------------------------------------------------------------------------
$script:stdinStream   = [Console]::OpenStandardInput()
$script:inputBuf      = [byte[]]::new(4096)
$script:inputPending  = [System.Collections.Generic.Queue[byte]]::new()

$script:stdinIsConsole = $true
try { [void][Console]::KeyAvailable } catch { $script:stdinIsConsole = $false }

$script:stdinReadTask = $null

function Stdin-EnsureTask {
  if ($null -eq $script:stdinReadTask) {
    $script:stdinReadTask = $script:stdinStream.ReadAsync($script:inputBuf, 0, $script:inputBuf.Length)
  }
}

function Stdin-HarvestTask {
  $n = $script:stdinReadTask.GetAwaiter().GetResult()
  $script:stdinReadTask = $null
  for ($i = 0; $i -lt $n; $i++) { $script:inputPending.Enqueue($script:inputBuf[$i]) }
  return $n
}

function Stdin-TryDrain {
  if ($script:inputPending.Count -gt 0) { return $true }
  if ($script:stdinIsConsole) { try { return [Console]::KeyAvailable } catch { $script:stdinIsConsole = $false } }
  Stdin-EnsureTask
  if (-not $script:stdinReadTask.IsCompleted) { return $false }
  [void](Stdin-HarvestTask)
  return $true
}

function Stdin-DataAvailable {
  if (-not [Console]::IsInputRedirected) { return ($script:inputPendingKeys.Count -gt 0 -or -not $script:inputQueue.IsEmpty) }
  return Stdin-TryDrain
}

function Stdin-ReadByte {
  while ($script:inputPending.Count -eq 0) {
    Stdin-EnsureTask
    $n = Stdin-HarvestTask
    if ($n -le 0) { return -1 }
  }
  return [int]$script:inputPending.Dequeue()
}

function Stdin-PeekAvailable {
  if ($null -ne $script:stdinReadTask -and $script:stdinReadTask.IsCompleted) {
    $n = Stdin-HarvestTask
    if ($n -le 0) { return }
  }
  while ($true) {
    Stdin-EnsureTask
    if (-not $script:stdinReadTask.Wait(1)) { break }
    $n = Stdin-HarvestTask
    if ($n -le 0) { break }
  }
}

function Stdin-DrainPaste {
  $sb     = [System.Text.StringBuilder]::new(4096)
  $escBuf = [System.Text.StringBuilder]::new()
  $inEsc  = $false

  $deadline = [System.Diagnostics.Stopwatch]::StartNew()

  while ($deadline.ElapsedMilliseconds -lt 2000) {
    if ($script:inputPending.Count -eq 0) {
      Stdin-PeekAvailable
      if ($script:inputPending.Count -eq 0) {
        $sleep = [Math]::Min(20, [Math]::Max(2, [int]($deadline.ElapsedMilliseconds / 50)))
        Start-Sleep -Milliseconds $sleep
        continue
      }
    }

    $b  = [int]$script:inputPending.Dequeue()
    if ($b -eq -1) { break }
    $ch = [char]$b

    if (-not $inEsc) {
      if ($b -eq 27) {
        $inEsc = $true
        $escBuf.Clear() | Out-Null
      } else {
        [void]$sb.Append($ch)
      }
    } else {
      [void]$escBuf.Append($ch)
      $esc = $escBuf.ToString()
      if ($esc -eq '[201~') {
        $inEsc = $false; break
      } elseif ('[201~'.StartsWith($esc)) {
        # still matching
      } else {
        [void]$sb.Append([char]27)
        [void]$sb.Append($esc)
        $inEsc = $false
      }
    }
  }
  return $sb.ToString()
}

function Make-KeyInfo([char]$ch, [System.ConsoleKey]$key, [System.ConsoleModifiers]$mods) {
  return [System.ConsoleKeyInfo]::new($ch, $key, `
    ($mods -band [System.ConsoleModifiers]::Shift) -ne 0, `
    ($mods -band [System.ConsoleModifiers]::Alt)   -ne 0, `
    ($mods -band [System.ConsoleModifiers]::Control) -ne 0)
}

function Parse-EscapeSequence([string]$seq) {
  if ($seq.StartsWith('[')) {
    $param = $seq.Substring(1)
    switch ($param) {
      'A'  { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::UpArrow)    0 }
      'B'  { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::DownArrow)  0 }
      'C'  { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::RightArrow) 0 }
      'D'  { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::LeftArrow)  0 }
      'H'  { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::Home)       0 }
      'F'  { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::End)        0 }
      '1~' { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::Home)       0 }
      '4~' { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::End)        0 }
      '5~' { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::PageUp)     0 }
      '6~' { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::PageDown)   0 }
      '2~' { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::Insert)     0 }
      '3~' { return Make-KeyInfo ([char]0)  ([System.ConsoleKey]::Delete)     0 }
      '1;2A' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    ([System.ConsoleModifiers]::Shift) }
      '1;2B' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  ([System.ConsoleModifiers]::Shift) }
      '1;2C' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) ([System.ConsoleModifiers]::Shift) }
      '1;2D' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  ([System.ConsoleModifiers]::Shift) }
      '49;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D1) ([System.ConsoleModifiers]::Control) }
      '50;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D2) ([System.ConsoleModifiers]::Control) }
      '51;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D3) ([System.ConsoleModifiers]::Control) }
      '52;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D4) ([System.ConsoleModifiers]::Control) }
      '53;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D5) ([System.ConsoleModifiers]::Control) }
      '54;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D6) ([System.ConsoleModifiers]::Control) }
      '55;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D7) ([System.ConsoleModifiers]::Control) }
      '56;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D8) ([System.ConsoleModifiers]::Control) }
      '57;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D9) ([System.ConsoleModifiers]::Control) }
      '48;5u'     { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D0) ([System.ConsoleModifiers]::Control) }
      '27;5;49~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D1) ([System.ConsoleModifiers]::Control) }
      '27;5;50~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D2) ([System.ConsoleModifiers]::Control) }
      '27;5;51~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D3) ([System.ConsoleModifiers]::Control) }
      '27;5;52~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D4) ([System.ConsoleModifiers]::Control) }
      '27;5;53~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D5) ([System.ConsoleModifiers]::Control) }
      '27;5;54~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D6) ([System.ConsoleModifiers]::Control) }
      '27;5;55~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D7) ([System.ConsoleModifiers]::Control) }
      '27;5;56~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D8) ([System.ConsoleModifiers]::Control) }
      '27;5;57~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D9) ([System.ConsoleModifiers]::Control) }
      '27;5;48~'  { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::D0) ([System.ConsoleModifiers]::Control) }
    }
  }
  if ($seq.StartsWith('O')) {
    switch ($seq.Substring(1)) {
      'A' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    0 }
      'B' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  0 }
      'C' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) 0 }
      'D' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  0 }
      'H' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::Home)       0 }
      'F' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::End)        0 }
    }
  }
  return Make-KeyInfo ([char]0) ([System.ConsoleKey]::NoName) 0
}

function Start-InputThread {
  if ([Console]::IsInputRedirected) { return }
  $script:inputThread = [PowerShell]::Create().AddScript({
    param($q)
    try {
      while ($true) {
        if ([Console]::KeyAvailable) {
          $ki = [Console]::ReadKey($true)
          $q.Enqueue($ki)
        } else {
          [System.Threading.Thread]::Sleep(10)
        }
      }
    } catch {}
  }).AddArgument($script:inputQueue)
  $script:inputHandle = $script:inputThread.BeginInvoke()
}

function Stop-InputThread {
  if ($null -ne $script:inputThread) {
    try { $script:inputThread.Stop() } catch {}
    try { $script:inputThread.Dispose() } catch {}
    $script:inputThread = $null
  }
}

function Stdin-DrainPasteInteractive {
  $sb = [System.Text.StringBuilder]::new()
  $seq = ""
  while ($true) {
    $ki = $null
    $waited = 0
    while (-not $script:inputQueue.TryDequeue([ref]$ki) -and $waited -lt 500) {
      [System.Threading.Thread]::Sleep(5); $waited += 5
    }
    if ($null -eq $ki) { break }
    $ch = $ki.KeyChar
    if ($ki.Key -eq [System.ConsoleKey]::Escape) {
      $seq = "`e"
      continue
    }
    if ($seq -ne "") {
      $seq += $ch
      if ($seq -eq "`e[201~") { break }
      if ("`e[201~".StartsWith($seq)) { continue }
      [void]$sb.Append($seq); $seq = ""
      continue
    }
    [void]$sb.Append($ch)
  }
  return $sb.ToString()
}

function Stdin-ReadKey {
  if ([Console]::IsInputRedirected) {
    $b = Stdin-ReadByte
    if ($b -eq -1) { return $null }
    return [System.ConsoleKeyInfo]::new([char]$b, 0, $false, $false, $false)
  }
  if ($script:inputPendingKeys.Count -gt 0) { return $script:inputPendingKeys.Dequeue() }
  $ki = $null
  while (-not $script:inputQueue.TryDequeue([ref]$ki)) {
    if (-not $script:running) { return $null }
    [System.Threading.Thread]::Sleep(10)
  }
  if ([int]$ki.KeyChar -eq 8) {
    return Make-KeyInfo ([char]8) ([System.ConsoleKey]::H) ([System.ConsoleModifiers]::Control)
  }
  return $ki
}

function Read-NextInputEvent {
  if (-not [Console]::IsInputRedirected) {
    $ki = Stdin-ReadKey
    if ($null -eq $ki) { return $null }
    if ($ki.Key -eq [System.ConsoleKey]::Escape) {
      $seq = "`e"
      $seqBufKeys = [System.Collections.Generic.List[object]]::new()
      $waited = 0
      while ($seq.Length -lt 6 -and $waited -lt 100) {
        $nki = $null
        if ($script:inputQueue.TryDequeue([ref]$nki)) {
          $seq += $nki.KeyChar
          $seqBufKeys.Add($nki)
          if ($seq -eq "`e[200~") { return [PSCustomObject]@{ Kind = "Paste"; Text = Stdin-DrainPasteInteractive } }
          if (-not "`e[200~".StartsWith($seq)) {
            foreach ($k in $seqBufKeys) { $script:inputPendingKeys.Enqueue($k) }
            break
          }
        } else {
          [System.Threading.Thread]::Sleep(5); $waited += 5
        }
      }
    }
    return [PSCustomObject]@{ Kind = "Key"; KeyInfo = $ki }
  }
  $b = Stdin-ReadByte
  if ($b -eq -1) {
    return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]17) ([System.ConsoleKey]::Q) ([System.ConsoleModifiers]::Control)) }
  }

  if ($b -eq 27) {
    Stdin-PeekAvailable
    if ($script:inputPending.Count -eq 0) {
      $w = 0
      while ($script:inputPending.Count -eq 0 -and $w -lt 50) {
        Start-Sleep -Milliseconds 5; $w += 5
        Stdin-PeekAvailable
      }
    }
    if ($script:inputPending.Count -eq 0) {
      return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
    }

    $seqBuf = [System.Text.StringBuilder]::new()
    $maxSeqLen = 12

    while ($script:inputPending.Count -gt 0 -and $seqBuf.Length -lt $maxSeqLen) {
      $nb = $script:inputPending.Peek()
      $nc = [char]$nb
      if ($nb -eq 27) { break }
      [void]$seqBuf.Append($nc)
      $script:inputPending.Dequeue() | Out-Null

      $seq = $seqBuf.ToString()

      if ($seq -eq '[200~') {
        $payload = Stdin-DrainPaste
        return [PSCustomObject]@{ Kind = 'Paste'; Text = $payload }
      }

      $ki = Parse-EscapeSequence $seq
      if ($ki.Key -ne [System.ConsoleKey]::NoName) {
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = $ki }
      }

      $couldContinue = ($seq.Length -eq 1 -and ($seq -eq '[' -or $seq -eq 'O')) `
                    -or ($seq.Length -gt 1 -and $seq[0] -eq '[' -and ($nc -match '[0-9;]'))
      if (-not $couldContinue) { break }
    }

    $seqStr = $seqBuf.ToString()
    $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($seqStr)
    $tmp = [System.Collections.Generic.Queue[byte]]::new()
    foreach ($rb in $rawBytes) { $tmp.Enqueue($rb) }
    foreach ($rb in $script:inputPending) { $tmp.Enqueue($rb) }
    $script:inputPending = $tmp
    return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
  }

  switch ($b) {
    0   { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]0)  ([System.ConsoleKey]::D2)        ([System.ConsoleModifiers]::Control)) } }
    13  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]13)  ([System.ConsoleKey]::Enter)     0) } }
    127 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }
    8   { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]8) ([System.ConsoleKey]::H) ([System.ConsoleModifiers]::Control)) } }
    9   { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]9)   ([System.ConsoleKey]::Tab)       0) } }
    27  {}
    28  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]28) ([System.ConsoleKey]::D4)        ([System.ConsoleModifiers]::Control)) } }
    29  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]29) ([System.ConsoleKey]::D5)        ([System.ConsoleModifiers]::Control)) } }
    30  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]30) ([System.ConsoleKey]::D6)        ([System.ConsoleModifiers]::Control)) } }
    31  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]31) ([System.ConsoleKey]::D7) ([System.ConsoleModifiers]::Control)) } }
    default {
      if ($b -ge 1 -and $b -le 26) {
        $letter = [char]($b + [int][char]'A' - 1)
        $ck     = [System.ConsoleKey]$letter.ToString()
        return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]$b) $ck ([System.ConsoleModifiers]::Control)) }
      }
    }
  }

  [byte[]]$charBytes = @($b)
  if ($b -ge 0xC0) {
    $extra = if ($b -ge 0xF0) { 3 } elseif ($b -ge 0xE0) { 2 } else { 1 }
    for ($i = 0; $i -lt $extra; $i++) { $charBytes += Stdin-ReadByte }
  }
  $ch = [System.Text.Encoding]::UTF8.GetString($charBytes)[0]

  $ck = try { [System.ConsoleKey]$ch.ToString().ToUpper() } catch { [System.ConsoleKey]::NoName }
  return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo $ch $ck 0) }
}

$script:lastRows = [System.Collections.Generic.List[string]]::new()
$script:lastCursorRow = -1
$script:lastCursorCol = -1
$script:lastCursorVisible = $false

function Out-Flush([string]$text) {
  $script:stdoutWriter.Write($text)
  $script:stdoutWriter.Flush()
}

function Reset-RenderShadow {
  $script:lastRows.Clear()
  $script:lastCursorRow = -1
  $script:lastCursorCol = -1
  $script:lastCursorVisible = $false
}

# ---------------------------------------------------------------------------
# .editorconfig
# ---------------------------------------------------------------------------
$script:ec = @{
  indent_style             = "space"
  indent_size              = 4
  tab_width                = 4
  end_of_line              = "lf"
  trim_trailing_whitespace = $false
  insert_final_newline     = $false
  charset                  = "utf-8"
  max_line_length          = 0
}

# Single source of truth for all keybindings — consumed by status bar + help dialog
$script:commands = @(
  [PSCustomObject]@{ Key = '^T'; Label = 'Theme' }
  [PSCustomObject]@{ Key = '^S'; Label = 'Save' }
  [PSCustomObject]@{ Key = '^Q'; Label = 'Quit' }
  [PSCustomObject]@{ Key = '^F'; Label = 'Find' }
  [PSCustomObject]@{ Key = '^Z'; Label = 'Undo' }
  [PSCustomObject]@{ Key = '^H'; Label = 'Help' }
  [PSCustomObject]@{ Key = '^D'; Label = 'Diag' }
  [PSCustomObject]@{ Key = '^Y'; Label = 'Redo' }
  [PSCustomObject]@{ Key = '^A'; Label = 'Select all' }
  [PSCustomObject]@{ Key = '^C'; Label = 'Copy' }
  [PSCustomObject]@{ Key = '^V'; Label = 'Paste' }
)


function Convert-EditorConfigGlobToRegex([string]$glob) {
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append('^')
  for ($i = 0; $i -lt $glob.Length; $i++) {
    $ch = $glob[$i]
    if ($ch -eq '*') {
      if ($i + 1 -lt $glob.Length -and $glob[$i + 1] -eq '*') {
        [void]$sb.Append('.*')
        $i++
      } else {
        [void]$sb.Append('[^/]*')
      }
      continue
    }
    if ($ch -eq '?') { [void]$sb.Append('[^/]'); continue }
    if ($ch -eq '.') { [void]$sb.Append('\.'); continue }
    if ('+()^$|{}'.Contains([string]$ch)) { [void]$sb.Append('\' + $ch); continue }
    if ($ch -eq '\\') {
      if ($i + 1 -lt $glob.Length) {
        $i++
        [void]$sb.Append([Regex]::Escape([string]$glob[$i]))
      }
      continue
    }
    [void]$sb.Append($ch)
  }
  [void]$sb.Append('$')
  $sb.ToString()
}

function Test-EditorConfigSectionMatch([string]$pattern, [string]$relativePath) {
  $normalized = $relativePath -replace '\\', '/'
  $rx = Convert-EditorConfigGlobToRegex $pattern
  if ($pattern.Contains('/')) {
    return $normalized -match $rx
  }
  return $normalized -match $rx -or ([IO.Path]::GetFileName($normalized) -match $rx)
}

function Load-EditorConfig([string]$filePath) {
  $script:ec.indent_style = "space"
  $script:ec.indent_size = 4
  $script:ec.tab_width = 4
  $script:ec.end_of_line = "lf"
  $script:ec.trim_trailing_whitespace = $false
  $script:ec.insert_final_newline = $false
  $script:ec.charset = "utf-8"
  $script:ec.max_line_length = 0

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
    $relativePath = if ($filePath) {
      [IO.Path]::GetRelativePath($baseDir, [IO.Path]::GetFullPath($filePath)) -replace '\\', '/'
    } else {
      $fileName
    }
    $active = $false
    try {
      foreach ($rawLine in [IO.File]::ReadAllLines($configPath)) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[(.*)\]$') {
          $active = Test-EditorConfigSectionMatch $Matches[1].Trim() $relativePath
          continue
        }
        if ($line -match '^([^=]+)=(.*)$') {
          $k = $Matches[1].Trim().ToLowerInvariant()
          $v = $Matches[2].Trim().ToLowerInvariant()
          if (-not $active) { continue }
          switch ($k) {
            'indent_style' { $script:ec.indent_style = $v }
            'indent_size' { if ($v -match '^\d+$') { $script:ec.indent_size = [int]$v } }
            'tab_width' { if ($v -match '^\d+$') { $script:ec.tab_width = [int]$v } }
            'end_of_line' { $script:ec.end_of_line = $v }
            'trim_trailing_whitespace' { $script:ec.trim_trailing_whitespace = ($v -eq 'true') }
            'insert_final_newline' { $script:ec.insert_final_newline = ($v -eq 'true') }
            'charset' { $script:ec.charset = $v }
            'max_line_length' { if ($v -match '^\d+$') { $script:ec.max_line_length = [int]$v } }
          }
        }
      }
    } catch {
      Write-DiagLog "editorconfig parse error '$configPath': $_"
    }
  }

  $state.Message = ' .editorconfig loaded '
}

function Get-IndentString {
  if ($script:ec.indent_style -eq 'tab') { return "`t" }
  return ' ' * [Math]::Max(1, $script:ec.indent_size)
}

# ---------------------------------------------------------------------------
# Clipboard
# ---------------------------------------------------------------------------
function Get-ClipboardText {
  $result = $null
  try {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { $result = [System.Windows.Forms.Clipboard]::GetText() }
    elseif ($IsMacOS) { $result = (& pbpaste 2>$null) }
    elseif (Get-Command wl-paste -ErrorAction SilentlyContinue) { $result = (& wl-paste 2>$null) }
    elseif (Get-Command xclip -ErrorAction SilentlyContinue) { $result = (& xclip -selection clipboard -o 2>$null) }
    elseif (Get-Command xsel -ErrorAction SilentlyContinue) { $result = (& xsel --clipboard --output 2>$null) }
  } catch {
    Write-DiagLog "clipboard read error: $_"
  }
  if ($null -eq $result) { return [string]::Empty }
  [string]$result
}

function Set-ClipboardText([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return }
  try {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { [System.Windows.Forms.Clipboard]::SetText($text); return }
    if ($IsMacOS) { $text | & pbcopy; return }
    if (Get-Command wl-copy -ErrorAction SilentlyContinue) { $text | & wl-copy; return }
    if (Get-Command xclip -ErrorAction SilentlyContinue) { $text | & xclip -selection clipboard; return }
    if (Get-Command xsel -ErrorAction SilentlyContinue) { $text | & xsel --clipboard --input; return }
  } catch {
    Write-DiagLog "clipboard write error: $_"
  }
}

if ($IsWindows -or $env:OS -eq 'Windows_NT') {
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
  } catch {
    Write-DiagLog "Windows.Forms load error: $_"
  }
}

# ---------------------------------------------------------------------------
# Windows mouse support
# ---------------------------------------------------------------------------
$script:mouseEnabled = $false
$script:origConsoleMode = 0
$script:consoleHandle = [IntPtr]::Zero

if ($IsWindows -or $env:OS -eq 'Windows_NT') {
  try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BabaeWin {
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint mode);
    [StructLayout(LayoutKind.Sequential)] struct COORD { public short X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE_EVENT_RECORD {
        public COORD MousePosition;
        public uint ButtonState, ControlKeyState, EventFlags;
    }
    [StructLayout(LayoutKind.Explicit)] struct INPUT_RECORD {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public MOUSE_EVENT_RECORD MouseEvent;
    }
    [DllImport("kernel32.dll")] static extern bool PeekConsoleInput(IntPtr h, [Out] INPUT_RECORD[] buf, uint len, out uint read);
    [DllImport("kernel32.dll")] static extern bool ReadConsoleInput(IntPtr h, [Out] INPUT_RECORD[] buf, uint len, out uint read);
    public const int STD_INPUT = -10;
    public const uint MOUSE_INPUT = 0x0010;
    public const uint QUICK_EDIT = 0x0040;
    public const uint EXTENDED_FLAGS = 0x0080;
    const ushort MOUSE_EVENT_TYPE = 0x0002;
    const uint RIGHT_BTN_PRESSED = 0x0002;
    public static IntPtr GetHandle() { return GetStdHandle(STD_INPUT); }
    public static uint GetMode(IntPtr h) { uint m = 0; GetConsoleMode(h, out m); return m; }
    public static void SetModeValue(IntPtr h, uint m) { SetConsoleMode(h, m); }
    public static bool PollRightClick(IntPtr h) {
        var buf = new INPUT_RECORD[16]; uint read;
        if (!PeekConsoleInput(h, buf, (uint)buf.Length, out read) || read == 0) return false;
        bool found = false;
        for (uint i = 0; i < read; i++) {
            if (buf[i].EventType == MOUSE_EVENT_TYPE && (buf[i].MouseEvent.ButtonState & RIGHT_BTN_PRESSED) != 0 && buf[i].MouseEvent.EventFlags == 0) {
                found = true; break;
            }
        }
        if (found) ReadConsoleInput(h, buf, read, out read);
        return found;
    }
}
'@ -ErrorAction SilentlyContinue
    $script:consoleHandle = [BabaeWin]::GetHandle()
    $script:origConsoleMode = [BabaeWin]::GetMode($script:consoleHandle)
    $newMode = ($script:origConsoleMode -bor [BabaeWin]::MOUSE_INPUT -bor [BabaeWin]::EXTENDED_FLAGS) -band (-bnot [BabaeWin]::QUICK_EDIT)
    [BabaeWin]::SetModeValue($script:consoleHandle, $newMode)
    $script:mouseEnabled = $true
  } catch {
    Write-DiagLog "Win32 mouse init error: $_"
  }
}

# ---------------------------------------------------------------------------
# Editor state
# ---------------------------------------------------------------------------
function Get-Language([string]$fp) {
  if ([string]::IsNullOrEmpty($fp)) { return 'Plain Text' }
  switch ([IO.Path]::GetExtension($fp).ToLowerInvariant()) {
    '.ps1' { 'PowerShell' }
    '.psm1' { 'PowerShell' }
    '.psd1' { 'PowerShell' }
    '.cs' { 'C#' }
    '.ts' { 'TypeScript' }
    '.tsx' { 'TypeScript' }
    '.js' { 'JavaScript' }
    '.jsx' { 'JavaScript' }
    '.py' { 'Python' }
    '.json' { 'JSON' }
    '.md' { 'Markdown' }
    '.sh' { 'Bash' }
    '.bash' { 'Bash' }
    default { 'Plain Text' }
  }
}

$state = [PSCustomObject]@{
  Buffer       = [System.Text.StringBuilder]::new()
  Cursor       = 0
  PreferredCol = 0
  ScrollRow    = 0
  FilePath     = ''
  Language     = 'Plain Text'
  Dirty        = $false
  Message      = ''
  LastSearch   = ''
  UndoStack    = [System.Collections.Generic.Stack[object]]::new()
  RedoStack    = [System.Collections.Generic.Stack[object]]::new()
  Mode         = 'edit'
  SearchBuf    = ''
  SelActive    = $false
  SelAnchor    = 0
}

# ── flat-buffer primitives ───────────────────────────────────────────────────

function BufText { $state.Buffer.ToString() }
function BufLen { $state.Buffer.Length }
function BufSet([string]$text) {
  $state.Buffer.Clear() | Out-Null
  if ($text) { $state.Buffer.Append($text) | Out-Null }
}
function ClampCursor {
  $state.Cursor = [Math]::Max(0, [Math]::Min($state.Cursor, (BufLen)))
}

function OffsetToRowCol([int]$offset) {
  $t = BufText
  $off = [Math]::Max(0, [Math]::Min($offset, $t.Length))
  $row = 0; $ls = 0
  for ($i = 0; $i -lt $off; $i++) {
    if ($t[$i] -eq "`n") { $row++; $ls = $i + 1 }
  }
  return $row, ($off - $ls)
}

function LineStart([int]$offset) {
  $t = BufText
  while ($offset -gt 0 -and $t[$offset - 1] -ne "`n") { $offset-- }
  return $offset
}

function LineEnd([int]$offset) {
  $t = BufText
  while ($offset -lt $t.Length -and $t[$offset] -ne "`n") { $offset++ }
  return $offset
}

function GetLine([int]$n) {
  $t = BufText; $row = 0; $start = 0
  for ($i = 0; $i -le $t.Length; $i++) {
    if ($i -eq $t.Length -or $t[$i] -eq "`n") {
      if ($row -eq $n) { return $t.Substring($start, $i - $start) }
      $row++; $start = $i + 1
    }
  }
  return $null
}

function RowColToOffset([int]$row, [int]$col) {
  $t = BufText; $r = 0; $start = 0
  for ($i = 0; $i -le $t.Length; $i++) {
    if ($i -eq $t.Length -or $t[$i] -eq "`n") {
      if ($r -eq $row) {
        return $start + [Math]::Max(0, [Math]::Min($col, $i - $start))
      }
      $r++; $start = $i + 1
    }
  }
  return $t.Length
}

function LineCount {
  $t = BufText
  if ($t.Length -eq 0) { return 1 }
  return 1 + ($t.ToCharArray() | Where-Object { $_ -eq "`n" }).Count
}

function SelBounds {
  [Math]::Min($state.SelAnchor, $state.Cursor),
  [Math]::Max($state.SelAnchor, $state.Cursor)
}

function State-Reset {
  BufSet ''
  $state.Cursor = 0; $state.PreferredCol = 0; $state.ScrollRow = 0
  $state.FilePath = ''; $state.Language = 'Plain Text'
  $state.Dirty = $false; $state.Message = ''; $state.LastSearch = ''
  $state.UndoStack.Clear(); $state.RedoStack.Clear()
  $state.Mode = 'edit'; $state.SearchBuf = ''
  $state.SelActive = $false; $state.SelAnchor = 0
}

function State-LoadFile([string]$path) {
  $state.FilePath = $path
  $state.Language = Get-Language $path
  $raw = ''
  try {
    $raw = if (Test-Path $path) {
      [IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
    } else { '' }
  } catch {
    Write-DiagLog "file read error '$path': $_"
  }
  BufSet $raw
  $state.Cursor = 0; $state.PreferredCol = 0; $state.ScrollRow = 0
}

function State-SaveFile {
  if ([string]::IsNullOrWhiteSpace($state.FilePath)) { $state.Message = ' No path '; return }
  $content = BufText
  if ($script:ec.trim_trailing_whitespace) {
    $content = ($content -split "`n", -1 | ForEach-Object { $_.TrimEnd() }) -join "`n"
  }
  if ($script:ec.insert_final_newline -and -not $content.EndsWith("`n")) { $content += "`n" }
  switch ($script:ec.end_of_line) {
    'crlf' { $content = $content -replace "`n", "`r`n" }
    'cr' { $content = $content -replace "`n", "`r" }
  }
  $enc = switch ($script:ec.charset) {
    'utf-8-bom' { [Text.UTF8Encoding]::new($true) }
    'latin1' { [Text.Encoding]::Latin1 }
    default { [Text.UTF8Encoding]::new($false) }
  }
  try {
    [IO.File]::WriteAllText($state.FilePath, $content, $enc)
    $state.Dirty = $false; $state.Message = ' Saved '
  } catch {
    Write-DiagLog "file save error '$($state.FilePath)': $_"
    $state.Message = ' Save failed! '
  }
}

function State-Snapshot {
  if ($state.UndoStack.Count -ge 200) {
    $arr = $state.UndoStack.ToArray(); $state.UndoStack.Clear()
    for ($i = 0; $i -lt ($arr.Count - 100); $i++) {
      $state.UndoStack.Push($arr[$arr.Count - 1 - $i])
    }
  }
  $state.UndoStack.Push([PSCustomObject]@{
      Buf = BufText; Cursor = $state.Cursor; PCol = $state.PreferredCol
    })
  $state.RedoStack.Clear()
}

function State-Apply([object]$snap, [System.Collections.Generic.Stack[object]]$target) {
  $target.Push([PSCustomObject]@{
      Buf = BufText; Cursor = $state.Cursor; PCol = $state.PreferredCol
    })
  BufSet $snap.Buf
  $state.Cursor = [Math]::Min($snap.Cursor, (BufLen))
  $state.PreferredCol = $snap.PCol
  $state.ScrollRow = 0
  $state.Dirty = $true
  Reset-RenderShadow
}

function State-Undo { if ($state.UndoStack.Count -eq 0) { $state.Message = ' Nothing to undo '; return }; State-Apply $state.UndoStack.Pop() $state.RedoStack }
function State-Redo { if ($state.RedoStack.Count -eq 0) { $state.Message = ' Nothing to redo '; return }; State-Apply $state.RedoStack.Pop() $state.UndoStack }

function Sel-Bounds { SelBounds }

function Get-SelectionText {
  if (-not $state.SelActive) { return [string]::Empty }
  $a, $b = SelBounds
  (BufText).Substring($a, $b - $a)
}

function Delete-Selection {
  if (-not $state.SelActive) { return }
  $a, $b = SelBounds; $t = BufText
  BufSet ($t.Substring(0, $a) + $t.Substring($b))
  $state.Cursor = $a
  $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]
  $state.SelActive = $false; $state.Dirty = $true
}

function Begin-Sel {
  if (-not $state.SelActive) {
    $state.SelActive = $true
    $state.SelAnchor = $state.Cursor
  }
}

function Paste-Text([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { $state.Message = ' Clipboard empty '; return }
  State-Snapshot
  if ($state.SelActive) { Delete-Selection }
  $norm = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $t = BufText
  BufSet ($t.Substring(0, $state.Cursor) + $norm + $t.Substring($state.Cursor))
  $state.Cursor += $norm.Length
  $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]
  $state.Dirty = $true; $state.Message = ' Pasted (clipboard) '; Reset-RenderShadow
}


function Clamp-Cursor { ClampCursor }

# ---------------------------------------------------------------------------
# Diag pane helpers
# ---------------------------------------------------------------------------

# How many extra rows the pane consumes (0 when hidden).
function DiagPaneRows {
  if (-not $script:diagPaneVisible) { return 0 }
  return 1 + $script:diagPaneHeight  # 1 separator bar + N log rows
}

# Build a single row of the diag pane.
# $diagRow = 0 → separator bar; 1..$diagPaneHeight → log lines (newest last).
function Build-DiagRow([int]$diagRow, [int]$screenWidth) {
  if ($diagRow -eq 0) {
    # Separator bar
    $count  = $script:diagRing.Count
    $label  = " DIAG | $count event$(if ($count -ne 1) {'s'} else {''}) "
    $hint   = " ^D close "
    $pad    = [Math]::Max(0, $screenWidth - $label.Length - $hint.Length)
    return "$(T 'bgBar')$(T 'fgAccent')${BOLD}$label$RESET$(T 'bgBar')$(T 'fgMuted')$(' ' * $pad)$hint$RESET"
  }

  # Log rows — display newest-last slice of the ring
  $entries  = @($script:diagRing)  # oldest→newest array
  $total    = $entries.Count
  # Which log lines to show: bottom $diagPaneHeight lines
  $startIdx = [Math]::Max(0, $total - $script:diagPaneHeight)
  $lineIdx  = $diagRow - 1  # 0-based within the visible slice
  $entryIdx = $startIdx + $lineIdx

  $bg = T 'bg'
  if ($entryIdx -ge $total) {
    return "${bg}$(T 'fgTilde') $(' ' * ($screenWidth - 1))$RESET"
  }
  $raw = $entries[$entryIdx]
  # Truncate to fit, strip any ANSI that crept in
  $raw = $raw -replace [char]0x1B, '?'
  if ($raw.Length -gt $screenWidth - 1) { $raw = $raw.Substring(0, $screenWidth - 1) }
  $pad = [Math]::Max(0, $screenWidth - 1 - $raw.Length)
  return "${bg}$(T 'fgMuted') $raw$(' ' * $pad)$RESET"
}

function Update-Scroll {
  $height = [Console]::WindowHeight - 2 - (DiagPaneRows)
  if ($height -lt 1) { $height = 1 }
  $curRow = (OffsetToRowCol $state.Cursor)[0]
  if ($curRow -lt $state.ScrollRow) { $state.ScrollRow = $curRow }
  elseif ($curRow -ge $state.ScrollRow + $height) { $state.ScrollRow = $curRow - $height + 1 }
}

function Move-To([int]$r, [int]$c) { "`e[$r;${c}H" }

function Build-EditorRow([int]$rowIndex, [int]$screenWidth, [int]$textWidth) {
  $height      = [Console]::WindowHeight
  $diagRows    = DiagPaneRows
  # Logical boundaries
  $contentTop  = 1          # first content row (0-indexed screen row)
  $statusRow   = $height - 1
  $diagSepRow  = if ($diagRows -gt 0) { $height - 1 - $diagRows } else { -1 }

  $curRow, $curCol = OffsetToRowCol $state.Cursor
  $selA = 0; $selB = 0
  if ($state.SelActive) { $selA, $selB = SelBounds }

  # ── header ──────────────────────────────────────────────────────────────
  if ($rowIndex -eq 0) {
    $themeName = $script:themes[$script:themeNames[$script:themeIdx]].name
    $fileName = if ($state.FilePath) { [IO.Path]::GetFileName($state.FilePath) } else { 'new file' }
    $dirty = if ($state.Dirty) { "$(T 'fgDirty')●$RESET$(T 'bgHeader')$(T 'fgHeader') " } else { '  ' }
    $plain = " babae | $fileName [$($state.Language)] | $themeName "
    $pad = [Math]::Max(0, $screenWidth - $plain.Length)
    return "$(T 'bgHeader')$(T 'fgHeader')${BOLD} babae $RESET$(T 'bgHeader')$(T 'fgMuted')| $RESET$(T 'bgHeader')$(T 'fgHeader')$dirty$fileName [$($state.Language)] $(T 'bgHeader')$(T 'fgMuted')| $RESET$(T 'bgHeader')$(T 'fgHeader')$themeName$(' ' * $pad)$RESET"
  }

  # ── status bar ──────────────────────────────────────────────────────────
  if ($rowIndex -eq $statusRow) {
    $msg = $state.Message
    $pos = " $($curRow + 1):$($curCol + 1) "
    $ecHint = if ($script:ec.indent_style -eq 'tab') { 'tab' } else { "$($script:ec.indent_size)sp" }
    $eol = $script:ec.end_of_line.ToUpperInvariant()
    if ($state.Mode -eq 'search') {
      $plain = " Search: $($state.SearchBuf)_ (Enter=jump Esc=cancel) "
      $pad = [Math]::Max(0, $screenWidth - $plain.Length)
      return "$(T 'bgBar')$(T 'fgAccent')${BOLD} Search:$RESET$(T 'bgBar')$(T 'fgNorm') $($state.SearchBuf)_ $(T 'fgMuted')(Enter=jump Esc=cancel)$(' ' * $pad)$RESET"
    }
    $barCmds = $script:commands | Where-Object { $_.Key -in '^T', '^S', '^Q', '^F', '^Z', '^H', '^D' }
    $leftPlain = ' ' + (($barCmds | ForEach-Object { "$($_.Key) $($_.Label)" }) -join ' ') + ' '
    $rightPlain = " $eol | $ecHint |$pos"
    if ($msg) { $rightPlain = " $msg |" + $rightPlain }
    if ($state.SelActive) { $rightPlain = " SEL |" + $rightPlain }
    $pad = [Math]::Max(0, $screenWidth - $leftPlain.Length - $rightPlain.Length)
    $right = ''
    if ($msg) { $right += "$(T 'fgSaved') $msg $RESET$(T 'bgBar')$(T 'fgMuted')│" }
    if ($state.SelActive) { $right += "$(T 'fgAccent') SEL $RESET$(T 'bgBar')$(T 'fgMuted')│" }
    $right += "$(T 'fgMuted') $eol $(T 'fgMuted')│ $(T 'fgMuted')$ecHint $(T 'fgMuted')│$(T 'fgAccent')$pos$RESET"
    $barLeft = "$(T 'bgBar')"
    foreach ($cmd in $barCmds) {
      $barLeft += "$(T 'fgAccent')${BOLD}$($cmd.Key)$RESET$(T 'bgBar')$(T 'fgMuted') $($cmd.Label) "
    }
    return "$barLeft$(' ' * $pad)$right"
  }

  # ── diag pane rows ───────────────────────────────────────────────────────
  if ($diagRows -gt 0 -and $rowIndex -ge $diagSepRow -and $rowIndex -lt $statusRow) {
    $diagRow = $r