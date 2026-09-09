defmodule AtlasWeb.SetupLiveTest do
  use AtlasWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Atlas.Control.{Onboarding, RegionSelection}

  test "wizard saves choices, validates regions and preserves Settings draft", %{conn: conn} do
    RegionSelection.toggle("germany")
    {:ok, view, _} = live(conn, ~p"/setup")
    assert has_element?(view, "h2", "What would you like to do?")
    view |> element("button[phx-value-name=transit]") |> render_click()
    view |> element("button[phx-click=next]") |> render_click()
    assert render(view) =~ "Where will you use Atlas?"

    assert view |> element("button[phx-click=next]") |> render_click() =~
             "Choose at least one region"

    view |> element("button[phx-value-name=germany]") |> render_click()

    assert has_element?(view, "[data-role=coverage-warning]", "Germany")
    view |> element("button[phx-value-name=berlin]") |> render_click()
    view |> element("button[phx-click=next]") |> render_click()
    assert has_element?(view, "[data-role=coverage-warning]", "You can continue")
    assert render(view) =~ "Ready to install"
    assert has_element?(view, "input[type=radio][value=motis][checked]")
    assert has_element?(view, "button[phx-click=install][disabled]")
    {:ok, refreshed, _} = live(conn, ~p"/setup")
    assert render(refreshed) =~ "Ready to install"
    assert Onboarding.draft()["regions"] == ["germany", "berlin"]
    assert has_element?(refreshed, "[data-role=coverage-warning]", "Germany")
    assert RegionSelection.active_names() == ["germany"]
  end

  test "back from review preserves region and feature choices across both previous steps", %{
    conn: conn
  } do
    draft = %{
      "capabilities" => ["routing", "transit"],
      "regions" => ["berlin"],
      "backend" => "motis",
      "step" => 3
    }

    Onboarding.save_draft(draft)
    {:ok, view, _} = live(conn, ~p"/setup")
    view |> element("#setup-back") |> render_click()
    assert has_element?(view, "h2", "Where will you use Atlas?")
    assert has_element?(view, "button[phx-value-name=berlin][aria-pressed=true]")
    view |> element("#setup-back") |> render_click()
    assert has_element?(view, "h2", "What would you like to do?")
    assert has_element?(view, "button[phx-value-name=transit][aria-pressed=true]")
    assert Onboarding.draft()["regions"] == ["berlin"]
    refute has_element?(view, "#setup-back")
  end

  test "installation details stay open during progress and remain closed when collapsed", %{
    conn: conn
  } do
    draft = %{
      "capabilities" => ["routing"],
      "regions" => ["berlin"],
      "backend" => "motis",
      "step" => 4
    }

    Onboarding.save_draft(draft)

    Atlas.Settings.set(
      "setup_job",
      Jason.encode!(%{"id" => "details-test", "draft" => draft, "status" => "preparing"})
    )

    {:ok, view, _} = live(conn, ~p"/setup")
    now = DateTime.utc_now()

    timeline = %{
      Atlas.Control.ApplyTimeline.start(["berlin"], ["valhalla"], now)
      | job_id: "details-test"
    }

    send(view.pid, {:timeline, timeline})
    assert has_element?(view, "#installation-details-content[hidden]")
    view |> element("#installation-details-toggle") |> render_click()
    assert has_element?(view, "#installation-details-toggle[aria-expanded=true]")

    updated =
      Atlas.Control.ApplyTimeline.apply_event(
        timeline,
        {:apply_progress,
         %{
           phase: :downloading,
           item: %{
             label: "berlin.pbf",
             source: "https://example.test/berlin.pbf",
             current: 50,
             total: 100
           }
         }},
        now
      )

    send(view.pid, {:timeline, updated})
    send(view.pid, :status_changed)
    assert has_element?(view, "#installation-details-toggle[aria-expanded=true]")
    refute has_element?(view, "#installation-details-content[hidden]")
    assert has_element?(view, "#installation-details-content", "50%")
    view |> element("#installation-details-toggle") |> render_click()
    send(view.pid, {:timeline, timeline})
    assert has_element?(view, "#installation-details-content[hidden]")
  end

  test "skipping returns to map and suppresses first run", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/setup")
    view |> element("header button[phx-click=skip]") |> render_click()
    assert_redirect(view, ~p"/")
    assert Atlas.Settings.get("setup_dismissed") == "true"
  end

  test "Settings provides a way back to the wizard", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "select_tab", %{"tab" => "settings"})
    assert has_element?(view, "a[href='/setup']", "Setup wizard")
  end
end
