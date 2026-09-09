$ErrorActionPreference = 'Stop'

function Start-BabaeEditor {
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
    # In test environments with redirected I/O, console handles are invalid
    # Skip TreatControlCAsInput and raw mode if handles are invalid
    $hasValidConsole = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
    if ($hasValidConsole) {
      try { [Console]::TreatControlCAsInput = $true } catch {}
      Enter-RawInputMode
    }
    Write-OutputBuffer("`e[?1049h`e[?2004h`e[?25l`e[2J`e[3J`e[H")
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