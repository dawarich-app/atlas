defmodule Atlas.Control.SeederTest do
  use Atlas.DataCase, async: false
  alias Atlas.Control.{Seeder, Service, ServiceSupervisor}

  setup do
    start_supervised!({Registry, keys: :unique, name: Atlas.Control.Registry})
    start_supervised!(ServiceSupervisor)
    start_supervised!({Atlas.Control.DockerCompose, runner: fn _, _ -> {"", 0} end})
    :ok
  end

  test "seed_and_start! inserts 8 service rows" do
    Seeder.seed_and_start!()
    names = Repo.all(Service) |> Enum.map(& &1.name) |> Enum.sort()
    assert names == ~w[libpostal motis otp overpass photon placeholder valhalla whosonfirst]
  end

  test "seed_and_start! is idempotent" do
    Seeder.seed_and_start!()
    Seeder.seed_and_start!()
    assert Repo.aggregate(Service, :count) == 8
  end

  test "seed_and_start! starts 8 ServiceState children" do
    Seeder.seed_and_start!()

    %{active: active} = DynamicSupervisor.count_children(ServiceSupervisor)
    assert active == 8
  end

  test "known_services exposes the eight service definitions" do
    names = Seeder.known_services() |> Enum.map(& &1.name) |> Enum.sort()
    assert names == ~w[libpostal motis otp overpass photon placeholder valhalla whosonfirst]
  end
end
