defmodule Inkwell.History do
  @moduledoc "In-memory store of recently opened files."
  use Agent

  @max_size 20

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def push(path) when is_binary(path) do
    Agent.update(__MODULE__, fn history ->
      [path | Enum.reject(history, &(&1 == path))] |> Enum.take(@max_size)
    end)
  end

  def list do
    Agent.get(__MODULE__, & &1)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> [] end)
  end
end
