defmodule AtlasWeb.Schemas do
  @moduledoc """
  OpenAPI schemas for `/api/v1/*`.

  M1: every endpoint shares a minimal `{data, meta}` envelope (`type: :object`).
  M4 will tighten these into per-endpoint response schemas mirroring the
  byte-diff parity goldens.
  """
  alias OpenApiSpex.Schema

  defmodule Error do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{error: %Schema{type: :object}}
    })
  end

  defmodule Response do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Response",
      type: :object,
      properties: %{
        data: %Schema{type: :object},
        meta: %Schema{type: :object}
      }
    })
  end
end
