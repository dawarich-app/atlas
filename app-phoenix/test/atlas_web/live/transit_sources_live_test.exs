defmodule AtlasWeb.TransitSourcesLiveTest do
  use AtlasWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Atlas.Control.TransitSources

  test "find and connect a region provider, disable realtime, and return to wizard", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/transport-data?from=setup")
    assert has_element?(view, "a[href='/setup']", "Back to setup")
    view |> element("form[phx-change=search]") |> render_change(%{"query" => "Japan"})
    assert render(view) =~ "No verified source"
    view |> element("form[phx-change=search]") |> render_change(%{"query" => "Germany"})
    view |> element("button[phx-click=connect]") |> render_click()
    assert has_element?(view, "#source-vbb", "Not downloaded yet")
    view |> element("#source-vbb button[phx-value-field=realtime]") |> render_click()
    assert hd(TransitSources.enabled())["realtime"] == false
    assert has_element?(view, "#source-vbb", "Live updates off")
    {:ok, refreshed, _} = live(conn, ~p"/transport-data")
    assert has_element?(refreshed, "#source-vbb", "Live updates off")
  end

  test "add a manual schedule-only source and do not render its secret", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/transport-data")
    view |> element("button[phx-click=add]") |> render_click()

    view
    |> form("#custom-source",
      source: %{
        name: "My City",
        coverage: "Town",
        url: "https://example.test/gtfs.zip",
        header_name: "Authorization",
        header_value: "my-secret"
      }
    )
    |> render_submit()

    assert render(view) =~ "Schedule only"
    assert render(view) =~ "API key saved"
    refute render(view) =~ "my-secret"
    refute has_element?(view, "#custom-source")
    assert [%{"name" => "My City"}] = TransitSources.enabled()
  end
end
