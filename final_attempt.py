import sys

with open('babae.ps1', 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    # 1. Non-blocking input path logic
    if '$script:stdinIsConsole = $true' in line:
        new_lines.append('$script:stdinIsConsole = $IsWindows\n')
        continue
    if 'try { [void][Console]::KeyAvailable } catch { $script:stdinIsConsole = $false }' in line:
        new_lines.append('try { if ($script:stdinIsConsole) { [void][Console]::KeyAvailable } } catch { $script:stdinIsConsole = $false }\n')
        continue

    # 2. Key Handlers (Slightly safer approach)
    if '13  { return [PSCustomObject]@{ Kind=\'Key\'; KeyInfo=(Make-KeyInfo ([char]13)  ([System.ConsoleKey]::Enter)     0) } }' in line:
        new_lines.append('    10, 13 { return [PSCustomObject]@{ Kind=\'Key\'; KeyInfo=(Make-KeyInfo ([char]13) ([System.ConsoleKey]::Enter) 0) } }\n')
        continue
    if '127 { return [PSCustomObject]@{ Kind=\'Key\'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }' in line:
        new_lines.append('    127, 8 { return [PSCustomObject]@{ Kind=\'Key\'; KeyInfo=(Make-KeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }\n')
        continue
    if '8   { return [PSCustomObject]@{ Kind=\'Key\'; KeyInfo=(Make-KeyInfo ([char]8)   ([System.ConsoleKey]::Backspace) 0) } }' in line:
        continue

    # 3. stty init
    if '[Console]::TreatControlCAsInput = $true' in line:
        new_lines.append(line)
        new_lines.append('  $script:unixSttyState = $null\n')
        new_lines.append('  if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {\n')
        new_lines.append('    try {\n')
        new_lines.append('      $script:unixSttyState = stty -g 2>/dev/null\n')
        new_lines.append('      stty raw -echo -ixon -isig -icanon 2>/dev/null\n')
        new_lines.append('    } catch {}\n')
        new_lines.append('  }\n')
        continue

    # 4. stty restore
    if '[Console]::TreatControlCAsInput = $oldCtrlC' in line:
        new_lines.append(line)
        new_lines.append('    if ($null -ne $script:unixSttyState) {\n')
        new_lines.append('      try { stty $script:unixSttyState 2>/dev/null } catch {}\n')
        new_lines.append('    }\n')
        continue

    new_lines.append(line)

with open('babae.ps1', 'w') as f:
    f.writelines(new_lines)
