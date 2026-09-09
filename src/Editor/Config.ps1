$ErrorActionPreference = 'Stop'

#region Editor Config Settings
$script:editorConfigSettings = @{
  indent_style             = "space"
  indent_size              = 4
  tab_width                = 4
  end_of_line              = "lf"
  trim_trailing_whitespace = $false
  insert_final_newline     = $false
  charset                  = "utf-8"
  max_line_length          = 0
}

$script:commandBindingDefinitions = @(
  [PSCustomObject]@{ Key = '^T'; Label = 'Theme' }
  [PSCustomObject]@{ Key = '^S'; Label = 'Save' }
  [PSCustomObject]@{ Key = '^Q'; Label = 'Quit' }
  [PSCustomObject]@{ Key = '^F'; Label = 'Find' }
  [PSCustomObject]@{ Key = '^Z'; Label = 'Undo' }
  [PSCustomObject]@{ Key = '^Y'; Label = 'Redo' }
  [PSCustomObject]@{ Key = '^A'; Label = 'Select all' }
  [PSCustomObject]@{ Key = '^C'; Label = 'Copy' }
  [PSCustomObject]@{ Key = '^V'; Label = 'Paste' }
  [PSCustomObject]@{ Key = '^F1'; Label = 'Help' }
)

#endregion
#region Glob To Regex
function ConvertFrom-EditorConfigGlobToRegex([string]$glob) {
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append('^')
  for ($i = 0; $i -lt $glob.Length; $i++) {
    $ch = $glob[$i]
    if ($ch -eq '*') {
      if ($i + 1 -lt $glob.Length -and $glob[$i + 1] -eq '*') {
        [void]$sb.Append('.*'); $i++
      } else { [void]$sb.Append('[^/]*') }
      continue
    }
    if ($ch -eq '?') { [void]$sb.Append('[^/]'); continue }
    if ($ch -eq '.') { [void]$sb.Append('\.'); continue }
    if ('+()^$|{}'.Contains([string]$ch)) { [void]$sb.Append('\' + $ch); continue }
    if ($ch -eq '\\') {
      if ($i + 1 -lt $glob.Length) { $i++; [void]$sb.Append([Regex]::Escape([string]$glob[$i])) }
      continue
    }
    [void]$sb.Append($ch)
  }
  [void]$sb.Append('$')
  return $sb.ToString()
}

function Test-EditorConfigSectionMatch([string]$pattern, [string]$relativePath) {
  $norm = $relativePath -replace '\\', '/'
  $rx = ConvertFrom-EditorConfigGlobToRegex $pattern
  if ($pattern.Contains('/')) { return $norm -match $rx }
  return $norm -match $rx -or ([IO.Path]::GetFileName($norm) -match $rx)
}

#endregion
#region Load EditorConfig
function Import-EditorConfig([string]$filePath) {
  $script:editorConfigSettings.indent_style = "space"
  $script:editorConfigSettings.indent_size = 4
  $script:editorConfigSettings.tab_width = 4
  $script:editorConfigSettings.end_of_line = "lf"
  $script:editorConfigSettings.trim_trailing_whitespace = $false
  $script:editorConfigSettings.insert_final_newline = $false
  $script:editorConfigSettings.charset = "utf-8"
  $script:editorConfigSettings.max_line_length = 0

  $dir = if ($filePath) { [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($filePath)) } else { $PWD.Path }
  $fileName = if ($filePath) { [IO.Path]::GetFileName([IO.Path]::GetFullPath($filePath)) } else { "" }
  $stack = [System.Collections.Generic.List[string]]::new()
  $current = $dir
  while ($current) {
    $candidate = Join-Path $current '.editorconfig'
    if (Test-Path $candidate) { $stack.Insert(0, $candidate) }
    $parent = [IO.Path]::GetDirectoryName($current)
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { break }
    $current = $parent
  }
  foreach ($configPath in $stack) {
    $baseDir = [IO.Path]::GetDirectoryName($configPath)
    $rel = if ($filePath) {
      [IO.Path]::GetRelativePath($baseDir, [IO.Path]::GetFullPath($filePath)) -replace '\\', '/'
    } else { $fileName }
    $active = $false
    foreach ($raw in [IO.File]::ReadAllLines($configPath)) {
      $line = $raw.Trim()
      if ($line -eq '' -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
      if ($line -match '^\[(.*)\]$') { $active = Test-EditorConfigSectionMatch $Matches[1].Trim() $rel; continue }
      if ($line -match '^([^=]+)=(.*)$') {
        $k = $Matches[1].Trim().ToLowerInvariant()
        $v = $Matches[2].Trim().ToLowerInvariant()
        if (-not $active) { continue }
        switch ($k) {
          'indent_style' { $script:editorConfigSettings.indent_style = $v }
          'indent_size' { if ($v -match '^\d+$') { $script:editorConfigSettings.indent_size = [int]$v } }
          'tab_width' { if ($v -match '^\d+$') { $script:editorConfigSettings.tab_width = [int]$v } }
          'end_of_line' { $script:editorConfigSettings.end_of_line = $v }
          'trim_trailing_whitespace' { $script:editorConfigSettings.trim_trailing_whitespace = ($v -eq 'true') }
          'insert_final_newline' { $script:editorConfigSettings.insert_final_newline = ($v -eq 'true') }
          'charset' { $script:editorConfigSettings.charset = $v }
          'max_line_length' { if ($v -match '^\d+$') { $script:editorConfigSettings.max_line_length = [int]$v } }
        }
      }
    }
  }
  $script:editorState.StatusMessage = ' .editorconfig loaded '
}

#endregion
#region Indentation String
function Get-IndentationString {
  if ($script:editorConfigSettings.indent_style -eq 'tab') { return "`t" }
  return ' ' * [Math]::Max(1, $script:editorConfigSettings.indent_size)
}

#endregion
#region Accessors
function Get-EditorConfigSettings {
  return $script:editorConfigSettings
}

function Get-CommandBindingDefinitions {
  return $script:commandBindingDefinitions
}
#endregion