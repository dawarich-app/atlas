defmodule AtlasWeb.Api.V1.FallbackController do
  @moduledoc """
  Translates orchestrator/control-flow error tuples into HTTP responses.

  Wired into every controller via `action_fallback`. Any `{:error, _}` that
  flows out of an action's `with` chain is dispatched here.

  Status mapping (parity with Rails):

  - `{:error, %Unavailable{}}` → 503 `UPSTREAM_UNAVAILABLE`
  - `{:error, %BadResponse{}}` → 502 `UPSTREAM_ERROR`
  - `{:error, :missing, param}` → 400 `MISSING_PARAM`
  - `{:error, :invalid, message, details}` → 422 `VALIDATION_ERROR`
  - `{:error, :too_many, max}` → 422 `VALIDATION_ERROR`
  """
  use AtlasWeb, :controller
  alias Atlas.Maps.Upstream.Client.{Unavailable, BadResponse}
  alias AtlasWeb.Api.V1.BaseController

  def call(conn, {:error, %Unavailable{message: m}}) do
    BaseController.error(conn, :service_unavailable, "UPSTREAM_UNAVAILABLE", m)
  end

  def call(conn, {:error, %BadResponse{message: m, status: s}}) do
    BaseController.error(conn, :bad_gateway, "UPSTREAM_ERROR", "upstream returned #{s}: #{m}")
  end

  def call(conn, {:error, :missing, param}) do
    BaseController.missing_param(conn, param)
  end

  def call(conn, {:error, :invalid, message, details}) when is_map(details) do
    BaseController.validation_error(conn, message, details)
  end

  def call(conn, {:error, :too_many, max}) do
    BaseController.validation_error(conn, "too many items, max #{max}", %{max: max})
  end
end
