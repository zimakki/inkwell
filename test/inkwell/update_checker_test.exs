defmodule Inkwell.UpdateCheckerTest do
  use ExUnit.Case, async: true

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "inkwell-update-checker-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf(tmp_dir) end)
    %{tmp_dir: tmp_dir}
  end

  test "reads cached latest version without making a fresh request", %{tmp_dir: tmp_dir} do
    checked_at = DateTime.utc_now() |> DateTime.to_iso8601()

    File.write!(
      Path.join(tmp_dir, "update_check.json"),
      Jason.encode!(%{"latest" => "0.3.0", "checked_at" => checked_at})
    )

    pid =
      start_supervised!(
        {Inkwell.UpdateChecker,
         [
           name: nil,
           state_dir: tmp_dir,
           request_fn: fn ->
             flunk("request_fn should not be called for fresh cache")
           end
         ]}
      )

    assert Inkwell.UpdateChecker.latest_version(pid) == "0.3.0"
  end

  test "refreshes stale cache asynchronously and rewrites the cache file", %{tmp_dir: tmp_dir} do
    stale =
      DateTime.utc_now()
      |> DateTime.add(-(25 * 60 * 60), :second)
      |> DateTime.to_iso8601()

    File.write!(
      Path.join(tmp_dir, "update_check.json"),
      Jason.encode!(%{"latest" => "0.2.12", "checked_at" => stale})
    )

    pid =
      start_supervised!(
        {Inkwell.UpdateChecker,
         [
           name: nil,
           state_dir: tmp_dir,
           request_fn: fn -> {:ok, %{"tag_name" => "v0.3.0"}} end
         ]}
      )

    assert eventually(fn -> Inkwell.UpdateChecker.latest_version(pid) == "0.3.0" end)

    assert {:ok, %{latest: "0.3.0", checked_at: checked_at}} =
             Inkwell.UpdateChecker.cached_info(state_dir: tmp_dir)

    assert {:ok, _, _} = DateTime.from_iso8601(checked_at)
  end

  test "retains cached version when API request fails", %{tmp_dir: tmp_dir} do
    stale =
      DateTime.utc_now()
      |> DateTime.add(-(25 * 60 * 60), :second)
      |> DateTime.to_iso8601()

    File.write!(
      Path.join(tmp_dir, "update_check.json"),
      Jason.encode!(%{"latest" => "0.2.12", "checked_at" => stale})
    )

    pid =
      start_supervised!(
        {Inkwell.UpdateChecker,
         [
           name: nil,
           state_dir: tmp_dir,
           request_fn: fn -> {:error, :nxdomain} end
         ]}
      )

    # Give handle_continue time to run
    Process.sleep(50)

    assert Inkwell.UpdateChecker.latest_version(pid) == "0.2.12"

    # Cache timestamp should be advanced so we don't re-check on next start
    assert {:ok, %{latest: "0.2.12", checked_at: checked_at}} =
             Inkwell.UpdateChecker.cached_info(state_dir: tmp_dir)

    {:ok, ts, _} = DateTime.from_iso8601(checked_at)
    assert DateTime.diff(DateTime.utc_now(), ts, :second) < 10
  end

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
