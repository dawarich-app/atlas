defmodule AtlasWeb.Admin.ServiceLogsLiveTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    System.put_env("ADMIN_USERNAME", "admin")
    System.put_env("ADMIN_PASSWORD", "s3cret")

    on_exit(fn ->
      Enum.each(~w[ADMIN_USERNAME ADMIN_PASSWORD], &System.delete_env/1)
    end)

    conn =
      build_conn()
      |> put_req_header("authorization", "Basic " <> Base.encode64("admin:s3cret"))

    {:ok, conn: conn}
  end

  test "GET /admin/services/:name/logs renders the streaming viewer", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/services/photon/logs")

    assert html =~ "Logs: photon"
    assert html =~ ~s(id="log-viewer")
    assert html =~ ~s(phx-hook="LogStream")
    assert html =~ ~s(phx-update="stream")
  end

  test "log_line messages append to the stream", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/services/photon/logs")

    send(view.pid, {:log_line, "hello world"})
    send(view.pid, {:log_line, "another line"})

    html = render(view)
    assert html =~ "hello world"
    assert html =~ "another line"
  end

  test "subscribes to logs:<name> topic on mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/services/valhalla/logs")

    Phoenix.PubSub.broadcast(Atlas.PubSub, "logs:valhalla", {:log_line, "broadcasted"})

    # Give the LiveView a tick to process the PubSub message.
    _ = :sys.get_state(view.pid)

    assert render(view) =~ "broadcasted"
  end

  test "the log viewer offers a copy button wired to the log element", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/services/valhalla/logs")

    # The hook copies `data-copy-target`'s textContent, so the id it names has
    # to be the element that actually holds the lines — a stale id copies
    # nothing and fails silently in the browser.
    assert html =~ ~s(phx-hook="CopyLogs")
    assert html =~ ~s(data-copy-target="log-viewer")
    assert html =~ ~s(id="log-viewer")
  end
end
