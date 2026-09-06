defmodule AtlasWeb.MapLiveTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    bypass = Bypass.open()

    Enum.each(
      ~w[PHOTON_URL PLACEHOLDER_URL LIBPOSTAL_URL VALHALLA_URL OTP_URL],
      &System.put_env(&1, "http://localhost:#{bypass.port}")
    )

    Atlas.Settings.set("transit_backend", "otp")

    on_exit(fn ->
      Enum.each(
        ~w[PHOTON_URL PLACEHOLDER_URL LIBPOSTAL_URL VALHALLA_URL OTP_URL],
        &System.delete_env/1
      )
    end)

    {:ok, bypass: bypass}
  end

  test "GET / renders map and sidebar cards", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Search"
    assert html =~ "Directions"
    assert html =~ "Places"
    assert html =~ "Settings"
    assert html =~ ~s(id="map")
    assert html =~ ~s(phx-hook="Map")
  end

  test "directions can be submitted with a button", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             ~s(form[phx-submit="route"] button[type="submit"]),
             "Get directions"
           )
  end

  test "changing travel mode preserves endpoints typed into the form", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.stub(bypass, "POST", "/route", &Plug.Conn.resp(&1, 200, ~s({"trip":{"legs":[]}})))

    Bypass.stub(
      bypass,
      "POST",
      "/otp/gtfs/v1",
      &Plug.Conn.resp(&1, 200, ~s({"data":{"planConnection":{"edges":[]}}}))
    )

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("form[phx-submit=route]", %{"from" => "47.141,9.521", "to" => "47.146,9.516"})
    |> render_change()

    view |> element(~s(button[phx-click="set_mode"][phx-value-mode="transit"])) |> render_click()
    assert has_element?(view, ~s(input[name="from"][value="47.141,9.521"]))
    assert has_element?(view, ~s(input[name="to"][value="47.146,9.516"]))
  end

  test "an invalid route mode does not crash the LiveView", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      render_hook(view, "route", %{
        "from" => "52.5,13.4",
        "to" => "52.6,13.5",
        "mode" => "invalid"
      })

    assert html =~ "Choose Drive, Bike, Walk or Transit."
    assert render(view) =~ "Directions"
  end

  test "routing failures clear the map and never announce Route ready", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.down(bypass)
    {:ok, view, _html} = live(conn, ~p"/")
    html = render_hook(view, "route", %{"from" => "52.5,13.4", "to" => "52.6,13.5"})
    assert html =~ "Routing service unavailable"
    refute html =~ "Route ready."

    assert_push_event(view, "map:draw_route", %{
      geojson: %{type: "FeatureCollection", features: []}
    })
  end

  test "uncovered route does not report a working service as unavailable", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/route", fn c ->
      Plug.Conn.resp(c, 400, ~s({"error":"No suitable edges near location","error_code":171}))
    end)

    {:ok, view, _html} = live(conn, ~p"/")
    html = render_hook(view, "route", %{"from" => "0,0", "to" => "0.1,0.1"})
    assert html =~ "Check that both points are inside the loaded region."
    refute html =~ "Routing service unavailable"
    refute html =~ "Route ready."

    assert_push_event(view, "map:draw_route", %{
      geojson: %{type: "FeatureCollection", features: []}
    })
  end

  test "empty transit results clear the previous route", %{conn: conn, bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/otp/gtfs/v1", fn c ->
      Plug.Conn.resp(c, 200, ~s({"data":{"planConnection":{"edges":[]}}}))
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      render_hook(view, "route", %{
        "from" => "52.5,13.4",
        "to" => "52.6,13.5",
        "mode" => "transit"
      })

    assert html =~ "No route found for this trip."

    assert_push_event(view, "map:draw_route", %{
      geojson: %{type: "FeatureCollection", features: []}
    })

    refute html =~ "Route ready."
  end

  test "search submit populates results", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/parser" ->
          Plug.Conn.resp(c, 200, "[]")

        "/api" ->
          Plug.Conn.resp(
            c,
            200,
            ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin","city":"Berlin","country":"Germany","osm_id":1,"osm_type":"R","osm_key":"place","osm_value":"city"}}]})
          )

        "/parser/search" ->
          Plug.Conn.resp(c, 200, "[]")

        _ ->
          Plug.Conn.resp(c, 200, "[]")
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form[phx-submit=search]", %{"q" => "berlin"})
      |> render_submit()
      |> then(fn _ -> render_async(view) end)

    assert html =~ "Berlin"
  end

  test "an unreachable geocoder says so inside the search panel", %{conn: conn, bypass: bypass} do
    # The user is looking at the search box, not at a page-wide banner. Silence
    # there is indistinguishable from "no such place" and from a dead button.
    Bypass.down(bypass)

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form[phx-submit=search]", %{"q" => "berlin"})
      |> render_submit()
      |> then(fn _ -> render_async(view) end)

    # Photon is not started in the test env, which is exactly the fresh-instance
    # case: the copy must name the tool, not say "unavailable".
    assert html =~ "Photon is not installed"
    refute html =~ "No results"
  end

  test "a successful search with no matches says that, not nothing", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect(bypass, fn c -> Plug.Conn.resp(c, 200, ~s({"features":[]})) end)

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form[phx-submit=search]", %{"q" => "asdfqwerzxcv"})
      |> render_submit()
      |> then(fn _ -> render_async(view) end)

    assert html =~ "No results"
    assert html =~ "asdfqwerzxcv"
    refute html =~ "is not installed"
  end

  test "the empty search panel stays quiet before anything is searched", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    refute html =~ "No results"
    refute html =~ "is not installed"
  end

  describe "type-as-you-go" do
    setup %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/api", fn c ->
        Plug.Conn.resp(
          c,
          200,
          ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin","city":"Berlin","country":"Germany","osm_id":1,"osm_type":"R","osm_key":"place","osm_value":"city"}}]})
        )
      end)

      Bypass.stub(bypass, "GET", "/parser", fn c -> Plug.Conn.resp(c, 200, "[]") end)
      Bypass.stub(bypass, "GET", "/parser/search", fn c -> Plug.Conn.resp(c, 200, "[]") end)
      :ok
    end

    test "results arrive from typing alone, with no submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> element("form[phx-change=search]")
        |> render_change(%{"q" => "berlin"})
        |> then(fn _ -> render_async(view) end)

      assert html =~ "Berlin"
    end

    test "the input carries a debounce, so each keystroke is not a Photon query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Scoped to the search input on purpose: the settings tab renders its own
      # phx-debounce on the same page, so a bare `html =~ "phx-debounce"` passes
      # whether or not this input has one.
      assert has_element?(view, ~s(form[phx-change="search"] input[name="q"][phx-debounce]))
    end

    test "a one-character query is ignored rather than queried", %{conn: conn} do
      # Photon on a single letter returns noise and costs a round trip per
      # keystroke. Rails used the same two-character floor.
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> element("form[phx-change=search]")
        |> render_change(%{"q" => "b"})

      refute html =~ "Berlin"
      refute html =~ "No results"
    end

    test "clearing the box drops the results instead of leaving them stale", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("form[phx-change=search]") |> render_change(%{"q" => "berlin"})
      assert render_async(view) =~ "Berlin"

      refute view |> element("form[phx-change=search]") |> render_change(%{"q" => ""}) =~
               "Results"
    end
  end

  describe "result markers" do
    setup %{bypass: bypass} do
      features =
        1..3
        |> Enum.map_join(",", fn i ->
          ~s({"geometry":{"coordinates":[13.#{i},52.#{i}]},"properties":{"name":"Berlin P#{i}","city":"Berlin","osm_id":#{i},"osm_type":"N","osm_key":"place","osm_value":"city"}})
        end)

      Bypass.stub(bypass, "GET", "/api", fn c ->
        Plug.Conn.resp(c, 200, ~s({"features":[#{features}]}))
      end)

      Bypass.stub(bypass, "GET", "/parser", fn c -> Plug.Conn.resp(c, 200, "[]") end)
      Bypass.stub(bypass, "GET", "/parser/search", fn c -> Plug.Conn.resp(c, 200, "[]") end)
      :ok
    end

    defp typed(view, q) do
      view |> element("form[phx-change=search]") |> render_change(%{"q" => q})
      render_async(view)
    end

    test "every result gets a marker, not just the one you click", %{conn: conn} do
      # This is what made the Rails map useful: you see where all the matches
      # are before choosing. Marking only the selection leaves the map bare.
      {:ok, view, _html} = live(conn, ~p"/")

      typed(view, "berlin")

      assert_push_event(view, "map:set_results", %{points: [_ | _] = points})
      assert length(points) == 3
      assert Enum.all?(points, &(is_number(&1.lat) and is_number(&1.lon) and is_binary(&1.label)))
    end

    test "emptying the box clears the pins, not just the list", %{conn: conn} do
      # Escape was fixed; backspacing was not. The list vanished while every
      # marker stayed on the map.
      {:ok, view, _html} = live(conn, ~p"/")
      typed(view, "berlin")
      assert_push_event(view, "map:set_results", %{points: [_ | _]})

      typed(view, "")

      assert_push_event(view, "map:set_results", %{points: []})
    end

    test "backspacing below the minimum clears them too", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      typed(view, "berlin")
      assert_push_event(view, "map:set_results", %{points: [_ | _]})

      typed(view, "b")

      assert_push_event(view, "map:set_results", %{points: []})
    end

    test "a search with no matches clears the map", %{conn: conn, bypass: bypass} do
      Bypass.stub(bypass, "GET", "/api", fn c -> Plug.Conn.resp(c, 200, ~s({"features":[]})) end)

      {:ok, view, _html} = live(conn, ~p"/")

      typed(view, "berlin")

      assert_push_event(view, "map:set_results", %{points: []})
    end

    test "an unreachable geocoder clears the map rather than stranding old pins", %{
      conn: conn,
      bypass: bypass
    } do
      {:ok, view, _html} = live(conn, ~p"/")
      typed(view, "berlin")
      assert_push_event(view, "map:set_results", %{points: [_ | _]})

      Bypass.down(bypass)
      typed(view, "berlin again")

      assert_push_event(view, "map:set_results", %{points: []})
    end

    test "selecting a result narrows the map to that one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      typed(view, "berlin")
      assert_push_event(view, "map:set_results", %{points: [first | _]})

      view |> element(~s(#search-results button[phx-value-id="N:1"])) |> render_click()

      assert_push_event(view, "map:set_results", %{points: [only]})
      assert only.label == first.label
    end

    test "selecting puts the label in the box and dismisses the list", %{conn: conn} do
      # Rails did both on commit; leaving the list open under a chosen result
      # makes the next keystroke ambiguous.
      {:ok, view, _html} = live(conn, ~p"/")
      typed(view, "berlin")

      html = view |> element(~s(#search-results button[phx-value-id="N:1"])) |> render_click()

      refute html =~ "search-results"
      refute html =~ "No results"
      assert html =~ ~s(value="Berlin P1, Berlin")
    end
  end

  describe "the query lives in the URL" do
    setup %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/api", fn c ->
        Plug.Conn.resp(
          c,
          200,
          ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin","city":"Berlin","osm_id":1,"osm_type":"N","osm_key":"place","osm_value":"city"}}]})
        )
      end)

      Bypass.stub(bypass, "GET", "/parser", fn c -> Plug.Conn.resp(c, 200, "[]") end)
      Bypass.stub(bypass, "GET", "/parser/search", fn c -> Plug.Conn.resp(c, 200, "[]") end)
      :ok
    end

    test "visiting a search URL runs the search", %{conn: conn} do
      # A shared link has to reproduce what the sender saw, not an empty box.
      {:ok, view, _html} = live(conn, ~p"/?q=berlin")
      html = render_async(view)

      assert html =~ "Berlin"
      assert html =~ ~s(value="berlin")
    end

    test "visiting a search URL marks the map too", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?q=berlin")
      render_async(view)

      assert_push_event(view, "map:set_results", %{points: [_ | _]})
    end

    test "typing writes the query into the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("form[phx-change=search]") |> render_change(%{"q" => "berlin"})

      assert_patch(view, "/?q=berlin")
    end

    test "clearing the box drops the parameter rather than leaving q=", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?q=berlin")
      render_async(view)

      view |> element("form[phx-change=search]") |> render_change(%{"q" => ""})

      assert_patch(view, "/")
    end

    test "a query below the minimum is still reflected, but not searched", %{conn: conn} do
      # The box shows "b", so the URL should too — but Photon is never asked.
      {:ok, view, _html} = live(conn, ~p"/")

      html = view |> element("form[phx-change=search]") |> render_change(%{"q" => "b"})

      assert_patch(view, "/?q=b")
      refute html =~ "Berlin"
    end

    test "other query parameters survive a search", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=settings")

      view |> element("form[phx-change=search]") |> render_change(%{"q" => "berlin"})

      path = assert_patch(view)
      assert path =~ "q=berlin"
      assert path =~ "tab=settings"
    end

    test "picking a result puts its label in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?q=berlin")
      render_async(view)

      view |> element(~s(#search-results button[phx-value-id="N:1"])) |> render_click()

      assert_patch(view, "/?q=Berlin")
    end

    test "an unchanged query does not re-run the search", %{conn: conn} do
      # push_patch feeds handle_params, so a naive implementation searches twice
      # for every keystroke. Re-entering handle_params with the SAME q is the
      # only thing that proves the guard — an unrelated message would pass
      # whether or not the guard exists.
      {:ok, view, _html} = live(conn, ~p"/?q=berlin")
      render_async(view)
      assert_push_event(view, "map:set_results", %{points: [_ | _]})

      view |> element("form[phx-change=search]") |> render_change(%{"q" => "berlin"})

      refute_push_event(view, "map:set_results", %{points: [_ | _]})
    end
  end

  describe "keyboard navigation" do
    setup %{bypass: bypass} do
      features =
        1..3
        |> Enum.map_join(",", fn i ->
          ~s({"geometry":{"coordinates":[13.#{i},52.#{i}]},"properties":{"name":"Berlin P#{i}","city":"Berlin","osm_id":#{i},"osm_type":"N","osm_key":"place","osm_value":"city"}})
        end)

      Bypass.stub(bypass, "GET", "/api", fn c ->
        Plug.Conn.resp(c, 200, ~s({"features":[#{features}]}))
      end)

      Bypass.stub(bypass, "GET", "/parser", fn c -> Plug.Conn.resp(c, 200, "[]") end)
      Bypass.stub(bypass, "GET", "/parser/search", fn c -> Plug.Conn.resp(c, 200, "[]") end)
      :ok
    end

    defp search(view, q) do
      view |> element("form[phx-change=search]") |> render_change(%{"q" => q})
      render_async(view)
      view
    end

    defp active_index(view) do
      view
      |> render()
      |> then(&Regex.scan(~r/data-active="(true|false)"/, &1))
      |> Enum.map(&List.last/1)
      |> Enum.find_index(&(&1 == "true"))
    end

    test "nothing is highlighted until an arrow key is pressed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert active_index(search(view, "berlin")) == nil
    end

    test "arrow down walks forward through the results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")

      render_hook(view, "search_move", %{"dir" => 1})
      assert active_index(view) == 0

      render_hook(view, "search_move", %{"dir" => 1})
      assert active_index(view) == 1
    end

    test "arrow up from nothing wraps to the last result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")

      render_hook(view, "search_move", %{"dir" => -1})
      assert active_index(view) == 2
    end

    test "walking past the end wraps to the start", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")

      for _ <- 1..3, do: render_hook(view, "search_move", %{"dir" => 1})
      assert active_index(view) == 2

      render_hook(view, "search_move", %{"dir" => 1})
      assert active_index(view) == 0
    end

    test "enter flies to the highlighted result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")

      render_hook(view, "search_move", %{"dir" => 1})
      render_hook(view, "search_commit", %{})

      assert_push_event(view, "map:fly_to", %{lat: _, lon: _})
    end

    test "enter with nothing highlighted flies nowhere", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")

      render_hook(view, "search_commit", %{})

      refute_push_event(view, "map:fly_to", %{})
    end

    test "escape dismisses the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")

      render_hook(view, "search_dismiss", %{})

      refute render(view) =~ "data-active"
    end

    test "escape clears the pins as well as the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")
      assert_push_event(view, "map:set_results", %{points: [_ | _]})

      render_hook(view, "search_dismiss", %{})

      assert_push_event(view, "map:set_results", %{points: []})
    end

    test "escape dismisses rather than claiming the search found nothing", %{conn: conn} do
      # Leaving `searched: true` with an empty list makes the panel answer a
      # successful search with "No results for berlin", which is a lie.
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")

      render_hook(view, "search_dismiss", %{})

      refute render(view) =~ "No results"
    end

    test "a fresh search clears any previous highlight", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view = search(view, "berlin")

      render_hook(view, "search_move", %{"dir" => 1})
      assert active_index(view) == 0

      assert active_index(search(view, "berlin2")) == nil
    end
  end

  describe "global search coverage" do
    setup %{bypass: bypass} do
      owner = self()

      Bypass.stub(bypass, "GET", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        send(owner, {:photon_params, conn.query_params})

        Plug.Conn.resp(
          conn,
          200,
          ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"name":"Berlin","osm_id":1,"osm_type":"N"}}]})
        )
      end)

      :ok
    end

    test "collects globally even after the map zooms into a city", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      render_hook(view, "viewport_changed", %{"bbox" => [13.0, 52.3, 13.8, 52.7]})
      search(view, "berlin")

      assert_receive {:photon_params,
                      %{"limit" => "50", "dedupe" => "false", "bbox" => "-180.0,-90.0,180.0,90.0"}}

      assert render(view) =~ "All matches loaded"
    end

    test "zoom and pan preserve the dataset without re-querying Photon", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      search(view, "berlin")
      assert_receive {:photon_params, _}
      assert_push_event(view, "map:set_results", %{points: [_ | _]})
      render_hook(view, "viewport_changed", %{"bbox" => [9.9, 53.4, 10.1, 53.6]})
      refute_receive {:photon_params, _}
      refute_push_event(view, "map:set_results", %{points: [_ | _]})
      assert render(view) =~ "All matches loaded"
    end

    test "panning cannot resurrect dismissed results", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      search(view, "berlin")
      assert_receive {:photon_params, _}
      render_hook(view, "search_dismiss", %{})
      render_hook(view, "viewport_changed", %{"bbox" => [9.9, 53.4, 10.1, 53.6]})
      refute_receive {:photon_params, _}
      refute render(view) =~ "search-results"
    end

    test "a shared link keeps the same global result set", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?q=berlin")
      render_async(view)
      assert_receive {:photon_params, _}

      render_hook(view, "viewport_changed", %{
        "bbox" => [-10.0, 35.0, 30.0, 60.0],
        "programmatic" => true
      })

      refute_receive {:photon_params, _}
      assert render(view) =~ "All matches loaded"
    end
  end

  test "the map receives every match while the sidebar stays bounded", %{
    conn: conn,
    bypass: bypass
  } do
    features =
      Enum.map(1..90, fn id ->
        %{
          "geometry" => %{"coordinates" => [-89 + 2 * id, 20]},
          "properties" => %{"osm_id" => id, "osm_type" => "N", "name" => "Branch #{id}"}
        }
      end)

    Bypass.stub(bypass, "GET", "/api", fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      [w, _, e, _] =
        conn.query_params["bbox"] |> String.split(",") |> Enum.map(&String.to_float/1)

      matches =
        features
        |> Enum.filter(fn f ->
          [lon, _] = f["geometry"]["coordinates"]
          lon >= w and lon <= e
        end)
        |> Enum.take(50)

      Plug.Conn.resp(conn, 200, Jason.encode!(%{features: matches}))
    end)

    {:ok, view, _} = live(conn, ~p"/?q=branch")
    html = render_async(view)
    assert html =~ "All matches loaded"
    assert has_element?(view, "#search-count strong", "90")
    assert length(Regex.scan(~r/phx-click="select_result"/, html)) == 40
    assert_push_event(view, "map:set_results", %{points: [_ | _] = initial, loading: true})
    assert length(initial) == 50
    assert_push_event(view, "map:set_results", %{points: [_ | _] = all, loading: false})
    assert length(all) == 90
    assert MapSet.size(MapSet.new(Enum.map(all, & &1.id))) == 90
  end

  test "dismissal cancels loading and ignores late progress", %{conn: conn, bypass: bypass} do
    owner = self()

    Bypass.stub(bypass, "GET", "/api", fn conn ->
      send(owner, {:held_search, self()})

      receive do
        :finish -> Plug.Conn.resp(conn, 200, ~s({"features":[]}))
      end
    end)

    {:ok, view, _} = live(conn, ~p"/?q=held")
    assert_receive {:held_search, held}
    old_id = :sys.get_state(view.pid).socket.assigns.search_request_id
    # Cancelling the HTTP client deliberately aborts this held Cowboy request.
    # Bypass otherwise turns that expected socket shutdown into an on_exit failure.
    Bypass.pass(bypass)
    render_hook(view, "search_dismiss", %{})
    send(view.pid, {:search_progress, old_id, %{features: [%{id: "stale"}]}})
    send(held, :finish)
    html = render_async(view)
    refute html =~ "Searching all installed data"
    refute html =~ "search-results"
    assert_push_event(view, "map:set_results", %{points: []})
  end

  test "a dismissed query can be submitted again without changing its text", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.stub(bypass, "GET", "/api", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"osm_id":1,"osm_type":"N","name":"Berlin"}}]})
      )
    end)

    {:ok, view, _} = live(conn, ~p"/?q=berlin")
    render_async(view)
    render_hook(view, "search_dismiss", %{})
    refute has_element?(view, "#search-results")
    search(view, "berlin")
    assert has_element?(view, "#search-results")
    assert has_element?(view, "#search-count", "All matches loaded")
  end

  test "status_changed handler does not crash the LiveView", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    send(view.pid, :status_changed)

    # Re-render proves the process is still alive and the message was processed.
    assert render(view) =~ "Search"
  end

  test "point_picked writes value into the From input", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "point_picked", %{"field" => "from", "lat" => 52.5, "lon" => 13.4})

    html = render(view)
    assert html =~ ~s(value="52.500000,13.400000")
  end

  test "point_picked writes value into the To input", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "point_picked", %{"field" => "to", "lat" => 51.0, "lon" => 10.0})

    html = render(view)
    assert html =~ ~s(value="51.000000,10.000000")
  end

  test "pick_point pushes map:enter_picker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "pick_point", %{"field" => "from"})

    # The push_event lands in the view's assigns/push log; assert_push_event helps.
    assert_push_event(view, "map:enter_picker", %{field: "from"})
  end

  test "toggle_region toggles RegionSelection rows", %{conn: conn} do
    import Ecto.Query
    alias Atlas.Control.RegionSelection
    alias Atlas.Repo

    Repo.delete_all(RegionSelection)

    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "toggle_region", %{"name" => "germany"})
    rows = Repo.all(from r in RegionSelection, where: r.region_name == ^"germany")
    assert [%RegionSelection{active: true, region_name: "germany"}] = rows

    render_hook(view, "toggle_region", %{"name" => "germany"})
    assert Repo.all(from r in RegionSelection, where: r.region_name == ^"germany") == []
  end

  test "toggle_service stages an intent instead of starting the service", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Staging must not crash the LiveView even when docker is unavailable.
    render_hook(view, "toggle_service", %{"name" => "photon"})

    html = render(view)
    assert html =~ "Settings"
    # A pending-changes summary now lists photon among the staged enables.
    assert html =~ "Pending changes"
    assert html =~ "photon"
  end

  test "applying a staged service clears the pending summary", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "toggle_service", %{"name" => "photon"})
    assert render(view) =~ "Pending changes"

    render_hook(view, "apply_selection", %{})

    # Safe.call swallows the unavailable ServiceState/RegionApplier; pending clears.
    refute render(view) =~ "Pending changes"
  end

  test "toggling a staged service back to its current state removes it from pending",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "toggle_service", %{"name" => "photon"})
    assert render(view) =~ "Pending changes"

    render_hook(view, "toggle_service", %{"name" => "photon"})
    refute render(view) =~ "Pending changes"
  end

  test "route event pushes map:draw_route with decoded LineString features", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/route" ->
          body =
            ~s({"trip":{"summary":{"length":1.0,"time":60},"legs":[{"shape":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","summary":{"length":1.0,"time":60}}]}})

          Plug.Conn.resp(c, 200, body)

        _ ->
          Plug.Conn.resp(c, 200, "{}")
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "route", %{"from" => "38.5,-120.2", "to" => "43.252,-126.453"})

    assert_push_event(view, "map:draw_route", %{geojson: geojson})

    assert %{type: "FeatureCollection", features: features} = geojson
    assert features != []

    Enum.each(features, fn feature ->
      assert %{type: "Feature", geometry: %{type: "LineString", coordinates: coords}} = feature
      assert is_list(coords)
      assert length(coords) >= 2
    end)
  end

  test "route event with transit mode queries OTP and draws the itinerary", %{
    conn: conn,
    bypass: bypass
  } do
    # Regression: the "transit" mode button must reach OTP, not Valhalla.
    # Valhalla.route/2 raises on an unknown costing, so a misrouted transit
    # request would crash the LiveView instead of returning an itinerary.
    Bypass.expect(bypass, fn c ->
      case c.request_path do
        "/otp/gtfs/v1" ->
          body =
            ~s({"data":{"planConnection":{"edges":[{"node":{"start":1,"end":2,"duration":600,"numberOfTransfers":0,"legs":[{"mode":"BUS","start":1,"end":2,"duration":600,"legGeometry":{"points":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}}]}}]}}})

          Plug.Conn.resp(c, 200, body)

        _ ->
          # A "/route" hit here would mean the request went to Valhalla by mistake.
          Plug.Conn.resp(c, 200, "{}")
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "route", %{
      "from" => "52.5,13.4",
      "to" => "52.6,13.5",
      "mode" => "transit"
    })

    assert_push_event(view, "map:draw_route", %{geojson: geojson})
    assert %{type: "FeatureCollection", features: features} = geojson
    assert features != []
    # Transit leg geometry is google_polyline5; decoding must yield real points.
    Enum.each(features, fn feature ->
      assert %{type: "Feature", geometry: %{type: "LineString", coordinates: coords}} = feature
      assert length(coords) >= 2
    end)
  end

  describe "service logs modal" do
    test "opens full-page, streams lines, and closes from the root LiveView", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=settings")

      view
      |> element("button[phx-click=settings_tab][phx-value-tab=services]")
      |> render_click()

      view
      |> element(~s(button[phx-click=open_logs][phx-value-name=photon]))
      |> render_click()

      html = render(view)
      # Full-page overlay (fixed to the viewport, not absolute inside the panel).
      assert html =~ ~s(data-role="logs-modal")
      assert html =~ "fixed inset-0"
      assert html =~ "Waiting for log output…" or html =~ "Could not start the log stream"

      send(view.pid, {:log_line, "photon booted"})
      assert render(view) =~ "photon booted"

      view |> element("button[phx-click=close_logs]") |> render_click()
      refute render(view) =~ ~s(data-role="logs-modal")
    end

    test "modal panel does not swallow clicks with stopPropagation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=settings")

      view
      |> element("button[phx-click=settings_tab][phx-value-tab=services]")
      |> render_click()

      view
      |> element(~s(button[phx-click=open_logs][phx-value-name=photon]))
      |> render_click()

      refute render(view) =~ "stopPropagation"
    end
  end

  # The settings panel's inline progress card now renders `Atlas.Control.ApplyTimeline`
  # broadcasts (see AtlasWeb.SettingsPanelTest), not this `apply_status` bookkeeping.
  # `apply_status` still drives the flash banners exercised below.
  describe "apply status flashes" do
    test "apply_error surfaces a flash with the phase and reason", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      job_id = Ecto.UUID.generate()

      send(view.pid, {:apply_start, %{job_id: job_id, regions: ["berlin"]}})

      send(
        view.pid,
        {:apply_progress, %{job_id: job_id, phase: :downloading, region: "berlin", progress: 0.4}}
      )

      send(
        view.pid,
        {:apply_error, %{job_id: job_id, phase: :downloading, reason: "HTTP 503"}}
      )

      html = render(view)
      assert html =~ "Region apply failed"
      assert html =~ "HTTP 503"
    end

    test "apply_done surfaces a flash naming the applied regions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      job_id = Ecto.UUID.generate()
      send(view.pid, {:apply_start, %{job_id: job_id, regions: ["berlin"]}})

      send(view.pid, {:apply_done, %{job_id: job_id, regions: ["berlin"]}})
      assert render(view) =~ "Regions applied: berlin"
    end
  end
end
