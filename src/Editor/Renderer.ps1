$ErrorActionPreference = 'Stop'

#region Build Editor Row Content
function Build-EditorRowContent([int]$rowIndex, [int]$screenWidth, [int]$textWidth) {
  $editorState = Get-EditorState
  $cursorRow, $cursorCol = Convert-OffsetToRowCol $editorState.CursorOffset
  $selStart = 0; $selEnd = 0
  if ($editorState.IsSelectionActive) { $selStart, $selEnd = Get-SelectionBoundaries }

  if ($rowIndex -eq 0) {
    $themeName = $script:themeDefinitions[$script:availableThemeNames[$script:currentThemeIndex]].displayName
    $fileName = if ($editorState.FilePath) { [IO.Path]::GetFileName($editorState.FilePath) } else { 'new file' }
    $dirty = if ($editorState.IsDirty) { "$(Get-ThemeColor 'foregroundDirty')●$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader') " } else { '  ' }
    $plain = " babae | $fileName [$($editorState.Language)] | $themeName "
    $pad = [Math]::Max(0, $screenWidth - $plain.Length)
    return "$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')${BOLD_SEQUENCE} babae $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundMuted')| $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$dirty$fileName [$($editorState.Language)] $(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundMuted')| $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundHeader')$(Get-ThemeColor 'foregroundHeader')$themeName$(' ' * $pad)$script:RESET_SEQUENCE"
  }

  try { $lastRow = [Console]::WindowHeight - 1 } catch { $lastRow = 23 }
  if ($rowIndex -eq $lastRow) {
    $msg = $editorState.StatusMessage
    $pos = " $($cursorRow + 1):$($cursorCol + 1) "
    $ecHint = if ($script:editorConfigSettings.indent_style -eq 'tab') { 'tab' } else { "$($script:editorConfigSettings.indent_size)sp" }
    $eol = $script:editorConfigSettings.end_of_line.ToUpperInvariant()
    if ($editorState.EditorMode -eq 'search') {
      $plain = " Search: $($editorState.SearchBuffer)_ (Enter=jump Esc=cancel) "
      $pad = [Math]::Max(0, $screenWidth - $plain.Length)
      return "$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundAccent')${BOLD_SEQUENCE} Search:$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundNormal') $($editorState.SearchBuffer)_ $(Get-ThemeColor 'foregroundMuted')(Enter=jump Esc=cancel)$(' ' * $pad)$script:RESET_SEQUENCE"
    }
    if ($editorState.EditorMode -eq 'save-as') {
      $plain = " Save as: $($editorState.SaveAsBuffer) (Enter=save Esc=cancel) "
      $pad = [Math]::Max(0, $screenWidth - $plain.Length)
      return "$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundAccent')${BOLD_SEQUENCE} Save as:$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundNormal') $($editorState.SaveAsBuffer) $(Get-ThemeColor 'foregroundMuted')(Enter=save Esc=cancel)$(' ' * $pad)$script:RESET_SEQUENCE"
    }
    $displayOrder = @('^F1', '^T', '^S', '^Q', '^F', '^Z')
    $barCmds = foreach ($k in $displayOrder) { $script:commandBindingDefinitions | Where-Object { $_.Key -eq $k } }
    $leftPlain = ' ' + (($barCmds | ForEach-Object { "$($_.Key) $($_.Label)" }) -join ' ') + ' '
    $rightPlain = " $eol | $ecHint |$pos"
    if ($msg) { $rightPlain = " $msg |" + $rightPlain }
    if ($editorState.IsSelectionActive) { $rightPlain = " SEL |" + $rightPlain }
    $pad = [Math]::Max(0, $screenWidth - $leftPlain.Length - $rightPlain.Length)
    $right = ''
    if ($msg) { $right += "$(Get-ThemeColor 'foregroundSaved') $msg $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundMuted')│" }
    if ($editorState.IsSelectionActive) { $right += "$(Get-ThemeColor 'foregroundAccent') SEL $script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundMuted')│" }
    $right += "$(Get-ThemeColor 'foregroundMuted') $eol $(Get-ThemeColor 'foregroundMuted')│ $(Get-ThemeColor 'foregroundMuted')$ecHint $(Get-ThemeColor 'foregroundMuted')│$(Get-ThemeColor 'foregroundAccent')$pos$script:RESET_SEQUENCE"
    $barLeft = "$(Get-ThemeColor 'backgroundStatusBar')"
    foreach ($cmd in $barCmds) {
      $barLeft += "$(Get-ThemeColor 'foregroundAccent')${BOLD_SEQUENCE}$($cmd.Key)$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundStatusBar')$(Get-ThemeColor 'foregroundMuted') $($cmd.Label) "
    }
    return "$barLeft$(' ' * $pad)$right"
  }

  $lineIndex = $rowIndex - 1 + $editorState.VerticalScrollRow
  $lineText = Get-LineByNumber $lineIndex
  if ($null -eq $lineText) {
    return "$(Get-ThemeColor 'backgroundGutter')$(Get-ThemeColor 'foregroundTilde')   ~ $script:RESET_SEQUENCE$(Get-ThemeColor 'background')$(' ' * $textWidth)$script:RESET_SEQUENCE"
  }

  $isCurrent = ($lineIndex -eq $cursorRow)
  $lineNum = ($lineIndex + 1).ToString().PadLeft(4)
  $gutter = if ($isCurrent) {
    "$(Get-ThemeColor 'backgroundGutter')$(Get-ThemeColor 'foregroundCurrentLineNumber')${BOLD_SEQUENCE}$lineNum$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundGutter') $script:RESET_SEQUENCE"
  } else {
    "$(Get-ThemeColor 'backgroundGutter')$(Get-ThemeColor 'foregroundLineNumber')$lineNum$script:RESET_SEQUENCE$(Get-ThemeColor 'backgroundGutter') $script:RESET_SEQUENCE"
  }

  $hScroll = $editorState.HorizontalScrollOffset
  $fullLine = $lineText
  $visibleStart = $hScroll
  $visibleLen = [Math]::Min($textWidth, $fullLine.Length - $visibleStart)
  if ($visibleLen -lt 0) { $visibleLen = 0 }
  $slice = if ($fullLine.Length -gt $visibleStart) { $fullLine.Substring($visibleStart, $visibleLen) } else { '' }
  $slice = $slice -replace [char]0x1B, '?'

  $cacheKey = "$lineIndex`:$fullLine"
  if (-not $editorState.SyntaxTokenCache.ContainsKey($cacheKey)) {
    $editorState.SyntaxTokenCache[$cacheKey] = Get-TokensForLine $fullLine $editorState.Language
  }
  $tokens = $editorState.SyntaxTokenCache[$cacheKey]

  $bg = if ($isCurrent) { Get-ThemeColor 'backgroundLine' } else { Get-ThemeColor 'background' }
  $lineOff = Convert-RowColToOffset $lineIndex 0
  $rulerCol = if ($script:editorConfigSettings.max_line_length -gt 0) { $script:editorConfigSettings.max_line_length } else { -1 }

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append($gutter)
  [void]$sb.Append($bg)
  $lineHasBreak = ($lineOff + $fullLine.Length -lt $editorState.TextBuffer.Length -and $editorState.TextBuffer[$lineOff + $fullLine.Length] -eq "`n")
  for ($ci = 0; $ci -lt $textWidth; $ci++) {
    $lineCharOffset = $ci + $visibleStart
    $hasTextCharacter = $lineCharOffset -lt $fullLine.Length
    $absOff = $lineOff + $lineCharOffset
    $ch = if ($ci -lt $slice.Length) { [string]$slice[$ci] } else { ' ' }
    $isLineBreakCell = -not $hasTextCharacter -and $lineCharOffset -eq $fullLine.Length -and $lineHasBreak
    $selectionOffset = if ($isLineBreakCell) { $lineOff + $fullLine.Length } else { $absOff }
    $inSel = ($hasTextCharacter -or $isLineBreakCell) -and $editorState.IsSelectionActive -and $selectionOffset -ge $selStart -and $selectionOffset -lt $selEnd
    $rulerHere = ($rulerCol -ge 0 -and ($ci + $visibleStart) -eq $rulerCol)

    $tokenType = $null
    foreach ($tok in $tokens) {
      if ($tok.Start -le $absOff - $lineOff -and ($tok.Start + $tok.Length) -gt $absOff - $lineOff) {
        $tokenType = $tok.Type; break
      }
    }
    $fgKey = 'foregroundNormal'
    if ($tokenType) { $fgKey = "foreground$tokenType" }

    if ($inSel) {
      [void]$sb.Append("$(Get-ThemeColor 'backgroundSelection')$(Get-ThemeColor $fgKey)$ch$bg")
    } elseif ($rulerHere) {
      [void]$sb.Append("$(Get-ThemeColor 'foregroundRuler')│$(Get-ThemeColor $fgKey)$ch")
    } else {
      [void]$sb.Append("$(Get-ThemeColor $fgKey)$ch")
    }
  }
  [void]$sb.Append($script:RESET_SEQUENCE)
  return $sb.ToString()
}

#endregion
#region Render Editor Frame
function Write-EditorFrame {
  $editorState = Get-EditorState
  try { $width = [Console]::WindowWidth } catch { $width = 80 }
  try { $height = [Console]::WindowHeight } catch { $height = 24 }
  $textWidth = $width - 5

  if ($script:cachedRenderRows.Count -ne $height) {
    Clear-RenderCache
    for ($i = 0; $i -lt $height; $i++) { $script:cachedRenderRows.Add('') }
    Write-OutputBuffer("`e[2J`e[3J")
  }

  $dirty = [System.Text.StringBuilder]::new()
  [void]$dirty.Append("`e[?25l")

  $anyRowChanged = $false
  for ($row = 0; $row -lt $height; $row++) {
    $rendered = Build-EditorRowContent $row $width $textWidth
    if ($script:cachedRenderRows[$row] -ne $rendered) {
      $script:cachedRenderRows[$row] = $rendered
      [void]$dirty.Append((Move-CursorToScreenCoordinate ($row + 1) 1))
      [void]$dirty.Append($rendered)
      $anyRowChanged = $true
    }
  }

  $cr, $cc = Convert-OffsetToRowCol $editorState.CursorOffset
  try { $maxTextRow = [Console]::WindowHeight - 1 } catch { $maxTextRow = 23 }
  $screenRow = [Math]::Min($maxTextRow, [Math]::Max(2, $cr - $editorState.VerticalScrollRow + 2))
  $screenCol = [Math]::Max(6, $cc - $editorState.HorizontalScrollOffset + 6)

  if ($anyRowChanged -or $screenRow -ne $script:cachedCursorRow -or $screenCol -ne $script:cachedCursorColumn) {
    [void]$dirty.Append((Move-CursorToScreenCoordinate $screenRow $screenCol))
    $script:cachedCursorRow = $screenRow
    $script:cachedCursorColumn = $screenCol
  }

  [void]$dirty.Append("`e[?25h")
  Write-OutputBuffer($dirty.ToString())
  $editorState.StatusMessage = ''
}

#endregion
#region Move Cursor To Screen Coordinate
function Move-CursorToScreenCoordinate([int]$r, [int]$c) { "`e[$r;${c}H" }
#endregion