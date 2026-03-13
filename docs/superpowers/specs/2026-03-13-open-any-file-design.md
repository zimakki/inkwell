# Open Any File from Fuzzy Finder — Design Spec

**Issue:** #9
**Date:** 2026-03-13
**Status:** Approved
**Platform:** macOS only (osascript). Linux/other platforms unsupported for now.

## Problem

The fuzzy finder only shows historically opened files and sibling files in the current directory. Users cannot open markdown files from arbitrary directories.

## Solution

Add a native macOS file picker (via `osascript`) accessible from the fuzzy finder UI. Two actions:

1. **Open File** — Opens macOS file chooser filtered to `.md` files. Selected file opens directly.
2. **Open Folder** — Opens macOS folder chooser. Selected directory's `.md` files populate the picker for browsing.

## Architecture

### New Module: `Inkwell.FileDialog`

Native file dialog using `System.cmd/3` with `osascript -e`:

- `pick_file/0` → `{:ok, path}` | `:cancel` | `{:error, reason}`
  - AppleScript: `choose file of type {"md"}` with prompt
- `pick_directory/0` → `{:ok, dir_path}` | `:cancel` | `{:error, reason}`
  - AppleScript: `choose folder` with prompt

Error handling:
- Non-zero exit code with "User canceled" in stderr → `:cancel`
- Non-zero exit code otherwise → `{:error, stderr_message}`
- `System.cmd/3` called with `stderr_to_stdout: true` for unified output parsing

### Search Module Changes

- `list_directory_files/1` — Lists `.md` files in any directory with title extraction, section: `:browse`. Returns `[]` for invalid/inaccessible directories (uses `File.ls/1` not `File.ls!/1`).
- `search_directory/2` — Fuzzy search within a browsed directory. Empty/nil query returns all files.

### Router Changes

New routes:
- `GET /pick-file` → Calls `FileDialog.pick_file()`, returns `{path, filename}` JSON or 204 if cancelled
- `GET /pick-directory` → Calls `FileDialog.pick_directory()`, returns list of `.md` files or 204 if cancelled
- `GET /browse?dir=<path>&q=<query>` → Lists/searches `.md` files in a directory. `q` is optional; omitted returns all `.md` files. Returns 400 if `dir` missing, returns empty list for invalid directories.

Modified routes:
- `GET /switch` — Accept `source=browse` param to bypass `allowed_path?` check. Still validates: file exists, ends with `.md`. Implementation: conditional in the `with` chain — when `source == "browse"`, skip the `allowed_path?` guard.
- `GET /preview` — Same `source=browse` bypass.

Note: `GET /open` is not affected — it's the CLI entry point and already allows any path.

### Frontend Changes (`app.js`)

State:
- `browseDir` — when set (string path), picker is in "browse mode"

Buttons in picker search bar:
- "Open File" button → `fetch('/pick-file')` → if 200, switch to returned file (close picker). If 204, no-op (user cancelled).
- "Open Folder" button → `fetch('/pick-directory')` → if 200, set `browseDir`, populate picker with returned files. Picker stays open. If 204, no-op.

Browse mode behavior:
- Search queries go to `/browse?dir=<browseDir>&q=<query>` instead of `/search`
- When `browseDir` is set, append `&source=browse` to `/switch` and `/preview` fetch URLs
- Section label shows the directory name (e.g., "Browse: /path/to/dir")
- "Open File" while in browse mode: switch to file, close picker, clear `browseDir`
- "Open Folder" while in browse mode: replace `browseDir` with new directory

Exiting browse mode:
- Closing the picker (`closePicker()`) clears `browseDir`
- Re-opening the picker starts fresh with normal recent+sibling view

### CSS Changes (`app.css`)

- Style browse buttons in picker search bar (existing `app.css` file)

## Security

- Browse-selected files bypass `allowed_path?` since the user explicitly chose them via native OS dialog
- Still validates: file exists, ends with `.md`
- The `/browse` endpoint exposes directory listing for `.md` files only. This is consistent with the local-only daemon security model (no auth, localhost only).
- No new attack surface — osascript runs locally and requires user interaction

## Testing

- `test/inkwell/file_dialog_test.exs` — Mock osascript, test pick_file/pick_directory responses, cancellation, and error handling
- Update `test/inkwell/search_test.exs` — Tests for `list_directory_files/1` including invalid directories
- Update `test/inkwell/router_test.exs` — Tests for new routes and `source=browse` param on `/switch` and `/preview`

## Verification

```bash
mix test
mix format --check-formatted
mix compile --warnings-as-errors
```
