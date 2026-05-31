defmodule Atlas.Control.ApplyProjectionTest do
  use Atlas.DataCase, async: false

  alias Atlas.Control.ApplyProjection

  test "summary/2 with no regions defaults to city scaling table" do
    proj = ApplyProjection.summary([], [])

    assert is_float(proj.total_disk_gb)
    assert is_float(proj.first_boot_hours)
    assert is_list(proj.lines)
    assert proj.service_intents == []
  end

  test "summary/2 for berlin uses city disk values" do
    proj = ApplyProjection.summary(["berlin"], [])

    assert proj.total_disk_gb >= 0.0
    # No services seeded → enabled set empty → lines empty
    assert is_list(proj.lines)
  end

  test "summary/2 with germany region uses country scaling" do
    {:ok, _} =
      Atlas.Repo.insert(%Atlas.Control.Service{
        name: "photon",
        profile: "geocoding",
        enabled: true
      })

    proj = ApplyProjection.summary(["germany"], [])

    photon = Enum.find(proj.lines, &(&1.name == "photon"))
    assert photon.disk_gb == 8.0
  end

  test "summary/2 with planet uses planet scaling" do
    {:ok, _} =
      Atlas.Repo.insert(%Atlas.Control.Service{
        name: "valhalla",
        profile: "routing",
        enabled: true
      })

    proj = ApplyProjection.summary(["planet"], [])

    valhalla = Enum.find(proj.lines, &(&1.name == "valhalla"))
    assert valhalla.disk_gb == 250.0
  end

  test "intents add services to the projected enabled set" do
    proj =
      ApplyProjection.summary(["berlin"], [%{name: "photon", enabled: true}])

    assert Enum.any?(proj.lines, &(&1.name == "photon"))
    assert Enum.any?(proj.service_intents, &(&1.name == "photon" and &1.enabled))
  end

  test "intents remove services from the projected enabled set" do
    {:ok, _} =
      Atlas.Repo.insert(%Atlas.Control.Service{
        name: "photon",
        profile: "geocoding",
        enabled: true
      })

    proj =
      ApplyProjection.summary(["berlin"], [%{name: "photon", enabled: false}])

    refute Enum.any?(proj.lines, &(&1.name == "photon"))
  end
end
