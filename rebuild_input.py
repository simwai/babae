import sys

def rebuild(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    # Find the start of Start-InputThread (around line 414)
    # Find the end of Read-NextInputEvent (after all the duplicates)

    start_idx = -1
    for i, line in enumerate(lines):
        if 'function Start-InputThread {' in line:
            start_idx = i
            break

    # The end marker should be the line before 'function Make-KeyInfo'
    # or just after the last duplicate of Read-NextInputEvent.
    # Let's find 'function Make-KeyInfo'
    end_idx = -1
    for i, line in enumerate(lines):
        if 'function Make-KeyInfo' in line:
            end_idx = i
            break

    if start_idx == -1 or end_idx == -1:
        print(f"Markers not found: start={start_idx}, end={end_idx}")
        sys.exit(1)

    input_section = r"""function Start-InputThread {
  if ([Console]::IsInputRedirected) { return }
  $script:inputThread = [PowerShell]::Create().AddScript({
    param($q)
    try {
      while ($true) {
        if ([Console]::KeyAvailable) {
          $ki = [Console]::ReadKey($true)
          $q.Enqueue($ki) | Out-Null
        } else {
          [System.Threading.Thread]::Sleep(10)
        }
      }
    } catch {
      $q.Enqueue([PSCustomObject]@{ Kind = 'Diag'; Message = $_.Exception.Message }) | Out-Null
    }
  }).AddArgument($script:inputQueue)
  $script:inputHandle = $script:inputThread.BeginInvoke()
}

function Stop-InputThread {
  if ($null -ne $script:inputThread) {
    try { $script:inputThread.Stop() } catch { Write-DiagLog 'INPUT' "Input thread stop failed: $($_.Exception.Message)" }
    try { $script:inputThread.Dispose() } catch { Write-DiagLog 'INPUT' "Input thread dispose failed: $($_.Exception.Message)" }
    $script:inputThread = $null
  }
}

function Stdin-DrainPasteInteractive {
  $sb = [System.Text.StringBuilder]::new()
  $seq = ""
  while ($true) {
    $ki = $null
    $waited = 0
    while (-not $script:inputQueue.TryDequeue([ref]$ki) -and $waited -lt 500) {
      [System.Threading.Thread]::Sleep(5); $waited += 5
    }
    if ($null -eq $ki) { break }
    $ch = $ki.KeyChar
    if ($ki.Key -eq [System.ConsoleKey]::Escape) {
      $seq = "`e"
      continue
    }
    if ($seq -ne "") {
      $seq += $ch
      if ($seq -eq "`e[201~") { break }
      if ("`e[201~".StartsWith($seq)) { continue }
      [void]$sb.Append($seq); $seq = ""
      continue
    }
    [void]$sb.Append($ch)
  }
  return $sb.ToString()
}

function Stdin-ReadKey {
  if ([Console]::IsInputRedirected) {
    $b = Stdin-ReadByte
    if ($b -eq -1) { return $null }
    return [System.ConsoleKeyInfo]::new([char]$b, 0, $false, $false, $false)
  }
  if ($script:inputPendingKeys.Count -gt 0) { return $script:inputPendingKeys.Dequeue() }
  while ($true) {
    $ki = $null
    while (-not $script:inputQueue.TryDequeue([ref]$ki)) {
      if (-not $script:running) { return $null }
      [System.Threading.Thread]::Sleep(10)
    }
    if ($ki -is [pscustomobject] -and $ki.Kind -eq 'Diag') {
      Write-DiagLog 'INPUT' "Input thread failed: $($ki.Message)"
      continue
    }

    # Console.ReadKey returns byte 8 for both Backspace and Ctrl+H on many Windows terminals.
    if ([int]$ki.KeyChar -eq 8) {
      if ($ki.Key -eq [System.ConsoleKey]::Backspace) {
        return Make-KeyInfo ([char]8) ([System.ConsoleKey]::Backspace) 0
      }
      return Make-KeyInfo ([char]8) ([System.ConsoleKey]::H) ([System.ConsoleModifiers]::Control)
    }
    return $ki
  }
}

function Read-NextInputEvent {
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
          $couldContinue = '[200~'.StartsWith($seq) -or '['.StartsWith($seq) -or '[<'.StartsWith($seq) -or ($seq -match '^\[<[\d;]*$')
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
  $b = Stdin-ReadByte
  if ($b -eq -1) {
    # EOF — stdin closed (test harness finished sending, or pipe broken).
    # Return a synthetic Ctrl+Q so the editor exits cleanly.
    return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo ([char]17) ([System.ConsoleKey]::Q) ([System.ConsoleModifiers]::Control)) }
  }

  # ── Bracketed-paste start: ESC [ 2 0 0 ~ ───────────────────────────────
  if ($b -eq 27) {
    Stdin-PeekAvailable
    if ($script:inputPending.Count -eq 0) {
      $w = 0
      while ($script:inputPending.Count -eq 0 -and $w -lt 50) {
        Start-Sleep -Milliseconds 5; $w += 5
        Stdin-PeekAvailable
      }
    }
    if ($script:inputPending.Count -eq 0) {
      return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Make-KeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
    }

    $seqBuf = [System.Text.StringBuilder]::new()
    [void]$seqBuf.Append([char]27)
    $maxSeqLen = $script:maxSeqLen

    while ($script:inputPending.Count -gt 0 -and $seqBuf.Length -lt $maxSeqLen) {
      $nb = Stdin-ReadByte
      if ($nb -eq -1) { break }
      $nc = [char]$nb
      [void]$seqBuf.Append($nc)
      $seq = $seqBuf.ToString().Substring(1)

      if ($seq -eq '[200~') {
        $payload = Stdin-DrainPaste
        return [PSCustomObject]@{ Kind = 'Paste'; Text = $payload }
      }

      $mouseEvent = Try-ParseMouseSequence $seq
      if ($null -ne $mouseEvent) { return $mouseEvent }

      $ki = Parse-EscapeSequence $seq
      if ($ki.Key -ne [System.ConsoleKey]::NoName) {
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = $ki }
      }

      $couldContinue = ($seq.Length -eq 1 -and ($seq -eq '[' -or $seq -eq 'O')) `
                    -or '[200~'.StartsWith($seq) `
                    -or $seq -eq '[<' `
                    -or $seq -match '^\[<[\d;]*[Mm]?$' `
                    -or ($seq.Length -gt 1 -and $seq[0] -eq '[' -and ($nc -match '[0-9;]'))
      if (-not $couldContinue) { break }
    }
    foreach ($c in $seqBuf.ToString().ToCharArray()) {
      $script:inputPending.Enqueue([byte][int]$c) | Out-Null
    }
    [void]$script:inputPending.Dequeue() # remove the ESC we already processed
  }

  $ch = [char]$b
  $ck = try { [System.ConsoleKey]$ch.ToString().ToUpper() } catch {
    Write-DiagLog 'INPUT' "ConsoleKey cast failed for '$ch': $($_.Exception.Message)"
    [System.ConsoleKey]::NoName
  }
  return [PSCustomObject]@{ Kind='Key'; KeyInfo=(Make-KeyInfo $ch $ck 0) }
}
"""

    new_content = "".join(lines[:start_idx]) + input_section + "".join(lines[end_idx:])

    with open(filepath, 'w') as f:
        f.write(new_content)

if __name__ == "__main__":
    rebuild(sys.argv[1])
