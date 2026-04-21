import sys
import re

with open('babae.ps1', 'r') as f:
    content = f.read()

# 1. Non-blocking input path logic
# Change $script:stdinIsConsole = $true to $script:stdinIsConsole = $IsWindows
# And wrap KeyAvailable check
content = content.replace(
    '$script:stdinIsConsole = $true\ntry { [void][Console]::KeyAvailable } catch { $script:stdinIsConsole = $false }',
    '$script:stdinIsConsole = $IsWindows\ntry { if ($script:stdinIsConsole) { [void][Console]::KeyAvailable } } catch { $script:stdinIsConsole = $false }'
)

# 2. Key Handlers (Enter: 10, 13; Backspace: 8, 127)
content = content.replace(
    "13  { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]13)  ([System.ConsoleKey]::Enter)     0) } }",
    "10, 13 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]13) ([System.ConsoleKey]::Enter) 0) } }"
)
content = content.replace(
    "127 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }",
    "127, 8 { return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }"
)
content = re.sub(r' +8 +\{ return \[PSCustomObject\]@\{ Kind=\'Key\'; KeyInfo=\(Make-KeyInfo \(\[char\]8\) +\(\[System\.ConsoleKey\]::Backspace\) +0\) \} \}\n', '', content)

# 3. stty raw mode at startup
stty_init = """
  [Console]::TreatControlCAsInput = $true
  if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {
    try {
      # Only apply stty if stdin is a TTY to avoid issues in redirected environments like tests
      if (-not [Console]::IsInputRedirected) {
        stty raw -echo -ixon -isig -icanon 2>/dev/null
      }
    } catch {}
  }"""
content = content.replace('[Console]::TreatControlCAsInput = $true', stty_init)

# 4. stty sane at cleanup
stty_restore = """
    [Console]::TreatControlCAsInput = $oldCtrlC
    if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {
      try {
        if (-not [Console]::IsInputRedirected) {
          stty sane 2>/dev/null
        }
      } catch {}
    }"""
content = content.replace('[Console]::TreatControlCAsInput = $oldCtrlC', stty_restore)

with open('babae.ps1', 'w') as f:
    f.write(content)
