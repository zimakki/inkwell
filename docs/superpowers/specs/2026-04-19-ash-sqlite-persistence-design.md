# Ash + SQLite Persistence Foundation Design

**Date:** 2026-04-19
**Status:** Approved

## Problem

Inkwell's recents list lives in `Inkwell.History`, an in-memory `Agent`. Every daemon restart — including the 10-minute idle shutdown — wipes it. The `Inkwell.Settings` docstring already names the next step: *"When the next PR adds Ash + SQLite, richer prefs (favorites, recents-with-metadata, tags) move into the database."*

This PR lays the **persistence foundation only**. Favorites and tags are deferred to follow-up PRs.

## Scope

**In scope:**

- Install `ash` and `ash_sqlite` via Igniter.
- Introduce `Inkwell.Repo` (`AshSqlite.Repo`), `Inkwell.Library` Ash domain, and `Inkwell.Library.RecentFile` Ash resource.
- SQLite database at `~/.inkwell/inkwell.db`.
- Run pending migrations on daemon boot; hard-fail if anything goes wrong.
- Replace `Inkwell.History` (deleted) with the Ash resource. Persist recents across restarts.
- Schema columns: `id`, `path` (unique), `last_opened_at`, `open_count`.

**Out of scope (future PRs):**

- Favorites resource / UI.
- Tags resource / UI.
- Full-text search indexing.
- Migrating `Inkwell.Settings` (theme) into the DB — stays file-based so the boot path doesn't depend on SQLite being ready.
- Migrating the `inkwell_git_repo_cache` ETS title cache into the DB.
- XDG Base Directory compliance for the DB path.

## Architecture Overview

### New Modules

- **`Inkwell.Repo`** — `use AshSqlite.Repo, otp_app: :inkwell`. Thin Ash-flavored wrapper over Ecto's SQLite3 adapter.
- **`Inkwell.Library`** — Ash domain. Exposes the stable API (`list_recent/0`, `push_recent/1`, `reset_recents/0`, plus the `list_recent_paths/0` helper).
- **`Inkwell.Library.RecentFile`** — Ash resource with `AshSqlite.DataLayer`. Owns schema + actions.
- **`Inkwell.Release`** — `migrate!/0` wraps `Ecto.Migrator.with_repo/2` for boot-time and test-time migration runs.

### Deleted

- **`Inkwell.History`** — entire module removed. Callers move to `Inkwell.Library`.

### Supervision Tree (daemon mode)

```
Inkwell.Supervisor (one_for_one)
├── Phoenix.PubSub                 (unchanged)
├── Registry: WatcherRegistry      (unchanged)
├── Inkwell.Repo                   ← NEW (replaces Inkwell.History)
├── Inkwell.Daemon                 (unchanged)
├── DynamicSupervisor: WatcherSupervisor (unchanged)
├── InkwellWeb.Telemetry           (unchanged)
└── InkwellWeb.Endpoint            (unchanged)
```

Client mode is unchanged — no Repo, no children.

### Boot Sequence in `Application.start/2`

1. Parse mode.
2. Resolve theme, write to `:persistent_term` (unchanged).
3. **`Inkwell.Release.migrate!()`** — ensure `~/.inkwell/` exists, run pending migrations against a *temporary* Repo instance spawned by `Ecto.Migrator.with_repo/2`. Any error raises and kills application start.
4. `Inkwell.GitRepo.init_cache()` (unchanged).
5. Build `children` (with `Inkwell.Repo` in place of `Inkwell.History`).
6. `Supervisor.start_link`.

Migrations run *before* the supervised `Inkwell.Repo` starts. `Ecto.Migrator.with_repo/2` starts a short-lived Repo process for the migration and shuts it down on return; our long-lived supervised Repo starts fresh immediately after.

### Config Surface

- **`config/config.exs`**:
  - `config :inkwell, ecto_repos: [Inkwell.Repo]`
  - `config :inkwell, :ash_domains, [Inkwell.Library]`
- **`config/runtime.exs`** (prod):
  - `config :inkwell, Inkwell.Repo, database: Path.join(System.user_home!(), ".inkwell/inkwell.db"), pool_size: 5, journal_mode: :wal`
- **`config/test.exs`**:
  - `config :inkwell, Inkwell.Repo, database: Path.join(System.tmp_dir!(), "inkwell_test.db"), pool_size: 5, journal_mode: :wal`

Runtime configuration is used in prod so `~/.inkwell/inkwell.db` is resolved on release boot, not at compile time.

## Resource & Domain

### `Inkwell.Library.RecentFile`

```elixir
defmodule Inkwell.Library.RecentFile do
  use Ash.Resource,
    domain: Inkwell.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "recent_files"
    repo Inkwell.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :path, :string, allow_nil?: false, public?: true
    attribute :last_opened_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :open_count, :integer, allow_nil?: false, default: 0, public?: true
  end

  identities do
    identity :unique_path, [:path]
  end

  actions do
    defaults [:read]

    read :list_recent do
      prepare build(sort: [last_opened_at: :desc], limit: 20)
    end

    create :push_recent do
      accept [:path]
      upsert? true
      upsert_identity :unique_path
      upsert_fields [:last_opened_at, :open_count]

      change set_attribute(:last_opened_at, &DateTime.utc_now/0)
      change atomic_update(:open_count, expr(open_count + 1))
      change set_attribute(:open_count, 1), where: [action_type(:create), not(is_upsert())]
    end

    destroy :reset_recents do
      # bulk destroy — called by tests / future "clear history" UI
    end
  end
end
```

**Implementation risks to verify during implementation** (flagged, not blocked on):

1. **Upsert conflict branch for `open_count`.** If Ash's upsert change pipeline does not cleanly compose `atomic_update` + a conditional `change`, the fallback is a custom `Ash.Resource.Change` module that inspects whether the record is being inserted vs. upserted. Behaviour to preserve: new row → `open_count = 1`; existing row → `open_count = open_count + 1`, `last_opened_at = now()`.
2. **Destroy-all via a resource action.** If the action form is awkward, the fallback is a domain helper that calls `Ash.bulk_destroy!/3`. Public behaviour from the caller's perspective is the same.

### `Inkwell.Library` domain

```elixir
defmodule Inkwell.Library do
  use Ash.Domain

  resources do
    resource Inkwell.Library.RecentFile do
      define :list_recent, action: :list_recent
      define :push_recent, action: :push_recent, args: [:path]
      define :reset_recents, action: :reset_recents
    end
  end

  def list_recent_paths do
    list_recent!() |> Enum.map(& &1.path)
  end
end
```

`list_recent_paths/0` is a plain function (not an Ash code interface) — a thin helper so callers in `Search` don't repeat `|> Enum.map(& &1.path)`.

## Data Flow & Call-Site Migration

### Production Call Sites

| File:Line | Before | After |
|---|---|---|
| `lib/inkwell.ex:19` | `Inkwell.History.push(path)` | `Inkwell.Library.push_recent!(path)` |
| `lib/inkwell_web/live/file_live.ex:13` | `Inkwell.History.push(resolved)` | `Inkwell.Library.push_recent!(resolved)` |
| `lib/inkwell/search.ex:63` | `Inkwell.History.list()` | `Inkwell.Library.list_recent_paths()` |
| `lib/inkwell/search.ex:99` | `Inkwell.History.list()` | `Inkwell.Library.list_recent_paths()` |
| `lib/inkwell/search.ex:257` | `Inkwell.History.list() \|> Enum.filter(...)` | `Inkwell.Library.list_recent_paths() \|> Enum.filter(...)` |

All production call sites use the **bang forms**. DB failures during normal operation must be loud, not silent — we do not wrap any of these in `try/rescue`.

### Test Call Sites

| File | Change |
|---|---|
| `test/inkwell/history_test.exs` | **deleted** — replaced by `test/inkwell/library/recent_file_test.exs` |
| `test/inkwell/search_test.exs:5,18` | `Inkwell.History.reset/push` → `Inkwell.Library.reset_recents!/push_recent!` |

### Untouched

- `Phoenix.PubSub` topics and broadcasts.
- `:persistent_term` theme cache.
- `:ets` `inkwell_git_repo_cache` title cache.
- `Inkwell.Settings` — theme still stored as `~/.inkwell/theme`, untouched.
- IPC files (`~/.inkwell/pid`, `~/.inkwell/port`, `~/.inkwell/secret`) — untouched.

## Error Handling

### Boot-Time (hard-fail)

```elixir
defmodule Inkwell.Release do
  @moduledoc false

  def migrate! do
    File.mkdir_p!(Inkwell.Settings.state_dir())

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Inkwell.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
      end)
  end
end
```

`Application.start/2` calls `migrate!/0` directly. No rescue, no fallback.

| Failure | Raised by | Result |
|---|---|---|
| `~/.inkwell/` not writable | `File.mkdir_p!/1` → `File.Error` | Daemon exits non-zero |
| Can't open DB file (perms, disk full) | `Ecto.Migrator.with_repo/2` → `DBConnection`/`Exqlite` error | Daemon exits non-zero |
| Migration SQL fails | `Ecto.Migrator.run/3` → `Ecto.MigrationError` | Daemon exits non-zero |
| DB corrupt | `Exqlite.Error` | Daemon exits non-zero |

**Recovery instructions** (documented in README under a new "Recovery" section): *If Inkwell won't start with a DB error, remove `~/.inkwell/inkwell.db` (and the `-wal` / `-shm` siblings if present) and retry.*

### Runtime (post-boot)

- `Inkwell.Library.push_recent!/1` raises → the calling LiveView / HTTP handler crashes → supervisor restarts → browser reconnects.
- `Inkwell.Library.list_recent_paths/0` raises → picker fails to render → LiveView crashes → same recovery path.
- If `Inkwell.Repo` itself crashes, the `:one_for_one` strategy restarts it. In-flight queries surface as `DBConnection.ConnectionError` to their callers — same recovery path.

### Deliberately Not Handled

- **Concurrent writer contention.** Single user, single daemon. SQLite's default locking is sufficient. No retry-on-`SQLITE_BUSY`.
- **Migration rollbacks.** Forward-only. We don't author `down/0` bodies beyond what `mix ash.codegen` generates for free.
- **Schema-ahead-of-code** (user downgrades the binary). Undefined behaviour. README warns against it; no code enforcement.
- **Backup / restore.** Out of scope.
- **Auto-move-aside on corruption.** Explicitly rejected during brainstorming. Users delete the DB file.

## Testing

### Isolation Strategy

`ecto_sqlite3` does not support `Ecto.Adapters.SQL.Sandbox` the way `postgrex` does. We use a **shared file-backed test DB** and clean records between tests rather than wrapping in transactions. Tests that touch the DB run with `async: false`.

### `test/test_helper.exs`

```elixir
db_path = Application.fetch_env!(:inkwell, Inkwell.Repo)[:database]

Enum.each([db_path, db_path <> "-wal", db_path <> "-shm"], &File.rm/1)

{:ok, _} = Inkwell.Repo.start_link()
Inkwell.Release.migrate!()

ExUnit.start()
```

### `test/support/data_case.ex`

```elixir
defmodule Inkwell.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Inkwell.DataCase
      alias Inkwell.Repo
    end
  end

  setup do
    Inkwell.Repo.delete_all(Inkwell.Library.RecentFile)
    :ok
  end
end
```

### Test Files

| File | Status | Coverage |
|---|---|---|
| `test/inkwell/history_test.exs` | deleted | — |
| `test/inkwell/library/recent_file_test.exs` | new | new row sets `open_count=1`; upsert refreshes `last_opened_at` and bumps `open_count`; `list_recent` sorts by `last_opened_at desc`; `list_recent` limits to 20; `reset_recents` clears all |
| `test/inkwell/release_test.exs` | new | `migrate!/0` creates DB + applies migrations from a clean slate; second call is idempotent; migration failure raises |
| `test/inkwell/search_test.exs` | updated | call-site migration at lines 5, 18 |

### Deliberately Skipped

- **Mocking the Repo.** Real file-based SQLite is fast enough; mocks hide the exact bugs we care about (schema / upsert semantics).
- **Property-based tests.** Upsert semantics are simple enough that enumerated cases suffice.
- **Automated Burrito-release boot test.** Documented as a manual smoke test instead.

### Manual Smoke Test (pre-merge)

1. `mix test` — green.
2. `rm -rf ~/.inkwell && ./burrito_out/inkwell_darwin_arm64 daemon` — verify DB created and migrations applied on first boot.
3. Open a file, stop daemon, start daemon, verify the file appears in the recents picker.
4. Corrupt the DB (`echo garbage > ~/.inkwell/inkwell.db`), restart daemon — verify hard-fail with a clear error message.

## Installation Steps (Igniter)

```bash
mix igniter.install ash ash_sqlite
```

Igniter handles: adding the deps to `mix.exs`, generating `Inkwell.Repo` with the AshSqlite adapter, registering `Inkwell.Repo` in `:ecto_repos`, adding `Inkwell.Repo` to the supervision tree, and scaffolding config. The generated code is then adjusted to:

- Move the `Inkwell.Repo` database path into `runtime.exs` (so it uses `~/.inkwell/inkwell.db` via `System.user_home!/0`).
- Gate `Inkwell.Repo` on daemon mode only in `Inkwell.Application`.
- Insert the `Inkwell.Release.migrate!()` call before the `children` list is built.

After Igniter finishes, the rest of the work (domain, resource, actions, call-site migration, tests) is authored by hand.

## Versioning & Changelog

Per `CLAUDE.md` memory: bump the patch version in `VERSION`, run `mix bump`, and add a `CHANGELOG.md` entry before opening the PR. Entry describes: "Persist recents across daemon restarts (Ash + SQLite foundation); `Inkwell.History` removed in favour of `Inkwell.Library`."
