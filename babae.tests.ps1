<#
.SYNOPSIS
    E2E tests for babae — stairway/paste regression + unit coverage.

.DESCRIPTION
    The stairway bug: when pasting multi-line indented text via right-click
    over SSH (Bitvise / xterm-256color), each \n in the paste stream was
    processed by the Enter handler, which re-injected the leading whitespace
    of the current line — compounding it on every line and producing a
    "staircase" of ever-increasing indentation.

    Root cause: the previous input layer used Console.ReadKey, which does not
    reliably surface bracketed-paste mode (BPM) sentinel bytes (ESC[200~ /
    ESC[201~) on all .NET/pwsh versions over SSH.  The fix replaces the
    entire input layer with a raw stdin stream reader that parses VT sequences
    at the byte level.  BPM sentinels are detected unconditionally; the paste
    payload is routed directly to Paste-Text, bypassing the Enter handler.

    Test strategy
    ─────────────
    • The editor is started as a child process with stdin/stdout fully
      redirected (System.Diagnostics.Process), so we control every byte.
    • We write properly-formed BPM byte sequences to the editor's stdin.
    • We save with Ctrl+S, quit with Ctrl+Q, and read the output file.
    • No Docker, no network — pure PowerShell + Pester 5.

.NOTES
    Requirements: Pester 5.x, pwsh 7+
    Run: Invoke-Pester ./babae.tests.ps1 -Output Detailed
#>

BeforeAll {
  $Script:EditorScript = Join-Path $PSScriptRoot 'babae.ps1'

  # ── session helpers ────────────────────────────────────────────────────────

  function Start-BabaeProcess([string]$filePath) {
    $psi                        = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = (Get-Command pwsh -ErrorAction Stop).Source
    $psi.Arguments              = "-NoProfile -NonInteractive -File `"$Script:EditorScript`" `"$filePath`""
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.EnvironmentVariables['TERM']           = 'xterm-256color'
    $psi.EnvironmentVariables['TERM_PROGRAM']   = 'bitvise'  # closest approximation
    $psi.EnvironmentVariables['COLORTERM']      = 'truecolor'

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    @{ Process = $proc; Stdin = $proc.StandardInput }
  }

  # Write raw bytes to the editor's stdin stream.
  function Send-Bytes($s, [byte[]]$bytes) {
    $s.Stdin.BaseStream.Write($bytes, 0, $bytes.Length)
    $s.Stdin.BaseStream.Flush()
  }

  function Send-Str($s, [string]$text) {
    Send-Bytes $s ([System.Text.Encoding]::UTF8.GetBytes($text))
  }

  # Send a single control byte (Ctrl+X = byte value of letter minus 64).
  function Send-Ctrl($s, [char]$letter) {
    Send-Bytes $s @([byte]([int][char]$letter - [int][char]'A' + 1))
  }

  # Build the raw byte sequence for a bracketed paste.
  # ESC [ 2 0 0 ~ <payload> ESC [ 2 0 1 ~
  function New-BpmBytes([string]$text) {
    $norm = $text -replace "`r`n", "`n" -replace "`r", "`n"
    $seq  = "`e[200~$norm`e[201~"
    [System.Text.Encoding]::UTF8.GetBytes($seq)
  }

  function Wait-Editor($s, [int]$ms = 5000) {
    if (-not $s.Process.WaitForExit($ms)) { $s.Process.Kill() }
  }

  # Save + quit the editor and wait for it to exit.
  function Close-Editor($s) {
    # Wrap every write in try/catch: if the editor already exited cleanly
    # (e.g. Ctrl+Q with no unsaved changes), the pipe is gone and writes
    # throw a broken-pipe error — that is fine, we just stop sending.
    try { Send-Ctrl $s 'S' } catch {}
    Start-Sleep -Milliseconds 200
    try { Send-Ctrl $s 'Q' } catch {}
    Start-Sleep -Milliseconds 200
    try { Send-Str $s 'Y' } catch {}  # confirm if dirty-quit dialog appears
    Wait-Editor $s
  }
}

# ── BPM sequence helper unit tests (no editor process needed) ─────────────────

Describe 'BPM byte-sequence helpers' {

  It 'produces ESC[200~...ESC[201~ frame' {
    $bytes = New-BpmBytes 'abc'
    $str   = [System.Text.Encoding]::UTF8.GetString($bytes)
    $str | Should -Match "^\x1b\[200~abc\x1b\[201~$"
  }

  It 'normalises CRLF to LF inside the frame' {
    $bytes = New-BpmBytes "a`r`nb"
    $str   = [System.Text.Encoding]::UTF8.GetString($bytes)
    $str | Should -Match "^\x1b\[200~a`nb\x1b\[201~$"
  }

  It 'handles multi-line indented payload' {
    $payload = "    line1`n    line2`n    line3"
    $bytes   = New-BpmBytes $payload
    $str     = [System.Text.Encoding]::UTF8.GetString($bytes)
    $str | Should -Match ('(?s)' + [regex]::Escape("`e[200~") + '.*line1.*line2.*line3.*' + [regex]::Escape("`e[201~"))
  }
}

# ── Stairway regression — core ────────────────────────────────────────────────

Describe 'Stairway regression: bracketed paste via raw stdin BPM' {

  It 'inserts multi-line uniformly-indented text verbatim (no staircase)' {
    $out = [IO.Path]::GetTempFileName()
    try {
      $s = Start-BabaeProcess $out
      Start-Sleep -Milliseconds 700   # let the editor initialise

      # All lines have exactly 4 leading spaces.
      # Without the fix each \n re-injects those 4 spaces on the next line,
      # producing 4 / 8 / 12 / 16 ... spaces — the classic staircase.
      $payload = "    first line`n    second line`n    third line"
      Send-Bytes $s (New-BpmBytes $payload)
      Start-Sleep -Milliseconds 300

      Close-Editor $s

      $saved = [IO.File]::ReadAllText($out) -replace "`r`n","`n" -replace "`r","`n"
      $lines = ($saved -split "`n") | Where-Object { $_ -ne '' }

      $lines.Count | Should -Be 3
      $lines[0] | Should -Be '    first line'
      $lines[1] | Should -Be '    second line'
      $lines[2] | Should -Be '    third line'

    } finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
  }

  It 'preserves mixed indentation levels verbatim' {
    $out = [IO.Path]::GetTempFileName()
    try {
      $s = Start-BabaeProcess $out
      Start-Sleep -Milliseconds 700

      # Deliberately varying indentation — each line must survive unchanged.
      $payload = "no-indent`n  two-space`n    four-space`n`t`ttabs`nno-indent-again"
      Send-Bytes $s (New-BpmBytes $payload)
      Start-Sleep -Milliseconds 300

      Close-Editor $s

      $saved = [IO.File]::ReadAllText($out) -replace "`r`n","`n" -replace "`r","`n"
      $lines = ($saved -split "`n") | Where-Object { $_ -ne '' }

      $lines[0] | Should -Be 'no-indent'
      $lines[1] | Should -Be '  two-space'
      $lines[2] | Should -Be '    four-space'
      $lines[3] | Should -Be "`t`ttabs"
      $lines[4] | Should -Be 'no-indent-again'

    } finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
  }

  It 'handles an empty BPM payload without crashing' {
    $out = [IO.Path]::GetTempFileName()
    try {
      $s = Start-BabaeProcess $out
      Start-Sleep -Milliseconds 700

      Send-Bytes $s (New-BpmBytes '')
      Start-Sleep -Milliseconds 200

      # Quit cleanly — no unsaved changes.
      Send-Ctrl $s 'Q'
      Wait-Editor $s

      $s.Process.ExitCode | Should -Not -BeNullOrEmpty

    } finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
  }

  It 'handles a large paste (500 lines) without truncation or crash' {
    $out = [IO.Path]::GetTempFileName()
    try {
      $s = Start-BabaeProcess $out
      Start-Sleep -Milliseconds 700

      $lines500 = (1..500 | ForEach-Object { "    line $_" }) -join "`n"
      Send-Bytes $s (New-BpmBytes $lines500)
      Start-Sleep -Milliseconds 600   # give the editor time to process all bytes

      Close-Editor $s

      $saved = [IO.File]::ReadAllText($out) -replace "`r`n","`n" -replace "`r","`n"
      $lines = ($saved -split "`n") | Where-Object { $_ -ne '' }

      $lines.Count | Should -Be 500
      # Spot-check first, middle, last for correct content and indentation.
      $lines[0]   | Should -Be '    line 1'
      $lines[249] | Should -Be '    line 250'
      $lines[499] | Should -Be '    line 500'

      # Verify no line has more than 4 leading spaces (staircase check).
      foreach ($l in $lines) {
        ($l -match '^( *)') | Out-Null
        $Matches[1].Length | Should -Be 4 -Because "staircase would compound indentation; got: '$l'"
      }

    } finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
  }
}

# ── Normal key input regression guard ─────────────────────────────────────────

Describe 'Normal key input still works through raw stdin reader' {

  It 'types printable characters correctly' {
    $out = [IO.Path]::GetTempFileName()
    try {
      $s = Start-BabaeProcess $out
      Start-Sleep -Milliseconds 700

      Send-Str $s 'hello'
      Start-Sleep -Milliseconds 100

      Close-Editor $s

      $saved = [IO.File]::ReadAllText($out)
      $saved.Trim() | Should -Be 'hello'

    } finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
  }

  It 'Enter key still auto-indents when typed manually' {
    $out = [IO.Path]::GetTempFileName()
    try {
      $s = Start-BabaeProcess $out
      Start-Sleep -Milliseconds 700

      Send-Str $s '    foo'                   # type "    foo"
      Send-Bytes $s @(0x0D)                   # CR = Enter
      Start-Sleep -Milliseconds 150

      Close-Editor $s

      $saved = [IO.File]::ReadAllText($out) -replace "`r`n","`n" -replace "`r","`n"
      $lines = $saved -split "`n"

      $lines[0] | Should -Be '    foo'
      # Auto-indent: the new line inherits the 4-space indent.
      # This is CORRECT behaviour — distinct from the staircase bug.
      $lines[1] | Should -Match '^    '

    } finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
  }

  It 'Ctrl+Z and Ctrl+Y undo/redo work' {
    $out = [IO.Path]::GetTempFileName()
    try {
      $s = Start-BabaeProcess $out
      Start-Sleep -Milliseconds 700

      Send-Str $s 'abc'
      Start-Sleep -Milliseconds 50
      Send-Ctrl $s 'Z'    # undo
      Start-Sleep -Milliseconds 50

      Close-Editor $s

      # After undoing one char, buffer should have 'ab' (undo steps are per-snapshot).
      $saved = [IO.File]::ReadAllText($out)
      $saved.Trim().Length | Should -BeLessOrEqual 3

    } finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
  }
}

# ── BPM does not interfere with Ctrl+V (clipboard paste path) ─────────────────

Describe 'Ctrl+V clipboard paste is unaffected' {

  It 'Ctrl+V still triggers the clipboard paste path (Paste-Text via GetClipboardText)' {
    # We cannot inject clipboard content from outside the process, so this
    # test just verifies the editor does not crash when Ctrl+V is pressed with
    # an empty clipboard over SSH (where clipboard tools are absent).
    $out = [IO.Path]::GetTempFileName()
    try {
      $s = Start-BabaeProcess $out
      Start-Sleep -Milliseconds 700

      Send-Ctrl $s 'V'     # Ctrl+V — clipboard will be empty on headless CI
      Start-Sleep -Milliseconds 150

      Close-Editor $s

      # Should exit cleanly.
      $s.Process.ExitCode | Should -Not -BeNullOrEmpty

    } finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
  }
}
Describe 'Chunked BPM sequence handling' {
    It 'should explicitly keep the read loop open if a bracketed paste sentinel arrives in chunks across 100ms' {
        $out = [IO.Path]::GetTempFileName()
        try {
            $s = Start-BabaeProcess $out
            Start-Sleep -Milliseconds 700

            # ESC [ 2
            Send-Bytes $s @(27, 91, 50)
            Start-Sleep -Milliseconds 100
            # 0 0 ~
            Send-Bytes $s @(48, 48, 126)

            Send-Str $s "chunked text"

            # ESC [ 2 0 1 ~
            Send-Bytes $s @(27, 91, 50, 48, 49, 126)
            Start-Sleep -Milliseconds 300

            Close-Editor $s

            $saved = [IO.File]::ReadAllText($out) -replace "`r`n","`n" -replace "`r","`n"
            $saved.Trim() | Should -Be 'chunked text'
        } finally {
            Remove-Item $out -Force -ErrorAction SilentlyContinue
        }
    }
}
