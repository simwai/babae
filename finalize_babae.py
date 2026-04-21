import sys
import re

with open('babae.ps1', 'r') as f:
    content = f.read()

# 1. Non-blocking input path
content = content.replace(
    '$script:stdinIsConsole = $true\ntry { [void][Console]::KeyAvailable } catch { $script:stdinIsConsole = $false }',
    '$script:stdinIsConsole = $IsWindows\ntry { if ($script:stdinIsConsole) { [void][Console]::KeyAvailable } } catch { $script:stdinIsConsole = $false }'
)

# 2. Handle Enter (10, 13) and Backspace (127, 8)
content = content.replace(
    "13  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]13)  ([System.ConsoleKey]::Enter)     0) } }",
    "10, 13 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]13) ([System.ConsoleKey]::Enter) 0) } }"
)
content = content.replace(
    "127 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }",
    "127, 8 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }"
)
# Use a more flexible regex for removing the redundant 8 handler
content = re.sub(r' +8 +\{ return \[PSCustomObject\]@\{ Kind=\'Key\'; KeyInfo=\(Make-KeyInfo \(\[char\]8\) +\(\[System\.ConsoleKey\]::Backspace\) +0\) \} \}\n', '', content)

# 3. stty in Edit-Babae
stty_init = """
  $script:unixSttyState = $null
  if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {
    if (-not [Console]::IsInputRedirected) {
      try {
        $script:unixSttyState = stty -g 2>/dev/null
        stty raw -echo -ixon -isig -icanon 2>/dev/null
      } catch {}
    }
  }
"""
content = content.replace(
    '[Console]::TreatControlCAsInput = $true',
    '[Console]::TreatControlCAsInput = $true' + stty_init
)

# 4. stty restore in finally block
stty_restore = """
    if ($null -ne $script:unixSttyState) {
      try { stty $script:unixSttyState 2>/dev/null } catch {}
    }
"""
content = content.replace(
    '[Console]::TreatControlCAsInput = $oldCtrlC',
    '[Console]::TreatControlCAsInput = $oldCtrlC' + stty_restore
)

with open('babae.ps1', 'w') as f:
    f.write(content)
