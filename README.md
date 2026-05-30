<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-7+-4c1d95?style=flat&logo=powershell&logoColor=white" alt="PowerShell 7+" />
  <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-5b21b6?style=flat&logoColor=white" alt="Cross-platform" />
  <img src="https://img.shields.io/badge/SSH-xterm--256color-6d28d9?style=flat&logoColor=white" alt="SSH / xterm-256color" />
  <img src="https://img.shields.io/badge/Pester-5.x-7c3aed?style=flat&logoColor=white" alt="Pester 5" />
  <img src="https://img.shields.io/badge/Status-Experimental-orange?style=flat&logoColor=white" alt="Experimental" />
  <img src="https://img.shields.io/badge/License-MIT-8b5cf6?style=flat&logoColor=white" alt="MIT License" />
</p>

---

> [!IMPORTANT]
> **babae is currently in an experimental state.** While it is designed to be a lightweight and efficient editor, it is not yet fully stable. Please be aware that bugs may occur, and there is a risk of file corruption when editing. It is recommended to use it on non-critical files and keep backups.

<!-- toc -->

- [Introduction](#introduction)
- [Key Features](#key-features)
- [Environment Setup Guide](#environment-setup-guide)
  * [1. Install PowerShell 7+](#1-install-powershell-7)
  * [2. Download babae](#2-download-babae)
- [Global Install](#global-install)
- [Usage Guide](#usage-guide)
  * [Keybindings](#keybindings)
- [Themes](#themes)
- [Language Detection](#language-detection)
- [The Staircase Paste Fix](#the-staircase-paste-fix)
- [Deep Dive: The Theory of the Terminal](#deep-dive-the-theory-of-the-terminal)
- [Testing](#testing)

<!-- tocstop -->

---

## Introduction

babae is a zero-dependency TUI text editor written in pure PowerShell. No NuGet packages, no compiled DLLs, no external binaries — just a single `.ps1` file you can drop anywhere and run. It renders via raw ANSI escape sequences, handles input via bracketed paste mode (BPM), and speaks `.editorconfig`.

Its primary reason for existence: most terminal editors misbehave when pasting indented text over SSH in Bitvise (xterm-256color). babae fixes that at the input layer.

## Key Features

- **Zero Dependencies**: One file. `pwsh ./babae.ps1`. Done.
- **SSH-Safe Paste**: Bracketed paste mode (BPM) support across both interactive and redirected stdin paths. Right-click paste over SSH does not staircase — ever. See [The Staircase Paste Fix](#the-staircase-paste-fix).
- **ANSI TUI Rendering**: Low-flicker frame rendering via a shadow row buffer and direct stdout stream writes. Only changed rows are redrawn.
- **Four Dark Themes**: babae dark, Catppuccin Mocha, Catppuccin Frappe, GitHub Dark. Cycle with `^T`.
- **Undo / Redo**: Snapshot-based undo stack (up to 200 entries) with `^Z` / `^Y`.
- **Incremental Search**: Live highlighting across the buffer with `^F`.
- **Cross-Platform Clipboard**: `^C` / `^V` via `xclip` / `xsel` / `wl-copy` on Linux (X11 and Wayland), `pbcopy` / `pbpaste` on macOS, `System.Windows.Forms.Clipboard` on Windows.
- **`.editorconfig` Support**: Picks up `indent_style`, `indent_size`, `end_of_line`, `trim_trailing_whitespace`, `insert_final_newline`, and `charset` from the nearest `.editorconfig`.
- **Mouse Right-Click Paste on Windows**: Win32 console API integration for native right-click paste events.
- **Language Detection**: Automatic language label in the header based on file extension (see [Language Detection](#language-detection)).
- **Global Install**: On first run outside `~/.babae/`, babae offers to install itself globally and register a `babae` shell function in your PowerShell profile.

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

## Global Install

On first run, if babae detects it is not already running from `~/.babae/babae.ps1`, it will prompt:

```
babae is not installed globally. Install to ~/.babae/babae.ps1 and add to profile? (y/n):
```

Answering `y` copies `babae.ps1` to `~/.babae/` and appends a `babae` function to your `$PROFILE`, so you can launch it from anywhere with:

```pwsh
babae myfile.txt
```

If a different version is already installed, the same prompt appears offering to update it. Set `$Env:BABAE_SKIP_INSTALL = 1` to suppress this check entirely.

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
| `^T` | Cycle theme |
| `^H` | Help |
| `Arrow keys` | Move cursor |
| `Shift+Arrows` | Extend selection |
| `Home` / `End` | Start / end of line |
| `PgUp` / `PgDn` | Scroll by screen |
| `Backspace` / `Del` | Delete character |
| `Enter` | New line with auto-indent |
| `Tab` | Insert indent (space or tab per `.editorconfig`) |
| `Esc` | Cancel search / clear selection |
| `RightClick` | Paste from clipboard (Windows only) |

## Themes

| Flag value | Name |
|------------|------|
| `dark` *(default)* | babae dark |
| `mocha` | Catppuccin Mocha |
| `frappe` | Catppuccin Frappe |
| `github-dark` | GitHub Dark |

## Language Detection

babae automatically displays a language label in the header bar based on the opened file's extension. No configuration needed.

| Extension(s) | Language |
|---|---|
| `.ps1`, `.psm1`, `.psd1` | PowerShell |
| `.cs` | C# |
| `.ts`, `.tsx` | TypeScript |
| `.js`, `.jsx` | JavaScript |
| `.py` | Python |
| `.json` | JSON |
| `.md` | Markdown |
| `.sh`, `.bash` | Bash |
| *(anything else)* | Plain Text |

## The Staircase Paste Fix

babae solves the "Staircase" bug (compound auto-indentation) using Bracketed Paste Mode (BPM).

For a deep dive into the anatomy of the bug and the technical implementation of the fix, see:
👉 **[STAIRCASE.md](STAIRCASE.md)**

## Deep Dive: The Theory of the Terminal

To understand the core architecture of babae, the .NET/PowerShell APIs used, and the ANSI specifications it follows, check out the comprehensive theory guide:
👉 **[THEORY.md](THEORY.md)**

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
- Staircase regression: uniform indent, mixed indent, empty paste, 500-line large paste
- Normal key input: printable chars, Enter auto-indent, Ctrl+Z undo/redo
- Ctrl+V clipboard paste path isolation
