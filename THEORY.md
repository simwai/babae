# babae: The Theory of the Terminal

This document provides a comprehensive guide to the underlying technologies, APIs, and architectural decisions behind **babae**. It is intended for beginners and contributors who want to understand how a modern Text User Interface (TUI) is constructed in pure PowerShell.

---

## 1. TUI Fundamentals

A TUI (Text User Interface) differs from a CLI (Command Line Interface) in that it treats the terminal as a two-dimensional grid of cells rather than a linear stream of text. To achieve this, several low-level terminal concepts must be managed.

### Canonical vs. Raw Mode
By default, terminals operate in **Canonical Mode** (or "cooked" mode). In this mode, the terminal line-buffers input: characters are not sent to the application until the user presses `Enter`. It also handles basic editing like backspace and signals like `Ctrl+C` automatically.

**babae** switches the terminal to **Raw Mode** using `stty raw -echo`. In Raw Mode:
- Every keystroke is sent immediately to the application.
- Echoing is disabled (the application is responsible for drawing what you type).
- Control characters (like `Ctrl+C`) are passed as data instead of triggering signals.

---

## 2. Input Architecture

babae uses a unified raw stdin stream input architecture to ensure consistent, non-blocking input handling across interactive terminal sessions, SSH connections, and automated test environments.

### Raw Stdin Stream & Async Byte Buffering
Rather than relying on `[Console]::ReadKey` or background runspaces, babae opens standard input directly via `[Console]::OpenStandardInput()`. An asynchronous byte-reader task (`ReadAsync`) non-blockingly drains stdin bytes into an internal byte queue.

- **VT/ANSI Escape Sequence Parsing:** Raw bytes are assembled and parsed byte-by-byte to recognize function keys, arrow keys, and control sequences across terminal emulators.
- **Bracketed Paste Detection:** Stdin byte stream processing unconditionally detects Bracketed Paste Mode (BPM) sentinel frames (`ESC [ 200 ~` and `ESC [ 201 ~`), allowing pasted payloads over SSH to be routed directly to buffer insertion without triggering individual key handling.

### The Bracketed Paste Fix

See [STAIRCASE.md](STAIRCASE.md) for a detailed explanation of the Staircase bug and how babae solves it.

---

## 3. Rendering Engine

babae renders frames using **ANSI Escape Sequences**. Instead of clearing the whole screen every time (which causes flicker), it uses a **Shadow Buffer**.

1.  The editor maintains the previous frame in memory.
2.  For the new frame, it compares every row to the shadow buffer.
3.  Only rows that have changed are sent to the terminal.
4.  It uses `[System.IO.StreamWriter]` pointed at `STDOUT` for bulk-writing, which is significantly faster than calling `Write-Host` repeatedly.

---

## 4. PowerShell & .NET API Reference

babae relies on the following core .NET classes within PowerShell:

| API Call | Description | Documentation |
|----------|-------------|---------------|
| `[Console]::IsInputRedirected` | Checks if stdin is a terminal or a pipe. | [Link](https://learn.microsoft.com/en-us/dotnet/api/system.console.isinputredirected) |
| `[Console]::OpenStandardInput()` | Gets the raw input stream for asynchronous byte reading. | [Link](https://learn.microsoft.com/en-us/dotnet/api/system.console.openstandardinput) |
| `[Console]::OpenStandardOutput()` | Gets the raw output stream for fast writing. | [Link](https://learn.microsoft.com/en-us/dotnet/api/system.console.openstandardoutput) |
| `[Console]::WindowWidth / Height` | Gets the current terminal dimensions. | [Link](https://learn.microsoft.com/en-us/dotnet/api/system.console.windowwidth) |
| `[Console]::OutputEncoding` | Ensures UTF-8 support for icons and emojis. | [Link](https://learn.microsoft.com/en-us/dotnet/api/system.console.outputencoding) |
| `[System.IO.StreamWriter]` | Buffered writer for high-performance rendering. | [Link](https://learn.microsoft.com/en-us/dotnet/api/system.io.streamwriter) |

---

## 5. ANSI/XTerm Specifications

The terminal is controlled via "In-band signaling" using Escape Sequences. Most sequences start with the **CSI** (Control Sequence Introducer): `ESC [` (or `\e[`).

### Common Sequences used in babae:
- **Cursor Movement:** `ESC [ {row};{col} H` (Moves cursor to specific coordinate).
- **Clear Screen:** `ESC [ 2 J` (Clears entire screen).
- **Color/Style (SGR):** `ESC [ {code} m` (e.g., `31` for red, `1` for bold, `48;2;R;G;B` for TrueColor background).
- **Alternate Buffer:** `ESC [ ? 1049 h` (Switches to a "clean" screen; `l` to switch back). This preserves your shell history when you quit the editor.
- **Hide/Show Cursor:** `ESC [ ? 25 l` (Hide), `ESC [ ? 25 h` (Show).

### Input Sequences:
When you press a key like `Up Arrow`, the terminal sends `ESC [ A`. babae's `Parse-EscapeSequence` function is responsible for mapping these back to logical actions.

---

## 6. Verification and Testing

Testing a TUI is notoriously difficult because it usually requires a human to "see" the screen. babae solves this by making the entire editor **deterministically scriptable via Stdin**.

By redirecting Stdin, we can feed the editor raw bytes (e.g., `h`, `e`, \`l\`, \`l\`, \`o\`, `Ctrl+S`, `Ctrl+Q`) and then verify the resulting file on disk. This is how `babae.tests.ps1` works:
1.  Launch babae as a child process with redirected pipes.
2.  Write byte sequences to its Stdin.
3.  Wait for the process to exit.
4.  Assert the content of the saved file matches expectations.

This removes "trial and error" from the development process and ensures that complex features like Bracketed Paste don't regress.
