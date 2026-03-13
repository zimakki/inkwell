defmodule Inkwell.FileDialog do
  @moduledoc """
  Native macOS file/folder picker using osascript.
  """

  @doc """
  Opens a macOS file chooser filtered to .md files.
  Returns {:ok, path}, :cancel, or {:error, reason}.
  """
  def pick_file do
    script = ~s|POSIX path of (choose file of type {"md"} with prompt "Open Markdown File")|

    {output, exit_code} = System.cmd("osascript", ["-e", script], stderr_to_stdout: true)
    parse_osascript_result(output, exit_code)
  end

  @doc """
  Opens a macOS folder chooser.
  Returns {:ok, dir_path}, :cancel, or {:error, reason}.
  """
  def pick_directory do
    script = ~s|POSIX path of (choose folder with prompt "Browse Markdown Files")|

    {output, exit_code} = System.cmd("osascript", ["-e", script], stderr_to_stdout: true)
    parse_osascript_result(output, exit_code)
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
end
