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
.EXAMPLE
    pwsh ./babae.ps1
    pwsh ./babae.ps1 myfile.txt -Theme mocha
#>
param(
  [Parameter(Position = 0)][string]$Path,
  [ValidateSet("dark", "mocha", "frappe", "github-dark")]
  [string]$Theme = "dark",
  [switch]$DiagPane,
  [switch]$DebugLog,
  [switch]$DiagPane,
  [switch]$DebugLog
)

# ---------------------------------------------------------------------------
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
      } catch {
        Write-DiagLog 'INSTALL' "Version comparison failed: $($_.Exception.Message)"
      }
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
$script:undoStackMax = 200
$script:undoStackTrim = 100
$script:pasteDeadlineMs = 2000
$script:inputBufSize = 4096
$script:maxSeqLen = 32
$script:escapeTimeoutMs = 100
$script:peekWaitMs = 50
$script:diagDefaultHeight = 5
$script:diagPaneMinHeight = 3
$script:diagLogMaxEntries = 200

$script:diagPaneVisible = $false
$script:diagPaneHeight = $script:diagDefaultHeight
$script:diagScrollOffset = 0
$script:diagDragging = $false
$script:diagDividerRow = -1
$script:diagRingBuffer = [System.Collections.Generic.Queue[string]]::new()

$script:undoStackMax = 200
$script:undoStackTrim = 100
$script:pasteDeadlineMs = 2000
$script:inputBufSize = 4096
$script:maxSeqLen = 32
$script:escapeTimeoutMs = 100
$script:peekWaitMs = 50
$script:diagDefaultHeight = 5
$script:diagPaneMinHeight = 3
$script:diagLogMaxEntries = 200

$script:diagPaneVisible = $false
$script:diagPaneHeight = $script:diagDefaultHeight
$script:diagScrollOffset = 0
$script:diagDragging = $false
$script:diagDividerRow = -1
$script:diagRingBuffer = [System.Collections.Generic.Queue[string]]::new()

$script:debugLog = $null
if ($DebugLog.IsPresent) {
  $script:debugLog = Join-Path . 'babae-debug.log'
}


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
# Raw stdin reader — owns all input so we can parse VT sequences ourselves.
#
# WHY: Console.ReadKey goes through .NET's console abstraction, which on
# older runtimes silently strips the '[' from bracketed-paste sentinels
# (ESC[200~ → ESC200~) making detection impossible.  Reading the raw byte
# stream sidesteps that entirely: bytes are bytes, sequences are intact.
#
# The reader owns a 4 KiB buffer it fills from the stdin stream.
# Read-NextInputEvent is the single call site: it blocks until at least one
# event is ready and returns either:
#   [PSCustomObject]@{ Kind='Key';   KeyInfo=<ConsoleKeyInfo> }
#   [PSCustomObject]@{ Kind='Paste'; Text=<string> }
# ---------------------------------------------------------------------------
$script:stdinStream   = [Console]::OpenStandardInput()
$script:inputBuf      = [byte[]]::new($script:inputBufSize)
$script:inputPending  = [System.Collections.Generic.Queue[byte]]::new()

# Detect once whether stdin is a real console or redirected.
# We cache this to pick the right non-blocking check in the hot path.
$script:stdinIsConsole = $true
try { [void][Console]::KeyAvailable } catch {
  $script:stdinIsConsole = $false
  Write-DiagLog 'INPUT' "Console key-availability probe failed: $($_.Exception.Message)"
}

# Single outstanding async read task — ALWAYS reads into the shared inputBuf.
# Rule: at most one ReadAsync in flight at any time.  Stdin-PeekAvailable calls
# Stdin-TryDrain instead of creating its own tasks.  This eliminates the
# concurrent-read race that caused missed bytes and hangs.
$script:stdinReadTask = $null

# Internal helpers ─────────────────────────────────────────────────────────────

# Ensure the shared async task is running.
function Stdin-EnsureTask {
  if ($null -eq $script:stdinReadTask) {
    $script:stdinReadTask = $script:stdinStream.ReadAsync($script:inputBuf, 0, $script:inputBuf.Length)
  }
}

# Collect a completed task's bytes into inputPending.  Returns byte count (0 = EOF).
function Stdin-HarvestTask {
  $n = $script:stdinReadTask.GetAwaiter().GetResult()
  $script:stdinReadTask = $null
  for ($i = 0; $i -lt $n; $i++) { $script:inputPending.Enqueue($script:inputBuf[$i]) | Out-Null }
  return $n
}

# Non-blocking poll: returns $true if data (or EOF) is available.
# Harvests any completed task bytes as a side-effect.
function Stdin-TryDrain {
  if ($script:inputPending.Count -gt 0) { return $true }
  if ($script:stdinIsConsole) {
    try { return [Console]::KeyAvailable } catch {
      $script:stdinIsConsole = $false
      Write-DiagLog 'INPUT' "Console key-availability poll failed: $($_.Exception.Message)"
    }
  }
  Stdin-EnsureTask
  if (-not $script:stdinReadTask.IsCompleted) { return $false }
  [void](Stdin-HarvestTask)
  return $true  # either data or EOF — either way, caller should read
}

# ── Public API ─────────────────────────────────────────────────────────────────

# Main-loop poll: returns $true when input is ready without blocking.
function Stdin-DataAvailable {
  if (-not [Console]::IsInputRedirected) { return ($script:inputPendingKeys.Count -gt 0 -or ($script:inputQueue.Count -ne 0)) }
  return Stdin-TryDrain
}

# Blocking read: returns next byte, or -1 on EOF.
function Stdin-ReadByte {
  while ($script:inputPending.Count -eq 0) {
    Stdin-EnsureTask
    $n = Stdin-HarvestTask   # blocks until data arrives
    if ($n -le 0) { return -1 }
  }
  return [int]$script:inputPending.Dequeue() | Out-Null
}

# Drain whatever is already buffered in the OS pipe — no new-data blocking.
# Uses the single shared task; never starts a second concurrent ReadAsync.
function Stdin-PeekAvailable {
  # Harvest any already-finished task first.
  if ($null -ne $script:stdinReadTask -and $script:stdinReadTask.IsCompleted) {
    $n = Stdin-HarvestTask
    if ($n -le 0) { return }  # EOF
  }
  # Loop: start task, wait 1 ms; instant completion → more buffered data exists.
  while ($true) {
    Stdin-EnsureTask
    if (-not $script:stdinReadTask.Wait(1)) { break }  # pipe empty — stop
    $n = Stdin-HarvestTask
    if ($n -le 0) { break }  # EOF
  }
}

# Read bytes until we see ESC[201~ or the deadline expires.
# Uses a Stopwatch-based deadline with adaptive backoff to avoid penalty
# stacking when SSH delivers the paste payload in many small TCP segments.
function Stdin-DrainPaste {
  $sb     = [System.Text.StringBuilder]::new(4096)
  $escBuf = [System.Text.StringBuilder]::new()
  $inEsc  = $false

  $deadline = [System.Diagnostics.Stopwatch]::StartNew()

  while ($deadline.ElapsedMilliseconds -lt $script:pasteDeadlineMs) {
    if ($script:inputPending.Count -eq 0) {
      Stdin-PeekAvailable
      if ($script:inputPending.Count -eq 0) {
        # Adaptive sleep: 2ms initially, grows to 20ms max as time passes.
        # Avoids fixed 5ms penalty per SSH segment while still yielding the thread.
        $sleep = [Math]::Min(20, [Math]::Max(2, [int]($deadline.ElapsedMilliseconds / 50)))
        Start-Sleep -Milliseconds $sleep
        continue
      }
    }

    $b  = [int]$script:inputPending.Dequeue() | Out-Null
    if ($b -eq -1) { break }    # EOF inside paste — return whatever we have
    $ch = [char]$b

    if (-not $inEsc) {
      if ($b -eq 27) {           # ESC — might be start of ESC[201~
        $inEsc = $true
        $escBuf.Clear() | Out-Null
      } else {
        [void]$sb.Append($ch)
      }
    } else {
      [void]$escBuf.Append($ch)
      $esc = $escBuf.ToString()
      if ($esc -eq '[201~') {
        # Confirmed end sentinel — paste complete.
        $inEsc = $false; break
      } elseif ('[201~'.StartsWith($esc)) {
        # Still matching — keep buffering.
      } else {
        # False ESC — flush it literally and continue.
        [void]$sb.Append([char]27)
        [void]$sb.Append($esc)
        $inEsc = $false
      }
    }
  }
  return $sb.ToString()
}

# Synthesise a ConsoleKeyInfo from a raw char (for plain printable bytes and
# control bytes that we handle ourselves).
function Make-KeyInfo([char]$ch, [System.ConsoleKey]$key, [System.ConsoleModifiers]$mods) {
  return [System.ConsoleKeyInfo]::new($ch, $key, `
    ($mods -band [System.ConsoleModifiers]::Shift) -ne 0, `
    ($mods -band [System.ConsoleModifiers]::Alt)   -ne 0, `
    ($mods -band [System.ConsoleModifiers]::Control) -ne 0)
}

# Parse a VT escape sequence (everything after the leading ESC) into a
# ConsoleKeyInfo.  $seq is the chars after ESC, e.g. '[A' for up-arrow.
function Parse-EscapeSequence([string]$seq) {
  # CSI sequences: ESC [ ...
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
      # Shift+arrows (xterm)
      '1;2A' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    ([System.ConsoleModifiers]::Shift) }
      '1;2B' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  ([System.ConsoleModifiers]::Shift) }
      '1;2C' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) ([System.ConsoleModifiers]::Shift) }
      '1;2D' { return Make-KeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  ([System.ConsoleModifiers]::Shift) }

      # Ctrl+1..9 (CSI u and common xterm variations)
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

      # Alternative xterm sequences for Ctrl+Digit
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
  # SS3 sequences: ESC O ...
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
  # Unknown sequence — return a null-char key so it is silently ignored.
  return Make-KeyInfo ([char]0) ([System.ConsoleKey]::NoName) 0
}

function Try-ParseMouseSequence([string]$seq) {
  if ($seq -notmatch '^\[<(\d+);(\d+);(\\d+)([Mm])$') { return $null }
  $buttonCode = [int]$Matches[1]; $x = [int]$Matches[2]; $y = [int]$Matches[3]; $suffix = $Matches[4]
  $release = ($suffix -eq 'm')
  return [PSCustomObject]@{
    Kind    = 'Mouse'
    X       = $x; Y = $y
    Left    = (($buttonCode -band 3) -eq 0)
    Right   = (($buttonCode -band 3) -eq 2)
    Down    = (-not $release); Release = $release
    Drag    = (($buttonCode -band 32) -ne 0)
  }
}


function Try-ParseMouseSequence([string]$seq) {
  if ($seq -notmatch '^\[<(\d+);(\d+);(\d+)([Mm])$') { return $null }
  $buttonCode = [int]$Matches[1]
  $x = [int]$Matches[2]
  $y = [int]$Matches[3]
  $suffix = $Matches[4]
  $release = ($suffix -eq 'm')
  return [PSCustomObject]@{
    Kind    = 'Mouse'
    X       = $x
    Y       = $y
    Left    = (($buttonCode -band 3) -eq 0)
    Right   = (($buttonCode -band 3) -eq 2)
    Down    = (-not $release)
    Release = $release
    Drag    = (($buttonCode -band 32) -ne 0)
  }
}      # Read one complete input event (key or paste) from raw stdin.
      $event = Read-NextInputEvent
      if ($null -eq $event) { continue }

      if ($event.Kind -eq 'Paste') {
        Paste-Text $event.Text
      } elseif ($event.Kind -eq 'Mouse') {
        if ($event.Release) {
          $script:diagDragging = $false
        } elseif ($event.Right -and $event.Down) {
          Paste-Text (Get-ClipboardText)
        } elseif ($script:diagPaneVisible -and $event.Left -and $event.Down -and $event.Y -eq $script:diagDividerRow) {
          $script:diagDragging = $true
          Handle-DiagMouseDrag $event.Y
        } elseif ($script:diagDragging -and $event.Left -and ($event.Drag -or $event.Down)) {
          Handle-DiagMouseDrag $event.Y
        }
      } else {
        switch ($state.Mode) {
          'edit'         { Handle-EditKey $event.KeyInfo }
          'search'       { Handle-SearchKey $event.KeyInfo }
          'confirm-quit' { Handle-ConfirmQuitKey $event.KeyInfo }
        }
      }
      ClampCursor

      if ($state.Mode -eq 'confirm-quit') {
        if ($state.Dirty) { Render-ConfirmQuit } else { $script:running = $false; continue }
      }
    }
  } finally {
    Stop-InputThread
    if ($script:mouseEnabled) {
      try { [BabaeWin]::SetModeValue($script:consoleHandle, $script:origConsoleMode) } catch {
        Write-DiagLog 'INPUT' "Windows console mode restore failed: $($_.Exception.Message)"
      }
    }
    [Console]::TreatControlCAsInput = $oldCtrlC
    if ($script:isUnix -and $script:oldStty -and -not [Console]::IsInputRedirected) {
      try { stty $script:oldStty 2>/dev/null } catch {
        Write-DiagLog 'INPUT' "stty restore failed: $($_.Exception.Message)"
      }
    }
    # Disable bracketed paste mode before handing the terminal back.
        $ansi = "`e[?1006l`e[?1003l`e[?1000l`e[?2004l`e[?1049l`e[?25h`e[0m"
    if ($script:diagPaneVisible) { $ansi = "`e[?1006l`e[?1003l`e[?1000l`e[?1006l`e[?1003l`e[?1000l`e[?2004l`e[?1049l`e[?25h`e[0m" }
    Out-Flush($ansi)
    Write-Host 'babae: session ended.' -ForegroundColor Cyan
    if ($state.FilePath) { Write-Host "File : $($state.FilePath)" -ForegroundColor DarkGray }
  }
}

Set-Alias -Name babae -Value Edit-Babae -Scope Global
Edit-Babae @PSBoundParameters
