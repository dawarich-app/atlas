defmodule AtlasWeb.DirectionsStatusTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias AtlasWeb.DirectionsStatus

  defp status(assigns), do: render_component(&DirectionsStatus.directions_status/1, assigns)

  test "shows only the selected transit engine and distinguishes off from ready" do
    html =
      status(%{
        backend: "motis",
        services: %{
          "valhalla" => %{enabled?: true, status: :ready},
          "motis" => %{enabled?: false, status: :ready},
          "otp" => %{enabled?: true, status: :ready}
        }
      })

    assert html =~ "Valhalla: Ready"
    assert html =~ "MOTIS: Off"
    refute html =~ "OpenTripPlanner"
    assert html =~ "Realtime feed health is not monitored"
    assert html =~ ~s(phx-click="open_services")
  end

  test "loading and errors take precedence over stale readiness; unknown is not green" do
    html =
      status(%{
        backend: "otp",
        services: %{
          "valhalla" => %{enabled?: true, status: :building, ready?: true},
          "otp" => %{enabled?: true, status: :error, ready?: true}
        }
      })

    assert html =~ "Valhalla: Building"
    assert html =~ "OpenTripPlanner: Unavailable"
    assert html =~ "motion-safe:animate-pulse"
    refute html =~ "bg-success"
    assert status(%{services: %{}}) =~ "MOTIS: Unknown"
  end

  test "switching displays only the target engine" do
    html = status(%{backend: "motis", switching: "otp", services: %{}})
    assert html =~ "OpenTripPlanner: Switching"
    refute html =~ "MOTIS"
  end
end
