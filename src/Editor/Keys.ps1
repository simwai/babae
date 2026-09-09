$ErrorActionPreference = 'Stop'

#region Search Mode Handler
function Invoke-SearchKey([ConsoleKeyInfo]$ki) {
  $editorState = Get-EditorState
  switch ($ki.Key) {
    'Escape' { $editorState.EditorMode = 'edit'; $editorState.SearchBuffer = ''; return }
    'Enter' { $editorState.EditorMode = 'edit'; Search-ForTerm $editorState.SearchBuffer; return }
    'Backspace' { if ($editorState.SearchBuffer.Length -gt 0) { $editorState.SearchBuffer = $editorState.SearchBuffer.Substring(0, $editorState.SearchBuffer.Length - 1) }; return }
    default { if ($ki.KeyChar -ne [char]0 -and -not [char]::IsControl($ki.KeyChar)) { $editorState.SearchBuffer += [string]$ki.KeyChar } }
  }
}

#endregion
#region Save As Mode Handler
function Invoke-SaveAsKey([ConsoleKeyInfo]$ki) {
  $editorState = Get-EditorState
  switch ($ki.Key) {
    'Escape' { $editorState.EditorMode = 'edit'; $editorState.SaveAsBuffer = ''; return }
    'Enter' {
      if ([string]::IsNullOrWhiteSpace($editorState.SaveAsBuffer)) { return }
      $editorState.FilePath = Join-Path $PWD $editorState.SaveAsBuffer
      $editorState.Language = Get-LanguageFromPath $editorState.FilePath
      Import-EditorConfig $editorState.FilePath
      Save-EditorFile
      $editorState.EditorMode = 'edit'; $editorState.SaveAsBuffer = ''
      return
    }
    'Backspace' { if ($editorState.SaveAsBuffer.Length -gt 0) { $editorState.SaveAsBuffer = $editorState.SaveAsBuffer.Substring(0, $editorState.SaveAsBuffer.Length - 1) }; return }
    default { if ($ki.KeyChar -ne [char]0 -and -not [char]::IsControl($ki.KeyChar)) { $editorState.SaveAsBuffer += [string]$ki.KeyChar } }
  }
}


#endregion
#region Editing Key Handler
function Invoke-EditingKey([ConsoleKeyInfo]$ki) {
  $editorState = Get-EditorState
  $key = $ki.Key
  $ctrl = ($ki.Modifiers -band [ConsoleModifiers]::Control) -ne 0
  $shift = ($ki.Modifiers -band [ConsoleModifiers]::Shift) -ne 0
  $ch = $ki.KeyChar

  if ($ctrl) {
    switch ($key) {
      'T' { Set-CurrentThemeIndex (($script:currentThemeIndex + 1) % $script:availableThemeNames.Count); $editorState.StatusMessage = " Theme: $(Get-CurrentThemeDisplayName) "; Clear-RenderCache; return }
      'S' {
        if ([string]::IsNullOrWhiteSpace($editorState.FilePath)) {
          $editorState.EditorMode = 'save-as'; $editorState.SaveAsBuffer = ''
        } else { Save-EditorFile }
        return
      }
      'Q' { $editorState.EditorMode = 'confirm-quit'; return }
      'Z' { Undo-LastChange; return }
      'Y' { Redo-LastChange; return }
      'F' { $editorState.EditorMode = 'search'; $editorState.SearchBuffer = ''; return }
      'A' { $editorState.IsSelectionActive = $true; $editorState.SelectionAnchor = 0; $editorState.CursorOffset = $editorState.TextBuffer.Length; $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; return }
      'C' { $selected = Get-SelectedText; if ([string]::IsNullOrEmpty($selected)) { $selected = Get-LineByNumber (Convert-OffsetToRowCol $editorState.CursorOffset)[0] }; Set-ClipboardContent $selected; $editorState.StatusMessage = ' Copied to clipboard '; return }
      'V' { Insert-TextFromClipboard (Get-ClipboardContent); return }
      'F1' { Show-HelpDialog; return }
    }
    return
  }

  switch ($key) {
    'LeftArrow' {
      if ($editorState.IsSelectionActive -and -not $shift) { $editorState.CursorOffset = (Get-SelectionBoundaries)[0] }
      elseif ($editorState.CursorOffset -gt 0) {
        if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
        $editorState.CursorOffset--
      }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; $editorState.AutocompleteMatches = $null
      return
    }
    'RightArrow' {
      if ($editorState.IsSelectionActive -and -not $shift) { $editorState.CursorOffset = (Get-SelectionBoundaries)[1] }
      elseif ($editorState.CursorOffset -lt $editorState.TextBuffer.Length) {
        if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
        $editorState.CursorOffset++
      }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; $editorState.AutocompleteMatches = $null
      return
    }
    'UpArrow' {
      if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $row = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]
      if ($row -gt 0) { $editorState.CursorOffset = Convert-RowColToOffset ($row - 1) $editorState.PreferredColumn }
      $editorState.AutocompleteMatches = $null
      return
    }
    'DownArrow' {
      if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $row = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]
      $editorState.CursorOffset = Convert-RowColToOffset ($row + 1) $editorState.PreferredColumn
      $editorState.AutocompleteMatches = $null
      return
    }
    'Home' {
      if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $editorState.CursorOffset = Get-LineStartOffset $editorState.CursorOffset; $editorState.PreferredColumn = 0; $editorState.AutocompleteMatches = $null
      return
    }
    'End' {
      if ($shift -and -not $editorState.IsSelectionActive) { $editorState.SelectionAnchor = $editorState.CursorOffset; $editorState.IsSelectionActive = $true }
      if (-not $shift) { $editorState.IsSelectionActive = $false }
      $editorState.CursorOffset = Get-LineEndOffset $editorState.CursorOffset
      $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; $editorState.AutocompleteMatches = $null
      return
    }
    'PageUp' { $editorState.IsSelectionActive = $false; $editorState.AutocompleteMatches = $null; try { $page = [Console]::WindowHeight - 2 } catch { $page = 22 }; $row = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]; $editorState.CursorOffset = Convert-RowColToOffset ([Math]::Max(0, $row - $page)) $editorState.PreferredColumn; return }
    'PageDown' { $editorState.IsSelectionActive = $false; $editorState.AutocompleteMatches = $null; try { $page = [Console]::WindowHeight - 2 } catch { $page = 22 }; $row = (Convert-OffsetToRowCol $editorState.CursorOffset)[0]; $editorState.CursorOffset = Convert-RowColToOffset ($row + $page) $editorState.PreferredColumn; return }
    'Enter' {
      Push-UndoSnapshot
      if ($editorState.IsSelectionActive) { Remove-SelectedText }
      $t = Get-BufferText
      Set-BufferContent ($t.Substring(0, $editorState.CursorOffset) + "`n" + $t.Substring($editorState.CursorOffset))
      $editorState.CursorOffset++
      $editorState.PreferredColumn = 0; $editorState.IsDirty = $true; $editorState.AutocompleteMatches = $null; return
    }
    'Backspace' {
      if ($editorState.IsSelectionActive) { Push-UndoSnapshot; Remove-SelectedText; $editorState.AutocompleteMatches = $null; return }
      if ($editorState.CursorOffset -gt 0) {
        Push-UndoSnapshot
        $t = Get-BufferText
        Set-BufferContent ($t.Substring(0, $editorState.CursorOffset - 1) + $t.Substring($editorState.CursorOffset))
        $editorState.CursorOffset--
        $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]; $editorState.IsDirty = $true
      }
      $editorState.AutocompleteMatches = $null; return
    }
    'Delete' {
      if ($editorState.IsSelectionActive) { Push-UndoSnapshot; Remove-SelectedText; $editorState.AutocompleteMatches = $null; return }
      if ($editorState.CursorOffset -lt $editorState.TextBuffer.Length) {
        Push-UndoSnapshot
        $t = Get-BufferText
        Set-BufferContent ($t.Substring(0, $editorState.CursorOffset) + $t.Substring($editorState.CursorOffset + 1))
        $editorState.IsDirty = $true
      }
      $editorState.AutocompleteMatches = $null; return
    }
    'Tab' {
      $prefix = Get-WordPrefixAtCursor
      if ($prefix -ne '' -and ($null -eq $editorState.AutocompleteMatches)) {
        $words = Get-AllWordsInBuffer
        $matchedWords = @($words | Where-Object { $_ -like "$prefix*" } | Sort-Object -Unique)
        if ($matchedWords.Count -eq 1) {
          Push-UndoSnapshot
          Insert-TextAtCursor ([string]$matchedWords[0]).Substring($prefix.Length)
          $editorState.AutocompleteMatches = $null
        } elseif ($matchedWords.Count -gt 1) {
          $editorState.AutocompleteMatches = $matchedWords
          $editorState.AutocompleteIndex = 0
          $editorState.AutocompleteBaseOffset = $editorState.CursorOffset - $prefix.Length
          Push-UndoSnapshot
          Set-CurrentWord [string]$matchedWords[0]
        } else { Push-UndoSnapshot; Insert-TextAtCursor (Get-IndentationString) }
      } elseif ($null -ne $editorState.AutocompleteMatches) {
        $editorState.AutocompleteIndex = ($editorState.AutocompleteIndex + 1) % $editorState.AutocompleteMatches.Count
        $t = Get-BufferText
        $before = $t.Substring(0, $editorState.AutocompleteBaseOffset)
        $after = $t.Substring($editorState.CursorOffset)
        $newWord = $editorState.AutocompleteMatches[$editorState.AutocompleteIndex]
        Set-BufferContent ($before + $newWord + $after)
        $editorState.CursorOffset = $editorState.AutocompleteBaseOffset + $newWord.Length
        $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
        $editorState.IsDirty = $true
        Clear-RenderCache
      } else { Push-UndoSnapshot; Insert-TextAtCursor (Get-IndentationString) }
      return
    }
    'Escape' { $editorState.EditorMode = 'edit'; $editorState.SearchBuffer = ''; $editorState.IsSelectionActive = $false; $editorState.AutocompleteMatches = $null; return }
  }

  if ([int]$ch -ge 32 -and [int]$ch -ne 127) {
    Push-UndoSnapshot
    if ($editorState.IsSelectionActive) { Remove-SelectedText }
    $t = Get-BufferText
    Set-BufferContent ($t.Substring(0, $editorState.CursorOffset) + $ch + $t.Substring($editorState.CursorOffset))
    $editorState.CursorOffset++
    $editorState.PreferredColumn = (Convert-OffsetToRowCol $editorState.CursorOffset)[1]
    $editorState.IsDirty = $true
    $editorState.AutocompleteMatches = $null
  }
}
#endregion