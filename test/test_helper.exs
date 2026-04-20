# The Repo is started by `Inkwell.Application` as part of the supervision
# tree, and migrations run during boot via `Inkwell.Release.migrate!/0`.
# Tests must NOT restart the Repo (use Inkwell.DataCase instead).
#
# To guarantee a fresh DB per test run we stop the app, nuke the DB files,
# and restart — which re-runs migrations on an empty file.
db_path = Application.fetch_env!(:inkwell, Inkwell.Repo)[:database]

Application.stop(:inkwell)

for file <- [db_path, db_path <> "-wal", db_path <> "-shm"], do: File.rm(file)

{:ok, _} = Application.ensure_all_started(:inkwell)

ExUnit.start()
