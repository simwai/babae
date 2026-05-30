import re
import sys

def apply_step1(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Parameters
    param_pattern = r'param\(\s+\[Parameter\(Position = 0\)\]\[string\]\$Path,\s+\[ValidateSet\("dark", "mocha", "frappe", "github-dark"\)\]\s+\[string\]\$Theme = "dark"\s+\)'
    new_params = 'param(\n  [Parameter(Position = 0)][string]$Path,\n  [ValidateSet("dark", "mocha", "frappe", "github-dark")]\n  [string]$Theme = "dark",\n  [switch]$DiagPane,\n  [switch]$DebugLog\n)'
    content = re.sub(param_pattern, new_params, content, flags=re.DOTALL)

    # 2. Global Variables
    # Insert after [Console]::InputEncoding setting
    globals_block = """
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
    # Remove existing script:frameDelayMs to avoid duplicate
    content = content.replace('$script:frameDelayMs = 33', '')

    # We find [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    search_str = '[Console]::InputEncoding = [System.Text.Encoding]::UTF8'
    if search_str in content:
        content = content.replace(search_str, search_str + globals_block)
    else:
        print("Could not find InputEncoding line")
        sys.exit(1)

    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    apply_step1(sys.argv[1])
