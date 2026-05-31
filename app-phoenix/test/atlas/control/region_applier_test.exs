defmodule Atlas.Control.RegionApplierTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.RegionApplier

  test "apply/1 returns a job id and invokes the merge runner with looked-up PBFs" do
    test_pid = self()

    runner = fn data_dir, sources, output ->
      send(test_pid, {:runner_called, self(), data_dir, sources, output})

      receive do
        :proceed -> :ok
      after
        2_000 -> :ok
      end

      {0, "ok"}
    end

    pbf_lookup = fn region -> "pbfs/#{region}.osm.pbf" end

    start_supervised!(
      {RegionApplier,
       runner: runner, pbf_lookup: pbf_lookup, data_dir: "/data", output_path: "merged.pbf"}
    )

    assert {:ok, job_id} = RegionApplier.start(["berlin", "bayern"])

    assert_receive {:runner_called, runner_pid, "/data",
                    ["pbfs/berlin.osm.pbf", "pbfs/bayern.osm.pbf"], "merged.pbf"},
                   1_000

    Phoenix.PubSub.subscribe(Atlas.PubSub, RegionApplier.topic(job_id))
    send(runner_pid, :proceed)

    assert_receive {:apply_done, ^job_id, ["berlin", "bayern"]}, 1_000
  end

  test "merge failure broadcasts :apply_error" do
    test_pid = self()

    runner = fn _data_dir, _sources, _output ->
      send(test_pid, {:failing_runner, self()})

      receive do
        :proceed -> :ok
      after
        2_000 -> :ok
      end

      {1, "boom"}
    end

    start_supervised!(
      {RegionApplier,
       runner: runner,
       pbf_lookup: fn r -> "#{r}.pbf" end,
       data_dir: "/d",
       output_path: "out.pbf"}
    )

    assert {:ok, job_id} = RegionApplier.start(["x"])

    assert_receive {:failing_runner, runner_pid}, 1_000
    Phoenix.PubSub.subscribe(Atlas.PubSub, RegionApplier.topic(job_id))
    send(runner_pid, :proceed)

    assert_receive {:apply_error, ^job_id, {1, "boom"}}, 1_000
  end
end
