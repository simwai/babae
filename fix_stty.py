import sys
with open('babae.ps1', 'r') as f:
    content = f.read()

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
