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
- With a search query: fuzzy match runs against filename + relative path + title, returns top 50 results

### 3. Backend API Changes

**`GET /search`** response gains a `repository` key:

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

- Without query: first 20 repo files (alphabetical), excluding duplicates from recent/siblings
- With query: fuzzy match across all repo files, top 50, deduped against recent/siblings
- `repository` is `null` when the current file isn't in a git repo

**Authorization** — `authorized?/3` updated to accept any file under the git root, not just recent + siblings.

### 4. Frontend Changes

**Repository section in picker:**
- New section below "Recent" and "Sibling Files" with header "Repository (name)" in blue accent (`#7aa2f7` in dark theme, matching heading color)
- Files show: title + filename on the left, relative directory path dimmed on the right
- Truncation hint at bottom: "Showing 20 of N files — type to search all"
- Keyboard nav, preview pane, and selection work seamlessly across all three sections
- Files already in Recent/Sibling sections are not repeated in Repository

**`renderFileList()` changes:**
- Parse new `repository` key from `/search` response
- Render third section with repo-specific styling
- Repository items include a `rel_dir` field displayed right-aligned

### 5. Empty State — No Path or Dir

When `GET /` is called with no `path` or `dir` parameter:

- Router serves the full HTML page (same template as browse mode) with a `data-no-file` attribute instead of the "Missing path or dir parameter" error
- `app.js` detects `data-no-file` and auto-opens the picker
- Picker calls `/search` with no `current` param to show just recent files
- Main content area shows a minimal welcome message (e.g., "Open a file to get started")
- Once user picks a file, switches to normal preview mode

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
| `lib/inkwell/search.ex` | Add repository results to `list_files/1` and `search/2` |
| `lib/inkwell/router.ex` | Update `/search` response format, update `authorized?/3`, handle empty `GET /` |
| `priv/static/app.js` | Parse repository section, render with directory paths, handle `data-no-file` |
| `priv/static/app.css` | Style for `.picker-section.repo` and `.picker-item-dir` |
