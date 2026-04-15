# Diff View & View Modes Design

**Date:** 2026-04-15
**Status:** Approved

## Problem

Inkwell's live reload is broken due to two bugs in the filesystem watcher, and even when working, there is no way to see *what* changed in a file — only the latest rendered state. When Claude Code or another tool edits a large markdown file, it's impossible to tell what was modified without manually comparing versions.

## Solution Overview

1. Fix the watcher bug so live reload works reliably with all text editors
2. Add three view modes: **Static**, **Live**, **Diff** (default)
3. In diff mode, show block-level + word-level rendered diffs with per-block and global accept

## Watcher Bug Fix

### Root Cause

Two bugs in `Inkwell.Watcher.handle_info/2` (`lib/inkwell/watcher.ex:91-108`):

1. **Symlink mismatch**: macOS FSEvents reports real paths (e.g., `/private/tmp/file.md`) but `Path.expand/1` doesn't follow symlinks (returns `/tmp/file.md`). The registered path and event path never match, so `MapSet.member?` always returns `false`.

2. **Event filter too strict**: The guard `if :modified in events` only matches direct in-place writes (e.g., shell `echo >`). Text editors do atomic writes (write-to-temp + rename), which produce `[:renamed]` events. These are silently dropped.

### Fix

- Resolve paths with `File.realpath/1` (falling back to `Path.expand/1`) when registering files in the MapSet AND when comparing incoming event paths.
- Broaden the event filter from `:modified in events` to `Enum.any?(events, &(&1 in [:modified, :renamed, :created]))`.

## View Modes

### Static

Captures the rendered HTML at load time. Ignores all subsequent file change events. The watcher still runs (so switching modes is possible), but incoming WebSocket payloads are stored in `pendingHtml` without updating the DOM.

### Live

Current intended behavior. Every file change triggers re-render and full DOM replacement. No diff logic involved. `baselineBlocks` is updated on every change.

### Diff (Default)

When a file change arrives, compute the diff between the previous baseline and the new HTML. Display the new content with block-level and word-level highlights. Includes per-block and global accept.

### Mode Switching

**CLI flag:** `inkwell preview file.md --mode diff|live|static` (default: `diff`)

**In-browser toggle:** Three compact buttons in the existing top bar (right side, next to the theme toggle): `Static` | `Live` | `Diff`. Active mode gets a filled/highlighted style (purple pill for active, dark gray for inactive). Clicking switches instantly, no server round-trip.

**Transition behavior:**

| From | To | Behavior |
|------|----|----------|
| Any | Static | Freeze current DOM as-is (diff highlights included if present) |
| Any | Live | Clear all diff highlights, set `baselineBlocks` to current, future changes do full DOM replacement |
| Any | Diff | Set current content as `baselineBlocks`, next file change shows diff |
| Static | Diff/Live | If file changed while static, immediately render latest (live) or diff against frozen content (diff) |

**Persistence:** Mode choice saved to `localStorage`, survives page refreshes. CLI `--mode` flag overrides `localStorage` on initial load.

## Diff Engine

### Architecture

Entirely client-side in JavaScript. The server continues to send full rendered HTML on every file change. The browser decides what to do with it based on the current mode. No server changes beyond the watcher bug fix and passing the mode flag.

### Block-Level Diffing

When a new HTML payload arrives in diff mode:

1. Parse both `baselineBlocks` and the incoming HTML into lists of top-level block elements (paragraphs, headings, lists, blockquotes, code blocks, tables, etc.)
2. Compare using a longest-common-subsequence (LCS) algorithm on `element.textContent` (normalized whitespace)
3. Classify each block:
   - **Added** — block exists in new, not in old
   - **Removed** — block exists in old, not in new
   - **Modified** — block exists in both positions but content differs
   - **Unchanged** — identical

### Word-Level Diffing

Only computed for blocks classified as "modified":

1. Extract text content from the old and new block
2. Run a word-level diff (LCS on word arrays)
3. Rebuild the block's `innerHTML` with `<span>` wrappers: green background for insertions, red strikethrough for deletions

### Rendering

| Classification | Visual Treatment | CSS Class |
|----------------|-----------------|-----------|
| Unchanged | Rendered as-is, no decoration | — |
| Added | Green left border, subtle green background tint | `.inkwell-diff-added` |
| Removed | Red left border, strikethrough, reduced opacity, inserted in DOM above original position | `.inkwell-diff-removed` |
| Modified | Amber left border, amber background tint, word-level `<span>` highlights inside | `.inkwell-diff-modified` |
| Word added | Green background on inserted words | `.inkwell-diff-word-added` |
| Word removed | Red background + strikethrough on deleted words | `.inkwell-diff-word-removed` |

### Edge Cases

- **Rapid consecutive saves:** Debounce with ~300ms delay. Always diff against `baselineBlocks`, not the previous intermediate state.
- **Very large files:** Block-level comparison is O(n) on block count (typically dozens to low hundreds). Word-level is only computed for modified blocks.
- **Structural HTML changes** (e.g., paragraph becomes a list): Treated as remove + add rather than modification.
- **Scroll position:** Diff mode builds the DOM surgically (updating/inserting/removing individual blocks) rather than replacing `innerHTML`, so scroll position is naturally preserved. Live mode continues to do full `innerHTML` replacement (scroll position not preserved, matching current behavior).

## Accept UX

### Per-Block Accept

- Each highlighted block shows a small checkmark icon on hover, positioned at the top-right of the block
- Clicking accepts that individual change: clears diff styling, removes any injected "removed" blocks, updates that block's entry in `baselineBlocks`
- Subtle fade-out animation (200ms)

### Global Accept

- Floating pill in the bottom-right corner with compact change summary (e.g., `+1 ~1`) and an "Accept" button
- Accepts all remaining highlighted blocks at once
- Disappears when no diff highlights remain
- Keyboard shortcut: `Cmd+Enter` / `Ctrl+Enter`

### Baseline Tracking

- `baselineBlocks` — array of `{ tag, textContent, outerHTML }` for each top-level block element, stored client-side
- Per-block accept updates that block's entry in `baselineBlocks` to the new version
- Global accept replaces `baselineBlocks` entirely with the current state
- When a new file change arrives, diff is computed against `baselineBlocks` (which may be a mix of old and selectively-accepted content)

## Server-Side Changes (Minimal)

### Watcher (`lib/inkwell/watcher.ex`)

- Resolve paths with `File.realpath/1` when registering and comparing
- Broaden event filter to `:modified | :renamed | :created`

### CLI (`lib/inkwell/cli.ex`)

- Add `mode: :string` to the option parser
- Pass `mode` through to the `/open` endpoint and initial page render

### Router (`lib/inkwell/router.ex`)

- Accept `mode` query param on `/open` and the page route
- Inject as `data-mode` on the `<body>` tag in initial HTML

### What Does NOT Change

- WebSocket handler — still sends full rendered HTML every time
- Renderer — still does full markdown→HTML conversion
- Registry/broadcast — still dispatches to all clients
- Daemon — no awareness of modes

## Client-Side Changes (`priv/static/app.js`)

### New State Variables

- `currentMode` — `'diff'` | `'live'` | `'static'` (read from `data-mode` or `localStorage`)
- `baselineBlocks` — array of `{ tag, textContent, outerHTML }` for each top-level block element, set on initial load
- `pendingHtml` — in static mode, stores the latest HTML received but not rendered

### Modified Functions

- `handleContentUpdate(data)` — branches on `currentMode`: static stores to `pendingHtml`, live does current behavior, diff runs the diff engine

### New Functions

- `computeBlockDiff(oldBlocks, newBlocks)` — LCS-based comparison returning `{ added, removed, modified, unchanged }`
- `computeWordDiff(oldText, newText)` — word-level diff for modified blocks
- `renderDiffView(diffResult, newHtml)` — builds final DOM with diff CSS classes
- `acceptBlock(blockIndex)` — clears highlight on one block, updates `baselineBlocks`
- `acceptAll()` — clears all highlights, replaces `baselineBlocks`
- `switchMode(mode)` — handles transitions, persists to `localStorage`

### No External Dependencies

Diff algorithms implemented inline (~100-150 lines for LCS + word diff). No npm libraries needed.

## Testing Strategy

### Watcher Bug Fix (Elixir tests)

- Test that `handle_info` with `[:renamed]` events triggers a reload
- Test that symlinked paths are resolved correctly when registering and matching

### Mode Switching (manual browser testing)

- Mode toggle buttons switch instantly
- `localStorage` persistence across page refreshes
- CLI `--mode` flag overrides stored preference
- Static mode ignores incoming WebSocket updates
- Switching from static to diff/live applies pending changes

### Diff Engine (browser console / test page)

- Block-level: added paragraph detected, removed paragraph shown, modified paragraph highlighted
- Word-level: single word change shows red/green spans, full sentence replacement handled
- Edge cases: empty → content, content → empty, reordered sections

### Accept Flow

- Per-block accept clears that block's highlight only
- Global accept clears all highlights, FAB disappears
- After partial accept, next file change diffs correctly against hybrid baseline
- `Cmd+Enter` shortcut triggers global accept
