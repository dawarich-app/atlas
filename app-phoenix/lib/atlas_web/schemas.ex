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

  defmodule CoverageDataset do
    @moduledoc false
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "CoverageDataset",
      type: :object,
      required: [:label, :kind, :evidence, :source],
      properties: %{
        label: %Schema{type: :string},
        kind: %Schema{type: :string},
        evidence: %Schema{type: :string},
        source: %Schema{type: :string},
        bounds: %Schema{type: :string, nullable: true},
        date: %Schema{type: :string, nullable: true}
      }
    })
  end

  defmodule CoverageTransitFeed do
    @moduledoc false
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "CoverageTransitFeed",
      type: :object,
      required: [:name, :coverage, :evidence],
      properties: %{
        name: %Schema{type: :string},
        coverage: %Schema{type: :string},
        evidence: %Schema{type: :string}
      }
    })
  end

  defmodule CoverageCapability do
    @moduledoc false
    require OpenApiSpex
    alias AtlasWeb.Schemas.{CoverageDataset, CoverageTransitFeed}
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "CoverageCapability",
      type: :object,
      required: [:available, :coverage_status, :datasets, :note, :regions, :service, :status],
      properties: %{
        available: %Schema{type: :boolean},
        coverage_status: %Schema{type: :string, enum: ["known", "unknown"]},
        datasets: %Schema{type: :array, items: CoverageDataset},
        note: %Schema{type: :string},
        regions: %Schema{type: :array, items: %Schema{type: :string}},
        service: %Schema{type: :string},
        status: %Schema{type: :string, enum: ["up", "down", "starting"]},
        inherits: %Schema{type: :string, enum: ["routing"]},
        transit_feeds: %Schema{type: :array, items: CoverageTransitFeed}
      }
    })
  end

  defmodule CoverageData do
    @moduledoc false
    require OpenApiSpex
    alias AtlasWeb.Schemas.CoverageCapability
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "CoverageData",
      type: :object,
      required: [:capabilities],
      properties: %{
        capabilities: %Schema{
          type: :object,
          required: [:geocoding, :routing, :map_matching, :pois, :transit],
          properties: %{
            geocoding: CoverageCapability,
            routing: CoverageCapability,
            map_matching: CoverageCapability,
            pois: CoverageCapability,
            transit: CoverageCapability
          }
        }
      }
    })
  end

  defmodule CoverageResponse do
    @moduledoc false
    require OpenApiSpex
    alias AtlasWeb.Schemas.CoverageData
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "CoverageResponse",
      type: :object,
      required: [:data, :meta],
      properties: %{
        data: CoverageData,
        meta: %Schema{
          type: :object,
          required: [:timestamp],
          properties: %{timestamp: %Schema{type: :string, format: :"date-time"}}
        }
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
