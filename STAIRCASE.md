# The Staircase Bug: Anatomy and Solution

## What is the Staircase Bug?

The "Staircase Bug" (sometimes referred to as the "Stairway" effect) is a common issue in terminal-based text editors, especially when used over SSH or in certain terminal emulators (like Bitvise or older xterm configurations).

When you paste multi-line, indented text into an editor using the terminal's native "Right-Click Paste" or "Middle-Click Paste", the terminal sends the text to the editor's standard input stream as if it were being typed extremely fast.

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

### 3. Dual-Path Input Handling
babae's input engine (both the interactive Runspace and the raw Stdin reader) is designed to look for these markers.

- **Detection:** When the `ESC [ 200 ~` sequence is detected, babae immediately switches its input state to "Pasting".
- **Verbatim Insertion:** While in the "Pasting" state, babae reads characters and inserts them **directly into the buffer** using the `Paste-Text` function.
- **Bypassing Handlers:** Because the text is routed through `Paste-Text` instead of the standard `Handle-EditKey` routine, the `Enter` key handler is never triggered for newlines inside the paste. No auto-indent logic runs, so no extra spaces are injected.
- **Completion:** Once `ESC [ 201 ~` is encountered, babae returns to normal "Typing" mode.

### 4. SSH Robustness
SSH often delivers data in small TCP segments. If a paste is large, the `ESC [ 201 ~` marker might arrive several milliseconds after the start of the paste. babae's `Stdin-DrainPaste` function uses an **adaptive backoff timer** (waiting up to 2000ms with small sleeps) to ensure it waits long enough for the full payload to arrive over a high-latency connection without timing out prematurely and leaving the editor in a broken state.

---

## Verification

You can verify the fix in babae by running the Pester test suite:
```pwsh
Invoke-Pester ./babae.tests.ps1 -TestName "Staircase regression"
```
These tests simulate raw byte streams containing BPM sequences and verify that the resulting file on disk matches the input exactly, with no compounded indentation.
