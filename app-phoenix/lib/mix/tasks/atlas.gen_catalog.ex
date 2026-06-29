defmodule Mix.Tasks.Atlas.GenCatalog do
  @moduledoc """
  Regenerate `priv/regions/catalog.json` from the Geofabrik index and the
  BBBike city list. Build/CI-time only — never runs on user hardware.

      mix atlas.gen_catalog
      mix atlas.gen_catalog --out /tmp/catalog.json

  By default it fetches the Geofabrik index + BBBike directory over HTTP and
  issues one HTTP HEAD per PBF URL for real sizes (HEAD failures leave the size
  null). When the build host cannot reach an upstream (e.g. Geofabrik blocks the
  egress IP), feed locally-obtained index files instead:

      mix atlas.gen_catalog \\
        --geofabrik-file index-v1-nogeom.json \\
        --bbbike-file bbbike-index.html \\
        --no-sizes

  Options:

    * `--out PATH`             — output file (default `priv/regions/catalog.json`)
    * `--geofabrik-file PATH`  — read the Geofabrik index JSON from disk instead of HTTP
    * `--bbbike-file PATH`     — read the BBBike directory HTML from disk instead of HTTP
    * `--no-geofabrik`         — skip Geofabrik entirely; build a cities-only catalog
                                 from BBBike alone. Use when Geofabrik is unreachable.
    * `--no-sizes`             — skip the HEAD size probes (all `pbf_bytes` null; the
                                 UI falls back to coarse tier hints). Use for fully
                                 offline / egress-blocked generation.
  """
  use Mix.Task
  alias Atlas.Control.CatalogGenerator

  @shortdoc "Regenerate priv/regions/catalog.json from Geofabrik + BBBike."
  @geofabrik_url "https://download.geofabrik.de/index-v1-nogeom.json"
  @bbbike_index "https://download.bbbike.org/osm/bbbike/"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          out: :string,
          geofabrik_file: :string,
          bbbike_file: :string,
          no_geofabrik: :boolean,
          no_sizes: :boolean
        ]
      )

    out = opts[:out] || Path.join(:code.priv_dir(:atlas), "regions/catalog.json")

    geofabrik = if opts[:no_geofabrik], do: %{"features" => []}, else: load_geofabrik(opts[:geofabrik_file])
    cities = load_bbbike(opts[:bbbike_file])

    Mix.shell().info("Geofabrik features: #{length(geofabrik["features"])}; BBBike cities: #{length(cities)}")

    head_fun = if opts[:no_sizes], do: fn _ -> {:error, :skipped} end, else: &head_size/1
    entries = CatalogGenerator.build(geofabrik, cities, head_fun)
    nulls = Enum.count(entries, &is_nil(&1["pbf_bytes"]))

    case CatalogGenerator.write(entries, out) do
      :ok -> Mix.shell().info("Wrote #{length(entries)} entries (#{nulls} without size) -> #{out}")
      {:error, msg} -> Mix.raise("catalog invalid: #{msg}")
    end
  end

  defp load_geofabrik(nil), do: Req.get!(@geofabrik_url).body
  defp load_geofabrik(path), do: path |> File.read!() |> Jason.decode!()

  defp load_bbbike(nil), do: @bbbike_index |> Req.get!() |> Map.fetch!(:body) |> parse_bbbike_index()
  defp load_bbbike(path), do: path |> File.read!() |> parse_bbbike_index()

  @doc "Extract `<City>` names from the BBBike directory index HTML."
  def parse_bbbike_index(html) do
    Regex.scan(~r/href="([^".\/][^"\/]*)\/"/, html)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  defp head_size(url) do
    case Req.head(url, retry: false) do
      {:ok, %{status: 200} = resp} ->
        case Req.Response.get_header(resp, "content-length") do
          [len | _] -> {:ok, String.to_integer(len)}
          _ -> {:error, :no_length}
        end

      _ ->
        {:error, :head_failed}
    end
  end
end
