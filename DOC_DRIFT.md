# Documentation Drift Report

- **Date/Time:** 2025-05-18 20:30:00 UTC
- **Branch Analyzed:** `dev`

## Files Reviewed

- `README.md`
- `THEORY.md`
- `STAIRCASE.md`
- `WINGET.md`
- `BOOTSTRAP.md`
- `STYLE_POLICY.md`

## Regressions Found

1. **`STAIRCASE.md` Function Name Drift:**
   - Mentioned `Paste-TextFromClipboard` which does not exist in the codebase. The actual implementation function is `Insert-TextFromClipboard`.
   - Mentioned `Handle-EditingKey` which does not exist in the codebase. The actual key dispatch function is `Invoke-EditingKey`.
2. **`THEORY.md` Function Name Drift:**
   - Mentioned `Parse-EscapeSequence` which does not exist in the codebase. The actual sequence conversion function is `ConvertFrom-EscapeSequence`.
3. **`README.md` `.editorconfig` Support Omission:**
   - Omitted `tab_width` and `max_line_length` (line length ruler) from the list of supported `.editorconfig` properties handled by `Config.ps1` and rendered by `Renderer.ps1`.

## Files Changed

- `STAIRCASE.md`
- `THEORY.md`
- `README.md`
- `DOC_DRIFT.md`

## Summary of Fixes

- Replaced stale references to `Paste-TextFromClipboard` with `Insert-TextFromClipboard` in `STAIRCASE.md`.
- Replaced stale references to `Handle-EditingKey` with `Invoke-EditingKey` in `STAIRCASE.md`.
- Replaced stale reference to `Parse-EscapeSequence` with `ConvertFrom-EscapeSequence` in `THEORY.md`.
- Added `tab_width` and `max_line_length` (line length ruler) to the `.editorconfig` feature description in `README.md`.
- Created `DOC_DRIFT.md` documenting the regression-prevention pass findings and resolution.
