$ErrorActionPreference = 'Stop'

#region Base Theme
$script:baseTheme = @{
  background                  = "48;2;17;15;26"
  backgroundLine              = "48;2;24;21;36"
  backgroundGutter            = "48;2;20;18;30"
  backgroundStatusBar         = "48;2;30;26;48"
  backgroundSelection         = "48;2;80;50;140"
  backgroundHeader            = "48;2;80;50;140"
  foregroundNormal            = "38;2;220;215;240"
  foregroundMuted             = "38;2;110;100;150"
  foregroundAccent            = "38;2;189;147;249"
  foregroundLineNumber        = "38;2;80;70;110"
  foregroundCurrentLineNumber = "38;2;189;147;249"
  foregroundHeader            = "38;2;255;255;255"
  foregroundSearch            = "38;2;255;184;108"
  foregroundDirty             = "38;2;255;121;198"
  foregroundSaved             = "38;2;80;250;123"
  foregroundTilde             = "38;2;60;50;90"
  foregroundSelection         = "38;2;255;255;255"
  foregroundRuler             = "38;2;110;100;150"
  foregroundKeyword           = "38;2;203;166;247"
  foregroundString            = "38;2;166;227;161"
  foregroundComment           = "38;2;166;173;200"
  foregroundNumber            = "38;2;250;179;135"
  foregroundType              = "38;2;245;194;231"
  foregroundVariable          = "38;2;205;214;244"
  foregroundFunction          = "38;2;137;180;250"
  foregroundOperator          = "38;2;148;226;213"
  foregroundPunctuation       = "38;2;166;173;200"
  foregroundConstant          = "38;2;235;160;172"
  displayName                 = ""
}

#endregion
function New-ThemeFromOverride([hashtable]$overrides, [string]$displayName) {
  $theme = $script:baseTheme.Clone()
  foreach ($key in $overrides.Keys) { $theme[$key] = $overrides[$key] }
  $theme.displayName = $displayName
  return $theme
}

$script:availableThemeNames = @("dark", "mocha", "frappe", "github-dark", "latte")
$script:themeDefinitions = @{
  "dark"           = New-ThemeFromOverride @{} "babae dark"
  "mocha"          = New-ThemeFromOverride @{
    background                  = "48;2;30;30;46"
    backgroundLine              = "48;2;40;38;53"
    backgroundGutter            = "48;2;24;24;37"
    backgroundStatusBar         = "48;2;17;17;27"
    backgroundSelection         = "48;2;88;91;112"
    backgroundHeader            = "48;2;17;17;27"
    foregroundNormal            = "38;2;205;214;244"
    foregroundMuted             = "38;2;88;91;112"
    foregroundAccent            = "38;2;203;166;247"
    foregroundLineNumber        = "38;2;88;91;112"
    foregroundCurrentLineNumber = "38;2;203;166;247"
    foregroundHeader            = "38;2;205;214;244"
    foregroundSearch            = "38;2;249;226;175"
    foregroundDirty             = "38;2;243;139;168"
    foregroundSaved             = "38;2;166;227;161"
    foregroundTilde             = "38;2;49;50;68"
    foregroundRuler             = "38;2;88;91;112"
    displayName                 = "Catppuccin Mocha"
  } "Catppuccin Mocha"
  "frappe"         = New-ThemeFromOverride @{
    background                  = "48;2;48;52;70"
    backgroundLine              = "48;2;65;69;89"
    backgroundGutter            = "48;2;41;44;60"
    backgroundStatusBar         = "48;2;35;38;52"
    backgroundSelection         = "48;2;98;104;128"
    backgroundHeader            = "48;2;35;38;52"
    foregroundNormal            = "38;2;198;208;245"
    foregroundMuted             = "38;2;98;104;128"
    foregroundAccent            = "38;2;202;158;230"
    foregroundLineNumber        = "38;2;98;104;128"
    foregroundCurrentLineNumber = "38;2;202;158;230"
    foregroundHeader            = "38;2;198;208;245"
    foregroundSearch            = "38;2;229;200;144"
    foregroundDirty             = "38;2;231;130;132"
    foregroundSaved             = "38;2;166;209;137"
    foregroundTilde             = "38;2;65;69;89"
    foregroundRuler             = "38;2;98;104;128"
    displayName                 = "Catppuccin Frappe"
  } "Catppuccin Frappe"
  "github-dark"    = New-ThemeFromOverride @{
    background                  = "48;2;13;17;23"
    backgroundLine              = "48;2;22;27;34"
    backgroundGutter            = "48;2;13;17;23"
    backgroundStatusBar         = "48;2;22;27;34"
    backgroundSelection         = "48;2;33;68;118"
    backgroundHeader            = "48;2;22;27;34"
    foregroundNormal            = "38;2;230;237;243"
    foregroundMuted             = "38;2;110;118;129"
    foregroundAccent            = "38;2;210;153;255"
    foregroundLineNumber        = "38;2;110;118;129"
    foregroundCurrentLineNumber = "38;2;210;153;255"
    foregroundHeader            = "38;2;230;237;243"
    foregroundSearch            = "38;2;255;212;0"
    foregroundDirty             = "38;2;248;81;73"
    foregroundSaved             = "38;2;63;185;80"
    foregroundTilde             = "38;2;33;38;45"
    foregroundRuler             = "38;2;110;118;129"
    displayName                 = "GitHub Dark"
  } "GitHub Dark"
  "latte" = New-ThemeFromOverride @{
    background                  = "48;2;239;241;245"
    backgroundLine              = "48;2;228;230;237"
    backgroundGutter            = "48;2;220;224;232"
    backgroundStatusBar         = "48;2;204;208;218"
    backgroundSelection         = "48;2;188;192;204"
    backgroundHeader            = "48;2;204;208;218"
    foregroundNormal            = "38;2;76;79;105"
    foregroundMuted             = "38;2;108;111;133"
    foregroundAccent            = "38;2;136;57;239"
    foregroundLineNumber        = "38;2;156;160;176"
    foregroundCurrentLineNumber = "38;2;136;57;239"
    foregroundHeader            = "38;2;76;79;105"
    foregroundSearch            = "38;2;254;100;11"
    foregroundDirty             = "38;2;210;15;57"
    foregroundSaved             = "38;2;64;160;43"
    foregroundTilde             = "38;2;188;192;204"
    foregroundRuler             = "38;2;108;111;133"
    foregroundKeyword           = "38;2;108;45;181"
    foregroundString            = "38;2;42;107;27"
    foregroundComment           = "38;2;67;71;80"
    foregroundNumber            = "38;2;196;77;0"
    foregroundType              = "38;2;194;82;163"
    foregroundVariable          = "38;2;60;63;86"
    foregroundFunction          = "38;2;20;73;196"
    foregroundOperator          = "38;2;14;110;114"
    foregroundPunctuation       = "38;2;85;88;104"
    foregroundConstant          = "38;2;178;36;54"
    displayName                 = "Catppuccin Latte"
  } "Catppuccin Latte"
}

$script:currentThemeIndex = 0
$script:RESET_SEQUENCE = "`e[0m"

function Get-ThemeColor([string]$key) {
  $currentTheme = $script:themeDefinitions[$script:availableThemeNames[$script:currentThemeIndex]]
  return "`e[$($currentTheme[$key])m"
}

function Set-CurrentThemeIndex([int]$index) {
  $script:currentThemeIndex = [Math]::Max(0, [Math]::Min($index, $script:availableThemeNames.Count - 1))
}

function Get-CurrentThemeIndex {
  return $script:currentThemeIndex
}

function Get-AvailableThemeNames {
  return $script:availableThemeNames
}

function Get-ThemeDefinitions {
  return $script:themeDefinitions
}

function Get-CurrentThemeDisplayName {
  $currentTheme = $script:themeDefinitions[$script:availableThemeNames[$script:currentThemeIndex]]
  return $currentTheme.displayName
}