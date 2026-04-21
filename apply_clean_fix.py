import sys
import re

with open('babae.ps1', 'r') as f:
    content = f.read()

# 1. Force non-blocking input path on Linux/macOS
# Replace the original block:
# $script:stdinIsConsole = $true
# try { [void][Console]::KeyAvailable } catch { $script:stdinIsConsole = $false }
# With:
# $script:stdinIsConsole = $IsWindows
# try { if ($script:stdinIsConsole) { [void][Console]::KeyAvailable } } catch { $script:stdinIsConsole = $false }

content = content.replace(
    '$script:stdinIsConsole = $true\ntry { [void][Console]::KeyAvailable } catch { $script:stdinIsConsole = $false }',
    '$script:stdinIsConsole = $IsWindows\ntry { if ($script:stdinIsConsole) { [void][Console]::KeyAvailable } } catch { $script:stdinIsConsole = $false }'
)

# 2. Key Handlers (10, 13 for Enter; 127, 8 for Backspace)
content = content.replace(
    "13  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]13)  ([System.ConsoleKey]::Enter)     0) } }",
    "10, 13 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]13) ([System.ConsoleKey]::Enter) 0) } }"
)
content = content.replace(
    "127 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }",
    "127, 8 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }"
)

# 3. Terminal Mode (stty) in Edit-Babae
# Find: [Console]::TreatControlCAsInput = $true
# Insert stty init after it.
stty_init = """
  [Console]::TreatControlCAsInput = $true

  $script:unixSttyState = $null
  if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {
    if (-not [Console]::IsInputRedirected) {
      try {
        $script:unixSttyState = stty -g 2>/dev/null
        stty raw -echo -ixon -isig -icanon 2>/dev/null
      } catch {}
    }
  }"""

content = content.replace('[Console]::TreatControlCAsInput = $true', stty_init)

# 4. stty restore in finally block
# Find: [Console]::TreatControlCAsInput = $oldCtrlC
# Insert stty restore after it.
stty_restore = """
    [Console]::TreatControlCAsInput = $oldCtrlC
    if ($null -ne $script:unixSttyState) {
      try { stty $script:unixSttyState 2>/dev/null } catch {}
    }"""

content = content.replace('[Console]::TreatControlCAsInput = $oldCtrlC', stty_restore)

with open('babae.ps1', 'w') as f:
    f.write(content)
