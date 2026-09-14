# Documentation Drift Report

- **Run Date/Time:** 2026-09-14 05:48 UTC
- **Branch Analyzed:** `dev`
- **Reviewed Documentation Files:**
  - `README.md`
  - `THEORY.md`
  - `STAIRCASE.md`
  - `WINGET.md`

## Concrete Regressions Discovered

1. **`README.md`**: Stale Win32 Mouse Right-Click Paste Feature Claim & Keybinding
   - `README.md` claimed native Win32 console API mouse right-click paste integration under Key Features and listed `RightClick` paste in the Keybindings table.
   - Codebase check (`src/Editor/Main.ps1` and `src/Editor/Input.ps1`) showed mouse tracking is explicitly turned off via `SEQ_MOUSE_TRACKING_OFF` and SGR mouse reports are silently discarded.

## Files Updated

- `README.md`
- `DOC_DRIFT.md`

## Fixes Made

- Removed stale Win32 mouse right-click paste feature entry from `README.md`.
- Removed `RightClick` paste row from the Keybindings table in `README.md`.
