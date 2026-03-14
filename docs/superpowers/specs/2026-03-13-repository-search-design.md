# Repository-Wide Markdown File Search

## Problem

When previewing a markdown file in Inkwell, the file picker only shows recent files and siblings in the same directory. Users working in git repositories need to find and open markdown files anywhere in the repo — similar to Telescope's find-files in Neovim.

Additionally, when Inkwell is opened without a file or directory argument (`GET /` with no params), it shows an unhelpful "Missing path or dir parameter" error instead of a usable UI.

## Design

### 1. Git Root Detection

New module `Inkwell.GitRepo` with:

- **`find_root/1`** — Given any file or directory path, walks up the directory tree looking for a `.git` directory. Returns `{:ok, root_path}` or `:error`.

Called from `Search.list_files/1` and `Search.search/2` to detect if the current file lives in a git repo.

### 2. Recursive File Discovery

**`Inkwell.GitRepo.find_markdown_files/1`** — Recursively walks the directory tree from the git root, collecting all `.md` files.

**Skip list** (directories skipped during traversal):
- `.git`, `node_modules`, `_build`, `deps`, `.elixir_ls`
- `_opam`, `target`, `vendor`, `.cache`, `dist`, `build`

Note: `.superpowers` is NOT skipped — markdown files there should be discoverable.

**Behavior:**
- Returns paths sorted alphabetically
- Paths stored as absolute paths internally, displayed as relative to git root in the UI
- Title extraction (first H1) uses existing `Search.extract_title/1`
- Without a search query: returns only the first 20 files (alphabetical). Title extraction only runs on those 20.
- With a search query: fuzzy match runs against filename + relative path + title, returns top 50 results. Scoring weights: filename 1.0, title 1.2 (matching existing behavior), relative path 0.8 (lower since it's supplementary context)

### 3. Backend API Changes

**Breaking change to `/search` response format.** The current endpoint returns a flat JSON array. The new format is a structured object:

```json
{
  "recent": [...],
  "siblings": [...],
  "repository": {
    "name": "inkwell",
    "files": [
      {
        "path": "/abs/path/docs/setup.md",
        "rel_path": "docs/setup.md",
        "filename": "setup.md",
        "title": "Getting Started",
        "section": "repository"
      }
    ],
    "total": 83
  }
}
```

The `recent` and `siblings` arrays contain the same file objects as the current flat array, just grouped. The `rel_dir` for display is derived client-side from `rel_path` (strip the filename).

- Without query: first 20 repo files (alphabetical), excluding duplicates from recent/siblings
- With query: fuzzy match across all repo files, top 50, deduped against recent/siblings
- `repository` is `null` when the current file isn't in a git repo
- Deduplication of repo files against recent/siblings happens server-side (consistent with existing sibling dedup in `search.ex`)

**Router `/search` handler changes:** The current handler uses `fetch_query_path(conn, "current")` which requires the param. This becomes an optional param with two code branches:
- When `current` is present: existing behavior + new repository results
- When `current` is absent: call `Search.list_recent/0` which returns `%{recent: files, siblings: [], repository: nil}` — only recent files from `Inkwell.History`

**`/search` is only consumed by `app.js`** — no external consumers (Tauri desktop app opens the browser which loads app.js; CLI only hits `/open`).

**Authorization** — `authorized?/3` updated to accept any file under the git root. For `source: "repository"`, derives the git root from `current_path` via `GitRepo.find_root/1` and verifies `new_path` starts with that root. When `current_path` is nil (empty state), repository source is not used — the user must pick via Open File/Open Folder buttons or select a recent file (which are already authorized).

### 4. Frontend Changes

**Repository section in picker:**
- New section below "Recent" and "Sibling Files" with header "Repository (name)" in blue accent (`#7aa2f7` in dark theme, matching heading color)
- Files show: title + filename on the left, relative directory path dimmed on the right
- Truncation hint at bottom: "Showing 20 of N files — type to search all"
- Keyboard nav, preview pane, and selection work seamlessly across all three sections
- Files already in Recent/Sibling sections are not repeated in Repository

**`loadSearch()` changes:**
- Parse the new structured response (instead of flat array) and merge `recent` + `siblings` + `repository.files` into `currentFiles` for keyboard navigation
- Store `repository.name` and `repository.total` for section header and truncation hint

**`renderFileList()` changes:**
- Render third section with repo-specific styling
- Repository items derive `rel_dir` from `rel_path` client-side (strip filename) and display it right-aligned

### 5. Empty State — No Path or Dir

When `GET /` is called with no `path` or `dir` parameter:

- Router serves the full HTML page (same template as browse mode) with a `data-no-file` attribute instead of the "Missing path or dir parameter" error
- `app.js` detects `data-no-file` and auto-opens the picker
- No WebSocket connection is established (existing code already skips `connect()` when both `currentPath` and `initialBrowseDir` are null — this behavior is preserved)
- Picker calls `/search` with no `current` param, which triggers `Search.list_recent/0` returning only recent files
- Main content area shows a minimal welcome message (e.g., "Open a file to get started")
- Once user picks a file, `selectFile()` calls `/switch`. In the empty state, `currentPath` is null, so `selectFile()` does a full page navigation (`window.location = '/?path=' + encodeURIComponent(path)`) instead of the normal `/switch` fetch, since `/switch` requires a valid `current` param. After navigation, the page loads in normal preview mode with WebSocket connection.

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| File discovery method | Pure Elixir recursive walk | No external dependencies, fast enough for markdown file counts |
| Files included | All `.md` files, not just git-tracked | Gitignored markdown files are still valuable to preview |
| Initial result cap | 20 files | Keeps picker snappy; recent + siblings cover most-likely files |
| Search result cap | 50 files | Matches existing search behavior |
| Path display | Title + filename left, directory right | Consistent with existing sections, adds directory context |
| Skip directories | Hardcoded list | Simple, covers common cases, avoids external deps |

## Files to Modify

| File | Change |
|------|--------|
| `lib/inkwell/git_repo.ex` | **New** — `find_root/1`, `find_markdown_files/1` |
| `lib/inkwell/search.ex` | Add repository results to `list_files/1` and `search/2`, add `list_recent/0` |
| `lib/inkwell/router.ex` | Update `/search` response format, update `authorized?/3`, handle empty `GET /` |
| `priv/static/app.js` | Parse repository section, render with directory paths, handle `data-no-file` |
| `priv/static/app.css` | Style for `.picker-section.repo` and `.picker-item-dir` |
