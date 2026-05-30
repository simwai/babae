import subprocess
import sys

def check_syntax(filepath):
    # Use pwsh to check syntax
    cmd = [
        "pwsh", "-NoProfile", "-Command",
        f"Try {{ $ErrorActionPreference = 'Stop'; [Management.Automation.Language.Parser]::ParseFile('{filepath}', [ref]$null, [ref]$errs); if ($errs) {{ $errs | ForEach-Object {{ Write-Host \"ERROR: $($_.Message) at line $($_.Extent.StartLineNumber), col $($_.Extent.StartColumnNumber)\" }} }} else {{ Write-Host \"SUCCESS\" }} }} Catch {{ Write-Host \"CRASH: $_\" }}"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(result.stdout)
    if result.stderr:
        print("STDERR:", result.stderr)

if __name__ == "__main__":
    check_syntax(sys.argv[1])
