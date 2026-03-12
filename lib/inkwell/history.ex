defmodule Inkwell.History do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def push(path) do
    Agent.update(__MODULE__, fn history ->
      [path | Enum.reject(history, &(&1 == path))] |> Enum.take(20)
    end)
  end

  def list do
    Agent.get(__MODULE__, & &1)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> [] end)
  end
end
