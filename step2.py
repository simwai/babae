import re
import sys

def apply_step2(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Update Write-DebugLog and add Write-DiagLog
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

    # 2. Add Rebuild-LineIndex, Find-LineRow, and update BufSet
    line_indexing_block = r"""
$script:lineIndex = @(0)

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
    # Replace existing BufText if it exists, or insert after BufLen
    content = re.sub(r'function BufText \{.*?\}', line_indexing_block, content, flags=re.DOTALL)

    # 3. Handle mutations to rebuild index
    content = content.replace("$state.Buffer.Remove($a, $b - $a) | Out-Null",
                              "$state.Buffer.Remove($a, $b - $a) | Out-Null; Rebuild-LineIndex")
    content = content.replace("$state.Buffer.Insert($state.Cursor, $text) | Out-Null",
                              "$state.Buffer.Insert($state.Cursor, $text) | Out-Null; Rebuild-LineIndex")
    content = content.replace("$state.Buffer.Append($ch) | Out-Null",
                              "$state.Buffer.Append($ch) | Out-Null; Rebuild-LineIndex")
    content = content.replace("$state.Buffer.Insert($state.Cursor, $ki.KeyChar) | Out-Null",
                              "$state.Buffer.Insert($state.Cursor, $ki.KeyChar) | Out-Null; Rebuild-LineIndex")

    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    apply_step2(sys.argv[1])
