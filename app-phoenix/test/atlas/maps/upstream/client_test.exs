defmodule Atlas.Maps.Upstream.ClientTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.Client
  alias Atlas.Maps.Upstream.Client.{BadResponse, Unavailable}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
  end

  test "returns {:ok, body} on 200", %{bypass: bypass, base_url: base_url} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"hello":"world"}))
      |> Plug.Conn.put_resp_content_type("application/json")
    end)

    req = Client.build(base_url)
    assert {:ok, %{"hello" => "world"}} = Client.get(req, "/api")
  end

  test "returns {:error, BadResponse} on 500", %{bypass: bypass, base_url: base_url} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn -> Plug.Conn.resp(conn, 500, "boom") end)
    req = Client.build(base_url)
    assert {:error, %BadResponse{status: 500}} = Client.get(req, "/api")
  end

  test "returns {:error, Unavailable} when port is closed", %{bypass: bypass, base_url: base_url} do
    Bypass.down(bypass)
    req = Client.build(base_url, open_timeout: 100, timeout: 100)
    assert {:error, %Unavailable{}} = Client.get(req, "/api")
  end

  test "encodes repeated query keys", %{bypass: bypass, base_url: base_url} do
    Bypass.expect_once(bypass, "GET", "/api", fn conn ->
      assert conn.query_string == "osm_tag=amenity%3Acafe&osm_tag=tourism%3Ahotel"
      Plug.Conn.resp(conn, 200, "{}")
    end)

    req = Client.build(base_url)
    Client.get(req, "/api", [{"osm_tag", "amenity:cafe"}, {"osm_tag", "tourism:hotel"}])
  end

  describe "upstream error bodies" do
    test "BadResponse carries the decoded body so callers can read the upstream reason", %{
      bypass: bypass,
      base_url: base_url
    } do
      # Without this, an upstream that explains itself in the body (Valhalla's
      # error_code, Photon's message) is reduced to a bare status, and the
      # caller has to invent a reason to show the user.
      Bypass.expect_once(bypass, "POST", "/api", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          400,
          ~s({"error_code":154,"error":"Path distance exceeds the max distance limit"})
        )
      end)

      req = Client.build(base_url)

      assert {:error, %BadResponse{status: 400, body: body}} = Client.post(req, "/api", %{})
      assert body["error_code"] == 154
      assert body["error"] =~ "max distance limit"
    end

    test "a non-JSON error body is still carried through", %{bypass: bypass, base_url: base_url} do
      Bypass.expect_once(bypass, "GET", "/api", fn conn ->
        Plug.Conn.resp(conn, 502, "upstream died")
      end)

      req = Client.build(base_url)

      assert {:error, %BadResponse{status: 502, body: "upstream died"}} = Client.get(req, "/api")
    end
  end

  describe "env_int/2" do
    test "reads an integer, and falls back for unset or unparseable values" do
      on_exit(fn -> System.delete_env("ATLAS_TEST_ENV_INT") end)

      assert Client.env_int("ATLAS_TEST_ENV_INT", 42) == 42

      System.put_env("ATLAS_TEST_ENV_INT", "7")
      assert Client.env_int("ATLAS_TEST_ENV_INT", 42) == 7

      # A typo must not 500 every request that reads the knob.
      System.put_env("ATLAS_TEST_ENV_INT", "10k")
      assert Client.env_int("ATLAS_TEST_ENV_INT", 42) == 42
    end

    test "an unset-but-declared knob falls back silently, a bad value warns" do
      # compose renders `${VAR:-}` as "" for every declared-but-unset knob, so
      # "" is the NORMAL case and must stay quiet — warning on it would log a
      # line per request per knob. A genuine typo must still be reported, so
      # asserting only the return value cannot tell the two apart.
      on_exit(fn -> System.delete_env("ATLAS_TEST_ENV_INT") end)

      System.put_env("ATLAS_TEST_ENV_INT", "")

      empty_log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Client.env_int("ATLAS_TEST_ENV_INT", 42) == 42
        end)

      System.put_env("ATLAS_TEST_ENV_INT", "nonsense")

      bad_log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Client.env_int("ATLAS_TEST_ENV_INT", 42) == 42
        end)

      assert empty_log == ""
      assert bad_log =~ "ATLAS_TEST_ENV_INT"
      assert bad_log =~ "not an integer"
    end
  end
end
