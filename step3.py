import re
import sys

def apply_step3(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Update BufLen
    content = content.replace('function BufLen { $state.Buffer.Length }',
                              'function BufLen { return $state.Buffer.Length }')

    # 2. Update OffsetToRowCol
    content = re.sub(r'function OffsetToRowCol\(\[int\]\$offset\) \{.*?return \$row, \(\$off - \$ls\)\n\}',
                     r'function OffsetToRowCol([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  $row = Find-LineRow $off\n  return $row, ($off - $script:lineIndex[$row])\n}',
                     content, flags=re.DOTALL)

    # 3. Update LineStart
    content = re.sub(r'function LineStart\(\[int\]\$offset\) \{.*?return \$offset\n\}',
                     r'function LineStart([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  return $script:lineIndex[(Find-LineRow $off)]\n}',
                     content, flags=re.DOTALL)

    # 4. Update LineEnd
    content = re.sub(r'function LineEnd\(\[int\]\$offset\) \{.*?return \$offset\n\}',
                     r'function LineEnd([int]$offset) {\n  $off = [Math]::Max(0, [Math]::Min($offset, (BufLen)))\n  $row = Find-LineRow $off\n  if ($row -lt ($script:lineIndex.Length - 1)) { return ($script:lineIndex[$row + 1] - 1) }\n  return (BufLen)\n}',
                     content, flags=re.DOTALL)

    # 5. Update GetLine
    content = re.sub(r'function GetLine\(\[int\]\$n\) \{.*?return \$null\n\}',
                     r'function GetLine([int]$n) {\n  if ($n -lt 0 -or $n -ge $script:lineIndex.Length) { return $null }\n  $start = $script:lineIndex[$n]\n  $end = if ($n -lt ($script:lineIndex.Length - 1)) { $script:lineIndex[$n + 1] - 1 } else { (BufLen) }\n  return (BufText).Substring($start, $end - $start)\n}',
                     content, flags=re.DOTALL)

    # 6. Update RowColToOffset
    content = re.sub(r'function RowColToOffset\(\[int\]\$row, \[int\]\$col\) \{.*?return \$t\.Length\s+\}',
                     r'function RowColToOffset([int]$row, [int]$col) {\n  if ($script:lineIndex.Length -eq 0) { return 0 }\n  $row = [Math]::Max(0, [Math]::Min($row, $script:lineIndex.Length - 1))\n  $start = $script:lineIndex[$row]\n  $end = if ($row -lt ($script:lineIndex.Length - 1)) { $script:lineIndex[$row + 1] - 1 } else { (BufLen) }\n  return $start + [Math]::Max(0, [Math]::Min($col, $end - $start))\n}',
                     content, flags=re.DOTALL)

    # 7. Update LineCount
    content = re.sub(r'function LineCount \{.*?Count\n\}',
                     r'function LineCount { return [Math]::Max(1, $script:lineIndex.Length) }',
                     content, flags=re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    apply_step3(sys.argv[1])
