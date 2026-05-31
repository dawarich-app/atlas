defmodule AtlasWeb.AdminErrorComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import AtlasWeb.AdminErrorComponents

  test "sidecar_unavailable/1 renders the unreachable message" do
    html = render_component(&sidecar_unavailable/1, %{details: nil})

    assert html =~ "Atlas Control is unreachable"
    assert html =~ "make status"
    assert html =~ ~s(data-error="sidecar_unavailable")
  end

  test "sidecar_unavailable/1 includes details when provided" do
    html = render_component(&sidecar_unavailable/1, %{details: "connect refused"})

    assert html =~ "connect refused"
  end

  test "sidecar_error/1 renders the error block" do
    html =
      render_component(&sidecar_error/1, %{
        command: "docker compose up -d photon",
        details: "exit 1"
      })

    assert html =~ "Atlas Control returned an error"
    assert html =~ "docker compose up -d photon"
    assert html =~ "exit 1"
    assert html =~ ~s(data-error="sidecar_error")
  end

  test "region_not_found/1 renders the missing region name" do
    html = render_component(&region_not_found/1, %{name: "atlantis", available: ["berlin", "germany"]})

    assert html =~ "atlantis"
    assert html =~ "berlin"
    assert html =~ "germany"
    assert html =~ ~s(data-error="region_not_found")
  end

  test "region_not_found/1 handles empty catalog" do
    html = render_component(&region_not_found/1, %{name: "atlantis", available: []})

    assert html =~ "No region presets are configured"
  end
end
