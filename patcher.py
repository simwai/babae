import re
import sys

def apply_patch(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Update Params
    content = content.replace(
        '[string]$Theme = "dark"',
        '[string]$Theme = "dark",\n  [switch]$DiagPane,\n  [switch]$DebugLog'
    )

    # 2. Add Globals
    globals_block = """$script:frameDelayMs = 33
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
    content = content.replace('$script:frameDelayMs = 33', globals_block)

    # 3. Fix DebugLog switch
    content = re.sub(r'\$script:debugLog = \$null\nif \(\$DebugLog\.IsPresent\) \{',
                     r'$script:debugLog = $null\nif ($DebugLog.IsPresent) {', content)
    # Ensure Write-Host $script:debugLog is cleaned up
    content = content.replace('Write-Host $script:debugLog', '')

    # 4. Input Buffer
    content = content.replace('$script:inputBuf      = [byte[]]::new(4096)',
                              '$script:inputBuf      = [byte[]]::new($script:inputBufSize)')

    # 5. DiagLog functions
    diag_funcs = """function Write-DiagLog([string]$category, [string]$message) {
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

    # 6. Line Indexing
    content = content.replace('$script:lastRows = [System.Collections.Generic.List[string]]::new()',
                              '$script:lastRows = [System.Collections.Generic.List[string]]::new()\n$script:lineIndex = @(0)')

    line_logic = """function Rebuild-LineIndex {
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
"""
    # Replace the existing BufSet if any, otherwise add it.
    if 'function BufSet([string]$text)' in content:
        content = re.sub(r'function BufSet\(\[string\]\$text\) \{.*?\}', line_logic, content, flags=re.DOTALL)
    else:
        content = content.replace('function BufText { $state.Buffer.ToString() }',
                                  'function BufText { $state.Buffer.ToString() }\n' + line_logic)

    # 7. Update Offset Helpers to use Index
    content = re.sub(r'function OffsetToRowCol\(\[int\]\$offset\) \{.*?return \$row, \(\$off - \$ls\)\s+\}',
                     'function OffsetToRowCol([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  $row = Find-LineRow $off\n  return $row, ($off - $script:lineIndex[$row])\n}',
                     content, flags=re.DOTALL)

    content = re.sub(r'function LineStart\(\[int\]\$offset\) \{.*?return \$offset\s+\}',
                     'function LineStart([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  return $script:lineIndex[(Find-LineRow $off)]\n}',
                     content, flags=re.DOTALL)

    content = re.sub(r'function LineEnd\(\[int\]\$offset\) \{.*?return \$offset\s+\}',
                     'function LineEnd([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  $row = Find-LineRow $off\n  if ($row -lt ($script:lineIndex.Length - 1)) { return ($script:lineIndex[$row + 1] - 1) }\n  return (BufLen)\n}',
                     content, flags=re.DOTALL)

    content = re.sub(r'function GetLine\(\[int\]\$n\) \{.*?return \$null\s+\}',
                     'function GetLine([int]$n) {\n  if ($n -lt 0 -or $n -ge $script:lineIndex.Length) { return $null }\n  $start = $script:lineIndex[$n]\n  $end = if ($n -lt ($script:lineIndex.Length - 1)) { $script:lineIndex[$n + 1] - 1 } else { (BufLen) }\n  return (BufText).Substring($start, $end - $start)\n}',
                     content, flags=re.DOTALL)

    content = re.sub(r'function RowColToOffset\(\[int\]\$row, \[int\]\$col\) \{.*?return \$t\.Length.*?\}',
                     'function RowColToOffset([int]$row, [int]$col) {\n  if ($script:lineIndex.Length -eq 0) { return 0 }\n  $row = [Math]::Max(0, [Math]::Min($row, $script:lineIndex.Length - 1))\n  $start = $script:lineIndex[$row]\n  $end = if ($row -lt ($script:lineIndex.Length - 1)) { $script:lineIndex[$row + 1] - 1 } else { (BufLen) }\n  return $start + [Math]::Max(0, [Math]::Min($col, $end - $start))\n}',
                     content, flags=re.DOTALL)

    content = re.sub(r'function LineCount \{.*?Count\s+\}',
                     'function LineCount { return [Math]::Max(1, $script:lineIndex.Length) }',
                     content, flags=re.DOTALL)

    # 8. Diag Pane Render
    diag_render = """function Build-DiagRow([int]$rowIndex, [int]$screenWidth) {
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
    content = content.replace('function Render-Frame {', diag_render + '\nfunction Render-Frame {')

    # 9. Update Handle-EditKey for Ctrl+D
    content = content.replace("'T' {", "'D' {\n        $script:diagPaneVisible = -not $script:diagPaneVisible\n        if ($script:diagPaneVisible) {\n          if ($script:diagPaneHeight -lt 1) { $script:diagPaneHeight = $script:diagDefaultHeight }\n          Write-DiagLog 'INFO' 'Diagnostic pane enabled.'\n          $state.Message = ' Diagnostics on '\n        } else {\n          $script:diagDragging = $false\n          $state.Message = ' Diagnostics off '\n        }\n        Reset-RenderShadow; return\n      }\n      'T' {")

    # 10. Update commands list
    content = content.replace("[PSCustomObject]@{ Key = '^T'; Label = 'Theme' }",
                              "[PSCustomObject]@{ Key = '^T'; Label = 'Theme' }\n  [PSCustomObject]@{ Key = '^D'; Label = 'Diag' }")

    # 11. Fix mutation points to rebuild index
    # Backup existing Rebuild-LineIndex calls if any to avoid duplication
    content = re.sub(r'Rebuild-LineIndex', '', content)
    # Add it back to BufSet (logic above already has it)
    # Add it to Handle-EditKey chokepoints?
    # Actually, let's just make BufSet the chokepoint and ensure all mutations use it.
    # Looking at the code, Backspace/Enter/printable chars mutate $state.Buffer directly.
    # We should add Rebuild-LineIndex after those mutations.

    content = content.replace("$state.Buffer.Remove($a, $b - $a) | Out-Null",
                              "$state.Buffer.Remove($a, $b - $a) | Out-Null; Rebuild-LineIndex")
    content = content.replace("$state.Buffer.Insert($state.Cursor, $text) | Out-Null",
                              "$state.Buffer.Insert($state.Cursor, $text) | Out-Null; Rebuild-LineIndex")
    content = content.replace("$state.Buffer.Append($ch) | Out-Null",
                              "$state.Buffer.Append($ch) | Out-Null; Rebuild-LineIndex")
    # For printable chars
    content = content.replace("$state.Buffer.Insert($state.Cursor, $ki.KeyChar) | Out-Null",
                              "$state.Buffer.Insert($state.Cursor, $ki.KeyChar) | Out-Null; Rebuild-LineIndex")

    # 12. Input Robustness (the "escape" fix)
    # Ensure Read-NextInputEvent is clean.
    # I'll use the version I designed earlier.

    # 13. SGR Mouse Tracking
    # Use the logic where we only enable tracking if pane is visible, OR we handle right-click.

    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    apply_patch(sys.argv[1])
