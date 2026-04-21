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

    # 2. stty raw mode at startup
    if '[Console]::TreatControlCAsInput = $true' in line:
        new_lines.append(line)
        new_lines.append('  if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {\n')
        new_lines.append('    stty raw -echo -ixon -isig -icanon 2>/dev/null\n')
        new_lines.append('  }\n')
        continue

    # 3. stty sane at cleanup
    if '[Console]::TreatControlCAsInput = $oldCtrlC' in line:
        new_lines.append(line)
        new_lines.append('    if (-not $IsWindows -and (Get-Command stty -ErrorAction SilentlyContinue)) {\n')
        new_lines.append('      stty sane 2>/dev/null\n')
        new_lines.append('    }\n')
        continue

    new_lines.append(line)

with open('babae.ps1', 'w') as f:
    f.writelines(new_lines)
