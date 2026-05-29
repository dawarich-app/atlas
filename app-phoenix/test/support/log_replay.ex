defmodule Atlas.Control.Parsers.LogReplay do
  @moduledoc """
  Test helper that feeds a log fixture file line-by-line through a Parser module
  and returns the final result.

  Mirrors the Go test harness in `atlas-control/internal/parsers/photon_test.go`
  (`feedFixture`), where each parser test reduces over a log fixture and inspects
  the last emitted Result.
  """

  @fixtures_dir Path.expand("../../priv/parser_fixtures", __DIR__)

  @doc "Absolute path to a fixture file by name (e.g. \"photon-download.log\")."
  def fixture(name), do: Path.join(@fixtures_dir, name)

  @doc """
  Feed every line of `fixture_path` through `parser_mod`, threading the
  accumulator. Returns the final %{phase, progress, ready, last_log_line}.
  """
  def replay(parser_mod, fixture_path) do
    {result, _acc} = replay_with_acc(parser_mod, fixture_path, parser_mod.init())
    result
  end

  @doc """
  Feed multiple fixtures in order through the same parser accumulator,
  preserving state across files. Returns the final result.
  """
  def replay_chain(parser_mod, fixture_paths) when is_list(fixture_paths) do
    {result, _acc} =
      Enum.reduce(fixture_paths, {nil, parser_mod.init()}, fn path, {_last, acc} ->
        replay_with_acc(parser_mod, path, acc)
      end)

    result
  end

  defp replay_with_acc(parser_mod, fixture_path, acc) do
    fixture_path
    |> File.stream!()
    |> Stream.map(&String.trim_trailing(&1, "\n"))
    |> Stream.map(&String.trim_trailing(&1, "\r"))
    |> Enum.reduce({nil, acc}, fn line, {_last_result, a} ->
      parser_mod.feed(line, a)
    end)
  end
end
