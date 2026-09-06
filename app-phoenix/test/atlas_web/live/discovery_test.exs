defmodule AtlasWeb.DiscoveryTest do
  use AtlasWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    bypass = Bypass.open()
    old = Map.new(~w(PHOTON_URL OVERPASS_URL), &{&1, System.get_env(&1)})
    Enum.each(old, fn {name, _} -> System.put_env(name, "http://localhost:#{bypass.port}") end)

    on_exit(fn ->
      Enum.each(old, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    %{bypass: bypass}
  end

  defp photon(bypass, owner) do
    Bypass.stub(bypass, "GET", "/api", fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(owner, {:photon, conn.query_params})

      Plug.Conn.resp(
        conn,
        200,
        ~s({"features":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"osm_type":"N","osm_id":1,"name":"McDonald's","osm_value":"fast_food"}}]})
      )
    end)
  end

  defp overpass(bypass, owner) do
    Bypass.stub(bypass, "POST", "/api/interpreter", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:overpass, body})

      Plug.Conn.resp(
        conn,
        200,
        ~s({"elements":[{"type":"node","id":2,"lat":52.51,"lon":13.41,"tags":{"name":"Corner Café","amenity":"cafe"}}]})
      )
    end)
  end

  test "a name works immediately; adding and removing a category preserves it", %{
    conn: conn,
    bypass: bypass
  } do
    photon(bypass, self())
    {:ok, view, _} = live(conn, "/?q=McDonalds")
    render_async(view)
    assert_receive {:photon, params}
    refute Map.has_key?(params, "osm_tag")
    refute has_element?(view, ~s(button[aria-label="Places"]))

    render_hook(view, "toggle_category", %{"id" => "fast_food"})
    render_async(view)
    assert_receive {:photon, %{"q" => "McDonalds", "osm_tag" => "amenity:fast_food"}}
    assert has_element?(view, ~s(button[aria-label="Remove Fast food"]))

    render_hook(view, "toggle_category", %{"id" => "fast_food"})
    render_async(view)
    assert_receive {:photon, params}
    refute Map.has_key?(params, "osm_tag")
    assert has_element?(view, ~s(#search-input[value="McDonalds"]))
  end

  test "category suggestions require explicit selection, then load places without text", %{
    conn: conn,
    bypass: bypass
  } do
    photon(bypass, self())
    overpass(bypass, self())
    {:ok, view, _} = live(conn, "/?q=cafe")
    render_async(view)
    assert has_element?(view, ~s(#category-suggestions button[phx-value-id="cafe"]), "Category")
    refute has_element?(view, ~s(button[aria-label="Remove Café"]))
    assert_receive {:photon, _}

    render_hook(view, "choose_category", %{"id" => "cafe"})
    html = render_async(view)
    assert_receive {:overpass, body}
    assert body =~ ~s(node["amenity"="cafe"])
    assert body =~ ~s(relation["amenity"="cafe"])
    assert html =~ "Corner Café"
    assert has_element?(view, ~s(#search-input[value=""]))
    assert_push_event(view, "map:set_results", %{points: [%{label: "Corner Café", id: "N:2"}]})
  end

  test "an area is frozen until Search here, and the URL restores filters", %{
    conn: conn,
    bypass: bypass
  } do
    photon(bypass, self())
    {:ok, view, _} = live(conn, "/?q=McDonalds&categories=fast_food&scope=area&bbox=13,52,14,53")
    render_async(view)
    assert_receive {:photon, %{"bbox" => "13.0,52.0,14.0,53.0", "osm_tag" => "amenity:fast_food"}}
    render_hook(view, "viewport_changed", %{"bbox" => [10.0, 50.0, 11.0, 51.0]})
    assert has_element?(view, "#search-area-changed", "previously searched area")
    refute_receive {:photon, _}
    render_hook(view, "search_here", %{})
    render_async(view)
    assert_receive {:photon, %{"bbox" => "10.0,50.0,11.0,51.0"}}
    refute has_element?(view, "#search-area-changed")
  end

  test "reset clears the text, categories, list and markers", %{conn: conn, bypass: bypass} do
    photon(bypass, self())
    {:ok, view, _} = live(conn, "/?q=McDonalds&categories=fast_food")
    render_async(view)
    render_hook(view, "search_reset", %{})
    assert has_element?(view, ~s(#search-input[value=""]))
    refute has_element?(view, ~s(button[aria-label="Remove Fast food"]))
    refute has_element?(view, "#search-results")
    assert_push_event(view, "map:set_results", %{points: []})
  end

  test "selecting a category after choosing an address clears the address query", %{
    conn: conn,
    bypass: bypass
  } do
    photon(bypass, self())
    overpass(bypass, self())
    {:ok, view, _} = live(conn, "/?q=Berlin")
    render_async(view)
    render_hook(view, "select_result", %{"id" => "N:1"})
    render_hook(view, "viewport_changed", %{"bbox" => [13.0, 52.0, 14.0, 53.0]})
    render_hook(view, "search_scope", %{"scope" => "area"})
    render_async(view)
    render_hook(view, "toggle_category", %{"id" => "cafe"})
    render_async(view)
    assert_receive {:overpass, _}
    assert has_element?(view, ~s(#search-input[value=""]))
  end

  test "an empty filtered response offers an escape and does not claim failure", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.stub(bypass, "GET", "/api", &Plug.Conn.resp(&1, 200, ~s({"features":[]})))
    {:ok, view, _} = live(conn, "/?q=missing&categories=cafe")
    html = render_async(view)
    assert html =~ "No results for"
    assert has_element?(view, ~s(button[phx-click="clear_categories"]), "Search all categories")
    refute html =~ "not responding"
  end

  test "Overpass timeout remarks are incomplete even with an HTTP 200", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.stub(
      bypass,
      "POST",
      "/api/interpreter",
      &Plug.Conn.resp(&1, 200, ~s({"elements":[],"remark":"runtime error: timeout"}))
    )

    {:ok, view, _} = live(conn, "/?categories=cafe")
    html = render_async(view)
    refute html =~ "No places found"
    refute html =~ "All matches loaded"
    assert has_element?(view, ~s(button[phx-click="search_retry"]))
  end

  test "multiple categories form a union and relation results remain clickable", %{
    conn: conn,
    bypass: bypass
  } do
    owner = self()

    Bypass.stub(bypass, "POST", "/api/interpreter", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:query, body})

      Plug.Conn.resp(
        conn,
        200,
        ~s({"elements":[{"type":"relation","id":99,"center":{"lat":52.51,"lon":13.41},"tags":{"name":"Dinner","amenity":"restaurant"}}]})
      )
    end)

    {:ok, view, _} = live(conn, "/?categories=cafe,restaurant")
    html = render_async(view)
    assert html =~ "Matches any selected category"
    assert_receive {:query, body}
    assert body =~ ~s(node["amenity"="cafe"])
    assert body =~ ~s(node["amenity"="restaurant"])

    assert_push_event(view, "map:set_results", %{
      points: [%{id: "R:99", osm_url: "https://www.openstreetmap.org/relation/99"}]
    })

    render_hook(view, "select_result", %{"id" => "R:99"})
    assert_push_event(view, "map:fly_to", %{lat: 52.51, lon: 13.41, zoom: 14})
  end
end
