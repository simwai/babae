# Documentation Drift & Regression Analysis

- **Date / Time:** 2026-09-07 05:52:49 UTC
- **Branch Analyzed:** `dev`
- **Files Reviewed:**
  - `README.md`
  - `STAIRCASE.md`
  - `THEORY.md`
- **Regressions Found:**
  1. `README.md`: Theme count stated "Four Dark Themes" and omitted `latte-contrast` (`Catppuccin Latte (high contrast)`) from the Themes table.
  2. `README.md`: Keybindings table listed `^H` for Help (actually bound to `^F1`), listed `Enter` as "New line with auto-indent" (Enter no longer auto-indents in the editor), and omitted autocomplete from `Tab` key description.
  3. `README.md`: Language Detection table missed 10 supported file extensions/languages (`.jsonc`, `.jsonl`, `.html`, `.htm`, `.css`, `.svg`, `.yaml`, `.yml`, `.toml`, `.java`, `.env`, `Dockerfile`).
  4. `THEORY.md`: Section 2 described an obsolete input architecture using a background PowerShell Runspace and `[Console]::ReadKey`, which was replaced by unified raw stdin stream reading (`[Console]::OpenStandardInput()` and `ReadAsync`). Section 4 table listed `[Console]::ReadKey(true)` instead of `[Console]::OpenStandardInput()`.
- **Files Changed:**
  - `README.md`
  - `THEORY.md`
  - `DOC_DRIFT.md`
- **Summary of Fixes:**
  - Updated `README.md` theme count to 5 themes and added `latte-contrast` to Themes table.
  - Corrected `README.md` keybindings table for `^F1` Help, `Enter` (new line), and `Tab` (indent / autocomplete).
  - Expanded `README.md` Language Detection table to include all supported file types.
  - Corrected `THEORY.md` input architecture and API reference to reflect raw stdin async stream reader.
