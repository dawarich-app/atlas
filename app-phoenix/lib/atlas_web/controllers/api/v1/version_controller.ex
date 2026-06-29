defmodule AtlasWeb.Api.V1.VersionController do
  @moduledoc """
  `GET /api/v1/version` — the running app's version and build revision, for
  support requests and integrations (Dawarich shows its backend versions the
  same way).
  """

  use AtlasWeb, :controller

  def show(conn, _params) do
    json(conn, %{
      data: %{version: Atlas.Version.version(), revision: Atlas.Version.revision()}
    })
  end
end
