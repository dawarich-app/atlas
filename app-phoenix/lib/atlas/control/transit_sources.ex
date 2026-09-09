defmodule Atlas.Control.TransitSources do
  @moduledoc "Transport source configuration, independent of street-data regions."
  alias Atlas.{Control.RegionApplier, Settings}
  @key "transit_sources"

  def catalog do
    Application.app_dir(:atlas, "priv/transit/providers.json") |> File.read!() |> Jason.decode!()
  end

  def configured?, do: Settings.get(@key) != nil
  def all, do: read(@key, [])
  def enabled, do: Enum.filter(all(), & &1["enabled"])

  def fingerprint(sources),
    do:
      :crypto.hash(:sha256, sources |> Enum.sort_by(& &1["id"]) |> :erlang.term_to_binary())
      |> Base.encode16(case: :lower)

  def pending?,
    do: configured?() and fingerprint(enabled()) != Settings.get("transit_sources_applied")

  def statuses, do: read("transit_source_status", %{})

  def put_status(id, status) do
    Settings.set("transit_source_status", Jason.encode!(Map.put(statuses(), id, status)))
  end

  def connect(id) do
    case Enum.find(catalog(), &(&1["id"] == id)) do
      nil -> {:error, "Unknown transport source."}
      source -> save(Map.merge(source, %{"enabled" => true, "realtime" => true}))
    end
  end

  def add(params) do
    source = %{
      "id" => "custom-" <> Ecto.UUID.generate(),
      "name" => String.trim(params["name"] || ""),
      "coverage" => String.trim(params["coverage"] || ""),
      "url" => String.trim(params["url"] || ""),
      "realtime_url" => String.trim(params["realtime_url"] || ""),
      "license" => "User-provided source — check provider terms",
      "license_url" => String.trim(params["license_url"] || ""),
      "header_name" => String.trim(params["header_name"] || ""),
      "header_value" => String.trim(params["header_value"] || ""),
      "enabled" => true,
      "realtime" => params["realtime_url"] not in [nil, ""]
    }

    with :ok <- validate(source), do: save(source)
  end

  def update(id, params) do
    case Enum.find(all(), &(&1["id"] == id)) do
      nil ->
        {:error, "Unknown transport source."}

      source ->
        changes = Map.take(params, ~w(name coverage url realtime_url license_url header_name))
        updated = Map.merge(source, Map.new(changes, fn {k, v} -> {k, String.trim(v)} end))

        updated =
          cond do
            params["clear_key"] == "true" ->
              Map.put(updated, "header_value", "")

            params["header_value"] not in [nil, ""] ->
              Map.put(updated, "header_value", String.trim(params["header_value"]))

            true ->
              updated
          end

        updated =
          if updated["url"] != source["url"] or updated["realtime_url"] != source["realtime_url"],
            do:
              updated
              |> Map.drop(~w(regions commercial notice attribution website))
              |> Map.put("license", "User-provided source — check provider terms"),
            else: updated

        with :ok <- validate(updated), do: save(updated)
    end
  end

  def toggle(id, field) when field in ~w(enabled realtime) do
    case Enum.find(all(), &(&1["id"] == id)) do
      nil -> {:error, "Unknown transport source."}
      source -> save(Map.update!(source, field, &(!&1)))
    end
  end

  def validate(source) do
    cond do
      source["name"] == "" ->
        {:error, "Enter a source name."}

      not valid_url?(source["url"]) ->
        {:error, "Enter an HTTP or HTTPS URL for the GTFS ZIP."}

      source["realtime_url"] not in [nil, ""] and not valid_url?(source["realtime_url"]) ->
        {:error, "Enter an HTTP or HTTPS URL for GTFS-RT."}

      source["license_url"] not in [nil, ""] and not valid_url?(source["license_url"]) ->
        {:error, "Enter an HTTP or HTTPS URL for the license."}

      true ->
        validate_header(source)
    end
  end

  defp validate_header(source) do
    cond do
      source["header_name"] not in [nil, ""] and
          not Regex.match?(~r/\A[A-Za-z0-9-]+\z/, source["header_name"]) ->
        {:error, "Use a valid HTTP header name, such as Authorization."}

      String.contains?(source["header_value"] || "", ["\r", "\n"]) ->
        {:error, "The API key must be a single line."}

      true ->
        :ok
    end
  end

  def valid_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme in ["https", "http"] and uri.host not in [nil, ""] and is_nil(uri.userinfo)
  end

  def valid_url?(_), do: false

  def headers(source) do
    base = %{"User-Agent" => "DawarichAtlas/0.5 (https://github.com/dawarich/atlas)"}

    if source["header_name"] not in [nil, ""] and source["header_value"] not in [nil, ""],
      do: Map.put(base, source["header_name"], source["header_value"]),
      else: base
  end

  def refresh do
    if configured?() do
      RegionApplier.start([], services: [Settings.transit_backend()], transit_only: true)
    else
      {:error, "Connect a transport source first."}
    end
  end

  defp save(source) do
    current = Atlas.Control.Safe.call(&RegionApplier.status/0, nil)

    if current && not Map.has_key?(current, :error) do
      {:error, "An installation is in progress. Try again when it finishes."}
    else
      sources = all()
      duplicate = Enum.any?(sources, &(&1["id"] != source["id"] and &1["url"] == source["url"]))

      if duplicate do
        {:error, "This GTFS URL is already connected."}
      else
        sources = Enum.reject(sources, &(&1["id"] == source["id"])) ++ [source]
        Settings.set(@key, Jason.encode!(sources))
        :ok
      end
    end
  end

  defp read(key, fallback) do
    case Jason.decode(Settings.get(key, "null")) do
      {:ok, nil} -> fallback
      {:ok, value} -> value
      _ -> fallback
    end
  end
end
