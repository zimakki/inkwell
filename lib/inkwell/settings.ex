defmodule Inkwell.Settings do
  @moduledoc """
  Persistent user preferences stored as plain files in `~/.inkwell/`.

  Currently just the theme. Designed to coexist with the existing IPC
  files (pid, port). When the next PR adds Ash + SQLite, richer prefs
  (favorites, recents-with-metadata, tags) move into the database;
  this module's small surface stays as the on-disk fallback for the
  handful of values that need to survive a daemon restart without
  taking a DB dep on the boot path.
  """

  @theme_file "theme"
  @valid_themes ~w(dark light)

  @doc "Returns the persisted theme as a string, or nil if none is set."
  def read_theme do
    path = Path.join(state_dir(), @theme_file)

    with {:ok, content} <- File.read(path),
         theme when theme in @valid_themes <- String.trim(content) do
      theme
    else
      _ -> nil
    end
  end

  @doc "Writes the theme to disk. Raises on invalid theme or filesystem failure."
  def write_theme(theme) when theme in @valid_themes do
    File.mkdir_p!(state_dir())
    File.write!(Path.join(state_dir(), @theme_file), theme)
  end

  @doc false
  def state_dir, do: Path.join(System.user_home!(), ".inkwell")
end
