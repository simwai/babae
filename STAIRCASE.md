# The Staircase Bug: Anatomy and Solution

## What is the Staircase Bug?

The "Staircase Bug" (sometimes referred to as the "Stairway" effect) is a common issue in terminal-based text editors, especially when used over SSH or in certain terminal emulators (like Bitvise or older xterm configurations).

When you paste multi-line, indented text into an editor using the terminal's native "Right-Click Paste" or "Middle-Click Paste", the terminal sends the text to the editor's standard input stream as if it were being typed extremely fast. This is separate from `Ctrl+V`, which reads the operating system clipboard directly.

### The Problem: Compounded Auto-Indentation
Most modern editors have an "Auto-Indent" feature: when you press `Enter` (`\n`), the editor automatically inserts the same amount of leading whitespace on the new line as the previous line.

During a paste, the following happens:
1.  **Line 1** is sent: `    line 1` (4 spaces).
2.  **Newline** is sent: `\n`.
3.  The editor's `Enter` handler triggers: it sees 4 spaces on the previous line and **injects 4 spaces** into the buffer.
4.  **Line 2** is sent from the paste buffer: `    line 2` (another 4 spaces).
5.  The result for Line 2 is now **8 spaces**.
6.  **Newline** is sent again.
7.  The editor injects 8 spaces.
8.  **Line 3** is sent with 4 spaces. Result: **12 spaces**.

This produces an ever-widening "staircase" of indentation that destroys the formatting of the pasted code.

---

## How babae Solves It

babae uses **Bracketed Paste Mode (BPM)** to distinguish between user typing and terminal-driven pasting.

### 1. Enabling BPM
On startup, babae sends the ANSI escape sequence `ESC [ ? 2004 h` to the terminal. This tells the terminal: *"If the user performs a paste operation, wrap the content in special markers."*

### 2. The Sentinels
When BPM is enabled, the terminal wraps the paste payload:
- **Start Marker:** `ESC [ 200 ~`
- **End Marker:** `ESC [ 201 ~`

### 3. Raw stdin detection and the bypass
babae does not use `Console.ReadKey` to process terminal input. It puts the input into raw mode and reads bytes from stdin, which allows the BPM prefix to be seen reliably even when the session is running over SSH or stdin is redirected.

- **Detection:** `Read-InputEvent` assembles an escape sequence byte by byte. When it recognizes `ESC [ 200 ~`, it returns a `Paste` event instead of a normal key event.
- **Verbatim insertion:** `Read-PastedText` drains the bytes already buffered after the prefix, decodes them as UTF-8, and normalizes CRLF/CR to LF. The main loop sends the resulting text to `Paste-TextFromClipboard`.
- **The bypass:** `Paste-TextFromClipboard` inserts the complete text into the buffer in one operation. It does not call `Handle-EditingKey`, so the embedded newlines never reach the normal Enter handler and cannot trigger indentation logic. The BPM markers are also removed defensively if they are present in the drained text.
- **Manual Enter remains separate:** A manually typed Enter is handled by `Handle-EditingKey` and inserts only a newline. It does not copy the current line's indentation. This independently prevents indentation from compounding if input is received outside the paste path.

### 4. Clipboard paste is a separate path
`Ctrl+V` calls `Get-ClipboardContent`, using Windows Forms on Windows or `pbpaste`, `wl-paste`, `xclip`, or `xsel` on Unix-like systems. The returned text is passed to the same `Paste-TextFromClipboard` insertion function, so it also bypasses the key-by-key Enter path. A terminal right-click paste does not use those clipboard tools; it arrives as a BPM-framed stdin stream.

The raw reader does wait briefly while reassembling an escape sequence, but it does not implement a separate adaptive 2000 ms paste timer or a paste state machine keyed off the closing marker. The current fix therefore relies on byte-level prefix detection, direct buffer insertion, defensive marker stripping, and the non-indenting manual Enter handler.

---

## Verification

You can verify the fix in babae by running the Pester test suite:
```pwsh
Invoke-Pester ./babae.tests.ps1 -FullNameFilter '*Staircase regression*'
```
These tests simulate raw byte streams containing BPM sequences and verify that the resulting file on disk matches the input exactly, with no compounded indentation. They also verify that manually typed Enter still works independently and that `Ctrl+V` remains a separate, non-crashing clipboard path.
