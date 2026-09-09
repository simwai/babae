$ErrorActionPreference = 'Stop'

#region Editor State Object
$script:editorState = [PSCustomObject]@{
  TextBuffer             = [System.Text.StringBuilder]::new()
  CursorOffset           = 0
  PreferredColumn        = 0
  VerticalScrollRow      = 0
  HorizontalScrollOffset = 0
  FilePath               = ''
  Language               = 'Plain Text'
  IsDirty                = $false
  StatusMessage          = ''
  LastSearchTerm         = ''
  UndoStack              = [System.Collections.Generic.Stack[object]]::new()
  RedoStack              = [System.Collections.Generic.Stack[object]]::new()
  EditorMode             = 'edit'
  SaveAsBuffer           = ''
  SearchBuffer           = ''
  IsSelectionActive      = $false
  SelectionAnchor        = 0
  SyntaxTokenCache       = @{}
  AutocompleteMatches    = $null
  AutocompleteIndex      = 0
  AutocompleteBaseOffset = 0
}

#endregion
#region Buffer Accessors
function Get-BufferText { $script:editorState.TextBuffer.ToString() }

function Set-BufferContent([string]$text) {
  $script:editorState.TextBuffer.Clear() | Out-Null
  if ($text) { $script:editorState.TextBuffer.Append($text) | Out-Null }
  $script:editorState.SyntaxTokenCache = @{}
}

function Set-CursorOffsetBounds {
  $script:editorState.CursorOffset = [Math]::Max(0, [Math]::Min($script:editorState.CursorOffset, $script:editorState.TextBuffer.Length))
}

#endregion
#region Offset RowCol Conversion
function Convert-OffsetToRowCol([int]$offset) {
  $text = $script:editorState.TextBuffer.ToString()
  $clamped = [Math]::Max(0, [Math]::Min($offset, $text.Length))
  $row = 0; $lineStart = 0
  for ($i = 0; $i -lt $clamped; $i++) {
    if ($text[$i] -eq "`n") { $row++; $lineStart = $i + 1 }
  }
  return $row, ($clamped - $lineStart)
}

function Get-LineStartOffset([int]$offset) {
  $text = $script:editorState.TextBuffer.ToString()
  while ($offset -gt 0 -and $text[$offset - 1] -ne "`n") { $offset-- }
  return $offset
}

function Get-LineEndOffset([int]$offset) {
  $text = $script:editorState.TextBuffer.ToString()
  while ($offset -lt $text.Length -and $text[$offset] -ne "`n") { $offset++ }
  return $offset
}

function Get-LineByNumber([int]$lineNum) {
  $text = $script:editorState.TextBuffer.ToString()
  $row = 0; $start = 0
  for ($i = 0; $i -le $text.Length; $i++) {
    if ($i -eq $text.Length -or $text[$i] -eq "`n") {
      if ($row -eq $lineNum) { return $text.Substring($start, $i - $start) }
      $row++; $start = $i + 1
    }
  }
  return $null
}

function Convert-RowColToOffset([int]$row, [int]$col) {
  $text = $script:editorState.TextBuffer.ToString()
  $r = 0; $start = 0
  for ($i = 0; $i -le $text.Length; $i++) {
    if ($i -eq $text.Length -or $text[$i] -eq "`n") {
      if ($r -eq $row) { return $start + [Math]::Max(0, [Math]::Min($col, $i - $start)) }
      $r++; $start = $i + 1
    }
  }
  return $text.Length
}

#endregion
#region Selection Helpers
function Get-SelectionBoundaries {
  return [Math]::Min($script:editorState.SelectionAnchor, $script:editorState.CursorOffset),
  [Math]::Max($script:editorState.SelectionAnchor, $script:editorState.CursorOffset)
}

#endregion
#region Editor State Reset
function Reset-EditorState {
  Set-BufferContent ''
  $script:editorState.CursorOffset = 0; $script:editorState.PreferredColumn = 0
  $script:editorState.VerticalScrollRow = 0; $script:editorState.HorizontalScrollOffset = 0
  $script:editorState.FilePath = ''; $script:editorState.Language = 'Plain Text'
  $script:editorState.IsDirty = $false; $script:editorState.StatusMessage = ''; $script:editorState.LastSearchTerm = ''
  $script:editorState.UndoStack.Clear(); $script:editorState.RedoStack.Clear()
  $script:editorState.EditorMode = 'edit'; $script:editorState.SearchBuffer = ''
  $script:editorState.IsSelectionActive = $false; $script:editorState.SelectionAnchor = 0
  $script:editorState.SyntaxTokenCache = @{}
  $script:editorState.AutocompleteMatches = $null
  $script:editorState.AutocompleteIndex = 0
  $script:editorState.AutocompleteBaseOffset = 0
}

#endregion
#region File I/O
function Import-FileIntoEditor([string]$path) {
  $script:editorState.FilePath = $path
  $script:editorState.Language = Get-LanguageFromPath $path
  $raw = if (Test-Path $path) {
    [IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  } else { '' }
  Set-BufferContent $raw
  $script:editorState.CursorOffset = 0; $script:editorState.PreferredColumn = 0
  $script:editorState.VerticalScrollRow = 0; $script:editorState.HorizontalScrollOffset = 0
}

function Save-EditorFile {
  if ([string]::IsNullOrWhiteSpace($script:editorState.FilePath)) { $script:editorState.StatusMessage = ' No path '; return }
  $content = Get-BufferText
  if ($script:editorConfigSettings.trim_trailing_whitespace) {
    $content = ($content -split "`n", -1 | ForEach-Object { $_.TrimEnd() }) -join "`n"
  }
  if ($script:editorConfigSettings.insert_final_newline -and -not $content.EndsWith("`n")) { $content += "`n" }
  switch ($script:editorConfigSettings.end_of_line) {
    'crlf' { $content = $content -replace "`n", "`r`n" }
    'cr' { $content = $content -replace "`n", "`r" }
  }
  $enc = switch ($script:editorConfigSettings.charset) {
    'utf-8-bom' { [Text.UTF8Encoding]::new($true) }
    'latin1' { [Text.Encoding]::Latin1 }
    default { [Text.UTF8Encoding]::new($false) }
  }
  [IO.File]::WriteAllText($script:editorState.FilePath, $content, $enc)
  $script:editorState.IsDirty = $false; $script:editorState.StatusMessage = ' Saved '
}

#endregion
#region Undo Redo
function Push-UndoSnapshot {
  if ($script:editorState.UndoStack.Count -ge 200) {
    $arr = $script:editorState.UndoStack.ToArray()
    $script:editorState.UndoStack.Clear()
    for ($i = 0; $i -lt ($arr.Count - 100); $i++) {
      $script:editorState.UndoStack.Push($arr[$arr.Count - 1 - $i])
    }
  }
  $script:editorState.UndoStack.Push([PSCustomObject]@{
      Buffer = Get-BufferText; Cursor = $script:editorState.CursorOffset; Preferred = $script:editorState.PreferredColumn
    })
  $script:editorState.RedoStack.Clear()
  $script:editorState.SyntaxTokenCache = @{}
}

function Restore-Snapshot($snap, $targetStack) {
  $targetStack.Push([PSCustomObject]@{
      Buffer = Get-BufferText; Cursor = $script:editorState.CursorOffset; Preferred = $script:editorState.PreferredColumn
    })
  Set-BufferContent $snap.Buffer
  $script:editorState.CursorOffset = [Math]::Min($snap.Cursor, $script:editorState.TextBuffer.Length)
  $script:editorState.PreferredColumn = $snap.Preferred
  $script:editorState.VerticalScrollRow = 0
  $script:editorState.HorizontalScrollOffset = 0
  $script:editorState.IsDirty = $true
  Clear-RenderCache
}

function Undo-LastChange {
  if ($script:editorState.UndoStack.Count -eq 0) { $script:editorState.StatusMessage = ' Nothing to undo '; return }
  Restore-Snapshot $script:editorState.UndoStack.Pop() $script:editorState.RedoStack
}

function Redo-LastChange {
  if ($script:editorState.RedoStack.Count -eq 0) { $script:editorState.StatusMessage = ' Nothing to redo '; return }
  Restore-Snapshot $script:editorState.RedoStack.Pop() $script:editorState.UndoStack
}

#endregion
#region Selection Operations
function Get-SelectedText {
  if (-not $script:editorState.IsSelectionActive) { return [string]::Empty }
  $s, $e = Get-SelectionBoundaries
  (Get-BufferText).Substring($s, $e - $s)
}

function Remove-SelectedText {
  if (-not $script:editorState.IsSelectionActive) { return }
  $s, $e = Get-SelectionBoundaries
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $s) + $t.Substring($e))
  $script:editorState.CursorOffset = $s
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.IsSelectionActive = $false; $script:editorState.IsDirty = $true
}

function Start-Selection {
  if (-not $script:editorState.IsSelectionActive) {
    $script:editorState.IsSelectionActive = $true
    $script:editorState.SelectionAnchor = $script:editorState.CursorOffset
  }
}

#endregion
#region Paste Text
function Insert-TextFromClipboard([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { $script:editorState.StatusMessage = ' Clipboard empty '; return }
  Push-UndoSnapshot
  if ($script:editorState.IsSelectionActive) { Remove-SelectedText }
  $norm = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $norm = $norm -replace "`e\[200~", '' -replace "`e\[201~", ''
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $script:editorState.CursorOffset) + $norm + $t.Substring($script:editorState.CursorOffset))
  $script:editorState.CursorOffset += $norm.Length
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.IsDirty = $true; $script:editorState.StatusMessage = ' Pasted (clipboard) '
  Clear-RenderCache
}

#endregion
#region Scroll Position
function Set-ScrollPosition {
  try { $height = [Console]::WindowHeight - 2 } catch { $height = 22 }
  if ($height -lt 1) { $height = 1 }
  $cursorRow = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  if ($cursorRow -lt $script:editorState.VerticalScrollRow) { $script:editorState.VerticalScrollRow = $cursorRow }
  elseif ($cursorRow -gt $script:editorState.VerticalScrollRow + $height - 1) { $script:editorState.VerticalScrollRow = $cursorRow - $height + 1 }
  $script:editorState.VerticalScrollRow = [Math]::Max(0, $script:editorState.VerticalScrollRow)

  try { $textWidth = [Console]::WindowWidth - 5 } catch { $textWidth = 75 }
  $cursorCol = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  if ($cursorCol -lt $script:editorState.HorizontalScrollOffset) { $script:editorState.HorizontalScrollOffset = $cursorCol }
  elseif ($cursorCol -ge $script:editorState.HorizontalScrollOffset + $textWidth) { $script:editorState.HorizontalScrollOffset = $cursorCol - $textWidth + 1 }
  $script:editorState.HorizontalScrollOffset = [Math]::Max(0, $script:editorState.HorizontalScrollOffset)
}

#endregion
#region Render Cache
$script:cachedRenderRows = [System.Collections.Generic.List[string]]::new()
$script:cachedCursorRow = -1
$script:cachedCursorColumn = -1

function Clear-RenderCache {
  $script:cachedRenderRows.Clear()
  $script:cachedCursorRow = -1
  $script:cachedCursorColumn = -1
}

#endregion
#region Cursor Movement
function Move-CursorLeft {
  if ($script:editorState.IsSelectionActive) { $script:editorState.CursorOffset = (Get-SelectionBoundaries)[0] }
  elseif ($script:editorState.CursorOffset -gt 0) { $script:editorState.CursorOffset-- }
  $script:editorState.IsSelectionActive = $false
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.AutocompleteMatches = $null
}

function Move-CursorRight {
  if ($script:editorState.IsSelectionActive) { $script:editorState.CursorOffset = (Get-SelectionBoundaries)[1] }
  elseif ($script:editorState.CursorOffset -lt $script:editorState.TextBuffer.Length) { $script:editorState.CursorOffset++ }
  $script:editorState.IsSelectionActive = $false
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.AutocompleteMatches = $null
}

function Move-CursorUp([bool]$extendSelection = $false) {
  if ($extendSelection -and -not $script:editorState.IsSelectionActive) { $script:editorState.SelectionAnchor = $script:editorState.CursorOffset; $script:editorState.IsSelectionActive = $true }
  if (-not $extendSelection) { $script:editorState.IsSelectionActive = $false }
  $row = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  if ($row -gt 0) { $script:editorState.CursorOffset = Convert-RowColToOffset ($row - 1) $script:editorState.PreferredColumn }
  $script:editorState.AutocompleteMatches = $null
}

function Move-CursorDown([bool]$extendSelection = $false) {
  if ($extendSelection -and -not $script:editorState.IsSelectionActive) { $script:editorState.SelectionAnchor = $script:editorState.CursorOffset; $script:editorState.IsSelectionActive = $true }
  if (-not $extendSelection) { $script:editorState.IsSelectionActive = $false }
  $row = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  $script:editorState.CursorOffset = Convert-RowColToOffset ($row + 1) $script:editorState.PreferredColumn
  $script:editorState.AutocompleteMatches = $null
}

function Move-CursorHome([bool]$extendSelection = $false) {
  if ($extendSelection -and -not $script:editorState.IsSelectionActive) { $script:editorState.SelectionAnchor = $script:editorState.CursorOffset; $script:editorState.IsSelectionActive = $true }
  if (-not $extendSelection) { $script:editorState.IsSelectionActive = $false }
  $script:editorState.CursorOffset = Get-LineStartOffset $script:editorState.CursorOffset
  $script:editorState.PreferredColumn = 0; $script:editorState.AutocompleteMatches = $null
}

function Move-CursorEnd([bool]$extendSelection = $false) {
  if ($extendSelection -and -not $script:editorState.IsSelectionActive) { $script:editorState.SelectionAnchor = $script:editorState.CursorOffset; $script:editorState.IsSelectionActive = $true }
  if (-not $extendSelection) { $script:editorState.IsSelectionActive = $false }
  $script:editorState.CursorOffset = Get-LineEndOffset $script:editorState.CursorOffset
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]; $script:editorState.AutocompleteMatches = $null
}

function Move-CursorPageUp {
  $script:editorState.IsSelectionActive = $false; $script:editorState.AutocompleteMatches = $null
  try { $page = [Console]::WindowHeight - 2 } catch { $page = 22 }
  $row = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  $script:editorState.CursorOffset = Convert-RowColToOffset ([Math]::Max(0, $row - $page)) $script:editorState.PreferredColumn
}

function Move-CursorPageDown {
  $script:editorState.IsSelectionActive = $false; $script:editorState.AutocompleteMatches = $null
  try { $page = [Console]::WindowHeight - 2 } catch { $page = 22 }
  $row = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  $script:editorState.CursorOffset = Convert-RowColToOffset ($row + $page) $script:editorState.PreferredColumn
}

#endregion
#region Editing Operations
function Insert-Newline {
  Push-UndoSnapshot
  if ($script:editorState.IsSelectionActive) { Remove-SelectedText }
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $script:editorState.CursorOffset) + "`n" + $t.Substring($script:editorState.CursorOffset))
  $script:editorState.CursorOffset++
  $script:editorState.PreferredColumn = 0; $script:editorState.IsDirty = $true; $script:editorState.AutocompleteMatches = $null
}

function Remove-Backward {
  if ($script:editorState.IsSelectionActive) { Push-UndoSnapshot; Remove-SelectedText; $script:editorState.AutocompleteMatches = $null; return }
  if ($script:editorState.CursorOffset -gt 0) {
    Push-UndoSnapshot
    $t = Get-BufferText
    Set-BufferContent ($t.Substring(0, $script:editorState.CursorOffset - 1) + $t.Substring($script:editorState.CursorOffset))
    $script:editorState.CursorOffset--
    $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]; $script:editorState.IsDirty = $true
  }
  $script:editorState.AutocompleteMatches = $null
}

function Remove-Forward {
  if ($script:editorState.IsSelectionActive) { Push-UndoSnapshot; Remove-SelectedText; $script:editorState.AutocompleteMatches = $null; return }
  if ($script:editorState.CursorOffset -lt $script:editorState.TextBuffer.Length) {
    Push-UndoSnapshot
    $t = Get-BufferText
    Set-BufferContent ($t.Substring(0, $script:editorState.CursorOffset) + $t.Substring($script:editorState.CursorOffset + 1))
    $script:editorState.IsDirty = $true
  }
  $script:editorState.AutocompleteMatches = $null
}

function Insert-Char([char]$ch) {
  Push-UndoSnapshot
  if ($script:editorState.IsSelectionActive) { Remove-SelectedText }
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $script:editorState.CursorOffset) + $ch + $t.Substring($script:editorState.CursorOffset))
  $script:editorState.CursorOffset++
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.IsDirty = $true
  $script:editorState.AutocompleteMatches = $null
}

function Insert-Indentation {
  Push-UndoSnapshot
  Insert-TextAtCursor (Get-IndentationString)
}

#endregion
#region Autocomplete Helpers
function Get-WordPrefixAtCursor {
  $t = Get-BufferText
  $end = $script:editorState.CursorOffset
  $start = $end
  while ($start -gt 0 -and $t[$start - 1] -match '[\w]') { $start-- }
  return $t.Substring($start, $end - $start)
}

function Get-AllWordsInBuffer {
  $t = Get-BufferText
  return $t -split '\W+' | Where-Object { $_.Length -gt 1 } | Sort-Object -Unique
}

function Insert-TextAtCursor([string]$s) {
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $script:editorState.CursorOffset) + $s + $t.Substring($script:editorState.CursorOffset))
  $script:editorState.CursorOffset += $s.Length
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.IsDirty = $true
  Clear-RenderCache
}

function Set-CurrentWord([string]$newWord) {
  $t = Get-BufferText
  $prefix = Get-WordPrefixAtCursor
  $start = $script:editorState.CursorOffset - $prefix.Length
  $before = $t.Substring(0, $start)
  $after = $t.Substring($script:editorState.CursorOffset)
  Set-BufferContent ($before + $newWord + $after)
  $script:editorState.CursorOffset = $start + $newWord.Length
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.IsDirty = $true
  Clear-RenderCache
}

#endregion
#region Search
function Search-ForTerm([string]$term) {
  if ([string]::IsNullOrWhiteSpace($term)) { return }
  $script:editorState.LastSearchTerm = $term
  $script:editorState.IsSelectionActive = $false
  $t = Get-BufferText
  $ix = $t.IndexOf($term, [Math]::Min($script:editorState.CursorOffset + 1, $t.Length), [StringComparison]::OrdinalIgnoreCase)
  if ($ix -lt 0) { $ix = $t.IndexOf($term, 0, [StringComparison]::OrdinalIgnoreCase) }
  if ($ix -lt 0) { $script:editorState.StatusMessage = ' Not found '; return }
  $script:editorState.IsSelectionActive = $true
  $script:editorState.SelectionAnchor = $ix
  $script:editorState.CursorOffset = $ix + $term.Length
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.StatusMessage = ' Found '
}

#endregion
#region Editor State Accessors
function Get-EditorState {
  return $script:editorState
}

function Set-EditorState([PSCustomObject]$state) {
  $script:editorState = $state
}
#endregion