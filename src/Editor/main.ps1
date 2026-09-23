<#
.SYNOPSIS
    Entry point for the babae terminal editor session.
.DESCRIPTION
    Initializes the editor, loads the target file or creates a new buffer,
    enters the main render loop, and restores the terminal on exit.
.NOTES
    Degrades gracefully when I/O is redirected (tests, pipes) by skipping
    raw console setup.
#>

$ErrorActionPreference = 'Stop'

function Start-BabaeEditor {
  <#
  .SYNOPSIS
      Starts the babae editor session for an optional file path.
  .DESCRIPTION
      Performs install check, state reset, optional file load, then enters
      the main loop that renders frames and dispatches input until exit.
  #>
  param([Parameter(Position = 0)][string]$Path)

  trap {
    Write-Host "TRAP: $_" -ForegroundColor Red
    Write-Host "TRAP: $($_.ScriptStackTrace)" -ForegroundColor Red
    continue
  }

  Invoke-InstallCheck

  Reset-EditorState
  Clear-RenderCache

  if ($Path) {
    $resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
    $editorState.FilePath = if ($resolved) { $resolved.Path } else { Join-Path $PWD $Path }
    Import-FileIntoEditor $editorState.FilePath
    Import-EditorConfig $editorState.FilePath
  } else {
    Set-BufferContent ''
    Import-EditorConfig ''
  }

  $prevW = 0; $prevH = 0
  $script:shouldExitApplication = $false

  try {
    # In test environments with redirected I/O, console handles are invalid.
    # Skip TreatControlCAsInput and raw mode when handles cannot be prepared.
    $hasValidConsole = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
    if ($hasValidConsole) {
      try { [Console]::TreatControlCAsInput = $true } catch {}
      Enter-RawInputMode
    }

    # Alternate-buffer entry + cursor hide + screen clear + mouse disable + autowrap disable.
    Write-OutputBuffer("`e[?1049h`e[?2004h`e[?25l`e[2J`e[3J`e[H")
    Write-OutputBuffer($script:SEQ_MOUSE_TRACKING_OFF)
    Write-OutputBuffer($script:SEQ_AUTOWRAP_OFF)

    while (-not $script:shouldExitApplication) {
      try { $w = [Console]::WindowWidth; $h = [Console]::WindowHeight } catch { $w = 80; $h = 24 }
      if ($w -ne $prevW -or $h -ne $prevH) {
        $prevW = $w; $prevH = $h; Clear-RenderCache
        Set-ScrollMargins 2 ($h - 1)
      }

      Set-ScrollPosition

      if ($editorState.EditorMode -eq 'confirm-quit') {
        Show-ConfirmQuitDialog
        continue
      }

      Write-EditorFrame

      $ev = Read-InputEvent
      if ($ev.Kind -eq 'Paste') { Insert-TextFromClipboard $ev.Text }
      else {
        switch ($editorState.EditorMode) {
          'edit' { Invoke-EditingKey $ev.KeyInfo }
          'search' { Invoke-SearchKey $ev.KeyInfo }
          'save-as' { Invoke-SaveAsKey $ev.KeyInfo }
        }
      }
      Set-CursorOffsetBounds
    }
  } finally {
    Exit-RawInputMode
    try { [Console]::TreatControlCAsInput = $true } catch {}
    Reset-ScrollMargins
    Write-OutputBuffer($script:SEQ_MOUSE_TRACKING_OFF)
    Write-OutputBuffer("`e[?2004l`e[?1049l`e[?25h`e[0m")
    Write-OutputBuffer($script:SEQ_AUTOWRAP_ON)
    Write-Host 'babae: session ended.' -ForegroundColor Cyan
    if ($editorState.FilePath) { Write-Host "File : $($editorState.FilePath)" -ForegroundColor DarkGray }
  }
}

Set-Alias -Name babae -Value Start-BabaeEditor -Scope Global
