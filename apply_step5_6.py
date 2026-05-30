import re
import sys

def apply(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Add Build-DiagRow and Handle-DiagMouseDrag before Render-Frame
    diag_render_funcs = r"""
function Build-DiagRow([int]$rowIndex, [int]$screenWidth) {
  if ($rowIndex -eq ($script:diagDividerRow - 1)) {
    $plain = " DIAG | $($script:diagRingBuffer.Count) events | drag to resize | Ctrl+D hide "
    $pad = [Math]::Max(0, $screenWidth - $plain.Length)
    return "$(T 'bgBar')$(T 'fgAccent')${BOLD} DIAG $RESET$(T 'bgBar')$(T 'fgMuted')| $($script:diagRingBuffer.Count) events | drag to resize | Ctrl+D hide$(' ' * $pad)$RESET"
  }
  $entries = @($script:diagRingBuffer.ToArray())
  $paneLine = $rowIndex - $script:diagDividerRow
  $start = [Math]::Max(0, $entries.Count - $script:diagPaneHeight - $script:diagScrollOffset)
  $idx = $start + $paneLine - 1
  $text = if ($idx -ge 0 -and $idx -lt $entries.Count) { $entries[$idx] } else { '' }
  if ($text.Length -gt $screenWidth) { $text = $text.Substring(0, $screenWidth) }
  $pad = [Math]::Max(0, $screenWidth - $text.Length)
  return "$(T 'bg')$(T 'fgMuted')$text$(' ' * $pad)$RESET"
}

function Handle-DiagMouseDrag([int]$mouseRow) {
  $height = [Console]::WindowHeight; $maxDiag = [Math]::Floor(($height - 4) / 2)
  if ($maxDiag -le 0) { return }
  $minDiag = [Math]::Min($script:diagPaneMinHeight, $maxDiag)
  $newHeight = [Math]::Max($minDiag, [Math]::Min($height - $mouseRow - 1, $maxDiag))
  if ($newHeight -ne $script:diagPaneHeight) { $script:diagPaneHeight = $newHeight; Reset-RenderShadow }
}
"""
    content = content.replace('function Render-Frame {', diag_render_funcs + '\nfunction Render-Frame {')

    # 2. Update Render-Frame
    render_new = r"""function Render-Frame {
  $width = [Console]::WindowWidth; $height = [Console]::WindowHeight; $textWidth = $width - 5
  if ($script:diagPaneVisible) {
    $maxDiag = [Math]::Floor(($height - 4) / 2)
    if ($maxDiag -le 0) { $script:diagPaneVisible = $false; $script:diagDividerRow = -1 }
    else {
      $minDiag = [Math]::Min($script:diagPaneMinHeight, $maxDiag)
      $script:diagPaneHeight = [Math]::Max($minDiag, [Math]::Min($script:diagPaneHeight, $maxDiag))
      $script:diagDividerRow = $height - 1 - $script:diagPaneHeight
    }
  } else { $script:diagDividerRow = -1 }

  if ($script:lastRows.Count -ne $height) { $script:lastRows.Clear(); for ($i = 0; $i -lt $height; $i++) { $script:lastRows.Add('') } }
  $dirty = [System.Text.StringBuilder]::new()
  for ($row = 0; $row -lt $height; $row++) {
    if ($script:diagPaneVisible -and $row -ge ($script:diagDividerRow - 1) -and $row -lt ($height - 1)) { $rendered = Build-DiagRow $row $width }
    else { $rendered = Build-EditorRow $row $width $textWidth }
    if ($script:lastRows[$row] -ne $rendered) { $script:lastRows[$row] = $rendered; [void]$dirty.Append((Move-To ($row + 1) 1)); [void]$dirty.Append($rendered) }
  }
  $curR, $curC = OffsetToRowCol $state.Cursor; $vRow = ($curR - $state.ScrollRow) + 1; $vCol = $curC + 6
  if ($vRow -ge 1 -and $vRow -lt ($height - ($script:diagPaneVisible ? $script:diagPaneHeight + 1 : 0))) {
    [void]$dirty.Append((Move-To $vRow $vCol))
    if (-not $script:lastCursorVisible) { [void]$dirty.Append("`e[?25h"); $script:lastCursorVisible = $true }
  } else { if ($script:lastCursorVisible) { [void]$dirty.Append("`e[?25l"); $script:lastCursorVisible = $false } }
  Out-Flush $dirty.ToString()
}"""
    content = re.sub(r'function Render-Frame \{.*?Out-Flush \$dirty\.ToString\(\)\s+\}', render_new, content, flags=re.DOTALL)

    # 3. Update Handle-EditKey for Ctrl+D
    content = content.replace("'T' {", r"""'D' {
        $script:diagPaneVisible = -not $script:diagPaneVisible
        if ($script:diagPaneVisible) {
          if ($script:diagPaneHeight -lt 1) { $script:diagPaneHeight = $script:diagDefaultHeight }
          Write-DiagLog 'INFO' 'Diagnostic pane enabled.'
          $state.Message = ' Diagnostics on '
        } else { $script:diagDragging = $false; $state.Message = ' Diagnostics off ' }
        Reset-RenderShadow; return
      }
      'T' {""")

    # 4. Main Loop updates
    # We find where Edit-Babae starts and replace its contents or specifically the while loop
    main_loop_new = r"""        while ($script:running) {
          $width = [Console]::WindowWidth; $height = [Console]::WindowHeight
          if ($width -ne $prevWidth -or $height -ne $prevHeight) { $prevWidth = $width; $prevHeight = $height; Reset-RenderShadow }

          Update-Scroll
          Render-Frame

          if ($script:mouseEnabled -and -not (Stdin-DataAvailable)) {
            if ([BabaeWin]::PollRightClick($script:consoleHandle)) { Paste-Text (Get-ClipboardText); continue }
            Start-Sleep -Milliseconds $script:frameDelayMs; continue
          }

          if (-not (Stdin-DataAvailable)) { Start-Sleep -Milliseconds $script:frameDelayMs; continue }

          $event = Read-NextInputEvent
          if ($null -eq $event) { continue }

          if ($event.Kind -eq 'Paste') { Paste-Text $event.Text }
          elif ($event.Kind -eq 'Mouse') {
            if ($event.Release) { $script:diagDragging = $false }
            elif ($event.Right -and $event.Down) { Paste-Text (Get-ClipboardText) }
            elif ($script:diagPaneVisible -and $event.Left -and $event.Down -and $event.Y -eq $script:diagDividerRow) { $script:diagDragging = $true; Handle-DiagMouseDrag $event.Y }
            elif ($script:diagDragging -and $event.Left -and ($event.Drag -or $event.Down)) { Handle-DiagMouseDrag $event.Y }
          } else {
            switch ($state.Mode) {
              'edit'         { Handle-EditKey $event.KeyInfo }
              'search'       { Handle-SearchKey $event.KeyInfo }
              'confirm-quit' { Handle-ConfirmQuitKey $event.KeyInfo }
            }
          }
          ClampCursor
          if ($state.Mode -eq 'confirm-quit') {
            if ($state.Dirty) { Render-ConfirmQuit } else { $script:running = $false; continue }
          }
        }"""
    # Replace the existing while loop in Edit-Babae
    # Note: Correcting elif to elseif
    main_loop_new = main_loop_new.replace('elif (', 'elseif (')
    content = re.sub(r'while \(\$script:running\) \{.*?\}', main_loop_new, content, flags=re.DOTALL)

    # 5. Terminal Setup/Cleanup
    content = content.replace('Out-Flush("`e[?1049h`e[?2004h`e[?25l`e[2J`e[H")',
                              'Out-Flush("`e[?1049h`e[?2004h`e[?1000h`e[?1003h`e[?1006h`e[?25l`e[2J`e[H")')
    content = content.replace('Out-Flush("`e[?2004l`e[?1049l`e[?25h`e[0m")',
                              'Out-Flush("`e[?1006l`e[?1003l`e[?1000l`e[?2004l`e[?1049l`e[?25h`e[0m")')

    # Fix MAIN setup DiagPane
    content = content.replace('$script:isUnix = $IsLinux -or $IsMacOS',
                              '$script:diagPaneVisible = $DiagPane.IsPresent\n  $script:diagPaneHeight = $script:diagDefaultHeight\n  $script:isUnix = $IsLinux -or $IsMacOS')

    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    apply(sys.argv[1])
