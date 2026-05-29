import re
import sys

def apply_all(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # --- 1. Params ---
    content = content.replace(
        '[string]$Theme = "dark"',
        '[string]$Theme = "dark",\n  [switch]$DiagPane,\n  [switch]$DebugLog'
    )

    # --- 2. Constants & State ---
    # Insert after OutputEncoding
    globals_block = r"""
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
"""
    content = content.replace('[Console]::InputEncoding = [System.Text.Encoding]::UTF8',
                              '[Console]::InputEncoding = [System.Text.Encoding]::UTF8' + globals_block)

    # --- 3. DebugLog Fix ---
    content = re.sub(r'\$script:debugLog = \$null\s+if \(\$DebugLog\.IsPresent\) \{.*?\}',
                     r"$script:debugLog = $null\nif ($DebugLog.IsPresent) {\n  $script:debugLog = Join-Path . 'babae-debug.log'\n}",
                     content, flags=re.DOTALL)
    content = content.replace('Write-Host $script:debugLog', '')

    # --- 4. DiagLog Utility ---
    diag_funcs = r"""
function Write-DiagLog([string]$category, [string]$message) {
  if ($null -eq $script:diagRingBuffer) {
    $script:diagRingBuffer = [System.Collections.Generic.Queue[string]]::new()
  }
  $line = "[{0}] [{1}] {2}" -f ([DateTimeOffset]::UtcNow.ToString('HH:mm:ss.fff')), $category.ToUpperInvariant(), $message
  $script:diagRingBuffer.Enqueue($line) | Out-Null
  while ($script:diagRingBuffer.Count -gt $script:diagLogMaxEntries) { [void]$script:diagRingBuffer.Dequeue() }
  if ($script:debugLog) {
    try {
      Add-Content -LiteralPath $script:debugLog -Value $line -Encoding UTF8
    } catch {}
  }
}

function Write-DebugLog([string]$message) {
"""
    content = content.replace('function Write-DebugLog([string]$message) {', diag_funcs)

    # --- 5. Line Indexing & Buffer Helpers ---
    content = content.replace('$script:lastRows = [System.Collections.Generic.List[string]]::new()',
                              '$script:lastRows = [System.Collections.Generic.List[string]]::new()\n$script:lineIndex = @(0)')

    buffer_logic = r"""
function Rebuild-LineIndex {
  $text = $state.Buffer.ToString()
  $starts = [System.Collections.Generic.List[int]]::new()
  $starts.Add(0)
  for ($i = 0; $i -lt $text.Length; $i++) {
    if ($text[$i] -eq "`n") { $starts.Add($i + 1) }
  }
  $script:lineIndex = $starts.ToArray()
}

function Find-LineRow([int]$offset) {
  $idx = $script:lineIndex
  if ($null -eq $idx -or $idx.Length -eq 0) { return 0 }
  $lo = 0; $hi = $idx.Length - 1
  while ($lo -le $hi) {
    $mid = [int](($lo + $hi) / 2)
    if ($idx[$mid] -le $offset) {
      if ($mid -eq ($idx.Length - 1) -or $idx[$mid + 1] -gt $offset) { return $mid }
      $lo = $mid + 1
    } else { $hi = $mid - 1 }
  }
  return 0
}

function BufSet([string]$text) {
  $state.Buffer.Clear() | Out-Null
  if ($text) { $state.Buffer.Append($text) | Out-Null }
  Rebuild-LineIndex
}

function BufText { $state.Buffer.ToString() }
"""
    content = re.sub(r'function BufText \{.*?\}', buffer_logic, content, flags=re.DOTALL)
    content = content.replace('function BufLen { $state.Buffer.Length }', 'function BufLen { return $state.Buffer.Length }')

    # Update OffsetToRowCol
    content = re.sub(r'function OffsetToRowCol\(\[int\]\$offset\) \{.*?return \$row, \(\$off - \$ls\)\n\}',
                     r'function OffsetToRowCol([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  $row = Find-LineRow $off\n  return $row, ($off - $script:lineIndex[$row])\n}',
                     content, flags=re.DOTALL)

    # Update LineStart
    content = re.sub(r'function LineStart\(\[int\]\$offset\) \{.*?return \$offset\n\}',
                     r'function LineStart([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  return $script:lineIndex[(Find-LineRow $off)]\n}',
                     content, flags=re.DOTALL)

    # Update LineEnd
    content = re.sub(r'function LineEnd\(\[int\]\$offset\) \{.*?return \$offset\n\}',
                     r'function LineEnd([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  $row = Find-LineRow $off\n  if ($row -lt ($script:lineIndex.Length - 1)) { return ($script:lineIndex[$row + 1] - 1) }\n  return (BufLen)\n}',
                     content, flags=re.DOTALL)

    # Update GetLine
    content = re.sub(r'function GetLine\(\[int\]\$n\) \{.*?return \$null\n\}',
                     r'function GetLine([int]$n) {\n  if ($n -lt 0 -or $n -ge $script:lineIndex.Length) { return $null }\n  $start = $script:lineIndex[$n]\n  $end = if ($n -lt ($script:lineIndex.Length - 1)) { $script:lineIndex[$n + 1] - 1 } else { (BufLen) }\n  return (BufText).Substring($start, $end - $start)\n}',
                     content, flags=re.DOTALL)

    # Update RowColToOffset
    content = re.sub(r'function RowColToOffset\(\[int\]\$row, \[int\]\$col\) \{.*?return \$t\.Length\s+\}',
                     r'function RowColToOffset([int]$row, [int]$col) {\n  if ($script:lineIndex.Length -eq 0) { return 0 }\n  $row = [Math]::Max(0, [Math]::Min($row, $script:lineIndex.Length - 1))\n  $start = $script:lineIndex[$row]\n  $end = if ($row -lt ($script:lineIndex.Length - 1)) { $script:lineIndex[$row + 1] - 1 } else { (BufLen) }\n  return $start + [Math]::Max(0, [Math]::Min($col, $end - $start))\n}',
                     content, flags=re.DOTALL)

    # Update LineCount
    content = re.sub(r'function LineCount \{.*?Count\n\}',
                     r'function LineCount { return [Math]::Max(1, $script:lineIndex.Length) }',
                     content, flags=re.DOTALL)

    # --- 6. UI & Pane ---
    content = content.replace("[PSCustomObject]@{ Key = '^T'; Label = 'Theme' }",
                              "[PSCustomObject]@{ Key = '^T'; Label = 'Theme' }\n  [PSCustomObject]@{ Key = '^D'; Label = 'Diag' }")

    diag_ui = r"""
function Build-DiagRow([int]$rowIndex, [int]$screenWidth) {
  if ($rowIndex -eq ($script:diagDividerRow - 1)) {
    $plain = " DIAG | $($script:diagRingBuffer.Count) events | drag to resize | Ctrl+D hide "
    $pad = [Math]::Max(0, $screenWidth - $plain.Length)
    return "$(T 'bgBar')$(T 'fgAccent')${BOLD} DIAG $RESET$(T 'bgBar')$(T 'fgMuted')| $($script:diagRingBuffer.Count) events | drag to resize | Ctrl+D hide$(' ' * $pad)$RESET"
  }
  $entries = @($script:diagRingBuffer.ToArray())
  $paneLine = $rowIndex - $script:diagDividerRow
  $start = [Math]::Max(0, $entries.Count - $script:diagPaneHeight - $script:diagScrollOffset)
  $idx = $start + $paneLine - 1
  $text = if ($idx -ge 0 -and $idx -lt $entries.Count) { $entries[$idx] } else { '' }
  if ($text.Length -gt $screenWidth) { $text = $text.Substring(0, $screenWidth) }
  $pad = [Math]::Max(0, $screenWidth - $text.Length)
  return "$(T 'bg')$(T 'fgMuted')$text$(' ' * $pad)$RESET"
}

function Handle-DiagMouseDrag([int]$mouseRow) {
  $height = [Console]::WindowHeight
  $maxDiag = [Math]::Floor(($height - 4) / 2)
  if ($maxDiag -le 0) { return }
  $minDiag = [Math]::Min($script:diagPaneMinHeight, $maxDiag)
  $newHeight = [Math]::Max($minDiag, [Math]::Min($height - $mouseRow - 1, $maxDiag))
  if ($newHeight -ne $script:diagPaneHeight) {
    $script:diagPaneHeight = $newHeight
    Reset-RenderShadow
  }
}
"""
    content = content.replace('function Render-Frame {', diag_ui + '\nfunction Render-Frame {')

    render_frame_new = r"""function Render-Frame {
  $width = [Console]::WindowWidth; $height = [Console]::WindowHeight; $textWidth = $width - 5
  if ($script:diagPaneVisible) {
    $maxDiag = [Math]::Floor(($height - 4) / 2)
    if ($maxDiag -le 0) { $script:diagPaneVisible = $false; $script:diagDividerRow = -1 }
    else {
      $minDiag = [Math]::Min($script:diagPaneMinHeight, $maxDiag)
      $script:diagPaneHeight = [Math]::Max($minDiag, [Math]::Min($script:diagPaneHeight, $maxDiag))
      $script:diagDividerRow = $height - 1 - $script:diagPaneHeight
    }
  } else { $script:diagDividerRow = -1 }

  if ($script:lastRows.Count -ne $height) {
    $script:lastRows.Clear(); for ($i = 0; $i -lt $height; $i++) { $script:lastRows.Add('') }
  }
  $dirty = [System.Text.StringBuilder]::new()
  for ($row = 0; $row -lt $height; $row++) {
    if ($script:diagPaneVisible -and $row -ge ($script:diagDividerRow - 1) -and $row -lt ($height - 1)) {
      $rendered = Build-DiagRow $row $width
    } else { $rendered = Build-EditorRow $row $width $textWidth }
    if ($script:lastRows[$row] -ne $rendered) {
      $script:lastRows[$row] = $rendered; [void]$dirty.Append((Move-To ($row + 1) 1)); [void]$dirty.Append($rendered)
    }
  }
  $curR, $curC = OffsetToRowCol $state.Cursor
  $vRow = ($curR - $state.ScrollRow) + 1; $vCol = $curC + 6
  if ($vRow -ge 1 -and $vRow -lt ($height - ($script:diagPaneVisible ? $script:diagPaneHeight + 1 : 0))) {
    [void]$dirty.Append((Move-To $vRow $vCol))
    if (-not $script:lastCursorVisible) { [void]$dirty.Append("`e[?25h"); $script:lastCursorVisible = $true }
  } else {
    if ($script:lastCursorVisible) { [void]$dirty.Append("`e[?25l"); $script:lastCursorVisible = $false }
  }
  Out-Flush $dirty.ToString()
}"""
    content = re.sub(r'function Render-Frame \{.*?Out-Flush \$dirty\.ToString\(\)\n\}', render_frame_new, content, flags=re.DOTALL)

    content = content.replace("'T' {", r"""'D' {
        $script:diagPaneVisible = -not $script:diagPaneVisible
        if ($script:diagPaneVisible) {
          if ($script:diagPaneHeight -lt 1) { $script:diagPaneHeight = $script:diagDefaultHeight }
          Write-DiagLog 'INFO' 'Diagnostic pane enabled.'
          $state.Message = ' Diagnostics on '
        } else {
          $script:diagDragging = $false
          $state.Message = ' Diagnostics off '
        }
        Reset-RenderShadow; return
      }
      'T' {""")

    # --- 7. Input Handling ---
    content = content.replace('$script:inputBuf      = [byte[]]::new(4096)', '$script:inputBuf      = [byte[]]::new($script:inputBufSize)')

    input_block = r"""function Try-ParseMouseSequence([string]$seq) {
  if ($seq -notmatch '^\[<(\d+);(\d+);(\d+)([Mm])$') { return $null }
  $buttonCode = [int]$Matches[1]; $x = [int]$Matches[2]; $y = [int]$Matches[3]; $suffix = $Matches[4]
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
}

function Start-InputThread {
  if ([Console]::IsInputRedirected) { return }
  $script:inputThread = [PowerShell]::Create().AddScript({
    param($q)
    try {
      while ($true) {
        if ([Console]::KeyAvailable) {
          $ki = [Console]::ReadKey($true)
          $q.Enqueue($ki) | Out-Null
        } else {
          [System.Threading.Thread]::Sleep(10)
        }
      }
    } catch {
      $q.Enqueue([PSCustomObject]@{ Kind = 'Diag'; Message = $_.Exception.Message }) | Out-Null
    }
  }).AddArgument($script:inputQueue)
  $script:inputHandle = $script:inputThread.BeginInvoke()
}

function Stop-InputThread {
  if ($null -ne $script:inputThread) {
    try { $script:inputThread.Stop() } catch { Write-DiagLog 'INPUT' "Input thread stop failed: $($_.Exception.Message)" }
    try { $script:inputThread.Dispose() } catch { Write-DiagLog 'INPUT' "Input thread dispose failed: $($_.Exception.Message)" }
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
  while ($true) {
    $ki = $null
    while (-not $script:inputQueue.TryDequeue([ref]$ki)) {
      if (-not $script:running) { return $null }
      [System.Threading.Thread]::Sleep(10)
    }
    if ($ki -is [pscustomobject] -and $ki.Kind -eq 'Diag') {
      Write-DiagLog 'INPUT' "Input thread failed: $($ki.Message)"
      continue
    }
    if ([int]$ki.KeyChar -eq 8) {
      if ($ki.Key -eq [System.ConsoleKey]::Backspace) {
        return Make-KeyInfo ([char]8) ([System.ConsoleKey]::Backspace) 0
      }
      return Make-KeyInfo ([char]8) ([System.ConsoleKey]::H) ([System.ConsoleModifiers]::Control)
    }
    return $ki
  }
}

function Read-NextInputEvent {
  if (-not [Console]::IsInputRedirected) {
    $ki = Stdin-ReadKey
    if ($null -eq $ki) { return $null }
    if ($ki.Key -eq [System.ConsoleKey]::Escape) {
      $seq = ""
      $seqBufKeys = [System.Collections.Generic.List[object]]::new()
      $waited = 0
      while ($seq.Length -lt $script:maxSeqLen -and $waited -lt $script:escapeTimeoutMs) {
        $nki = $null
        if ($script:inputQueue.TryDequeue([ref]$nki)) {
          if ($nki -is [pscustomobject] -and $nki.Kind -eq 'Diag') { continue }
          $seq += [string]$nki.KeyChar
          $seqBufKeys.Add($nki) | Out-Null
          if ($seq -eq '[200~') { return [PSCustomObject]@{ Kind = 'Paste'; Text = Stdin-DrainPasteInteractive } }
          $mouseEvent = Try-ParseMouseSequence $seq
          if ($null -ne $mouseEvent) { return $mouseEvent }
          $parsed = Parse-EscapeSequence $seq
          if ($parsed.Key -ne [System.ConsoleKey]::NoName) { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = $parsed } }
          $couldContinue = '[200~'.StartsWith($seq) -or '['.StartsWith($seq) -or '[<'.StartsWith($seq) -or ($seq -match '^\[<[\d;]*$')
          if (-not $couldContinue) {
            foreach ($k in $seqBufKeys) { $script:inputPendingKeys.Enqueue($k) | Out-Null }
            break
          }
        } else {
          [System.Threading.Thread]::Sleep(5); $waited += 5
        }
      }
      return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
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
      while ($script:inputPending.Count -eq 0 -and $w -lt 50) { Start-Sleep -Milliseconds 5; $w += 5; Stdin-PeekAvailable }
    }
    if ($script:inputPending.Count -eq 0) { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) } }
    $seqBuf = [System.Text.StringBuilder]::new(); [void]$seqBuf.Append([char]27)
    while ($script:inputPending.Count -gt 0 -and $seqBuf.Length -lt $script:maxSeqLen) {
      $nb = Stdin-ReadByte; if ($nb -eq -1) { break }; $nc = [char]$nb; [void]$seqBuf.Append($nc)
      $seq = $seqBuf.ToString().Substring(1)
      if ($seq -eq '[200~') { return [PSCustomObject]@{ Kind = 'Paste'; Text = Stdin-DrainPaste } }
      $mouseEvent = Try-ParseMouseSequence $seq; if ($null -ne $mouseEvent) { return $mouseEvent }
      $ki = Parse-EscapeSequence $seq; if ($ki.Key -ne [System.ConsoleKey]::NoName) { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = $ki } }
      $couldContinue = ($seq.Length -eq 1 -and ($seq -eq '[' -or $seq -eq 'O')) `
                    -or '[200~'.StartsWith($seq) `
                    -or $seq -eq '[<' `
                    -or $seq -match '^\[<[\d;]*[Mm]?$' `
                    -or ($seq.Length -gt 1 -and $seq[0] -eq '[' -and ($nc -match '[0-9;]'))
      if (-not $couldContinue) { break }
    }
    return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
  }
  $ch = [char]$b; $ck = try { [System.ConsoleKey]$ch.ToString().ToUpper() } catch { [System.ConsoleKey]::NoName }
  return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo $ch $ck 0) }
}
"""
    content = re.sub(r'function Start-InputThread \{.*?function Read-NextInputEvent \{.*?return \[PSCustomObject\]@\{ Kind=\'Key\'; KeyInfo=\(Make-KeyInfo \$ch \$ck 0\) \}\n\}',
                     input_block, content, flags=re.DOTALL)

    # Main Loop
    main_loop_block = r"""      # Read one complete input event (key or paste) from raw stdin.
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
      } else {"""
    content = re.sub(r'\s+# Read one complete input event.*?if \(\$event\.Kind -eq \'Paste\'\) \{.*?\} else \{',
                     main_loop_block, content, flags=re.DOTALL)

    # --- 8. Mutation points ---
    content = content.replace("$state.Buffer.Remove($a, $b - $a) | Out-Null",
                              "$state.Buffer.Remove($a, $b - $a) | Out-Null; Rebuild-LineIndex")
    content = content.replace("$state.Buffer.Insert($state.Cursor, $text) | Out-Null",
                              "$state.Buffer.Insert($state.Cursor, $text) | Out-Null; Rebuild-LineIndex")
    content = content.replace("$state.Buffer.Append($ch) | Out-Null",
                              "$state.Buffer.Append($ch) | Out-Null; Rebuild-LineIndex")
    content = content.replace("$state.Buffer.Insert($state.Cursor, $ki.KeyChar) | Out-Null",
                              "$state.Buffer.Insert($state.Cursor, $ki.KeyChar) | Out-Null; Rebuild-LineIndex")

    # --- 9. Terminal Setup & Cleanup ---
    content = content.replace('`e[?1049h`e[?2004h`e[?25l`e[2J`e[H',
                              '`e[?1049h`e[?2004h`e[?1000h`e[?1003h`e[?1006h`e[?25l`e[2J`e[H')
    content = content.replace('`e[?2004l`e[?1049l`e[?25h`e[0m',
                              '`e[?1006l`e[?1003l`e[?1000l`e[?2004l`e[?1049l`e[?25h`e[0m')

    # Initial state in Main
    content = content.replace('$script:isUnix = $IsLinux -or $IsMacOS',
                              '$script:diagPaneVisible = $DiagPane.IsPresent\n  $script:diagPaneHeight = $script:diagDefaultHeight\n  $script:isUnix = $IsLinux -or $IsMacOS')

    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    apply_all(sys.argv[1])
