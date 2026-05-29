function Render-Frame {
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

  if ($script:lastRows.Count -ne $height) {
    $script:lastRows.Clear(); for ($i = 0; $i -lt $height; $i++) { $script:lastRows.Add('') }
  }
  $dirty = [System.Text.StringBuilder]::new()
  for ($row = 0; $row -lt $height; $row++) {
    if ($script:diagPaneVisible -and $row -ge ($script:diagDividerRow - 1) -and $row -lt ($height - 1)) {
      $rendered = Build-DiagRow $row $width
    } else { $rendered = Build-EditorRow $row $width $textWidth }
    if ($script:lastRows[$row] -ne $rendered) {
      $script:lastRows[$row] = $rendered; [void]$dirty.Append((Move-To ($row + 1) 1)); [void]$dirty.Append($rendered)
    }
  }
  $curR, $curC = OffsetToRowCol $state.Cursor
  $vRow = ($curR - $state.ScrollRow) + 1; $vCol = $curC + 6
  if ($vRow -ge 1 -and $vRow -lt ($height - ($script:diagPaneVisible ? $script:diagPaneHeight + 1 : 0))) {
    [void]$dirty.Append((Move-To $vRow $vCol))
    if (-not $script:lastCursorVisible) { [void]$dirty.Append("`e[?25h"); $script:lastCursorVisible = $true }
  } else {
    if ($script:lastCursorVisible) { [void]$dirty.Append("`e[?25l"); $script:lastCursorVisible = $false }
  }
  Out-Flush $dirty.ToString()
}
