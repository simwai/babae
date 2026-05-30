import re
import sys

def apply(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Update Parameters
    param_pattern = r'param\(\s+\[Parameter\(Position = 0\)\]\[string\]\$Path,\s+\[ValidateSet\("dark", "mocha", "frappe", "github-dark"\)\]\s+\[string\]\$Theme = "dark"\s+\)'
    new_params = 'param(\n  [Parameter(Position = 0)][string]$Path,\n  [ValidateSet("dark", "mocha", "frappe", "github-dark")]\n  [string]$Theme = "dark",\n  [switch]$DiagPane,\n  [switch]$DebugLog\n)'
    content = re.sub(param_pattern, new_params, content, flags=re.DOTALL)

    # 2. Update Global Variables block
    # Insert after [Console]::InputEncoding setting
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
    # Remove old frameDelayMs
    content = content.replace('$script:frameDelayMs = 33', '')

    # Insert new block
    search_str = '[Console]::InputEncoding = [System.Text.Encoding]::UTF8'
    content = content.replace(search_str, search_str + globals_block)

    # 3. Fix DebugLog block at the top
    debug_log_block = r"""
$script:debugLog = $null
if ($DebugLog.IsPresent) {
  $script:debugLog = Join-Path . 'babae-debug.log'
}
"""
    # We find where themes start
    themes_marker = '# Themes'
    content = content.replace(themes_marker, debug_log_block + '\n' + themes_marker)

    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    apply(sys.argv[1])
