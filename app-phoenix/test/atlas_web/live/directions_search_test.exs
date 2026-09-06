defmodule AtlasWeb.DirectionsSearchTest do
  use AtlasWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    bypass = Bypass.open()
    vars = ~w(PHOTON_URL LIBPOSTAL_URL PLACEHOLDER_URL VALHALLA_URL)
    previous = Map.new(vars, &{&1, System.get_env(&1)})
    Enum.each(vars, &System.put_env(&1, "http://localhost:#{bypass.port}"))

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    Bypass.stub(bypass, "POST", "/route", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"trip":{"legs":[],"summary":{}}}))
    end)

    Bypass.stub(bypass, "GET", "/parser", &Plug.Conn.resp(&1, 200, "[]"))

    Bypass.stub(bypass, "GET", "/api", fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      {name, lon} =
        if conn.query_params["q"] == "Gate",
          do: {"Brandenburger Tor", 13.3777},
          else: {"Alexanderplatz", 13.4132}

      body = %{
        features: [
          %{
            geometry: %{coordinates: [lon, 52.52]},
            properties: %{
              name: name,
              street: "Teststrasse",
              housenumber: "10",
              city: "Berlin",
              country: "Germany",
              osm_id: 1,
              osm_type: "N"
            }
          }
        ]
      }

      Plug.Conn.resp(conn, 200, Jason.encode!(body))
    end)

    {:ok, bypass: bypass}
  end

  test "selecting both addresses automatically routes and swapping recalculates once", %{
    conn: conn,
    bypass: bypass
  } do
    owner = self()

    Bypass.stub(bypass, "POST", "/route", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:locations, Jason.decode!(body)["locations"]})

      Plug.Conn.resp(
        conn,
        200,
        ~s({"trip":{"legs":[{"shape":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}],"summary":{}}})
      )
    end)

    {:ok, view, _} = live(conn, ~p"/")
    from = choose(view, "from", "Gate", "", "")
    assert from =~ "Teststrasse 10"
    refute_receive {:locations, _}
    to = choose(view, "to", "Square", from, "")
    assert_receive {:locations, [%{"lon" => 13.3777}, %{"lon" => 13.4132}]}

    assert_push_event(view, "map:draw_route", %{
      geojson: %{features: [%{geometry: %{type: "LineString", coordinates: [_, _ | _]}}]}
    })

    render_hook(view, "swap_route", %{})
    assert has_element?(view, ~s(input[name=from][value="#{to}"]))
    assert has_element?(view, ~s(input[name=to][value="#{from}"]))
    assert_receive {:locations, [%{"lon" => 13.4132}, %{"lon" => 13.3777}]}
    change(view, "from", to, from)
    refute_receive {:locations, _}
  end

  test "editing a chosen place never silently uses its old coordinates", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    _from = choose(view, "from", "Gate", "", "52.5,13.4")
    html = render_hook(view, "route", %{"from" => "Changed address", "to" => "52.5,13.4"})
    assert html =~ "Choose a From search result"
    render_async(view)
    refute render(view) =~ "Route ready."
  end

  test "coordinate endpoints work without geocoding and validate ranges", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/route", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body)["locations"] == [
               %{"lat" => 52.5, "lon" => 13.4},
               %{"lat" => 52.6, "lon" => 13.5}
             ]

      Plug.Conn.resp(conn, 200, ~s({"trip":{"legs":[],"summary":{}}}))
    end)

    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "route", %{"from" => " 52.5, 13.4 ", "to" => "52.6,13.5"})

    assert render_hook(view, "route", %{"from" => "95,13.4", "to" => "52.6,13.5"}) =~
             "Choose a From"
  end

  test "keyboard selection and dismiss keep independent endpoint lists", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, "from", "Gate", "Square")
    render_async(view)
    assert has_element?(view, "#route-from-results", "Brandenburger Tor")
    refute has_element?(view, "#route-to-results")
    render_hook(view, "route_move", %{"field" => "from", "query" => "Gate", "dir" => 1})
    assert has_element?(view, "#route-from-option-0[aria-selected=true]")
    render_hook(view, "route_select", %{"field" => "from", "query" => "Gate"})
    assert has_element?(view, ~s(input[name=from][value^="Brandenburger Tor"]))
    render_hook(view, "route_focus", %{"field" => "to"})
    assert has_element?(view, "#route-to-results", "Alexanderplatz")
    render_hook(view, "route_dismiss", %{})
    refute has_element?(view, "#route-to-results")
  end

  test "map picking replaces a selected address with coordinates", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    choose(view, "from", "Gate", "", "")
    render_hook(view, "point_picked", %{"field" => "from", "lat" => 52.51, "lon" => 13.4})
    assert has_element?(view, ~s(input[name=from][value="52.510000,13.400000"]))
    assert_push_event(view, "route:endpoint", %{field: "from", value: "52.510000,13.400000"})
  end

  test "empty results and search failures are explained", %{conn: conn, bypass: bypass} do
    Bypass.stub(bypass, "GET", "/api", &Plug.Conn.resp(&1, 200, ~s({"features":[]})))
    {:ok, view, _} = live(conn, ~p"/")
    change(view, "from", "Missing", "")
    assert render_async(view) =~ "No places found"
    Bypass.stub(bypass, "GET", "/api", &Plug.Conn.resp(&1, 400, "{}"))
    change(view, "from", "Unavailable", "")
    assert render_async(view) =~ "Search unavailable"
  end

  test "late search cannot overwrite a subsequently picked coordinate", %{
    conn: conn,
    bypass: bypass
  } do
    owner = self()

    Bypass.stub(bypass, "GET", "/api", fn conn ->
      send(owner, {:search_started, self()})

      receive do
        :finish -> Plug.Conn.resp(conn, 200, ~s({"features":[]}))
      end
    end)

    {:ok, view, _} = live(conn, ~p"/")
    change(view, "from", "Gate", "")
    assert_receive {:search_started, request}
    render_hook(view, "point_picked", %{"field" => "from", "lat" => 52.5, "lon" => 13.4})
    send(request, :finish)
    render_async(view)
    assert has_element?(view, ~s(input[name=from][value="52.500000,13.400000"]))
    refute has_element?(view, "#route-from-results")
    Bypass.pass(bypass)
  end

  test "map endpoints follow coordinates, edits, selections and an atomic swap", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, "from", "52.5,13.4", "52.6,13.5")

    assert_push_event(view, "map:set_route_endpoints", %{
      points: [
        %{field: "from", lat: 52.5, lon: 13.4},
        %{field: "to", lat: 52.6, lon: 13.5}
      ]
    })

    render_hook(view, "swap_route", %{})

    assert_push_event(view, "map:set_route_endpoints", %{
      points: [
        %{field: "from", lat: 52.6, lon: 13.5},
        %{field: "to", lat: 52.5, lon: 13.4}
      ]
    })

    refute_receive {_, {:push_event, "map:set_route_endpoints", _}}
    change(view, "from", "Gate", "52.5,13.4")
    assert_push_event(view, "map:set_route_endpoints", %{points: [%{field: "to"}]})
    render_async(view)
    refute_receive {_, {:push_event, "map:set_route_endpoints", _}}
    view |> element("#route-from-option-0") |> render_click()

    assert_push_event(view, "map:set_route_endpoints", %{
      points: [
        %{field: "from", lat: 52.52, lon: 13.3777},
        %{field: "to", lat: 52.5, lon: 13.4}
      ]
    })

    change(view, "to", "", "")
    assert_push_event(view, "map:set_route_endpoints", %{points: []})
  end

  test "coordinate entry routes automatically and changing mode recalculates", %{
    conn: conn,
    bypass: bypass
  } do
    owner = self()

    Bypass.stub(bypass, "POST", "/route", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:costing, Jason.decode!(body)["costing"]})
      Plug.Conn.resp(conn, 200, ~s({"trip":{"legs":[],"summary":{}}}))
    end)

    {:ok, view, _} = live(conn, ~p"/")

    change(view, "from", "52.49,13.46", "")
    refute_receive {:costing, _}
    change(view, "to", "52.49,13.46", "52.42,13.49")

    assert_receive {:costing, "auto"}
    render_hook(view, "set_mode", %{"mode" => "pedestrian"})
    assert_receive {:costing, "pedestrian"}
    render_hook(view, "set_mode", %{"mode" => "bicycle"})
    assert_receive {:costing, "bicycle"}
    render_hook(view, "set_mode", %{"mode" => "bicycle"})
    refute_receive {:costing, _}
    render_hook(view, "toggle_route_option", %{"option" => "avoid_ferries"})
    assert_receive {:costing, "bicycle"}
  end

  test "editing waits for a confirmed place and map picking immediately recalculates", %{
    conn: conn,
    bypass: bypass
  } do
    owner = self()

    Bypass.stub(bypass, "POST", "/route", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:locations, Jason.decode!(body)["locations"]})

      Plug.Conn.resp(
        conn,
        200,
        ~s({"trip":{"legs":[{"shape":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}],"summary":{}}})
      )
    end)

    {:ok, view, _} = live(conn, ~p"/")
    change(view, "to", "52.5,13.4", "52.6,13.5")
    assert_receive {:locations, _}
    assert_push_event(view, "map:draw_route", %{geojson: %{features: [_]}})

    change(view, "from", "Gate", "52.6,13.5")
    render_async(view)
    assert_push_event(view, "map:draw_route", %{geojson: %{features: []}})
    refute_receive {:locations, _}

    view |> element("#route-from-option-0") |> render_click()
    assert_receive {:locations, [%{"lon" => 13.3777}, %{"lon" => 13.5}]}
    assert_push_event(view, "map:draw_route", %{geojson: %{features: [_]}})

    render_hook(view, "point_picked", %{"field" => "to", "lat" => 52.51, "lon" => 13.41})
    assert_receive {:locations, [%{"lon" => 13.3777}, %{"lat" => 52.51, "lon" => 13.41}]}
    refute_receive {:locations, _}
  end

  defp change(view, field, from, to) do
    render_hook(view, "route_changed", %{"from" => from, "to" => to, "_target" => [field]})
  end

  defp choose(view, field, query, from, to) do
    {from, to} = if field == "from", do: {query, to}, else: {from, query}
    change(view, field, from, to)
    render_async(view)

    label =
      view
      |> element("#route-#{field}-option-0")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> String.trim()

    view |> element("#route-#{field}-option-0") |> render_click()
    label
  end
end
