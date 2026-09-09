$ErrorActionPreference = 'Stop'

#region Help Dialog
function Show-HelpDialog {
  try { $width = [Console]::WindowWidth } catch { $width = 80 }
  try { $height = [Console]::WindowHeight } catch { $height = 24 }
  $themeName = Get-CurrentThemeDisplayName
  $cmdLines = Get-CommandBindingDefinitions | ForEach-Object {
    $pad = ' ' * ([Math]::Max(1, 10 - $_.Key.Length))
    "  $($_.Key)$pad$($_.Label)"
  }
  $lines = @(
    '', '  babae  —  keybindings', '  ────────────────────────────────────',
    "  Theme now: $themeName", ''
  ) + $cmdLines + @(
    '', '  Shift+Arrows  Extend selection',
    '  RightClick    Paste from clipboard',
    '  Esc           Cancel search / clear selection',
    '  Tab           Indent / autocomplete',
    '', '  Press any key to close...', ''
  )
  $boxW = 52
  $boxH = $lines.Count + 2
  $top = [int](($height - $boxH) / 2)
  $left = [int](($width - $boxW) / 2)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("`e[?25l")
  for ($i = 0; $i -lt $boxH; $i++) {
    [void]$sb.Append((Move-CursorToScreenCoordinate ($top + $i) $left))
    if ($i -eq 0 -or $i -eq ($boxH - 1)) {
      [void]$sb.Append("$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$(' ' * $boxW)$script:RESET_SEQUENCE")
      continue
    }
    $text = $lines[$i - 1]
    $pad = [Math]::Max(0, $boxW - $text.Length)
    [void]$sb.Append("$(Get-ThemeColor 'backgroundLine')$(Get-ThemeColor 'foregroundNormal')$text$(' ' * $pad)$script:RESET_SEQUENCE")
  }
  $editorState = Get-EditorState
  $cr, $cc = Convert-OffsetToRowCol $editorState.CursorOffset
  [void]$sb.Append((Move-CursorToScreenCoordinate ($cr - $editorState.VerticalScrollRow + 2) ($cc - $editorState.HorizontalScrollOffset + 6)))
  [void]$sb.Append("`e[?25h")
  Write-OutputBuffer($sb.ToString())
  Read-InputEvent | Out-Null
  Clear-RenderCache
}

#endregion
#region Confirm Quit Dialog
function Show-ConfirmQuitDialog {
  try { $width = [Console]::WindowWidth } catch { $width = 80 }
  try { $height = [Console]::WindowHeight } catch { $height = 24 }
  $msg = '  Unsaved changes — quit anyway?  [y / N]  '
  $boxW = $msg.Length + 2
  $top = [int](($height - 3) / 2)
  $left = [int](($width - $boxW) / 2)
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("`e[?25l")
  [void]$sb.Append((Move-CursorToScreenCoordinate $top $left))
  [void]$sb.Append("$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$(' ' * $boxW)$script:RESET_SEQUENCE")
  [void]$sb.Append((Move-CursorToScreenCoordinate ($top + 1) $left))
  [void]$sb.Append("$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$msg$(' ' * ($boxW - $msg.Length))$script:RESET_SEQUENCE")
  [void]$sb.Append((Move-CursorToScreenCoordinate ($top + 2) $left))
  [void]$sb.Append("$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$(' ' * $boxW)$script:RESET_SEQUENCE")
  Write-OutputBuffer($sb.ToString())
  $editorState = Get-EditorState
  while ($true) {
    $ev = Read-InputEvent
    if ($ev.Kind -ne 'Key') { continue }
    $key = $ev.KeyInfo.Key
    $ch = $ev.KeyInfo.KeyChar
    if ($key -eq 'Y' -or $ch -eq 'Y' -or $ch -eq 'y') { $script:shouldExitApplication = $true; return }
    if ($key -in 'N', 'Escape', 'Enter' -or $ch -eq 'N' -or $ch -eq 'n') { $editorState.EditorMode = 'edit'; $editorState.StatusMessage = ' Quit cancelled '; Clear-RenderCache; return }
  }
}
#endregion