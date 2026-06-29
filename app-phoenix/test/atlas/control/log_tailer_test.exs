defmodule Atlas.Control.LogTailerTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.LogTailer

  setup do
    start_supervised!({Registry, keys: :unique, name: Atlas.Control.Registry})

    fixture =
      Path.join(System.tmp_dir!(), "tailer-fixture-#{System.unique_integer([:positive])}.log")

    File.write!(fixture, "line one\nline two\n")
    on_exit(fn -> File.rm(fixture) end)
    {:ok, fixture: fixture}
  end

  test "broadcasts each line and an EOF marker when the stream ends", %{fixture: fixture} do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "logs:photon")

    start_supervised!(
      {LogTailer, name: "photon", executable: System.find_executable("cat"), args: [fixture]}
    )

    assert_receive {:log_line, "line one"}, 1_000
    assert_receive {:log_line, "line two"}, 1_000
    assert_receive {:log_eof, 0}, 1_000
  end

  test "recent/1 replays buffered lines to late-opening viewers", %{fixture: fixture} do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "logs:photon")

    # Emit the fixture then stay alive, like `docker compose logs -f`.
    start_supervised!(
      {LogTailer,
       name: "photon",
       executable: System.find_executable("sh"),
       args: ["-c", "cat #{fixture}; sleep 5"]}
    )

    assert_receive {:log_line, "line two"}, 1_000

    assert LogTailer.recent("photon") == ["line one", "line two"]
  end

  test "recent/1 is empty when no tailer runs" do
    assert LogTailer.recent("ghost") == []
  end

  test "default args tail compose logs with history" do
    args = LogTailer.default_args("photon")
    assert args == ["compose", "logs", "-f", "--tail=200", "photon"]
  end

  test "default args resolve the compose project against HOST_PROJECT_DIR" do
    System.put_env("HOST_PROJECT_DIR", "/srv/atlas")
    on_exit(fn -> System.delete_env("HOST_PROJECT_DIR") end)

    args = LogTailer.default_args("photon")

    assert args == [
             "compose",
             "--project-directory",
             "/srv/atlas",
             "logs",
             "-f",
             "--tail=200",
             "photon"
           ]
  end
end
