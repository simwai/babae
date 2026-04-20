<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-7+-4c1d95?style=flat&logo=powershell&logoColor=white" alt="PowerShell 7+" />
  <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-5b21b6?style=flat&logoColor=white" alt="Cross-platform" />
  <img src="https://img.shields.io/badge/SSH-xterm--256color-6d28d9?style=flat&logoColor=white" alt="SSH / xterm-256color" />
  <img src="https://img.shields.io/badge/Pester-5.x-7c3aed?style=flat&logoColor=white" alt="Pester 5" />
  <img src="https://img.shields.io/badge/Status-Highly%20Experimental-ff4444?style=flat&logoColor=white" alt="Highly Experimental" />
  <img src="https://img.shields.io/badge/License-MIT-8b5cf6?style=flat&logoColor=white" alt="MIT License" />
</p>

---

> [!WARNING]
> **babae is highly experimental.** It is a quick and dirty attempt at building a PowerShell-based TUI code editor. Expect rough edges, missing features, and occasional cursed behaviour. Use at your own risk — preferably not on production systems.

<!-- toc -->

- [Introduction](#introduction)
- [Key Features](#key-features)
- [Environment Setup Guide](#environment-setup-guide)
  * [1. Install PowerShell 7+](#1-install-powershell-7)
  * [2. Download babae](#2-download-babae)
- [Usage Guide](#usage-guide)
  * [Keybindings](#keybindings)
- [Themes](#themes)
- [The Stairway Paste Fix](#the-stairway-paste-fix)
- [Testing](#testing)

<!-- tocstop -->

---

## Introduction

babae is a zero-dependency TUI text editor written in pure PowerShell. No NuGet packages, no compiled DLLs, no external binaries — just a single `.ps1` file you can drop anywhere and run. It renders via raw ANSI escape sequences, reads input at the byte level, and speaks `.editorconfig`.

Its primary reason for existence: most terminal editors misbehave when pasting indented text over SSH in Bitvise (xterm-256color). babae fixes that at the input layer.

## Key Features

- **Zero Dependencies**: One file. `pwsh ./babae.ps1`. Done.
- **SSH-Safe Paste**: Raw stdin byte reader with bracketed paste mode (BPM) support. Right-click paste over SSH does not staircase — ever. See [The Stairway Paste Fix](#the-stairway-paste-fix).
- **ANSI TUI Rendering**: Low-flicker frame rendering via a shadow row buffer and direct stdout stream writes. Only changed rows are redrawn.
- **Four Dark Themes**: babae dark, Catppuccin Mocha, Catppuccin Frappe, GitHub Dark. Cycle with `^1`.
- **Undo / Redo**: Snapshot-based undo stack (up to 200 entries) with `^Z` / `^Y`.
- **Incremental Search**: Live highlighting across the buffer with `^F`.
- **Cross-Platform Clipboard**: `^C` / `^V` via `xclip` / `xdotool` on Linux, `pbcopy` / `pbpaste` on macOS, `Set-Clipboard` on Windows.
- **`.editorconfig` Support**: Picks up `indent_style`, `indent_size`, `end_of_line`, `trim_trailing_whitespace`, `insert_final_newline`, and `charset` from the nearest `.editorconfig`.
- **Mouse Right-Click Paste on Windows**: Win32 console API integration for native right-click paste events.

## Environment Setup Guide

### 1. Install PowerShell 7+

babae requires PowerShell 7 or later.

- **Ubuntu / Debian**:
  ```bash
  sudo apt-get install -y powershell
  ```
  Or follow the [official Microsoft guide](https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu).

- **macOS**:
  ```bash
  brew install powershell
  ```

- **Windows**: PowerShell 7 ships with modern Windows. If needed, download from [github.com/PowerShell/PowerShell](https://github.com/PowerShell/PowerShell/releases).

### 2. Download babae

```bash
curl -O https://raw.githubusercontent.com/simwai/babae/main/babae.ps1
```

That is the entire installation.

## Usage Guide

```bash
# Open a new buffer
pwsh ./babae.ps1

# Open an existing file
pwsh ./babae.ps1 myfile.txt

# Open with a specific theme
pwsh ./babae.ps1 myfile.txt -Theme mocha
```

### Keybindings

| Key | Action |
|-----|--------|
| `^S` | Save |
| `^Q` | Quit |
| `^Z` | Undo |
| `^Y` | Redo |
| `^F` | Find (incremental search) |
| `^A` | Select all |
| `^C` | Copy selection (or current line) |
| `^V` | Paste from clipboard |
| `^1` | Cycle theme |
| `^2` | Help |
| `Arrow keys` | Move cursor |
| `Home` / `End` | Start / end of line |
| `PgUp` / `PgDn` | Scroll by screen |
| `Backspace` / `Del` | Delete character |
| `Enter` | New line with auto-indent |
| `Tab` | Insert indent (space or tab per `.editorconfig`) |

## Themes

| Flag value | Name |
|------------|------|
| `dark` *(default)* | babae dark |
| `mocha` | Catppuccin Mocha |
| `frappe` | Catppuccin Frappe |
| `github-dark` | GitHub Dark |

## The Stairway Paste Fix

When pasting multi-line indented text via right-click over SSH (Bitvise, xterm-256color), every `\n` in the paste stream used to hit the `Enter` handler, which re-injected the current line's leading whitespace — compounding it on every successive line and producing an ever-widening staircase of indentation.

This is an [open bug in micro](https://github.com/micro-editor/micro/issues/3571) and stems from using `Console.ReadKey`, which silently strips the `[` from bracketed-paste sentinels (`ESC[200~` → `ESC200~`) on older .NET runtimes ([dotnet/runtime#60101](https://github.com/dotnet/runtime/issues/60101)).

babae sidesteps this entirely by reading `Console.OpenStandardInput()` as raw bytes. Bytes are bytes regardless of runtime or SSH layer. BPM sentinels are detected at the byte level, and the paste payload is routed directly to the insert routine — bypassing the `Enter` handler and its auto-indent logic completely.

Nano uses the same principle (raw `read()` syscall). babae brings it to pure PowerShell.

## Testing

E2E tests use Pester 5 with no Docker. Each test starts babae as a child process with stdin/stdout fully redirected, writes raw byte sequences to stdin, and verifies the output file.

```bash
# Install Pester (once)
Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser

# Run the suite
Invoke-Pester ./babae.tests.ps1 -Output Detailed
```

The suite covers:

- BPM byte-sequence helper unit tests
- Stairway regression: uniform indent, mixed indent, empty paste, 500-line large paste
- Normal key input: printable chars, Enter auto-indent, Ctrl+Z undo/redo
- Ctrl+V clipboard paste path isolation
