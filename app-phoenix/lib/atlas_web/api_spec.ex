defmodule AtlasWeb.ApiSpec do
  @moduledoc """
  OpenAPI 3.0 spec for the Dawarich Atlas API.

  Paths are built from `AtlasWeb.Router` by walking controller
  `operation/2` annotations. The rendered spec is served at
  `GET /api/v1/openapi.json`.

  At M1 schemas are intentionally minimal (`type: :object`). M4's parity
  cutover will tighten the schemas so the spec doubles as a request/response
  contract.
  """
  alias OpenApiSpex.{Info, OpenApi, Paths, Server}
  @behaviour OpenApi

  @impl true
  def spec do
    %OpenApi{
      info: %Info{title: "Dawarich Atlas API", version: "2.0.0"},
      servers: [%Server{url: "/"}],
      paths: Paths.from_router(AtlasWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
