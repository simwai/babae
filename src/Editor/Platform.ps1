<#
.SYNOPSIS
    Platform-specific console raw mode handling.
.DESCRIPTION
    Enters and exits raw terminal mode on Windows (Win32 Console API) and
    Unix (stty), preserving the original settings for later restoration.
#>

$ErrorActionPreference = 'Stop'

$script:isWindowsPlatform = $IsWindows -or $env:OS -eq 'Windows_NT'
$script:isUnixPlatform = $IsLinux -or $IsMacOS
$script:originalSttySettings = $null
$script:originalConsoleMode = $null

function Enter-RawInputMode {
  <#
  .SYNOPSIS
      Puts the console into raw mode for direct key reading.
  .DESCRIPTION
      Uses stty on Unix and Win32 Console API on Windows. Original settings
      are cached so Exit-RawInputMode can restore them deterministically.
  #>
  if ($script:isUnixPlatform -and -not [Console]::IsInputRedirected) {
    try { $script:originalSttySettings = stty -g 2>/dev/null } catch {}
    try { stty raw -echo 2>/dev/null } catch {}
    return
  }
  if (-not $script:isWindowsPlatform) { return }

  try {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    public static class ConsoleRaw {
        [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
        [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint mode);
        public const int STD_INPUT_HANDLE = -10;
        public const uint ENABLE_ECHO_INPUT = 0x0004;
        public const uint ENABLE_LINE_INPUT = 0x0002;
        public const uint ENABLE_PROCESSED_INPUT = 0x0001;
        public const uint ENABLE_EXTENDED_FLAGS = 0x0080;
        public const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
        public const uint ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
    }
    '@ -ErrorAction SilentlyContinue

    $handle = [ConsoleRaw]::GetStdHandle([ConsoleRaw]::STD_INPUT_HANDLE)
    [uint]$mode = 0
    [void][ConsoleRaw]::GetConsoleMode($handle, [ref]$mode)
    $script:originalConsoleMode = $mode
    # Disable echo, line input, processed input, and quick edit; enable VT input.
    $newMode = ($mode -band (-bnot ([ConsoleRaw]::ENABLE_ECHO_INPUT -bor [ConsoleRaw]::ENABLE_LINE_INPUT -bor [ConsoleRaw]::ENABLE_PROCESSED_INPUT -bor [ConsoleRaw]::ENABLE_QUICK_EDIT_MODE))) `
      -bor [ConsoleRaw]::ENABLE_EXTENDED_FLAGS -bor [ConsoleRaw]::ENABLE_VIRTUAL_TERMINAL_INPUT
    [void][ConsoleRaw]::SetConsoleMode($handle, $newMode)
  } catch {}
}

function Exit-RawInputMode {
  <#
  .SYNOPSIS
      Restores the console to its original mode.
  .DESCRIPTION
      Reverses Enter-RawInputMode using the cached original settings for
      both Windows Console API and Unix stty paths.
  #>
  if ($null -ne $script:originalConsoleMode) {
    try {
      $handle = [ConsoleRaw]::GetStdHandle([ConsoleRaw]::STD_INPUT_HANDLE)
      [ConsoleRaw]::SetConsoleMode($handle, $script:originalConsoleMode)
    } catch {}
  }
  if ($script:originalSttySettings -and -not [Console]::IsInputRedirected) {
    try { stty $script:originalSttySettings 2>/dev/null } catch {}
  }
}
