$errs = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'babae.ps1'), [ref]$tokens, [ref]$errs)
if ($errs) {
    $errs | ForEach-Object { "ERROR: $($_.Message) at line $($_.Extent.StartLineNumber), col $($_.Extent.StartColumnNumber)" }
} else {
    "OK"
}
