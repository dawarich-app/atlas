defmodule AtlasWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP Basic Auth plug guarding `/admin/*` routes.

  Credentials are read from `ADMIN_USERNAME` / `ADMIN_PASSWORD` env vars
  at request time (not compile time) so the plug picks up `.env` reloads
  from `docker compose restart`.

  If either env var is missing or blank, the plug halts with HTTP 503 and
  an instructive message. This avoids the worse failure mode where a
  missing env var falls through to a permissive default.
  """
  import Plug.Conn

  @realm "Dawarich Atlas admin"

  def init(opts), do: opts

  def call(conn, _opts) do
    user = System.get_env("ADMIN_USERNAME")
    pass = System.get_env("ADMIN_PASSWORD")

    if blank?(user) or blank?(pass) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(:service_unavailable,
        "Admin panel unconfigured. Set ADMIN_USERNAME and ADMIN_PASSWORD in .env, then `docker compose restart`."
      )
      |> halt()
    else
      Plug.BasicAuth.basic_auth(conn, username: user, password: pass, realm: @realm)
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""
end
