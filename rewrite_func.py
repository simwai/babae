import re
import sys

def rewrite_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    start_marker = 'function Read-NextInputEvent {'
    # The end of the redirected path part is where the pipe handling starts
    end_marker = '  $b = Stdin-ReadByte'

    start_idx = content.find(start_marker)
    end_idx = content.find(end_marker)

    if start_idx == -1 or end_idx == -1:
        print(f"Markers not found: start={start_idx}, end={end_idx}")
        sys.exit(1)

    new_part = """function Read-NextInputEvent {
  if (-not [Console]::IsInputRedirected) {
    $ki = Stdin-ReadKey
    if ($null -eq $ki) { return $null }

    if ($ki.Key -eq [System.ConsoleKey]::Escape) {
      $seq = ""
      $seqBufKeys = [System.Collections.Generic.List[object]]::new()
      $waited = 0
      while ($seq.Length -lt $script:maxSeqLen -and $waited -lt $script:escapeTimeoutMs) {
        $nki = $null
        if ($script:inputQueue.TryDequeue([ref]$nki)) {
          if ($nki -is [pscustomobject] -and $nki.Kind -eq 'Diag') {
            Write-DiagLog 'INPUT' "Input thread failed: $($nki.Message)"
            continue
          }
          $seq += [string]$nki.KeyChar
          $seqBufKeys.Add($nki) | Out-Null

          if ($seq -eq '[200~') { return [PSCustomObject]@{ Kind = 'Paste'; Text = Stdin-DrainPasteInteractive } }

          $mouseEvent = Try-ParseMouseSequence $seq
          if ($null -ne $mouseEvent) { return $mouseEvent }

          $parsed = Parse-EscapeSequence $seq
          if ($parsed.Key -ne [System.ConsoleKey]::NoName) {
            return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = $parsed }
          }

          # Continue if sequence is potentially a prefix of something we handle.
          $couldContinue = '[200~'.StartsWith($seq) -or '['.StartsWith($seq) -or '[<'.StartsWith($seq) -or ($seq -match '^\\\\[<[\\\\d;]*$')
          if (-not $couldContinue) {
            foreach ($k in $seqBufKeys) { $script:inputPendingKeys.Enqueue($k) | Out-Null }
            break
          }
        } else {
          [System.Threading.Thread]::Sleep(5); $waited += 5
        }
      }
      return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
    }
    return [PSCustomObject]@{ Kind = "Key"; KeyInfo = $ki }
  }
"""
    # Note: I used \\\\d and \\\\ to escape for Python and then for PowerShell's regex engine if needed,
    # but wait, the PowerShell string is '...'. In PS, -match uses regex.
    # The regex I want in PS is '^\[<[\d;]*$'.
    # So in the string it should be '^\[<[\d;]*$'.
    # In Python's triple quote string, I need to escape the backslash: '^\\[<[\\d;]*$'.

    new_part = new_part.replace('\\\\', '\\') # Convert \\ to \

    content = content[:start_idx] + new_part + content[end_idx:]

    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    rewrite_file(sys.argv[1])
