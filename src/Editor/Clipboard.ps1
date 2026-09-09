$ErrorActionPreference = 'Stop'

function Find-ClipboardTool {
  if ($IsWindows -or $env:OS -eq 'Windows_NT') { return 'WinForms' }
  if ($IsMacOS) { return 'pbcopy' }
  if (Get-Command wl-copy -ErrorAction SilentlyContinue) { return 'wl-copy' }
  if (Get-Command xclip -ErrorAction SilentlyContinue) { return 'xclip' }
  if (Get-Command xsel -ErrorAction SilentlyContinue) { return 'xsel' }
  return $null
}

function Get-ClipboardContent {
  $tool = Find-ClipboardTool
  try {
    switch ($tool) {
      'WinForms' { return [System.Windows.Forms.Clipboard]::GetText() }
      'pbcopy' { return & pbpaste 2>$null }
      'wl-copy' { return & wl-paste 2>$null }
      'xclip' { return & xclip -selection clipboard -o 2>$null }
      'xsel' { return & xsel --clipboard --output 2>$null }
      default { return [string]::Empty }
    }
  } catch { return [string]::Empty }
}

function Set-ClipboardContent([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return }
  $tool = Find-ClipboardTool
  try {
    switch ($tool) {
      'WinForms' { [System.Windows.Forms.Clipboard]::SetText($text); return }
      'pbcopy' { $text | & pbcopy; return }
      'wl-copy' { $text | & wl-copy; return }
      'xclip' { $text | & xclip -selection clipboard; return }
      'xsel' { $text | & xsel --clipboard --input; return }
    }
  } catch {}
}

if ($IsWindows -or $env:OS -eq 'Windows_NT') {
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
}