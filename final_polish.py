import re
import sys

def polish(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Main Loop robustness
    loop_part = """      # Read one complete input event (key or paste) from raw stdin.
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
                     loop_part, content, flags=re.DOTALL)

    # 2. Term Setup: Add Mouse tracking codes
    content = content.replace('`e[?1049h`e[?2004h`e[?25l`e[2J`e[H',
                              '`e[?1049h`e[?2004h`e[?1000h`e[?1003h`e[?1006h`e[?25l`e[2J`e[H')
    content = content.replace('`e[?2004l`e[?1049l`e[?25h`e[0m',
                              '`e[?1006l`e[?1003l`e[?1000l`e[?2004l`e[?1049l`e[?25h`e[0m')

    # 3. Add DiagPane param handling in main
    content = content.replace('$script:diagPaneVisible = $DiagPane.IsPresent', '')
    content = content.replace('$script:isUnix = $IsLinux -or $IsMacOS',
                              '$script:diagPaneVisible = $DiagPane.IsPresent\n  $script:diagPaneHeight = $script:diagDefaultHeight\n  $script:isUnix = $IsLinux -or $IsMacOS')

    with open(filepath, 'w') as f:
        f.write(content)

polish('babae.ps1')
