<#
.SYNOPSIS
    Mutable editor state and buffer operations.
.DESCRIPTION
    Defines the central editor state object and provides buffer accessors,
    offset/row/col conversion, selection helpers, undo/redo, file I/O,
    scroll position, and search.
#>

$ErrorActionPreference = 'Stop'

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

function Get-BufferText {
  <#
  .SYNOPSIS
      Returns the current buffer content as a string.
  #>
  $script:editorState.TextBuffer.ToString()
}

function Set-BufferContent([string]$text) {
  <#
  .SYNOPSIS
      Replaces the buffer content and resets the syntax token cache.
  #>
  $script:editorState.TextBuffer.Clear() | Out-Null
  if ($text) { $script:editorState.TextBuffer.Append($text) | Out-Null }
  $script:editorState.SyntaxTokenCache = @{}
}

function Set-CursorOffsetBounds {
  <#
  .SYNOPSIS
      Clamps the cursor offset to the current buffer length.
  #>
  $script:editorState.CursorOffset = [Math]::Max(0, [Math]::Min($script:editorState.CursorOffset, $script:editorState.TextBuffer.Length))
}

function Convert-OffsetToRowCol([int]$offset) {
  <#
  .SYNOPSIS
      Converts a character offset to (row, column) coordinates.
  .DESCRIPTION
      Row and column are zero-based. Column is measured from the start of
      the line, not from the gutter.
  #>
  $text = $script:editorState.TextBuffer.ToString()
  $clamped = [Math]::Max(0, [Math]::Min($offset, $text.Length))
  $row = 0; $lineStart = 0
  for ($i = 0; $i -lt $clamped; $i++) {
    if ($text[$i] -eq "`n") { $row++; $lineStart = $i + 1 }
  }
  return $row, ($clamped - $lineStart)
}

function Get-LineStartOffset([int]$offset) {
  <#
  .SYNOPSIS
      Returns the offset of the first character on the line containing offset.
  #>
  $text = $script:editorState.TextBuffer.ToString()
  while ($offset -gt 0 -and $text[$offset - 1] -ne "`n") { $offset-- }
  return $offset
}

function Get-LineEndOffset([int]$offset) {
  <#
  .SYNOPSIS
      Returns the offset just past the last character on the line containing offset.
  #>
  $text = $script:editorState.TextBuffer.ToString()
  while ($offset -lt $text.Length -and $text[$offset] -ne "`n") { $offset++ }
  return $offset
}

function Get-LineByNumber([int]$lineNum) {
  <#
  .SYNOPSIS
      Returns the text of a zero-based line number, or $null if out of range.
  #>
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
  <#
  .SYNOPSIS
      Converts (row, column) coordinates to a character offset.
  .DESCRIPTION
      Column is clamped to the line length so callers never receive an
      offset beyond the buffer.
  #>
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

function Get-SelectionBoundaries {
  <#
  .SYNOPSIS
      Returns the ordered (start, end) offsets of the active selection.
  #>
  return [Math]::Min($script:editorState.SelectionAnchor, $script:editorState.CursorOffset),
  [Math]::Max($script:editorState.SelectionAnchor, $script:editorState.CursorOffset)
}

function Reset-EditorState {
  <#
  .SYNOPSIS
      Resets all mutable editor state to defaults for a fresh session.
  #>
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

function Import-FileIntoEditor([string]$path) {
  <#
  .SYNOPSIS
      Loads a file into the editor buffer and updates file metadata.
  .DESCRIPTION
      Reads the file with LF normalization, sets the language from the
      path, and resets scroll/cursor state.
  #>
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
  <#
  .SYNOPSIS
      Writes the buffer to disk using the current editor config.
  .DESCRIPTION
      Applies trailing-whitespace trimming, final-newline insertion, line-
      ending conversion, and charset selection before writing.
  #>
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

function Push-UndoSnapshot {
  <#
  .SYNOPSIS
      Pushes the current buffer/cursor state onto the undo stack.
  .DESCRIPTION
      Caps the undo stack at 200 entries, retaining the most recent 100
      when the cap is exceeded. Clears the redo stack on new changes.
  #>
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
  <#
  .SYNOPSIS
      Restores a snapshot onto the target stack and swaps buffer state.
  #>
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
  <#
  .SYNOPSIS
      Pops the last undo snapshot and restores the previous buffer state.
  #>
  if ($script:editorState.UndoStack.Count -eq 0) { $script:editorState.StatusMessage = ' Nothing to undo '; return }
  Restore-Snapshot $script:editorState.UndoStack.Pop() $script:editorState.RedoStack
}

function Redo-LastChange {
  <#
  .SYNOPSIS
      Pops the last redo snapshot and restores the forward buffer state.
  #>
  if ($script:editorState.RedoStack.Count -eq 0) { $script:editorState.StatusMessage = ' Nothing to redo '; return }
  Restore-Snapshot $script:editorState.RedoStack.Pop() $script:editorState.UndoStack
}

function Get-SelectedText {
  <#
  .SYNOPSIS
      Returns the currently selected text, or an empty string if none.
  #>
  if (-not $script:editorState.IsSelectionActive) { return [string]::Empty }
  $s, $e = Get-SelectionBoundaries
  (Get-BufferText).Substring($s, $e - $s)
}

function Remove-SelectedText {
  <#
  .SYNOPSIS
      Deletes the selected range and collapses the cursor to its start.
  #>
  if (-not $script:editorState.IsSelectionActive) { return }
  $s, $e = Get-SelectionBoundaries
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $s) + $t.Substring($e))
  $script:editorState.CursorOffset = $s
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.IsSelectionActive = $false; $script:editorState.IsDirty = $true
}

function Start-Selection {
  <#
  .SYNOPSIS
      Activates selection anchored at the current cursor position.
  #>
  if (-not $script:editorState.IsSelectionActive) {
    $script:editorState.IsSelectionActive = $true
    $script:editorState.SelectionAnchor = $script:editorState.CursorOffset
  }
}

function Insert-TextFromClipboard([string]$text) {
  <#
  .SYNOPSIS
      Inserts clipboard text at the cursor, replacing any active selection.
  .DESCRIPTION
      Normalizes line endings to LF, strips paste bracketing sequences,
      and updates cursor, dirty state, and render cache.
  #>
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

function Set-ScrollPosition {
  <#
  .SYNOPSIS
      Adjusts vertical and horizontal scroll offsets to keep the cursor visible.
  #>
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

$script:cachedRenderRows = [System.Collections.Generic.List[string]]::new()
$script:cachedCursorRow = -1
$script:cachedCursorColumn = -1

function Clear-RenderCache {
  <#
  .SYNOPSIS
      Invalidates cached rendered rows and cursor screen coordinates.
  #>
  $script:cachedRenderRows.Clear()
  $script:cachedCursorRow = -1
  $script:cachedCursorColumn = -1
}

function Move-CursorLeft {
  <#
  .SYNOPSIS
      Moves the cursor left, collapsing selection if active.
  #>
  if ($script:editorState.IsSelectionActive) { $script:editorState.CursorOffset = (Get-SelectionBoundaries)[0] }
  elseif ($script:editorState.CursorOffset -gt 0) { $script:editorState.CursorOffset-- }
  $script:editorState.IsSelectionActive = $false
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.AutocompleteMatches = $null
}

function Move-CursorRight {
  <#
  .SYNOPSIS
      Moves the cursor right, collapsing selection if active.
  #>
  if ($script:editorState.IsSelectionActive) { $script:editorState.CursorOffset = (Get-SelectionBoundaries)[1] }
  elseif ($script:editorState.CursorOffset -lt $script:editorState.TextBuffer.Length) { $script:editorState.CursorOffset++ }
  $script:editorState.IsSelectionActive = $false
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.AutocompleteMatches = $null
}

function Move-CursorUp([bool]$extendSelection = $false) {
  <#
  .SYNOPSIS
      Moves the cursor up, optionally extending the selection.
  #>
  if ($extendSelection -and -not $script:editorState.IsSelectionActive) { $script:editorState.SelectionAnchor = $script:editorState.CursorOffset; $script:editorState.IsSelectionActive = $true }
  if (-not $extendSelection) { $script:editorState.IsSelectionActive = $false }
  $row = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  if ($row -gt 0) { $script:editorState.CursorOffset = Convert-RowColToOffset ($row - 1) $script:editorState.PreferredColumn }
  $script:editorState.AutocompleteMatches = $null
}

function Move-CursorDown([bool]$extendSelection = $false) {
  <#
  .SYNOPSIS
      Moves the cursor down, optionally extending the selection.
  #>
  if ($extendSelection -and -not $script:editorState.IsSelectionActive) { $script:editorState.SelectionAnchor = $script:editorState.CursorOffset; $script:editorState.IsSelectionActive = $true }
  if (-not $extendSelection) { $script:editorState.IsSelectionActive = $false }
  $row = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  $script:editorState.CursorOffset = Convert-RowColToOffset ($row + 1) $script:editorState.PreferredColumn
  $script:editorState.AutocompleteMatches = $null
}

function Move-CursorHome([bool]$extendSelection = $false) {
  <#
  .SYNOPSIS
      Moves the cursor to the start of the line, optionally extending selection.
  #>
  if ($extendSelection -and -not $script:editorState.IsSelectionActive) { $script:editorState.SelectionAnchor = $script:editorState.CursorOffset; $script:editorState.IsSelectionActive = $true }
  if (-not $extendSelection) { $script:editorState.IsSelectionActive = $false }
  $script:editorState.CursorOffset = Get-LineStartOffset $script:editorState.CursorOffset
  $script:editorState.PreferredColumn = 0; $script:editorState.AutocompleteMatches = $null
}

function Move-CursorEnd([bool]$extendSelection = $false) {
  <#
  .SYNOPSIS
      Moves the cursor to the end of the line, optionally extending selection.
  #>
  if ($extendSelection -and -not $script:editorState.IsSelectionActive) { $script:editorState.SelectionAnchor = $script:editorState.CursorOffset; $script:editorState.IsSelectionActive = $true }
  if (-not $extendSelection) { $script:editorState.IsSelectionActive = $false }
  $script:editorState.CursorOffset = Get-LineEndOffset $script:editorState.CursorOffset
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]; $script:editorState.AutocompleteMatches = $null
}

function Move-CursorPageUp {
  <#
  .SYNOPSIS
      Moves the cursor up by one screenful, collapsing selection.
  #>
  $script:editorState.IsSelectionActive = $false; $script:editorState.AutocompleteMatches = $null
  try { $page = [Console]::WindowHeight - 2 } catch { $page = 22 }
  $row = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  $script:editorState.CursorOffset = Convert-RowColToOffset ([Math]::Max(0, $row - $page)) $script:editorState.PreferredColumn
}

function Move-CursorPageDown {
  <#
  .SYNOPSIS
      Moves the cursor down by one screenful, collapsing selection.
  #>
  $script:editorState.IsSelectionActive = $false; $script:editorState.AutocompleteMatches = $null
  try { $page = [Console]::WindowHeight - 2 } catch { $page = 22 }
  $row = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[0]
  $script:editorState.CursorOffset = Convert-RowColToOffset ($row + $page) $script:editorState.PreferredColumn
}

#endregion
#region Editing Operations
function Insert-Newline {
  <#
  .SYNOPSIS
      Splits the current line at the cursor and records an undo snapshot.
  #>
  Push-UndoSnapshot
  if ($script:editorState.IsSelectionActive) { Remove-SelectedText }
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $script:editorState.CursorOffset) + "`n" + $t.Substring($script:editorState.CursorOffset))
  $script:editorState.CursorOffset++
  $script:editorState.PreferredColumn = 0; $script:editorState.IsDirty = $true; $script:editorState.AutocompleteMatches = $null
}

function Remove-Backward {
  <#
  .SYNOPSIS
      Deletes the character before the cursor, or the selection if active.
  #>
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
  <#
  .SYNOPSIS
      Deletes the character after the cursor, or the selection if active.
  #>
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
  <#
  .SYNOPSIS
      Inserts a single character at the cursor, replacing any selection.
  #>
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
  <#
  .SYNOPSIS
      Inserts the configured indentation string at the cursor.
  #>
  Push-UndoSnapshot
  Insert-TextAtCursor (Get-IndentationString)
}

#endregion
#region Autocomplete Helpers
function Get-WordPrefixAtCursor {
  <#
  .SYNOPSIS
      Returns the word fragment immediately before the cursor.
  #>
  $t = Get-BufferText
  $end = $script:editorState.CursorOffset
  $start = $end
  while ($start -gt 0 -and $t[$start - 1] -match '[\w]') { $start-- }
  return $t.Substring($start, $end - $start)
}

function Get-AllWordsInBuffer {
  <#
  .SYNOPSIS
      Returns unique words longer than one character from the buffer.
  #>
  $t = Get-BufferText
  return $t -split '\W+' | Where-Object { $_.Length -gt 1 } | Sort-Object -Unique
}

function Insert-TextAtCursor([string]$s) {
  <#
  .SYNOPSIS
      Inserts text at the cursor position and invalidates the render cache.
  #>
  $t = Get-BufferText
  Set-BufferContent ($t.Substring(0, $script:editorState.CursorOffset) + $s + $t.Substring($script:editorState.CursorOffset))
  $script:editorState.CursorOffset += $s.Length
  $script:editorState.PreferredColumn = (Convert-OffsetToRowCol $script:editorState.CursorOffset)[1]
  $script:editorState.IsDirty = $true
  Clear-RenderCache
}

function Set-CurrentWord([string]$newWord) {
  <#
  .SYNOPSIS
      Replaces the word under the cursor with newWord.
  #>
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

function Search-ForTerm([string]$term) {
  <#
  .SYNOPSIS
      Searches forward from the cursor for a case-insensitive match.
  .DESCRIPTION
      Wraps to the top of the buffer when no match is found ahead. Sets
      the active selection on success.
  #>
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

function Get-EditorState {
  <#
  .SYNOPSIS
      Returns the current editor state object.
  #>
  return $script:editorState
}

function Set-EditorState([PSCustomObject]$state) {
  <#
  .SYNOPSIS
      Replaces the current editor state object.
  #>
  $script:editorState = $state
}
