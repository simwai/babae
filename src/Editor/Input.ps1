$ErrorActionPreference = 'Stop'

#region Input Output Infrastructure
$script:outputWriter = $null
$script:inputStream = $null
$script:inputReadBuffer = [byte[]]::new(4096)
$script:pendingByteQueue = [System.Collections.Generic.Queue[byte]]::new()
$script:isInteractiveConsole = $true
$script:currentReadTask = $null

function Initialize-InputStreams {
  if ($null -eq $script:outputWriter) {
    try {
      $script:outputWriter = [System.IO.StreamWriter]::new([Console]::OpenStandardOutput())
      $script:outputWriter.AutoFlush = $false
      $script:inputStream = [Console]::OpenStandardInput()
      try { [void][Console]::KeyAvailable } catch { $script:isInteractiveConsole = $false }
    } catch {
      $script:outputWriter = [System.IO.StreamWriter]::new([System.IO.Stream]::Null)
      $script:outputWriter.AutoFlush = $false
      $script:inputStream = [System.IO.Stream]::Null
      $script:isInteractiveConsole = $false
    }
  }
}

function Write-OutputBuffer([string]$text) {
  Initialize-InputStreams
  $script:outputWriter.Write($text)
  $script:outputWriter.Flush()
}

function Start-AsyncInputRead {
  Initialize-InputStreams
  if ($null -eq $script:currentReadTask) {
    $script:currentReadTask = $script:inputStream.ReadAsync($script:inputReadBuffer, 0, $script:inputReadBuffer.Length)
  }
}

function Complete-AsyncInputRead {
  $bytesRead = $script:currentReadTask.GetAwaiter().GetResult()
  $script:currentReadTask = $null
  for ($i = 0; $i -lt $bytesRead; $i++) {
    $script:pendingByteQueue.Enqueue($script:inputReadBuffer[$i])
  }
  return $bytesRead
}

function Test-InputQueueDrained {
  if ($script:pendingByteQueue.Count -gt 0) { return $true }
  if ($script:isInteractiveConsole) {
    try { return [Console]::KeyAvailable } catch { $script:isInteractiveConsole = $false }
  }
  Start-AsyncInputRead
  if (-not $script:currentReadTask.IsCompleted) { return $false }
  [void](Complete-AsyncInputRead)
  return $true
}

function Test-InputDataAvailable { return Test-InputQueueDrained }

function Read-ByteFromInput {
  Initialize-InputStreams
  while ($script:pendingByteQueue.Count -eq 0) {
    Start-AsyncInputRead
    $bytesRead = Complete-AsyncInputRead
    if ($bytesRead -le 0) { return -1 }
  }
  return [int]$script:pendingByteQueue.Dequeue()
}

function Clear-OsPipeBuffers {
  Initialize-InputStreams
  if ($null -ne $script:currentReadTask -and $script:currentReadTask.IsCompleted) {
    $bytesRead = Complete-AsyncInputRead
    if ($bytesRead -le 0) { return }
  }
  while ($true) {
    Start-AsyncInputRead
    if (-not $script:currentReadTask.Wait(1)) { break }
    $bytesRead = Complete-AsyncInputRead
    if ($bytesRead -le 0) { break }
  }
}

function Read-AllAvailableText {
  if ($null -ne $script:currentReadTask) {
    if ($script:currentReadTask.IsCompleted) {
      [void]$script:currentReadTask.GetAwaiter().GetResult()
    }
    $script:currentReadTask = $null
  }

  Clear-OsPipeBuffers

  $deadline = [System.Diagnostics.Stopwatch]::StartNew()
  while ($deadline.ElapsedMilliseconds -lt 15) {
    Start-AsyncInputRead
    if ($script:currentReadTask.Wait(5)) {
      $read = Complete-AsyncInputRead
      if ($read -le 0) { break }
    } else { break }
  }

  Clear-OsPipeBuffers
  $count = $script:pendingByteQueue.Count
  if ($count -eq 0) { return [string]::Empty }

  $allBytes = [byte[]]::new($count)
  $script:pendingByteQueue.CopyTo($allBytes, 0)
  $script:pendingByteQueue.Clear()

  if ($null -ne $script:currentReadTask) {
    if ($script:currentReadTask.IsCompleted) {
      [void]$script:currentReadTask.GetAwaiter().GetResult()
    }
    $script:currentReadTask = $null
  }

  $text = [System.Text.Encoding]::UTF8.GetString($allBytes)
  return $text
}

function Read-PastedText {
  Clear-OsPipeBuffers
  $count = $script:pendingByteQueue.Count
  if ($count -eq 0) { return [string]::Empty }

  $allBytes = [byte[]]::new($count)
  $script:pendingByteQueue.CopyTo($allBytes, 0)
  $script:pendingByteQueue.Clear()
  $text = [System.Text.Encoding]::UTF8.GetString($allBytes) -replace "`r`n", "`n" -replace "`r", "`n"
  return $text
}

#endregion
#region ConsoleKeyInfo Builder
function Build-ConsoleKeyInfo([char]$ch, [System.ConsoleKey]$key, [System.ConsoleModifiers]$modifiers) {
  return [System.ConsoleKeyInfo]::new($ch, $key,
    ($modifiers -band [System.ConsoleModifiers]::Shift) -ne 0,
    ($modifiers -band [System.ConsoleModifiers]::Alt) -ne 0,
    ($modifiers -band [System.ConsoleModifiers]::Control) -ne 0)
}

#endregion
#region Escape Sequence Parser
function ConvertFrom-EscapeSequence([string]$sequence) {
  if ($sequence.StartsWith('[')) {
    $param = $sequence.Substring(1)
    switch ($param) {
      'A' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    0 }
      'B' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  0 }
      'C' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) 0 }
      'D' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  0 }
      'H' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Home)       0 }
      'F' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::End)        0 }
      '1~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Home)       0 }
      '4~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::End)        0 }
      '5~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::PageUp)     0 }
      '6~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::PageDown)   0 }
      '2~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Insert)     0 }
      '3~' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Delete)     0 }
      '1;2A' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    ([System.ConsoleModifiers]::Shift) }
      '1;2B' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  ([System.ConsoleModifiers]::Shift) }
      '1;2C' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) ([System.ConsoleModifiers]::Shift) }
      '1;2D' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  ([System.ConsoleModifiers]::Shift) }
      '1;2H' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Home)       ([System.ConsoleModifiers]::Shift) }
      '1;2F' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::End)        ([System.ConsoleModifiers]::Shift) }
      '1;5P' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::F1) ([System.ConsoleModifiers]::Control) }
      '49;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D1) ([System.ConsoleModifiers]::Control) }
      '50;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D2) ([System.ConsoleModifiers]::Control) }
      '51;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D3) ([System.ConsoleModifiers]::Control) }
      '52;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D4) ([System.ConsoleModifiers]::Control) }
      '53;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D5) ([System.ConsoleModifiers]::Control) }
      '54;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D6) ([System.ConsoleModifiers]::Control) }
      '55;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D7) ([System.ConsoleModifiers]::Control) }
      '56;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D8) ([System.ConsoleModifiers]::Control) }
      '57;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D9) ([System.ConsoleModifiers]::Control) }
      '48;5u' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::D0) ([System.ConsoleModifiers]::Control) }
    }
  }
  if ($sequence.StartsWith('O')) {
    switch ($sequence.Substring(1)) {
      'A' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::UpArrow)    0 }
      'B' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::DownArrow)  0 }
      'C' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::RightArrow) 0 }
      'D' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::LeftArrow)  0 }
      'H' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::Home)       0 }
      'F' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::End)        0 }
      'P' { return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::F1)         0 }
    }
  }
  return Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::NoName) 0
}

#endregion
#region Read Input Event
function Read-InputEvent {
  $firstByte = Read-ByteFromInput
  if ($firstByte -eq -1) {
    return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]26) ([System.ConsoleKey]::Z) ([System.ConsoleModifiers]::Control)) }
  }

  if ($firstByte -eq 27) {  # ESC
    Clear-OsPipeBuffers
    if ($script:pendingByteQueue.Count -eq 0) {
      $w = 0
      while ($script:pendingByteQueue.Count -eq 0 -and $w -lt 5) { Start-Sleep -Milliseconds 2; $w++; Clear-OsPipeBuffers }
      if ($script:pendingByteQueue.Count -eq 0) { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) } }
    }
    $peekChar = [char]$script:pendingByteQueue.Peek()
    if ($peekChar -ne '[' -and $peekChar -ne 'O') {
      return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
    }
    $seqBuilder = [System.Text.StringBuilder]::new()
    $maxSeqLen = 24   # widened slightly to comfortably fit SGR mouse reports
    $maxWaitIterations = 40
    while ($seqBuilder.Length -lt $maxSeqLen) {
      if ($script:pendingByteQueue.Count -eq 0) {
        $waited = 0
        while ($script:pendingByteQueue.Count -eq 0 -and $waited -lt $maxWaitIterations) {
          Start-Sleep -Milliseconds 2
          Clear-OsPipeBuffers
          $waited++
        }
        if ($script:pendingByteQueue.Count -eq 0) { break }
      }
      $nb = $script:pendingByteQueue.Peek()
      if ($nb -eq 27) { break }
      $nc = [char]$nb
      [void]$seqBuilder.Append($nc)
      $script:pendingByteQueue.Dequeue() | Out-Null
      $seq = $seqBuilder.ToString()

      if ($seq -eq '[200~') {
        $paste = Read-PastedText
        return [PSCustomObject]@{ Kind = 'Paste'; Text = $paste }
      }

      # SGR mouse report: no mouse handling, discard silently.
      if ($seq -match '^\[<[0-9;]+[Mm]$') {
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]0) ([System.ConsoleKey]::NoName) 0) }
      }

      $ki = ConvertFrom-EscapeSequence $seq
      if ($ki.Key -ne [System.ConsoleKey]::NoName) {
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = $ki }
      }

      $couldContinue = ($seq.Length -eq 1 -and ($seq -eq '[' -or $seq -eq 'O')) `
        -or ($seq.Length -eq 2 -and $seq -eq '[<') `
        -or ($seq.Length -gt 2 -and $seq.StartsWith('[<') -and ($nc -match '[0-9;Mm]')) `
        -or ($seq.Length -gt 1 -and $seq[0] -eq '[' -and -not $seq.StartsWith('[<') -and ($nc -match '[0-9;]'))
      if (-not $couldContinue) { break }
    }
    $seqStr = $seqBuilder.ToString()
    if ($script:debugMode) {
      $raw = [System.Text.Encoding]::UTF8.GetBytes($seqStr)
      $tmpQueue = [System.Collections.Generic.Queue[byte]]::new()
      foreach ($b in $raw) { $tmpQueue.Enqueue($b) }
      foreach ($b in $script:pendingByteQueue) { $tmpQueue.Enqueue($b) }
      $script:pendingByteQueue = $tmpQueue
    }
    return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]27) ([System.ConsoleKey]::Escape) 0) }
  }

  if ($firstByte -ge 32 -and $firstByte -le 126) {
    Clear-OsPipeBuffers
  }

  switch ($firstByte) {
    0 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]0)  ([System.ConsoleKey]::D2)        ([System.ConsoleModifiers]::Control)) } }
    13 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]13) ([System.ConsoleKey]::Enter)     0) } }
    127 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]127) ([System.ConsoleKey]::Backspace) 0) } }
    8 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]8)   ([System.ConsoleKey]::Backspace) 0) } }
    9 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]9)  ([System.ConsoleKey]::Tab)       0) } }
    27 { }
    28 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]28) ([System.ConsoleKey]::D4)        ([System.ConsoleModifiers]::Control)) } }
    29 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]29) ([System.ConsoleKey]::D5)        ([System.ConsoleModifiers]::Control)) } }
    30 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]30) ([System.ConsoleKey]::D6)        ([System.ConsoleModifiers]::Control)) } }
    31 { return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]31) ([System.ConsoleKey]::D7)        ([System.ConsoleModifiers]::Control)) } }
    default {
      if ($firstByte -ge 1 -and $firstByte -le 26) {
        $letter = [char]($firstByte + [int][char]'A' - 1)
        $ck = [System.ConsoleKey]$letter.ToString()
        return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo ([char]$firstByte) $ck ([System.ConsoleModifiers]::Control)) }
      }
    }
  }

  [byte[]]$utf8Bytes = @($firstByte)
  if ($firstByte -ge 0xC0) {
    $extra = if ($firstByte -ge 0xF0) { 3 } elseif ($firstByte -ge 0xE0) { 2 } else { 1 }
    for ($i = 0; $i -lt $extra; $i++) { $utf8Bytes += Read-ByteFromInput }
  }
  $char = [System.Text.Encoding]::UTF8.GetString($utf8Bytes)[0]
  $ck = try { [System.ConsoleKey]$char.ToString().ToUpper() } catch { [System.ConsoleKey]::NoName }
  return [PSCustomObject]@{ Kind = 'Key'; KeyInfo = (Build-ConsoleKeyInfo $char $ck 0) }
}

#endregion
#region Terminal Sequences
$script:SEQ_MOUSE_TRACKING_OFF = "`e[?1000l`e[?1002l`e[?1003l"
$script:SEQ_AUTOWRAP_OFF = "`e[?7l"
$script:SEQ_AUTOWRAP_ON = "`e[?7h"

function Set-ScrollMargins([int]$top, [int]$bottom) {
  Write-OutputBuffer "`e[$top;${bottom}r"
}
function Reset-ScrollMargins() {
  Write-OutputBuffer "`e[r"
}
#endregion