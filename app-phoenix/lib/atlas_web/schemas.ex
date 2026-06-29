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

  defmodule Place do
    @moduledoc false
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Place",
      description: "Canonical geocoding result shared by search/reverse/geocode.",
      type: :object,
      properties: %{
        id: %Schema{type: :string, example: "W:42"},
        name: %Schema{type: :string, nullable: true},
        label: %Schema{type: :string},
        type: %Schema{type: :string, nullable: true},
        coords: %Schema{
          type: :object,
          properties: %{lat: %Schema{type: :number}, lon: %Schema{type: :number}}
        },
        admin: %Schema{
          type: :object,
          description: "Legacy admin block (deprecated; use address)."
        },
        address: %Schema{
          type: :object,
          properties: %{
            house_number: %Schema{type: :string, nullable: true},
            street: %Schema{type: :string, nullable: true},
            city: %Schema{type: :string, nullable: true},
            county: %Schema{type: :string, nullable: true},
            state: %Schema{type: :string, nullable: true},
            postcode: %Schema{type: :string, nullable: true},
            country: %Schema{type: :string, nullable: true},
            countrycode: %Schema{type: :string, nullable: true}
          }
        },
        match_type: %Schema{
          type: :string,
          enum: ["rooftop", "street", "locality", "region", "country", "unknown"]
        },
        confidence: %Schema{
          type: :number,
          nullable: true,
          description: "Reserved for enrichment (SP3); null today."
        }
      }
    })
  end
end
