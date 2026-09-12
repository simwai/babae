<#
.SYNOPSIS
    Cross-platform clipboard access for the editor.
.DESCRIPTION
    Detects the available clipboard tool for the current platform and
    provides get/set operations with graceful fallback when no tool is found.
#>

$ErrorActionPreference = 'Stop'

function Find-ClipboardTool {
  <#
  .SYNOPSIS
      Detects the available clipboard mechanism for the current platform.
  #>
  if ($IsWindows -or $env:OS -eq 'Windows_NT') { return 'WinForms' }
  if ($IsMacOS) { return 'pbcopy' }
  if (Get-Command wl-copy -ErrorAction SilentlyContinue) { return 'wl-copy' }
  if (Get-Command xclip -ErrorAction SilentlyContinue) { return 'xclip' }
  if (Get-Command xsel -ErrorAction SilentlyContinue) { return 'xsel' }
  return $null
}

function Get-ClipboardContent {
  <#
  .SYNOPSIS
      Returns the current clipboard text, or an empty string when unavailable.
  #>
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
  <#
  .SYNOPSIS
      Writes text to the system clipboard.
  #>
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
