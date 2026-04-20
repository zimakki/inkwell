# Ash + SQLite Persistence Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Ash + `ash_sqlite` as the persistence foundation for Inkwell. Replace the ephemeral `Inkwell.History` Agent with an Ash resource backed by SQLite at `~/.inkwell/inkwell.db`, with migrations running hard-fail on daemon boot. Recents persist across daemon restarts.

**Architecture:** `Inkwell.Library` Ash domain wraps a single `Inkwell.Library.RecentFile` resource (`AshSqlite.DataLayer`) with three actions: `list_recent` (sort + limit 20), `push_recent` (upsert: new row → `open_count=1`; existing → refresh `last_opened_at`, increment `open_count`), `reset_recents` (bulk destroy). Boot-time migrations run via `Ecto.Migrator.with_repo/2` before the supervision tree starts; any failure raises and kills the OTP app. The supervised `Inkwell.Repo` replaces `Inkwell.History` as a child, daemon-mode only.

**Tech Stack:** Elixir 1.19, Ash Framework, `ash_sqlite` (atop `ecto_sqlite3`), Igniter (install + codegen), ExUnit.

**Spec:** `docs/superpowers/specs/2026-04-19-ash-sqlite-persistence-design.md` (commit `adcd6d8`).

---

### Task 1: Install Ash + AshSqlite via Igniter

**Files:**
- Modify: `mix.exs` (deps)
- Modify: `config/config.exs` (`ash_domains`, `ecto_repos`)
- Create: `lib/inkwell/repo.ex`
- Modify: `lib/inkwell/application.ex` (Igniter will add `Inkwell.Repo` to the children list — we clean this up in Task 13)
- Modify: `mix.lock`

- [ ] **Step 1: Install the `igniter_new` archive** (idempotent — safe to re-run)

```bash
mix archive.install hex igniter_new --force
```

Expected: either "already installed" or successful install. This makes `mix igniter.install` available without polluting `mix.exs` with a bootstrapping dep.

- [ ] **Step 2: Run Igniter's installer for Ash + AshSqlite**

```bash
mix igniter.install ash ash_sqlite --yes
```

Expected output includes:
- `Add dep {:ash, "~> 3.x"}` (accepted)
- `Add dep {:ash_sqlite, "~> 0.x"}` (accepted)
- `Create lib/inkwell/repo.ex`
- `Update config/config.exs` — adds `config :inkwell, :ash_domains, []` and `config :inkwell, ecto_repos: [Inkwell.Repo]`
- `Update lib/inkwell/application.ex` — adds `Inkwell.Repo` to children

If Igniter asks interactive questions not auto-answered by `--yes`, accept defaults.

- [ ] **Step 3: Inspect the generated `lib/inkwell/repo.ex`**

It should look approximately like:

```elixir
defmodule Inkwell.Repo do
  use AshSqlite.Repo, otp_app: :inkwell

  def installed_extensions do
    []
  end
end
```

If the generated module uses `Ecto.Repo` directly instead of `AshSqlite.Repo`, replace the `use` line with `use AshSqlite.Repo, otp_app: :inkwell` — this is the Ash-idiomatic form that delegates to `Ecto.Repo` internally but sets Ash-friendly defaults.

- [ ] **Step 4: Inspect `mix.exs`** — confirm deps were added

`ash` and `ash_sqlite` should now appear in the `deps/0` list. Leave them where Igniter placed them.

- [ ] **Step 5: Inspect `config/config.exs`** — confirm Igniter's additions

Should contain (approximately):

```elixir
config :inkwell, :ash_domains, []
config :inkwell, ecto_repos: [Inkwell.Repo]
```

Both lines are needed. If only one is present, add the missing one.

- [ ] **Step 6: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile. Ignore deprecation warnings from transitive deps (Ash emits none at this stage).

- [ ] **Step 7: Commit**

```bash
git add mix.exs mix.lock config/config.exs lib/inkwell/repo.ex lib/inkwell/application.ex
git commit -m "chore: install ash + ash_sqlite via igniter

Scaffolds Inkwell.Repo (AshSqlite.Repo), registers :ash_domains and
:ecto_repos, and adds Repo to the supervision tree. Follow-up tasks
gate the Repo on daemon mode and wire boot-time migrations."
```

---

### Task 2: Configure Repo database paths for prod and test

**Files:**
- Modify: `config/runtime.exs` (prod DB path)
- Modify: `config/test.exs` (test DB path)

The default `config/dev.exs` database path that Igniter generates is fine for `mix phx.server` development (unused by Inkwell but won't hurt). We override only prod (runtime.exs) and test.

- [ ] **Step 1: Check current `config/runtime.exs`**

```bash
cat config/runtime.exs
```

- [ ] **Step 2: Add the prod Repo config to `config/runtime.exs`**

Inside the `if config_env() == :prod do` block (or create one at the bottom of the file if it doesn't exist), add:

```elixir
if config_env() == :prod do
  inkwell_home = Path.join(System.user_home!(), ".inkwell")
  File.mkdir_p!(inkwell_home)

  config :inkwell, Inkwell.Repo,
    database: Path.join(inkwell_home, "inkwell.db"),
    pool_size: 5,
    journal_mode: :wal
end
```

This resolves `~/.inkwell/inkwell.db` at runtime (release boot), not compile time — critical for Burrito releases where `System.user_home!/0` returns the user's home directory, not the build machine's.

- [ ] **Step 3: Add the test Repo config to `config/test.exs`**

Append:

```elixir
config :inkwell, Inkwell.Repo,
  database: Path.join(System.tmp_dir!(), "inkwell_test.db"),
  pool_size: 5,
  journal_mode: :wal
```

Single shared DB file, cleared between tests by `Inkwell.DataCase` (Task 6).

- [ ] **Step 4: Add a minimal `config/dev.exs` stub if missing**

If Igniter didn't create one, add:

```elixir
import Config

config :inkwell, Inkwell.Repo,
  database: Path.expand("../inkwell_dev.db", __DIR__),
  pool_size: 5
```

This prevents runtime errors if someone runs `iex -S mix` in dev. The dev DB lives at the project root.

- [ ] **Step 5: Add `inkwell_dev.db*` and `inkwell_test.db*` to `.gitignore`**

Append to `.gitignore`:

```
# SQLite databases
/inkwell_dev.db
/inkwell_dev.db-*
```

(Test DB lives in `System.tmp_dir!()` — no gitignore needed.)

- [ ] **Step 6: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add config/runtime.exs config/test.exs config/dev.exs .gitignore
git commit -m "chore: configure Inkwell.Repo database paths

Prod DB at ~/.inkwell/inkwell.db (resolved at runtime for Burrito
releases). Test DB in System.tmp_dir!() for isolation."
```

---

### Task 3: Create the `Inkwell.Library` Ash domain

**Files:**
- Create: `lib/inkwell/library.ex`
- Modify: `config/config.exs` (register domain)

- [ ] **Step 1: Create `lib/inkwell/library.ex`**

```elixir
defmodule Inkwell.Library do
  @moduledoc """
  Ash domain owning persistent reader-history primitives.

  For now: `Inkwell.Library.RecentFile` — recently opened markdown files.
  Future PRs will add favorites and tags to this domain.
  """

  use Ash.Domain

  resources do
    resource Inkwell.Library.RecentFile
  end
end
```

The `resources do ... end` block is intentionally minimal — code interfaces are added in later tasks as each action is implemented.

- [ ] **Step 2: Register the domain in `config/config.exs`**

Replace the line Igniter added:

```elixir
config :inkwell, :ash_domains, []
```

with:

```elixir
config :inkwell, :ash_domains, [Inkwell.Library]
```

- [ ] **Step 3: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile. (Ash will likely warn about the domain having no resources yet if `Inkwell.Library.RecentFile` isn't referenced — if so, continue; the resource module arrives in Task 4.)

- [ ] **Step 4: Commit**

```bash
git add lib/inkwell/library.ex config/config.exs
git commit -m "feat: add Inkwell.Library Ash domain

Empty domain registered in :ash_domains. Resources and code
interfaces arrive in subsequent tasks."
```

---

### Task 4: Create `Inkwell.Library.RecentFile` resource (attributes + identity)

**Files:**
- Create: `lib/inkwell/library/recent_file.ex`

Actions will be added in Tasks 7-10 via TDD. This task sets up the schema shape so migration generation in Task 5 has something to snapshot.

- [ ] **Step 1: Create `lib/inkwell/library/recent_file.ex`**

```elixir
defmodule Inkwell.Library.RecentFile do
  @moduledoc """
  Ash resource tracking recently opened markdown files.

  Replaces `Inkwell.History` (ephemeral Agent). Recents persist across
  daemon restarts. Schema owns `path` (unique), `last_opened_at`, and
  `open_count`. Actions are defined in sibling tasks.
  """

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
  end
end
```

`defaults [:read]` gives us a generic `:read` action so the resource compiles. Named actions are added in later tasks.

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add lib/inkwell/library/recent_file.ex
git commit -m "feat: add Inkwell.Library.RecentFile resource (schema only)

Attributes: id (uuid), path (unique), last_opened_at, open_count.
Identity :unique_path on the path column. Actions added in follow-up
tasks."
```

---

### Task 5: Generate the initial migration

**Files:**
- Create: `priv/repo/migrations/<timestamp>_initialize_recent_files.exs` (generated)
- Create: `priv/resource_snapshots/...` (generated)

- [ ] **Step 1: Run `mix ash.codegen`**

```bash
mix ash.codegen initialize_recent_files --yes
```

Expected output:
- "Generating migrations..."
- Creates `priv/repo/migrations/<YYYYMMDDHHMMSS>_initialize_recent_files.exs`
- Creates `priv/resource_snapshots/repo/recent_files/<YYYYMMDDHHMMSS>.json`

If the `--yes` flag doesn't skip all prompts, accept defaults interactively.

- [ ] **Step 2: Inspect the generated migration**

```bash
ls priv/repo/migrations/
cat priv/repo/migrations/*_initialize_recent_files.exs
```

Expected contents (approximately):

```elixir
defmodule Inkwell.Repo.Migrations.InitializeRecentFiles do
  use Ecto.Migration

  def up do
    create table(:recent_files, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :path, :text, null: false
      add :last_opened_at, :utc_datetime_usec, null: false
      add :open_count, :bigint, null: false, default: 0
    end

    create unique_index(:recent_files, [:path], name: "recent_files_unique_path_index")
  end

  def down do
    drop_if_exists unique_index(:recent_files, [:path], name: "recent_files_unique_path_index")
    drop table(:recent_files)
  end
end
```

If the `:id` column type is `:binary_id` / `:uuid` discrepancy causes issues in SQLite (which has no native UUID), `ash_sqlite` stores UUIDs as text — that's the intended behavior. Leave the migration as generated.

- [ ] **Step 3: Run the migration to verify it applies cleanly against a dev DB**

```bash
mix ecto.create
mix ecto.migrate
```

Expected: "The database for Inkwell.Repo has been created." then "Running Inkwell.Repo.Migrations.InitializeRecentFiles.up/0 forwards".

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations priv/resource_snapshots
git commit -m "feat: generate initial migration for recent_files table

Generated via mix ash.codegen. Creates the recent_files table with
a unique index on path."
```

---

### Task 6: Create `Inkwell.Release.migrate!/0`, test support, and test helper

**Files:**
- Create: `lib/inkwell/release.ex`
- Create: `test/support/data_case.ex`
- Modify: `mix.exs` (add `test/support` to `elixirc_paths(:test)`)
- Modify: `test/test_helper.exs`

This task sets up the plumbing that Tasks 7-11 depend on: a migration function we can call programmatically, a test case template that resets DB state between tests, and a test helper that starts the Repo before tests run.

- [ ] **Step 1: Create `lib/inkwell/release.ex`**

```elixir
defmodule Inkwell.Release do
  @moduledoc """
  Runtime hooks for the release. Owns boot-time database migration.

  Called from `Inkwell.Application.start/2` in daemon mode before the
  supervision tree is built. Any failure raises and kills the OTP
  application start — this is the hard-fail policy (see spec).
  """

  @doc """
  Ensure the state directory exists, then run all pending migrations.

  Raises on any failure: missing directory perms, unable to open DB,
  migration SQL errors, corruption.
  """
  def migrate! do
    File.mkdir_p!(Inkwell.Settings.state_dir())

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Inkwell.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
      end)

    :ok
  end
end
```

`Ecto.Migrator.with_repo/2` spawns a temporary Repo instance, runs the function, and stops the Repo — so `migrate!/0` doesn't leave a Repo running. The supervised `Inkwell.Repo` starts fresh afterward.

- [ ] **Step 2: Verify `test/support/` exists and is compiled for the test env**

```bash
grep -n "elixirc_paths" mix.exs
```

Should show:

```elixir
defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

If `test/support` is not listed, add it as shown above.

- [ ] **Step 3: Create `test/support/data_case.ex`**

```elixir
defmodule Inkwell.DataCase do
  @moduledoc """
  ExUnit case template for tests that hit the Repo.

  SQLite doesn't support the Ecto sandbox the way Postgres does, so we
  use a shared file-backed test DB and delete all RecentFile rows in
  `setup`. Tests that `use Inkwell.DataCase` must run with `async: false`.
  """

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

- [ ] **Step 4: Update `test/test_helper.exs`**

Replace its contents with:

```elixir
# Nuke any leftover test DB from a prior run, start the Repo, migrate fresh.
db_path = Application.fetch_env!(:inkwell, Inkwell.Repo)[:database]

for file <- [db_path, db_path <> "-wal", db_path <> "-shm"], do: File.rm(file)

{:ok, _} = Inkwell.Repo.start_link()
Inkwell.Release.migrate!()

ExUnit.start()
```

- [ ] **Step 5: Run the existing test suite to confirm the plumbing works**

```bash
mix test
```

Expected: all existing tests still pass. (Tests that don't use `Inkwell.DataCase` aren't affected; the Repo is simply running in the background.) If any test fails because the Repo config is missing, check Task 2 was completed.

- [ ] **Step 6: Commit**

```bash
git add lib/inkwell/release.ex test/support/data_case.ex test/test_helper.exs mix.exs
git commit -m "feat: add Inkwell.Release.migrate! + test data case

Release.migrate!/0 wraps Ecto.Migrator.with_repo for boot-time and
test-time migration. Inkwell.DataCase resets RecentFile rows between
tests. test_helper starts the Repo and migrates before ExUnit runs."
```

---

### Task 7: TDD the `list_recent` action

**Files:**
- Create: `test/inkwell/library/recent_file_test.exs`
- Modify: `lib/inkwell/library/recent_file.ex` (add action)
- Modify: `lib/inkwell/library.ex` (add code interface)

- [ ] **Step 1: Write the failing test for `list_recent` returning an empty list**

Create `test/inkwell/library/recent_file_test.exs`:

```elixir
defmodule Inkwell.Library.RecentFileTest do
  use Inkwell.DataCase, async: false

  alias Inkwell.Library

  describe "list_recent/0" do
    test "returns an empty list when no recents exist" do
      assert Library.list_recent!() == []
    end
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: FAIL with something like `undefined function list_recent!/0`.

- [ ] **Step 3: Add the action to the resource**

In `lib/inkwell/library/recent_file.ex`, replace the `actions do ... end` block with:

```elixir
actions do
  defaults [:read]

  read :list_recent do
    prepare build(sort: [last_opened_at: :desc], limit: 20)
  end
end
```

- [ ] **Step 4: Expose the action via the domain's code interface**

In `lib/inkwell/library.ex`, replace the `resources do ... end` block with:

```elixir
resources do
  resource Inkwell.Library.RecentFile do
    define :list_recent, action: :list_recent
  end
end
```

- [ ] **Step 5: Run the test — it should pass**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: PASS.

- [ ] **Step 6: Add a second test covering sort order**

Append to `describe "list_recent/0"` in the test file:

```elixir
test "returns entries sorted by last_opened_at descending" do
  now = DateTime.utc_now()

  {:ok, _} =
    Inkwell.Library.RecentFile
    |> Ash.Changeset.for_create(:create, %{
      path: "/tmp/a.md",
      last_opened_at: DateTime.add(now, -60, :second),
      open_count: 1
    })
    |> Ash.create()

  {:ok, _} =
    Inkwell.Library.RecentFile
    |> Ash.Changeset.for_create(:create, %{
      path: "/tmp/b.md",
      last_opened_at: now,
      open_count: 1
    })
    |> Ash.create()

  paths = Library.list_recent!() |> Enum.map(& &1.path)
  assert paths == ["/tmp/b.md", "/tmp/a.md"]
end
```

This uses the default `:create` action (from `defaults [:read]` → we need `:create` too).

- [ ] **Step 7: Add `:create` to the resource's default actions**

In `lib/inkwell/library/recent_file.ex`, change:

```elixir
defaults [:read]
```

to:

```elixir
defaults [:create, :read]
```

- [ ] **Step 8: Run the tests**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: PASS for both tests.

- [ ] **Step 9: Commit**

```bash
git add test/inkwell/library/recent_file_test.exs lib/inkwell/library/recent_file.ex lib/inkwell/library.ex
git commit -m "feat: add list_recent action + code interface

Sorted by last_opened_at desc, capped at 20. Default :create action
enabled so tests can seed fixtures directly."
```

---

### Task 8: TDD the `push_recent` action (new-row branch)

**Files:**
- Modify: `test/inkwell/library/recent_file_test.exs`
- Modify: `lib/inkwell/library/recent_file.ex`
- Modify: `lib/inkwell/library.ex`

This task covers the first half of `push_recent`'s behavior: inserting a brand-new recent file sets `open_count = 1` and `last_opened_at` to the current time. Task 9 covers the upsert branch.

- [ ] **Step 1: Write the failing test**

Append to the test file:

```elixir
describe "push_recent/1" do
  test "inserts a new recent with open_count = 1 and fresh last_opened_at" do
    before = DateTime.utc_now()
    {:ok, recent} = Library.push_recent("/tmp/new.md")
    after_ = DateTime.utc_now()

    assert recent.path == "/tmp/new.md"
    assert recent.open_count == 1
    assert DateTime.compare(recent.last_opened_at, before) in [:gt, :eq]
    assert DateTime.compare(recent.last_opened_at, after_) in [:lt, :eq]
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: FAIL with `undefined function push_recent/1`.

- [ ] **Step 3: Add the `push_recent` action to the resource**

In the `actions do ... end` block of `lib/inkwell/library/recent_file.ex`, append:

```elixir
create :push_recent do
  accept [:path]
  upsert? true
  upsert_identity :unique_path
  upsert_fields [:last_opened_at, :open_count]

  change set_attribute(:last_opened_at, &DateTime.utc_now/0)
  change set_attribute(:open_count, 1)
end
```

For this task we start with `set_attribute(:open_count, 1)` on every call. Task 9 adds the "bump on upsert" branch — at that point this changes to a conditional.

- [ ] **Step 4: Expose via the domain's code interface**

In `lib/inkwell/library.ex`, extend the resource block:

```elixir
resource Inkwell.Library.RecentFile do
  define :list_recent, action: :list_recent
  define :push_recent, action: :push_recent, args: [:path]
end
```

- [ ] **Step 5: Run the test — it should pass**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add test/inkwell/library/recent_file_test.exs lib/inkwell/library/recent_file.ex lib/inkwell/library.ex
git commit -m "feat: add push_recent action (new-row branch)

Creates a RecentFile with open_count=1 and last_opened_at=now.
Upsert semantics for the existing-row branch follow in the next
task."
```

---

### Task 9: TDD the upsert branch of `push_recent`

**Files:**
- Modify: `test/inkwell/library/recent_file_test.exs`
- Modify: `lib/inkwell/library/recent_file.ex`

The tricky part flagged in the spec's implementation risks. We're verifying that calling `push_recent(path)` for an existing path refreshes `last_opened_at` and increments `open_count`.

- [ ] **Step 1: Write the failing upsert test**

Append to the `describe "push_recent/1"` block:

```elixir
test "refreshes last_opened_at and increments open_count on existing path" do
  {:ok, first} = Library.push_recent("/tmp/repeat.md")
  assert first.open_count == 1

  # Small sleep to make the timestamp comparison meaningful.
  Process.sleep(2)

  {:ok, second} = Library.push_recent("/tmp/repeat.md")
  assert second.id == first.id
  assert second.open_count == 2
  assert DateTime.compare(second.last_opened_at, first.last_opened_at) == :gt
end

test "three pushes of the same path produce open_count = 3" do
  {:ok, _} = Library.push_recent("/tmp/three.md")
  {:ok, _} = Library.push_recent("/tmp/three.md")
  {:ok, third} = Library.push_recent("/tmp/three.md")
  assert third.open_count == 3
end
```

- [ ] **Step 2: Run the tests to see them fail**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: both new tests FAIL — `open_count` stays at 1 because the current `push_recent` unconditionally sets it to 1.

- [ ] **Step 3: Replace the `push_recent` action with the upsert-aware version**

In `lib/inkwell/library/recent_file.ex`, replace the existing `create :push_recent do ... end` block with:

```elixir
create :push_recent do
  accept [:path]
  upsert? true
  upsert_identity :unique_path
  upsert_fields [:last_opened_at, :open_count]

  change set_attribute(:last_opened_at, &DateTime.utc_now/0)

  change fn changeset, _context ->
    if changeset.context[:private][:upsert?] do
      Ash.Changeset.atomic_update(changeset, :open_count, Ash.Expr.expr(open_count + 1))
    else
      Ash.Changeset.change_attribute(changeset, :open_count, 1)
    end
  end
end
```

- [ ] **Step 4: Run the tests**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: PASS for all tests.

**If the tests still fail** (the inline change may not see `context[:private][:upsert?]` — Ash internals vary by version), fall back to a dedicated `Ash.Resource.Change` module. Replace the inline `change fn ...` with:

```elixir
change {Inkwell.Library.Changes.BumpOrSetOpenCount, []}
```

and create `lib/inkwell/library/changes/bump_or_set_open_count.ex`:

```elixir
defmodule Inkwell.Library.Changes.BumpOrSetOpenCount do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if upsert?(changeset) do
      Ash.Changeset.atomic_update(changeset, :open_count, Ash.Expr.expr(open_count + 1))
    else
      Ash.Changeset.change_attribute(changeset, :open_count, 1)
    end
  end

  defp upsert?(changeset) do
    # Ash exposes the upsert flag on the changeset itself (not context)
    # in recent versions.
    Map.get(changeset, :upsert?, false) == true
  end
end
```

Re-run the tests after the fallback.

**If neither approach works** — this is the spec's flagged implementation risk materializing. The last-resort fallback is to split `push_recent` into a two-step domain function:

```elixir
# In lib/inkwell/library.ex
def push_recent(path) do
  now = DateTime.utc_now()

  case Ash.get(Inkwell.Library.RecentFile, %{path: path}) do
    {:ok, existing} ->
      existing
      |> Ash.Changeset.for_update(:bump_recent, %{last_opened_at: now})
      |> Ash.update()

    {:error, %Ash.Error.Query.NotFound{}} ->
      Inkwell.Library.RecentFile
      |> Ash.Changeset.for_create(:create, %{path: path, last_opened_at: now, open_count: 1})
      |> Ash.create()
  end
end
```

This loses atomicity for the increment (TOCTOU between `get` and `update`) but single-writer daemon means no real concurrency, and it's guaranteed to work. Add a separate `update :bump_recent` action to the resource.

- [ ] **Step 5: Commit**

```bash
git add test/inkwell/library/recent_file_test.exs lib/inkwell/library/recent_file.ex
# If fallback used:
# git add lib/inkwell/library/changes/bump_or_set_open_count.ex
git commit -m "feat: push_recent upserts — bump open_count, refresh timestamp

Existing rows get last_opened_at bumped to now and open_count
incremented atomically. New rows start at open_count=1."
```

---

### Task 10: TDD the `list_recent` cap of 20

**Files:**
- Modify: `test/inkwell/library/recent_file_test.exs`

The `list_recent` action was implemented with `limit: 20` in Task 7. This task adds explicit test coverage for the cap.

- [ ] **Step 1: Add the cap test**

In the `describe "list_recent/0"` block of the test file, append:

```elixir
test "caps at 20 entries, dropping the oldest" do
  now = DateTime.utc_now()

  for i <- 1..25 do
    {:ok, _} =
      Inkwell.Library.RecentFile
      |> Ash.Changeset.for_create(:create, %{
        path: "/tmp/f#{i}.md",
        last_opened_at: DateTime.add(now, -i, :second),
        open_count: 1
      })
      |> Ash.create()
  end

  recents = Library.list_recent!()
  assert length(recents) == 20

  paths = Enum.map(recents, & &1.path)
  # Most recent (i=1 → -1s ago) is first.
  assert List.first(paths) == "/tmp/f1.md"
  # 20th most recent is /tmp/f20.md; /tmp/f21..f25 should be dropped.
  assert List.last(paths) == "/tmp/f20.md"
  refute "/tmp/f25.md" in paths
end
```

- [ ] **Step 2: Run the test**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/inkwell/library/recent_file_test.exs
git commit -m "test: cover list_recent's cap of 20"
```

---

### Task 11: TDD the `reset_recents` action

**Files:**
- Modify: `test/inkwell/library/recent_file_test.exs`
- Modify: `lib/inkwell/library/recent_file.ex`
- Modify: `lib/inkwell/library.ex`

- [ ] **Step 1: Write the failing test**

Append to the test file:

```elixir
describe "reset_recents/0" do
  test "deletes all recent files" do
    {:ok, _} = Library.push_recent("/tmp/x.md")
    {:ok, _} = Library.push_recent("/tmp/y.md")
    assert length(Library.list_recent!()) == 2

    :ok = Library.reset_recents()
    assert Library.list_recent!() == []
  end

  test "is idempotent when already empty" do
    assert :ok = Library.reset_recents()
    assert :ok = Library.reset_recents()
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: FAIL with `undefined function reset_recents/0`.

- [ ] **Step 3: Add a domain-level `reset_recents/0`**

Ash's bulk-destroy syntax varies by version. The cleanest cross-version approach is a plain function on the domain that calls `Ash.bulk_destroy!/3`. In `lib/inkwell/library.ex`, append inside the module (after the `resources do` block):

```elixir
def reset_recents do
  Inkwell.Library.RecentFile
  |> Ash.read!()
  |> Ash.bulk_destroy!(:destroy, %{}, return_errors?: true)

  :ok
end
```

This uses the default `:destroy` action that ships with Ash resources (enabled via `defaults`). Ensure `:destroy` is in the defaults list.

- [ ] **Step 4: Add `:destroy` to the resource defaults**

In `lib/inkwell/library/recent_file.ex`, change:

```elixir
defaults [:create, :read]
```

to:

```elixir
defaults [:create, :read, :destroy]
```

- [ ] **Step 5: Run the tests**

```bash
mix test test/inkwell/library/recent_file_test.exs
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add test/inkwell/library/recent_file_test.exs lib/inkwell/library/recent_file.ex lib/inkwell/library.ex
git commit -m "feat: add reset_recents/0 domain function

Bulk-destroys all RecentFile rows. Used by tests and (future)
clear-history UI."
```

---

### Task 12: TDD `Inkwell.Release.migrate!/0` idempotency and integration

**Files:**
- Create: `test/inkwell/release_test.exs`

The test_helper already calls `migrate!/0` once. This test exercises it explicitly to verify idempotency (second call is a no-op) and that it returns `:ok` on success.

- [ ] **Step 1: Write the test**

```elixir
defmodule Inkwell.ReleaseTest do
  use ExUnit.Case, async: false

  test "migrate!/0 returns :ok when migrations are already applied" do
    # test_helper.exs already called migrate!/0 once on startup.
    # A second call should be a no-op and return :ok.
    assert :ok = Inkwell.Release.migrate!()
  end

  test "migrate!/0 creates the state directory if missing" do
    # We can't actually remove ~/.inkwell from a test — instead, verify
    # the function references Inkwell.Settings.state_dir and that dir exists.
    assert File.exists?(Inkwell.Settings.state_dir())
  end
end
```

- [ ] **Step 2: Run the test**

```bash
mix test test/inkwell/release_test.exs
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/inkwell/release_test.exs
git commit -m "test: cover Inkwell.Release.migrate! idempotency"
```

---

### Task 13: Wire boot-time migrations into `Inkwell.Application.start/2`

**Files:**
- Modify: `lib/inkwell/application.ex`

Igniter in Task 1 added `Inkwell.Repo` to the children list unconditionally. We need to (a) gate it on daemon mode and (b) call `Inkwell.Release.migrate!()` before the tree starts.

- [ ] **Step 1: Read the current state of `lib/inkwell/application.ex`**

```bash
cat lib/inkwell/application.ex
```

Igniter likely inserted `Inkwell.Repo` somewhere in the children list (possibly at the top of the daemon `case` branch, possibly in a shared list).

- [ ] **Step 2: Modify the daemon branch of `start/2`**

Locate the `:daemon ->` branch of the `case mode do` in `start/2`. Replace the entire branch with:

```elixir
:daemon ->
  theme = resolve_theme(parsed[:theme])
  :persistent_term.put(:inkwell_theme, theme)
  if parsed[:theme], do: Inkwell.Settings.write_theme(theme)

  Inkwell.Release.migrate!()
  Inkwell.GitRepo.init_cache()

  [
    {Phoenix.PubSub, name: Inkwell.PubSub},
    {Registry, keys: :unique, name: Inkwell.WatcherRegistry},
    Inkwell.Repo,
    {Inkwell.Daemon, []},
    {DynamicSupervisor, strategy: :one_for_one, name: Inkwell.WatcherSupervisor},
    InkwellWeb.Telemetry,
    InkwellWeb.Endpoint
  ]
```

Key changes from the existing code:
- `Inkwell.Release.migrate!()` runs **before** `children` is built — any migration failure raises here.
- `{Inkwell.History, []}` is **removed** (History deletion happens in Task 16; leaving it here for this task is harmless, but if it's gone, remove it).
- `Inkwell.Repo` takes History's slot in the tree.
- **Not** in `:client ->` branch — client mode never touches the DB.

- [ ] **Step 3: Remove any Igniter-added `Inkwell.Repo` from the wrong place**

Scan the file for stray `Inkwell.Repo` references outside the daemon branch. If Igniter added it to a shared children list, remove it from there.

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile. (Unused alias / module warnings may appear for `Inkwell.History` if it's still present — that's expected; deletion is in Task 16.)

- [ ] **Step 5: Start the app in dev mode to verify it boots**

```bash
mix run --no-halt -e "IO.puts(\"started\")" 2>&1 | head -5
```

Expected: output includes `started` with no crashes. If `Inkwell.Release.migrate!/0` fails here because the dev DB isn't set up, run `mix ecto.create && mix ecto.migrate` first.

- [ ] **Step 6: Commit**

```bash
git add lib/inkwell/application.ex
git commit -m "feat: wire boot-time migrations + Repo into daemon supervision

Inkwell.Release.migrate!/0 runs synchronously before the supervision
tree is built. Repo is gated on daemon mode only; client-mode CLI
commands never touch the DB."
```

---

### Task 14: Migrate production call sites to `Inkwell.Library`

**Files:**
- Modify: `lib/inkwell/library.ex` (add `list_recent_paths/0` helper)
- Modify: `lib/inkwell/search.ex` (3 call sites)
- Modify: `lib/inkwell.ex` (1 call site)
- Modify: `lib/inkwell_web/live/file_live.ex` (1 call site)

- [ ] **Step 1: Add `list_recent_paths/0` helper to the domain**

In `lib/inkwell/library.ex`, append after `reset_recents/0`:

```elixir
@doc """
Convenience: returns just the paths of recent files, in the same
order as `list_recent/0`. Used by the picker where only the path
string is needed.
"""
def list_recent_paths do
  list_recent!() |> Enum.map(& &1.path)
end
```

- [ ] **Step 2: Update `lib/inkwell/search.ex` — three occurrences of `Inkwell.History.list()`**

Replace all three occurrences (lines 63, 99, 257) of:

```elixir
Inkwell.History.list()
```

with:

```elixir
Inkwell.Library.list_recent_paths()
```

Use `grep -n "Inkwell.History.list" lib/inkwell/search.ex` to find and verify each before editing.

- [ ] **Step 3: Update `lib/inkwell.ex:19`**

Replace:

```elixir
Inkwell.History.push(path)
```

with:

```elixir
Inkwell.Library.push_recent!(path)
```

Note the bang — DB failures during `open_file/2` must crash, not silently succeed.

- [ ] **Step 4: Update `lib/inkwell_web/live/file_live.ex:13`**

Replace:

```elixir
Inkwell.History.push(resolved)
```

with:

```elixir
Inkwell.Library.push_recent!(resolved)
```

- [ ] **Step 5: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile. A warning about `Inkwell.History` being unused is expected — the module itself is deleted in Task 16.

- [ ] **Step 6: Commit**

```bash
git add lib/inkwell/library.ex lib/inkwell/search.ex lib/inkwell.ex lib/inkwell_web/live/file_live.ex
git commit -m "feat: migrate production call sites to Inkwell.Library

All reads of recent files go through Library.list_recent_paths/0.
All writes go through Library.push_recent!/1. Inkwell.History
itself is removed in a follow-up commit."
```

---

### Task 15: Migrate test call sites and delete the old History tests

**Files:**
- Modify: `test/inkwell/search_test.exs` (lines 5, 18)
- Delete: `test/inkwell/history_test.exs`

- [ ] **Step 1: Update `test/inkwell/search_test.exs` line 5**

Replace:

```elixir
Inkwell.History.reset()
```

with:

```elixir
Inkwell.Library.reset_recents()
```

Also ensure the test module `use`s `Inkwell.DataCase` if it touches the DB now. Check the top of the file — if it currently uses `ExUnit.Case`, change to:

```elixir
use Inkwell.DataCase, async: false
```

Otherwise, if the test isolation was relying on `Inkwell.History.reset/0` only, the `Inkwell.DataCase` `setup` hook already clears rows between tests — the explicit `reset_recents()` call becomes redundant and can be removed. Prefer removing it for clarity.

- [ ] **Step 2: Update `test/inkwell/search_test.exs` line 18**

Replace:

```elixir
Inkwell.History.push(current)
```

with:

```elixir
Inkwell.Library.push_recent!(current)
```

- [ ] **Step 3: Delete the old History test file**

```bash
git rm test/inkwell/history_test.exs
```

- [ ] **Step 4: Run the full test suite**

```bash
mix test
```

Expected: all tests PASS. The deleted `history_test.exs` was replaced by `test/inkwell/library/recent_file_test.exs` which provides equivalent coverage against the new Ash resource.

- [ ] **Step 5: Commit**

```bash
git add test/inkwell/search_test.exs
git commit -m "test: migrate search_test and drop history_test

history_test.exs replaced by library/recent_file_test.exs. search_test
now uses Inkwell.DataCase for DB isolation."
```

---

### Task 16: Delete the `Inkwell.History` module

**Files:**
- Delete: `lib/inkwell/history.ex`

All call sites were migrated in Tasks 14-15. Now the module itself can go.

- [ ] **Step 1: Verify no remaining references**

```bash
grep -rn "Inkwell.History" lib/ test/ config/
```

Expected: zero results.

- [ ] **Step 2: Delete the module**

```bash
git rm lib/inkwell/history.ex
```

- [ ] **Step 3: Compile with warnings-as-errors**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile.

- [ ] **Step 4: Run the full test suite**

```bash
mix test
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: remove Inkwell.History

All call sites migrated to Inkwell.Library in prior commits.
Recents now persist across daemon restarts via SQLite."
```

---

### Task 17: Version bump, CHANGELOG, precommit, manual smoke test

**Files:**
- Modify: `VERSION`
- Modify: `mix.exs` (via `mix bump`)
- Modify: `src-tauri/Cargo.toml` (via `mix bump`)
- Modify: `src-tauri/tauri.conf.json` (via `mix bump`)
- Modify: `src-tauri/Cargo.lock` (via `mix bump`)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump the patch version in `VERSION`**

```bash
cat VERSION
```

If the current version is `0.3.1`, update to `0.3.2`:

```bash
echo "0.3.2" > VERSION
```

(Or the next appropriate patch version — bump the last component by 1.)

- [ ] **Step 2: Propagate the version via `mix bump`**

```bash
mix bump
```

Expected: `mix.exs`, `src-tauri/Cargo.toml`, `src-tauri/tauri.conf.json`, and `src-tauri/Cargo.lock` all updated.

- [ ] **Step 3: Add a CHANGELOG entry**

Open `CHANGELOG.md` and add a new section at the top (below the top-level header):

```markdown
## 0.3.2 — 2026-04-19

### Added

- Recently opened files now persist across daemon restarts. Backed by SQLite
  at `~/.inkwell/inkwell.db` via a new `Inkwell.Library` Ash domain.

### Changed

- `Inkwell.History` (ephemeral Agent) removed; callers migrated to
  `Inkwell.Library.list_recent_paths/0` and `Inkwell.Library.push_recent!/1`.
- Daemon now runs pending migrations on boot. If migration fails, the
  daemon refuses to start. Recovery: remove `~/.inkwell/inkwell.db` and
  restart.
```

(Use the exact version from Step 1.)

- [ ] **Step 4: Run the full precommit suite**

```bash
mix precommit
```

This runs `format --check-formatted`, `deps.unlock --check-unused`, `compile --warnings-as-errors`, `credo --strict`, and `test`. All must pass.

If `mix format` flags files, run:

```bash
mix format
```

and re-run `mix precommit`. Commit the format changes separately if needed.

- [ ] **Step 5: Build a release and run the manual smoke test**

```bash
mix release
```

Expected: `burrito_out/inkwell_darwin_arm64` (and peers) exist.

Run the four-step manual smoke test from the spec:

1. **`mix test` — green.**
   Already done in Step 4.

2. **Fresh-boot DB creation:**
   ```bash
   rm -rf ~/.inkwell && ./burrito_out/inkwell_darwin_arm64 daemon
   ```
   Expected: daemon starts, `~/.inkwell/inkwell.db` appears. `ls ~/.inkwell/` shows `inkwell.db`, `pid`, `port`, `secret`.
   Stop it with `./burrito_out/inkwell_darwin_arm64 stop`.

3. **Persistence across restarts:**
   ```bash
   ./burrito_out/inkwell_darwin_arm64 /path/to/some/file.md
   # Open the preview URL, confirm it renders. Stop:
   ./burrito_out/inkwell_darwin_arm64 stop
   # Restart:
   ./burrito_out/inkwell_darwin_arm64 daemon
   # Open http://localhost:<port>/ — the file should appear in the picker's Recents section.
   ./burrito_out/inkwell_darwin_arm64 stop
   ```

4. **Corruption hard-fail:**
   ```bash
   echo "this is not a valid sqlite database" > ~/.inkwell/inkwell.db
   ./burrito_out/inkwell_darwin_arm64 daemon
   ```
   Expected: daemon fails to start with a clear `Exqlite`-flavored error mentioning the corrupt DB. Non-zero exit.

   Clean up:
   ```bash
   rm ~/.inkwell/inkwell.db ~/.inkwell/inkwell.db-wal ~/.inkwell/inkwell.db-shm 2>/dev/null
   ```

- [ ] **Step 6: Commit**

```bash
git add VERSION mix.exs src-tauri/Cargo.toml src-tauri/tauri.conf.json src-tauri/Cargo.lock CHANGELOG.md
git commit -m "chore: bump version for Ash + SQLite persistence

Bumps the patch version and adds a CHANGELOG entry documenting the
new Ash-backed recents-with-metadata persistence layer."
```

- [ ] **Step 7: Open the PR**

Follow the project's standard PR flow. PR body should describe:
- What: "Foundation PR adding Ash + SQLite as Inkwell's persistence layer. Recents now persist across daemon restarts. Foundation only — favorites and tags are deferred to follow-up PRs."
- Why: reference the `Inkwell.Settings` docstring that explicitly foreshadowed this step.
- Testing: link the new tests; describe the manual smoke test performed.

No "Generated with Claude Code" / AI attribution footer (per global instructions).

---

## Appendix: Known Unknowns

Two areas where the exact Ash API may differ slightly from what this plan uses. Both are flagged in the spec's implementation risks. If encountered during implementation:

1. **Upsert conflict detection in `push_recent`** — Task 9 has a fallback path. If the inline `change fn ...` can't detect upsert context, use the dedicated `Ash.Resource.Change` module form. Last-resort fallback: two-step find-or-create in a domain function.

2. **Bulk destroy for `reset_recents`** — Task 11 uses a domain-level function calling `Ash.bulk_destroy!/3`. If the return shape differs by Ash version, adjust the function's return value to always yield `:ok` on success.

Neither risk blocks the plan — both have deterministic fallbacks that work without new dependencies.
