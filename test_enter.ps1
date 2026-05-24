$ErrorActionPreference = "Continue"
function Write-DiagLog { param($c, $m) }
. ./babae_no_run.ps1

$state = [PSCustomObject]@{
  Buffer       = [System.Text.StringBuilder]::new()
  Cursor       = 0
  UndoStack    = [System.Collections.Generic.Stack[object]]::new()
  RedoStack    = [System.Collections.Generic.Stack[object]]::new()
  PreferredCol = 0
  SelActive    = $false
  Mode         = 'edit'
  Dirty        = $false
}

function State-Snapshot {}
function Delete-Selection {}

$state.Buffer.Append("initial") | Out-Null
Rebuild-LineIndex
$state.Cursor = 3

$curLine = GetLine (OffsetToRowCol $state.Cursor)[0]
$leadingWS = if ($curLine -match '^(\s+)') { $Matches[1] } else { '' }
$ins = "`n" + $leadingWS; $t = $state.Buffer.ToString()
BufSet ($t.Substring(0, $state.Cursor) + $ins + $t.Substring($state.Cursor))
$state.Cursor += $ins.Length
$state.PreferredCol = $leadingWS.Length; $state.Dirty = $true

Write-Host "Buffer: '$($state.Buffer.ToString())'"
Write-Host "LineIndex: $($script:lineIndex -join ', ')"
