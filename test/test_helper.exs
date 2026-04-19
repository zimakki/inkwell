Inkwell.GitRepo.init_cache()

# Nuke any leftover test DB from a prior run, start the Repo, migrate fresh.
db_path = Application.fetch_env!(:inkwell, Inkwell.Repo)[:database]

for file <- [db_path, db_path <> "-wal", db_path <> "-shm"], do: File.rm(file)

{:ok, _} = Inkwell.Repo.start_link()
Inkwell.Release.migrate!()

ExUnit.start()
