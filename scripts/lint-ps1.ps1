<#[
.SYNOPSIS
    Wrapper for Invoke-ScriptAnalyzer to work with lint-staged.
#>
param(
    [Parameter(Mandatory, Position=0)][string[]]$Paths
)

$ErrorActionPreference = "Stop"

$hasErrors = $false
foreach ($path in $Paths) {
    if (-not (Test-Path $path)) {
        Write-Error "File not found: $path"
        $hasErrors = $true
        continue
    }

    $results = Invoke-ScriptAnalyzer -Path $path -Severity Error,Warning -ExcludeRule PSAvoidUsingConvertToSecureStringWithPlainText,PSAvoidUsingPlainTextForPassword

    if ($results) {
        foreach ($result in $results) {
            if ($result.Severity -eq 'Error') {
                $hasErrors = $true
            }
        }
    }
}

if ($hasErrors) {
    exit 1
}
exit 0