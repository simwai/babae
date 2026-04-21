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
  [string]$Theme = "dark"
)

$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$script:frameDelayMs = 33
$script:debugLog = $null
if ($DebugLog.IsPresent) {
  $script:debugLog = Join-Path . 'babae-debug.log'
}
Write-Host $script:debugLog

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
$script:inputBuf      = [byte[]]::new(4096)
$script:inputPending  = [System.Collections.Generic.Queue[byte]]::new()

# Detect once whether stdin is a real console or redirected.
# We cache this to pick the right non-blocking check in the hot path.
$script:stdinIsConsole = $IsWindows
try { if ($script:stdinIsConsole) { [void][Console]::KeyAvailable } } catch { $script:stdinIsConsole = $false }

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
  for ($i = 0; $i -lt $n; $i++) { $script:inputPending.Enqueue($script:inputBuf[$i]) }
  return $n
}

# Non-blocking poll: returns $true if data (or EOF) is available.
# Harvests any completed task bytes as a side-effect.
function Stdin-TryDrain {
  if ($script:inputPending.Count -gt 0) { return $true }
  if ($script:stdinIsConsole) { return [Console]::KeyAvailable }
  Stdin-EnsureTask
  if (-not $script:stdinReadTask.IsCompleted) { return $false }
  [void](Stdin-HarvestTask)
  return $true  # either data or EOF — either way, caller should read
}

# ── Public API ─────────────────────────────────────────────────────────────────

# Main-loop poll: returns $true when input is ready without blocking.
function Stdin-DataAvailable { Stdin-TryDrain }

# Blocking read: returns next byte, or -1 on EOF.
function Stdin-ReadByte {
  while ($script:inputPending.Count -eq 0) {
    Stdin-EnsureTask
    $n = Stdin-HarvestTask   # blocks until data arrives
    if ($n -le 0) { return -1 }
  }
  return [int]$script:inputPending.Dequeue()
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

# Read bytes until we see ESC[201~ or the queue+stream runs dry.
# Returns the accumulated paste payload as a string.
function Stdin-DrainPaste {
  $sb       = [System.Text.StringBuilder]::new()
  $escBuf   = [System.Text.StringBuilder]::new()  # speculative ESC sequence
  $inEsc    = $false

  while ($true) {
    # If queue is empty, wait briefly for more bytes (SSH may segment the payload).
    if ($script:inputPending.Count -eq 0) {
      $waited = 0
      while ($script:inputPending.Count -eq 0 -and $waited -lt 500) {
        Start-Sleep -Milliseconds 5; $waited += 5
        Stdin-PeekAvailable
      }
      if ($script:inputPending.Count -eq 0) { break }  # timed out
    }

    $b  = [int]$script:inputPending.Dequeue()
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

# Read one complete input event from stdin.
# Returns either a Key event or a Paste event.
function Read-NextInputEvent {
  $b = Stdin-ReadByte
  if ($b -eq -1) {
    # EOF — stdin closed (test harness finished sending, or pipe broken).
    # Return a synthetic Ctrl+Q so the editor exits cleanly.
    return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]17) ([System.ConsoleKey]::Q) ([System.ConsoleModifiers]::Control)) }
  }

  # ── Bracketed-paste start: ESC [ 2 0 0 ~ ───────────────────────────────
  # We detect it at the byte level by reading ahead after an ESC.
  if ($b -eq 27) {
    # Wait briefly for the bytes that follow ESC to arrive.
    # On a real tty they are all in the kernel buffer already.
    # On a redirected pipe they may arrive in a separate read() call.
    Stdin-PeekAvailable
    if ($script:inputPending.Count -eq 0) {
      # Nothing arrived yet — wait up to 50 ms for an escape sequence.
      $w = 0
      while ($script:inputPending.Count -eq 0 -and $w -lt 50) {
        Start-Sleep -Milliseconds 5; $w += 5
        Stdin-PeekAvailable
      }
    }
    if ($script:inputPending.Count -eq 0) {
      # Still nothing after waiting → bare ESC keypress.
      return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
    }

    # Accumulate the rest of the sequence until it either matches a known
    # pattern or contains a char that can't continue any sequence.
    $seqBuf = [System.Text.StringBuilder]::new()
    $maxSeqLen = 12  # longest sequence we care about is '1;2D' = 4 chars after '['

    while ($script:inputPending.Count -gt 0 -and $seqBuf.Length -lt $maxSeqLen) {
      $nb = $script:inputPending.Peek()
      $nc = [char]$nb
      # Stop if this byte starts a new, unrelated sequence or is printable.
      if ($nb -eq 27) { break }  # another ESC — stop here
      [void]$seqBuf.Append($nc)
      $script:inputPending.Dequeue() | Out-Null

      $seq = $seqBuf.ToString()

      # Bracketed paste start ─────────────────────────────────────────────
      if ($seq -eq '[200~') {
        $payload = Stdin-DrainPaste
        return [PSCustomObject]@{ Kind = 'Paste'; Text = $payload }
      }

      # Known terminal sequence — stop as soon as it matches ──────────────
      $ki = Parse-EscapeSequence $seq
      if ($ki.Key -ne [System.ConsoleKey]::NoName) {
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = $ki }
      }

      # Keep accumulating if we might still complete a valid sequence.
      # A sequence is "potentially continuable" when it starts with [ or O
      # and consists only of digits, semicolons, or letters we handle.
      $couldContinue = ($seq.Length -eq 1 -and ($seq -eq '[' -or $seq -eq 'O')) `
                    -or ($seq.Length -gt 1 -and $seq[0] -eq '[' -and ($nc -match '[0-9;]'))
      if (-not $couldContinue) { break }
    }

    # Sequence ended without a match — emit ESC + accumulated chars as
    # individual key events.  Push them back onto the front of the queue.
    $seqStr = $seqBuf.ToString()
    # Push the accumulated chars back (in reverse, since Queue.Enqueue goes to back).
    # Simplest: re-queue the raw bytes, then immediately return the bare ESC.
    $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($seqStr)
    # Prepend them to the pending queue by rebuilding it.
    $tmp = [System.Collections.Generic.Queue[byte]]::new()
    foreach ($rb in $rawBytes) { $tmp.Enqueue($rb) }
    foreach ($rb in $script:inputPending) { $tmp.Enqueue($rb) }
    $script:inputPending = $tmp
    return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
  }

  # ── Control bytes ────────────────────────────────────────────────────────
  switch ($b) {
    13  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]13)  ([System.ConsoleKey]::Enter)     0) } }
    127 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }
    8   { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]8)   ([System.ConsoleKey]::Backspace) 0) } }
    9   { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]9)   ([System.ConsoleKey]::Tab)       0) } }
    27  {}  # handled above
    # Ctrl+A..Z
    default {
      if ($b -ge 1 -and $b -le 26) {
        $letter = [char]($b + [int][char]'A' - 1)
        $ck     = [System.ConsoleKey]$letter.ToString()
        return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]$b) $ck ([System.ConsoleModifiers]::Control)) }
      }
    }
  }

  # ── Printable UTF-8 character ────────────────────────────────────────────
  # Decode multi-byte sequences.
  [byte[]]$charBytes = @($b)
  if ($b -ge 0xC0) {
    $extra = if ($b -ge 0xF0) { 3 } elseif ($b -ge 0xE0) { 2 } else { 1 }
    for ($i = 0; $i -lt $extra; $i++) { $charBytes += Stdin-ReadByte }
  }
  $ch = [System.Text.Encoding]::UTF8.GetString($charBytes)[0]

  # Map printable to a ConsoleKey — best-effort, editor only uses KeyChar.
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
# Debug logging
# ---------------------------------------------------------------------------
function Write-DebugLog([string]$message) {
  if ($null -eq $script:debugLog) { return }
  $ts = [DateTimeOffset]::UtcNow.ToString('HH:mm:ss.fff')
  Add-Content -LiteralPath $script:debugLog -Value "[$ts] $message" -Encoding UTF8
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
  [PSCustomObject]@{ Key = '^1'; Label = 'Theme' }
  [PSCustomObject]@{ Key = '^S'; Label = 'Save' }
  [PSCustomObject]@{ Key = '^Q'; Label = 'Quit' }
  [PSCustomObject]@{ Key = '^F'; Label = 'Find' }
  [PSCustomObject]@{ Key = '^Z'; Label = 'Undo' }
  [PSCustomObject]@{ Key = '^Y'; Label = 'Redo' }
  [PSCustomObject]@{ Key = '^A'; Label = 'Select all' }
  [PSCustomObject]@{ Key = '^C'; Label = 'Copy' }
  [PSCustomObject]@{ Key = '^V'; Label = 'Paste' }
  [PSCustomObject]@{ Key = '^2'; Label = 'Help' }
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
  } catch {}
  # Always return [string] — never $null — so callers can safely IsNullOrEmpty-check
  if ($null -eq $result) { return [string]::Empty }
  [string]$result
}

function Set-ClipboardText([string]$text) {
  # Clipboard.SetText throws on null/empty on some Windows builds — guard it
  if ([string]::IsNullOrEmpty($text)) { return }
  try {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { [System.Windows.Forms.Clipboard]::SetText($text); return }
    if ($IsMacOS) { $text | & pbcopy; return }
    if (Get-Command wl-copy -ErrorAction SilentlyContinue) { $text | & wl-copy; return }
    if (Get-Command xclip -ErrorAction SilentlyContinue) { $text | & xclip -selection clipboard; return }
    if (Get-Command xsel -ErrorAction SilentlyContinue) { $text | & xsel --clipboard --input; return }
  } catch {}
}

if ($IsWindows -or $env:OS -eq 'Windows_NT') {
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
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
  } catch {}
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

# 0-based [row, col] for a buffer offset
function OffsetToRowCol([int]$offset) {
  $t = BufText
  $off = [Math]::Max(0, [Math]::Min($offset, $t.Length))
  $row = 0; $ls = 0
  for ($i = 0; $i -lt $off; $i++) {
    if ($t[$i] -eq "`n") { $row++; $ls = $i + 1 }
  }
  return $row, ($off - $ls)
}

# Offset of first char of the line containing $offset
function LineStart([int]$offset) {
  $t = BufText
  while ($offset -gt 0 -and $t[$offset - 1] -ne "`n") { $offset-- }
  return $offset
}

# Offset just past the last char of the line (before \n or at end-of-buffer)
function LineEnd([int]$offset) {
  $t = BufText
  while ($offset -lt $t.Length -and $t[$offset] -ne "`n") { $offset++ }
  return $offset
}

# Text of logical line $n (0-based); $null when out of range
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

# Buffer offset for [row, col] — col is clamped to line length
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
  return $t.Length   # row beyond last line — clamp to end
}

# Total number of logical lines
function LineCount {
  $t = BufText
  if ($t.Length -eq 0) { return 1 }
  return 1 + ($t.ToCharArray() | Where-Object { $_ -eq "`n" }).Count
}

# Ordered [lo, hi] selection offsets
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
  $raw = if (Test-Path $path) {
    [IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  } else { '' }
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
  [IO.File]::WriteAllText($state.FilePath, $content, $enc)
  $state.Dirty = $false; $state.Message = ' Saved '
}

function State-Snapshot {
  if ($state.UndoStack.Count -ge 200) {
    $arr = $state.UndoStack.ToArray(); $state.UndoStack.Clear()
    # Keep newest 100, discard oldest 100 — amortized O(1) trim
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

function Update-Scroll {
  $height = [Console]::WindowHeight - 2
  $curRow = (OffsetToRowCol $state.Cursor)[0]
  if ($curRow -lt $state.ScrollRow) { $state.ScrollRow = $curRow }
  elseif ($curRow -ge $state.ScrollRow + $height) { $state.ScrollRow = $curRow - $height + 1 }
}

function Move-To([int]$r, [int]$c) { "`e[$r;${c}H" }

function Build-EditorRow([int]$rowIndex, [int]$screenWidth, [int]$textWidth) {
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
  if ($rowIndex -eq ([Console]::WindowHeight - 1)) {
    $msg = $state.Message
    $pos = " $($curRow + 1):$($curCol + 1) "
    $ecHint = if ($script:ec.indent_style -eq 'tab') { 'tab' } else { "$($script:ec.indent_size)sp" }
    $eol = $script:ec.end_of_line.ToUpperInvariant()
    if ($state.Mode -eq 'search') {
      $plain = " Search: $($state.SearchBuf)_ (Enter=jump Esc=cancel) "
      $pad = [Math]::Max(0, $screenWidth - $plain.Length)
      return "$(T 'bgBar')$(T 'fgAccent')${BOLD} Search:$RESET$(T 'bgBar')$(T 'fgNorm') $($state.SearchBuf)_ $(T 'fgMuted')(Enter=jump Esc=cancel)$(' ' * $pad)$RESET"
    }
    $barCmds = $script:commands | Where-Object { $_.Key -in '^1', '^S', '^Q', '^F', '^Z', '^2' }
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

  # ── content row ─────────────────────────────────────────────────────────
  $lineIdx = $rowIndex - 1 + $state.ScrollRow
  $lineText = GetLine $lineIdx
  if ($null -eq $lineText) {
    return "$(T 'bgGutter')$(T 'fgTilde')   ~ $RESET$(T 'bg')$(' ' * $textWidth)$RESET"
  }

  $isCurrent = ($lineIdx -eq $curRow)
  $lineNumber = ($lineIdx + 1).ToString().PadLeft(4)
  $gutter = if ($isCurrent) {
    "$(T 'bgGutter')$(T 'fgCurNum')${BOLD}$lineNumber$RESET$(T 'bgGutter') $RESET"
  } else {
    "$(T 'bgGutter')$(T 'fgLineNum')$lineNumber$RESET$(T 'bgGutter') $RESET"
  }

  $slice = if ($lineText.Length -gt $textWidth) { $lineText.Substring(0, $textWidth) } else { $lineText }
  $slice = $slice -replace [char]0x1B, '?'
  $bg = if ($isCurrent) { T 'bgLine' } else { T 'bg' }

  $lineOffset = RowColToOffset $lineIdx 0
  $lineEndOff = $lineOffset + $lineText.Length
  $rulerCol = if ($script:ec.max_line_length -gt 0) { $script:ec.max_line_length } else { -1 }
  $lineInSel = $state.SelActive -and ($selA -lt $lineEndOff) -and ($selB -gt $lineOffset)

  if (-not $lineInSel -and ($rulerCol -lt 0 -or $rulerCol -ge $textWidth)) {
    $pad = [Math]::Max(0, $textWidth - $slice.Length)
    return "$gutter$bg$(T 'fgNorm')$slice$(' ' * $pad)$RESET"
  }

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append($gutter); [void]$sb.Append($bg)
  for ($ci = 0; $ci -lt $textWidth; $ci++) {
    $absOff = $lineOffset + $ci
    $ch = if ($ci -lt $slice.Length) { [string]$slice[$ci] } else { ' ' }
    $inSel = $state.SelActive -and $absOff -ge $selA -and $absOff -lt $selB
    if ($inSel) {
      [void]$sb.Append("$(T 'bgSel')$(T 'fgSel')$ch$bg$(T 'fgNorm')")
    } elseif ($rulerCol -ge 0 -and $ci -eq $rulerCol) {
      [void]$sb.Append("$(T 'fgRuler')│$(T 'fgNorm')")
    } else {
      [void]$sb.Append($ch)
    }
  }
  [void]$sb.Append($RESET)
  $sb.ToString()
}

function Render-Frame {
  $width = [Console]::WindowWidth
  $height = [Console]::WindowHeight
  $textWidth = $width - 5

  if ($script:lastRows.Count -ne $height) {
    Reset-RenderShadow
    for ($i = 0; $i -lt $height; $i++) { $script:lastRows.Add('') }
    Out-Flush("`e[2J`e[?25l")
    $script:lastCursorVisible = $false
  }

  $dirty = [System.Text.StringBuilder]::new()
  if (-not $script:lastCursorVisible) {
    [void]$dirty.Append("`e[?25l")
    $script:lastCursorVisible = $true
  }

  for ($row = 0; $row -lt $height; $row++) {
    $rendered = Build-EditorRow $row $width $textWidth
    if ($script:lastRows[$row] -ne $rendered) {
      $script:lastRows[$row] = $rendered
      [void]$dirty.Append((Move-To ($row + 1) 1))
      [void]$dirty.Append($rendered)
    }
  }

  # Cursor screen position derived from buffer offset
  $cr, $cc = OffsetToRowCol $state.Cursor
  $screenRow = $cr - $state.ScrollRow + 2
  $screenCol = $cc + 6
  if ($screenRow -ne $script:lastCursorRow -or $screenCol -ne $script:lastCursorCol) {
    [void]$dirty.Append((Move-To $screenRow $screenCol))
    $script:lastCursorRow = $screenRow
    $script:lastCursorCol = $screenCol
  }

  [void]$dirty.Append("`e[?25h")
  Out-Flush($dirty.ToString())
  $state.Message = ''
}

function Show-Help {
  $width = [Console]::WindowWidth
  $height = [Console]::WindowHeight
  $themeName = $script:themes[$script:themeNames[$script:themeIdx]].name
  $cmdLines = $script:commands | ForEach-Object {
    $pad = ' ' * ([Math]::Max(1, 10 - $_.Key.Length))
    "  $($_.Key)$pad$($_.Label)"
  }
  $lines = @(
    '',
    '  babae  —  keybindings',
    '  ────────────────────────────────────',
    "  Theme now: $themeName",
    ''
  ) + $cmdLines + @(
    '',
    '  Shift+Arrows  Extend selection',
    '  RightClick    Paste from clipboard (Windows)',
    '  Esc           Cancel search / clear selection',
    '',
    '  Press any key to close...',
    ''
  )
  $boxWidth = 52
  $boxHeight = $lines.Count + 2
  $top = [int](($height - $boxHeight) / 2)
  $left = [int](($width - $boxWidth) / 2)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("`e[?25l")
  for ($i = 0; $i -lt $boxHeight; $i++) {
    [void]$sb.Append((Move-To ($top + $i) $left))
    if ($i -eq 0 -or $i -eq ($boxHeight - 1)) {
      [void]$sb.Append("$(T 'bgHeader')$(T 'fgHeader')$(' ' * $boxWidth)$RESET")
      continue
    }
    $text = $lines[$i - 1]
    $pad = [Math]::Max(0, $boxWidth - $text.Length)
    [void]$sb.Append("$(T 'bgLine')$(T 'fgNorm')$text$(' ' * $pad)$RESET")
  }
  $cr, $cc = OffsetToRowCol $state.Cursor
  [void]$sb.Append((Move-To ($cr - $state.ScrollRow + 2) ($cc + 6)))
  [void]$sb.Append("`e[?25h")
  Out-Flush($sb.ToString())
  Read-NextInputEvent | Out-Null  # consume one event to close the help dialog
  Reset-RenderShadow
}

function Search-Execute([string]$term) {
  if ([string]::IsNullOrWhiteSpace($term)) { return }
  $state.LastSearch = $term; $state.SelActive = $false
  $t = BufText
  $ix = $t.IndexOf($term, [Math]::Min($state.Cursor + 1, $t.Length), [StringComparison]::OrdinalIgnoreCase)
  if ($ix -lt 0) { $ix = $t.IndexOf($term, 0, [StringComparison]::OrdinalIgnoreCase) }
  if ($ix -lt 0) { $state.Message = ' Not found '; return }
  $state.SelActive = $true; $state.SelAnchor = $ix
  $state.Cursor = $ix + $term.Length
  $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]
  $state.Message = ' Found '
}

function Handle-EditKey([ConsoleKeyInfo]$keyInfo) {
  $key = $keyInfo.Key
  $ctrl = ($keyInfo.Modifiers -band [ConsoleModifiers]::Control) -ne 0
  $shift = ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift) -ne 0
  $char = $keyInfo.KeyChar

  # ── Ctrl ────────────────────────────────────────────────────────────────
  if ($ctrl) {
    switch ($key) {
      'D1' {
        $script:themeIdx = ($script:themeIdx + 1) % $script:themeNames.Count
        $state.Message = " Theme: $($script:themes[$script:themeNames[$script:themeIdx]].name) "
        Reset-RenderShadow; return
      }
      'S' { State-SaveFile; return }
      'Q' { $state.Mode = 'confirm-quit'; return }
      'Z' { State-Undo; return }
      'Y' { State-Redo; return }
      'F' { $state.Mode = 'search'; $state.SearchBuf = ''; return }
      'A' {
        $state.SelActive = $true; $state.SelAnchor = 0
        $state.Cursor = BufLen
        $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]; return
      }
      'C' {
        $text = Get-SelectionText
        if ([string]::IsNullOrEmpty($text)) { $text = GetLine (OffsetToRowCol $state.Cursor)[0] }
        Set-ClipboardText $text; $state.Message = ' Copied to clipboard '; return
      }
      'V' { Paste-Text (Get-ClipboardText); return }
      'D2' { Show-Help; return }
      'H' {
        if ($state.SelActive) { State-Snapshot; Delete-Selection; return }
        if ($state.Cursor -gt 0) {
          State-Snapshot; $t = BufText
          BufSet ($t.Substring(0, $state.Cursor - 1) + $t.Substring($state.Cursor))
          $state.Cursor--
          $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]; $state.Dirty = $true
        }
        return
      }
    }
    return
  }

  # ── navigation ───────────────────────────────────────────────────────────
  switch ($key) {

    'LeftArrow' {
      if ($state.SelActive -and -not $shift) { $state.Cursor = (SelBounds)[0] }
      elseif ($state.Cursor -gt 0) {
        if ($shift -and -not $state.SelActive) { $state.SelAnchor = $state.Cursor; $state.SelActive = $true }
        $state.Cursor--
      }
      if (-not $shift) { $state.SelActive = $false }
      $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]; return
    }

    'RightArrow' {
      if ($state.SelActive -and -not $shift) { $state.Cursor = (SelBounds)[1] }
      elseif ($state.Cursor -lt (BufLen)) {
        if ($shift -and -not $state.SelActive) { $state.SelAnchor = $state.Cursor; $state.SelActive = $true }
        $state.Cursor++
      }
      if (-not $shift) { $state.SelActive = $false }
      $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]; return
    }

    'UpArrow' {
      if ($shift -and -not $state.SelActive) { $state.SelAnchor = $state.Cursor; $state.SelActive = $true }
      if (-not $shift) { $state.SelActive = $false }
      $row = (OffsetToRowCol $state.Cursor)[0]
      if ($row -gt 0) { $state.Cursor = RowColToOffset ($row - 1) $state.PreferredCol }
      return
    }

    'DownArrow' {
      if ($shift -and -not $state.SelActive) { $state.SelAnchor = $state.Cursor; $state.SelActive = $true }
      if (-not $shift) { $state.SelActive = $false }
      $row = (OffsetToRowCol $state.Cursor)[0]
      $state.Cursor = RowColToOffset ($row + 1) $state.PreferredCol; return
    }

    'Home' {
      if ($shift -and -not $state.SelActive) { $state.SelAnchor = $state.Cursor; $state.SelActive = $true }
      if (-not $shift) { $state.SelActive = $false }
      $state.Cursor = LineStart $state.Cursor; $state.PreferredCol = 0; return
    }

    'End' {
      if ($shift -and -not $state.SelActive) { $state.SelAnchor = $state.Cursor; $state.SelActive = $true }
      if (-not $shift) { $state.SelActive = $false }
      $state.Cursor = LineEnd $state.Cursor
      $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]; return
    }

    'PageUp' {
      $state.SelActive = $false
      $page = [Console]::WindowHeight - 2
      $row = (OffsetToRowCol $state.Cursor)[0]
      $state.Cursor = RowColToOffset ([Math]::Max(0, $row - $page)) $state.PreferredCol; return
    }

    'PageDown' {
      $state.SelActive = $false
      $page = [Console]::WindowHeight - 2
      $row = (OffsetToRowCol $state.Cursor)[0]
      $state.Cursor = RowColToOffset ($row + $page) $state.PreferredCol; return
    }

    # ── editing ─────────────────────────────────────────────────────────────

    'Enter' {
      State-Snapshot
      if ($state.SelActive) { Delete-Selection }
      $curLine = GetLine (OffsetToRowCol $state.Cursor)[0]
      $leadingWS = if ($curLine -match '^(\s+)') { $Matches[1] } else { '' }
      $ins = "`n" + $leadingWS; $t = BufText
      BufSet ($t.Substring(0, $state.Cursor) + $ins + $t.Substring($state.Cursor))
      $state.Cursor += $ins.Length
      $state.PreferredCol = $leadingWS.Length; $state.Dirty = $true; return
    }

    'Backspace' {
      if ($state.SelActive) { State-Snapshot; Delete-Selection; return }
      if ($state.Cursor -gt 0) {
        State-Snapshot; $t = BufText
        BufSet ($t.Substring(0, $state.Cursor - 1) + $t.Substring($state.Cursor))
        $state.Cursor--
        $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]; $state.Dirty = $true
      }
      return
    }

    { $_ -in 'Delete', 'DeleteChar' } {
      if ($state.SelActive) { State-Snapshot; Delete-Selection; return }
      if ($state.Cursor -lt (BufLen)) {
        State-Snapshot; $t = BufText
        BufSet ($t.Substring(0, $state.Cursor) + $t.Substring($state.Cursor + 1))
        $state.Dirty = $true
      }
      return
    }

    'Tab' {
      State-Snapshot
      if ($state.SelActive) { Delete-Selection }
      $ins = Get-IndentString; $t = BufText
      BufSet ($t.Substring(0, $state.Cursor) + $ins + $t.Substring($state.Cursor))
      $state.Cursor += $ins.Length
      $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]; $state.Dirty = $true; return
    }

    'Escape' { $state.SelActive = $false; return }
  }

  # ── printable char ───────────────────────────────────────────────────────
  if ([int]$char -ge 32 -and [int]$char -ne 127) {
    State-Snapshot
    if ($state.SelActive) { Delete-Selection }
    $t = BufText
    BufSet ($t.Substring(0, $state.Cursor) + $char + $t.Substring($state.Cursor))
    $state.Cursor++
    $state.PreferredCol = (OffsetToRowCol $state.Cursor)[1]; $state.Dirty = $true
  }
}

function Handle-SearchKey([ConsoleKeyInfo]$keyInfo) {
  switch ($keyInfo.Key) {
    'Escape' { $state.Mode = 'edit'; $state.SearchBuf = ''; return }
    'Enter' { $state.Mode = 'edit'; Search-Execute $state.SearchBuf; return }
    'Backspace' { if ($state.SearchBuf.Length -gt 0) { $state.SearchBuf = $state.SearchBuf.Substring(0, $state.SearchBuf.Length - 1) }; return }
    default {
      if ($keyInfo.KeyChar -ne [char]0 -and -not [char]::IsControl($keyInfo.KeyChar)) { $state.SearchBuf += [string]$keyInfo.KeyChar }
    }
  }
}

function Handle-ConfirmQuitKey([ConsoleKeyInfo]$keyInfo) {
  switch ($keyInfo.Key) {
    'Y' { $script:running = $false }
    { $_ -in 'N', 'Escape' } { $state.Mode = 'edit'; $state.Message = ' Quit cancelled '; Reset-RenderShadow }
    default { $state.Message = ' Unsaved! Y = quit   N / Esc = cancel ' }
  }
}

function Render-ConfirmQuit {
  $width = [Console]::WindowWidth
  $height = [Console]::WindowHeight
  $message = '  Unsaved changes — quit anyway?  [Y / N]  '
  $boxWidth = $message.Length + 2
  $top = [int](($height - 3) / 2)
  $left = [int](($width - $boxWidth) / 2)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append((Move-To $top $left))
  [void]$sb.Append("$(T 'bgHeader')$(T 'fgHeader')$(' ' * $boxWidth)$RESET")
  [void]$sb.Append((Move-To ($top + 1) $left))
  [void]$sb.Append("$(T 'bgHeader')$(T 'fgHeader')$message$(' ' * ($boxWidth - $message.Length))$RESET")
  [void]$sb.Append((Move-To ($top + 2) $left))
  [void]$sb.Append("$(T 'bgHeader')$(T 'fgHeader')$(' ' * $boxWidth)$RESET")
  Out-Flush($sb.ToString())
}

function Edit-Babae {
  [CmdletBinding()]
  param([Parameter(Position = 0)][string]$Path)

  State-Reset
  Reset-RenderShadow

  if ($Path) {
    $resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
    $state.FilePath = if ($resolved) { $resolved.Path } else { Join-Path $PWD $Path }
    State-LoadFile $state.FilePath
    Load-EditorConfig $state.FilePath
  } else {
    BufSet ''
    Load-EditorConfig ''
  }

  $oldCtrlC = [Console]::TreatControlCAsInput
  [Console]::TreatControlCAsInput = $true
  if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {
    try { stty raw -echo -ixon -isig -icanon 2>/dev/null } catch {}
  }
  # Enable bracketed paste mode (ESC[?2004h).  With this the terminal wraps
  # every right-click / middle-click paste in ESC[200~...ESC[201~ sentinels.
  # Our raw stdin reader picks those up and routes the payload directly to
  # Paste-Text, bypassing the Enter handler and its auto-indent injection.
  Out-Flush("`e[2J`e[H`e[?25l`e[?2004h")

  $prevWidth = 0
  $prevHeight = 0
  $script:running = $true

  try {
    while ($script:running) {
      $width = [Console]::WindowWidth
      $height = [Console]::WindowHeight
      if ($width -ne $prevWidth -or $height -ne $prevHeight) {
        $prevWidth = $width
        $prevHeight = $height
        Reset-RenderShadow
      }

      Update-Scroll
      Render-Frame

      # Windows-only: poll for right-click paste via Win32 mouse events.
      if ($script:mouseEnabled -and -not (Stdin-DataAvailable)) {
        if ([BabaeWin]::PollRightClick($script:consoleHandle)) {
          Paste-Text (Get-ClipboardText)
          continue
        }
        Start-Sleep -Milliseconds $script:frameDelayMs
        continue
      }

      # Non-blocking: skip Read-NextInputEvent when nothing is waiting.
      if (-not (Stdin-DataAvailable)) {
        Start-Sleep -Milliseconds $script:frameDelayMs
        continue
      }

      # Read one complete input event (key or paste) from raw stdin.
      $event = Read-NextInputEvent

      if ($event.Kind -eq 'Paste') {
        Paste-Text $event.Text
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
    if ($script:mouseEnabled) {
      try { [BabaeWin]::SetModeValue($script:consoleHandle, $script:origConsoleMode) } catch {}
    }
    [Console]::TreatControlCAsInput = $oldCtrlC
    if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {
      try { stty sane 2>/dev/null } catch {}
    }
    # Disable bracketed paste mode before handing the terminal back.
    Out-Flush("`e[?2004l`e[?25h`e[2J`e[H`e[0m")
    Write-Host 'babae: session ended.' -ForegroundColor Cyan
    if ($state.FilePath) { Write-Host "File : $($state.FilePath)" -ForegroundColor DarkGray }
  }
}

Set-Alias -Name babae -Value Edit-Babae -Scope Global
Edit-Babae @PSBoundParameters
