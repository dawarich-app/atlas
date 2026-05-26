defmodule Atlas.Control.ServiceTest do
  use Atlas.DataCase, async: true
  alias Atlas.Control.Service

  test "valid changeset with name + profile" do
    cs = Service.changeset(%Service{}, %{name: "photon", profile: "geocoding"})
    assert cs.valid?
  end

  test "requires name and profile" do
    cs = Service.changeset(%Service{}, %{})
    refute cs.valid?
    assert "can't be blank" in errors_on(cs).name
    assert "can't be blank" in errors_on(cs).profile
  end

  test "validates progress between 0 and 1" do
    refute Service.changeset(%Service{}, %{name: "x", profile: "p", progress: -0.1}).valid?
    refute Service.changeset(%Service{}, %{name: "x", profile: "p", progress: 1.1}).valid?
    assert Service.changeset(%Service{}, %{name: "x", profile: "p", progress: 0.5}).valid?
  end

  test "status enum stores integers matching Rails" do
    cs = Service.changeset(%Service{}, %{name: "x", profile: "p", status: :ready})
    assert Ecto.Changeset.get_change(cs, :status) == :ready
  end

  test "name is unique" do
    {:ok, _} =
      Atlas.Repo.insert(Service.changeset(%Service{}, %{name: "photon", profile: "geocoding"}))

    {:error, cs} =
      Atlas.Repo.insert(Service.changeset(%Service{}, %{name: "photon", profile: "geocoding"}))

    assert "has already been taken" in errors_on(cs).name
  end
end
