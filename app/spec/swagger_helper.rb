require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "Dawarich Atlas API",
        version: "v1",
        description: "Local-first geocoding, routing, and POI lookup. " \
                     "All endpoints aggregate one or more upstream OSM-derived services " \
                     "(Photon, Placeholder, libpostal, Valhalla, Overpass)."
      },
      servers: [
        { url: "{scheme}://{host}", variables: {
            scheme: { default: "http", enum: %w[http https] },
            host:   { default: "localhost:8484" }
        } }
      ],
      paths: {},
      components: {
        schemas: {
          ErrorEnvelope: {
            type: :object,
            required: %w[error],
            properties: {
              error: {
                type: :object,
                required: %w[code message],
                properties: {
                  code:    { type: :string, example: "VALIDATION_ERROR" },
                  message: { type: :string },
                  details: { type: :array, items: { type: :object } }
                }
              }
            }
          },
          Coords: {
            type: :object,
            required: %w[lat lon],
            properties: {
              lat: { type: :number, format: :double, example: 52.5200 },
              lon: { type: :number, format: :double, example: 13.4050 }
            }
          },
          AdminHierarchy: {
            type: :object,
            properties: {
              country:  { type: :string, nullable: true, example: "Germany" },
              state:    { type: :string, nullable: true, example: "Berlin" },
              county:   { type: :string, nullable: true },
              city:     { type: :string, nullable: true, example: "Berlin" },
              postcode: { type: :string, nullable: true }
            }
          },
          GeocodeFeature: {
            type: :object,
            required: %w[id label coords],
            properties: {
              id:     { type: :string, example: "node:240109189" },
              name:   { type: :string, nullable: true, example: "Berlin" },
              label:  { type: :string, example: "Berlin, Germany" },
              type:   { type: :string, nullable: true, example: "city" },
              coords: { "$ref" => "#/components/schemas/Coords" },
              admin:  { "$ref" => "#/components/schemas/AdminHierarchy" }
            }
          },
          ResponseMeta: {
            type: :object,
            properties: {
              timestamp: { type: :string, format: "date-time" },
              upstream:  { type: :string, example: "ok" },
              count:     { type: :integer, example: 5 }
            }
          },
          SearchResponse: {
            type: :object,
            properties: {
              data: { type: :array, items: { "$ref" => "#/components/schemas/GeocodeFeature" } },
              meta: { "$ref" => "#/components/schemas/ResponseMeta" }
            }
          },
          ReverseResponse: {
            type: :object,
            properties: {
              data: {
                type: :object,
                properties: {
                  here:  { "$ref" => "#/components/schemas/GeocodeFeature", nullable: true },
                  admin: { "$ref" => "#/components/schemas/AdminHierarchy" }
                }
              },
              meta: { "$ref" => "#/components/schemas/ResponseMeta" }
            }
          },
          BatchReverseRequest: {
            type: :object,
            required: %w[coords],
            properties: {
              coords: {
                type: :array,
                maxItems: 500,
                items: {
                  type: :object,
                  required: %w[lat lon],
                  properties: {
                    id:  { type: :string, nullable: true, example: "p_42" },
                    lat: { type: :number, format: :double, example: 52.5163 },
                    lon: { type: :number, format: :double, example: 13.3777 }
                  }
                }
              },
              lang: { type: :string, nullable: true, example: "de" }
            }
          },
          BatchReverseResponse: {
            type: :object,
            properties: {
              data: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    id:    { type: :string, nullable: true },
                    coord: { "$ref" => "#/components/schemas/Coords" },
                    here:  { "$ref" => "#/components/schemas/GeocodeFeature", nullable: true },
                    admin: { "$ref" => "#/components/schemas/AdminHierarchy" },
                    error: { type: :string, nullable: true }
                  }
                }
              },
              meta: {
                allOf: [
                  { "$ref" => "#/components/schemas/ResponseMeta" },
                  { type: :object, properties: {
                      cache_hits:      { type: :integer, example: 184 },
                      cache_misses:    { type: :integer, example: 16 },
                      upstream_errors: { type: :integer, example: 0 },
                      grid_precision:  { type: :integer, example: 4, description: "Decimal places used for cache-key snapping (4 ≈ 11 m)" },
                      max_coords:      { type: :integer, example: 500 }
                  } }
                ]
              }
            }
          },
          WhatsHereResponse: {
            type: :object,
            properties: {
              data: {
                type: :object,
                properties: {
                  here:   { type: :object, nullable: true },
                  nearby: { type: :array, items: { type: :object } }
                }
              },
              meta: { "$ref" => "#/components/schemas/ResponseMeta" }
            }
          },
          RouteResponse: {
            type: :object,
            properties: {
              data: {
                type: :object,
                properties: {
                  summary:      { type: :object },
                  legs:         { type: :array, items: { type: :object } },
                  shape_format: { type: :string, example: "valhalla_encoded_polyline6" }
                }
              },
              meta: { "$ref" => "#/components/schemas/ResponseMeta" }
            }
          },
          GeocodeResponse: {
            type: :object,
            description: "Union of forward and reverse responses depending on which params are supplied.",
            properties: {
              data: { oneOf: [
                { "$ref" => "#/components/schemas/GeocodeFeature" },
                { type: :array, items: { "$ref" => "#/components/schemas/GeocodeFeature" } },
                { type: :object,
                  description: "Reverse-geocode wrapper",
                  properties: {
                    here:  { "$ref" => "#/components/schemas/GeocodeFeature", nullable: true },
                    admin: { "$ref" => "#/components/schemas/AdminHierarchy" }
                  }
                }
              ] },
              meta: { "$ref" => "#/components/schemas/ResponseMeta" }
            }
          }
        }
      }
    },
    "admin/swagger.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "Dawarich Atlas Admin API",
        version: "admin",
        description: "Admin panel endpoints (HTTP Basic auth via ADMIN_USERNAME / ADMIN_PASSWORD)."
      },
      servers: [
        { url: "{scheme}://{host}",
          variables: { scheme: { default: "http", enum: %w[http https] },
                       host: { default: "localhost:8484" } } }
      ],
      components: {
        securitySchemes: {
          basicAuth: { type: :http, scheme: :basic }
        },
        schemas: {
          ServiceSnapshot: {
            type: :object,
            properties: {
              name:       { type: :string },
              enabled:    { type: :boolean },
              status:     { type: :string },
              phase:      { type: :string, nullable: true },
              progress:   { type: :number, nullable: true },
              disk_bytes: { type: :integer }
            }
          },
          ApplyProjectionResponse: {
            type: :object,
            properties: {
              projection: {
                type: :object,
                properties: {
                  total_disk_gb:    { type: :number },
                  first_boot_hours: { type: :number },
                  lines:            { type: :array, items: { type: :object } }
                }
              }
            }
          }
        }
      },
      security: [{ basicAuth: [] }],
      paths: {}
    }
  }

  config.openapi_format = :yaml
end

# Default Authorization value for any rswag spec — required because admin/swagger.yaml
# declares a global `security: [{ basicAuth: [] }]` and rswag-specs resolves header
# parameters by calling a `let` of the same name on the spec context. Specs that
# actually exercise auth can override; everyone else gets a no-op nil.
RSpec.shared_context "rswag default Authorization", type: :request do
  let(:Authorization) { nil }
end
RSpec.configure { |c| c.include_context "rswag default Authorization", type: :request }
