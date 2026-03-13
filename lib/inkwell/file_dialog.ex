defmodule Inkwell.FileDialog do
  @moduledoc """
  Native macOS file/folder picker using osascript.
  """

  @doc """
  Opens a macOS file chooser filtered to .md files.
  Returns {:ok, path}, :cancel, or {:error, reason}.
  """
  def pick_file do
    script = ~s|choose file of type {"md"} with prompt "Open Markdown File"|

    {output, exit_code} = System.cmd("osascript", ["-e", script], stderr_to_stdout: true)

    case parse_osascript_result(output, exit_code) do
      {:ok, hfs_path} -> {:ok, hfs_to_posix(hfs_path)}
      other -> other
    end
  end

  @doc """
  Opens a macOS folder chooser.
  Returns {:ok, dir_path}, :cancel, or {:error, reason}.
  """
  def pick_directory do
    script = ~s|choose folder with prompt "Browse Markdown Files"|

    {output, exit_code} = System.cmd("osascript", ["-e", script], stderr_to_stdout: true)

    case parse_osascript_result(output, exit_code) do
      {:ok, hfs_path} -> {:ok, hfs_to_posix(hfs_path)}
      other -> other
    end
  end

  @doc """
  Parses osascript output and exit code into a result tuple.
  """
  def parse_osascript_result(output, exit_code) do
    trimmed = String.trim(output)

    case {exit_code, trimmed} do
      {0, ""} ->
        {:error, "empty response"}

      {0, path} ->
        {:ok, path}

      {_, msg} when msg == "" ->
        {:error, "empty response"}

      {_, msg} ->
        if String.contains?(String.downcase(msg), "cancel") do
          :cancel
        else
          {:error, msg}
        end
    end
  end

  defp hfs_to_posix(path) do
    # osascript returns HFS paths like "Macintosh HD:Users:foo:file.md"
    # Convert to POSIX if needed
    if String.contains?(path, ":") and not String.starts_with?(path, "/") do
      {posix, 0} =
        System.cmd("osascript", [
          "-e",
          ~s|POSIX path of "#{path}"|
        ])

      String.trim(posix)
    else
      path
    end
  end
end
