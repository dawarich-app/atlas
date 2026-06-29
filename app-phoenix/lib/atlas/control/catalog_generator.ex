defmodule Atlas.Control.CatalogGenerator do
  @moduledoc """
  Build the baked region catalog from upstream indexes. Pure, network-free
  transforms plus a writer; the live HTTP fetch lives in the Mix task that
  drives this module.

  Catalog entries are plain maps with string keys, ready for `Jason.encode!/1`:

      %{name, label, kind, source, parent, country_code, iso, pbf_url, pbf_bytes}

  `name` is a source-prefixed slug (`gf:germany`, `bbbike:berlin`) so it never
  collides with the curated `.env` presets or existing `region_selections` rows.
  """

  @doc "Geofabrik `index-v1-nogeom.json` (decoded) → catalog entries."
  def from_geofabrik(%{"features" => features}) do
    Enum.map(features, fn %{"properties" => p} ->
      iso1 = p["iso3166-1:alpha2"] || []
      iso2 = p["iso3166-2"] || []

      %{
        "name" => "gf:" <> p["id"],
        "label" => p["name"],
        "kind" => geofabrik_kind(p["parent"], iso1),
        "source" => "geofabrik",
        "parent" => if(p["parent"], do: "gf:" <> p["parent"]),
        "country_code" => iso1 |> List.first() |> downcase_or_nil(),
        "iso" => iso1 ++ iso2,
        "pbf_url" => get_in(p, ["urls", "pbf"]),
        "pbf_bytes" => nil
      }
    end)
  end

  defp geofabrik_kind(nil, _iso1), do: "continent"
  defp geofabrik_kind(_parent, iso1) when iso1 != [], do: "country"
  defp geofabrik_kind(_parent, _iso1), do: "subregion"

  defp downcase_or_nil(nil), do: nil
  defp downcase_or_nil(s), do: String.downcase(s)

  # Geofabrik country id (no `gf:` prefix) → ISO 3166-1 alpha-2.
  @country_cc %{
    "germany" => "de", "austria" => "at", "switzerland" => "ch", "france" => "fr",
    "united-kingdom" => "gb", "ireland-and-northern-ireland" => "ie", "netherlands" => "nl",
    "belgium" => "be", "luxembourg" => "lu", "spain" => "es", "portugal" => "pt",
    "italy" => "it", "denmark" => "dk", "sweden" => "se", "norway" => "no", "finland" => "fi",
    "poland" => "pl", "czech-republic" => "cz", "hungary" => "hu", "slovenia" => "si",
    "croatia" => "hr", "bosnia-herzegovina" => "ba", "serbia" => "rs", "bulgaria" => "bg",
    "greece" => "gr", "estonia" => "ee", "latvia" => "lv", "lithuania" => "lt",
    "belarus" => "by", "ukraine" => "ua", "russia" => "ru", "turkey" => "tr",
    "us" => "us", "canada" => "ca", "mexico" => "mx", "brazil" => "br", "argentina" => "ar",
    "uruguay" => "uy", "chile" => "cl", "peru" => "pe", "bolivia" => "bo", "colombia" => "co",
    "japan" => "jp", "china" => "cn", "south-korea" => "kr", "india" => "in",
    "thailand" => "th", "vietnam" => "vn", "cambodia" => "kh", "mongolia" => "mn",
    "malaysia-singapore-brunei" => "sg", "azerbaijan" => "az", "iran" => "ir", "iraq" => "iq",
    "lebanon" => "lb", "syria" => "sy", "israel-and-palestine" => "il", "egypt" => "eg",
    "south-africa" => "za", "morocco" => "ma", "australia" => "au", "new-zealand" => "nz"
  }

  # BBBike city dir name → Geofabrik country id. Cities whose country is absent
  # here (or absent from the index) float at the top level via reconcile_parents/1.
  @bbbike_city_country %{
    "Aachen" => "germany", "Augsburg" => "germany", "Bamberg" => "germany",
    "Berlin" => "germany", "Bielefeld" => "germany", "Bochum" => "germany",
    "Bonn" => "germany", "BrandenburgHavel" => "germany", "Braunschweig" => "germany",
    "Bremen" => "germany", "Bremerhaven" => "germany", "Chemnitz" => "germany",
    "Cottbus" => "germany", "Darmstadt" => "germany", "Dessau" => "germany",
    "Dortmund" => "germany", "Dresden" => "germany", "Duesseldorf" => "germany",
    "Duisburg" => "germany", "Emden" => "germany", "Erfurt" => "germany",
    "Erlangen" => "germany", "Flensburg" => "germany", "Frankfurt" => "germany",
    "FrankfurtOder" => "germany", "Freiburg" => "germany", "Gera" => "germany",
    "Goerlitz" => "germany", "Goettingen" => "germany", "Halle" => "germany",
    "Hamburg" => "germany", "Hamm" => "germany", "Hannover" => "germany",
    "Heilbronn" => "germany", "Jena" => "germany", "Kaiserslautern" => "germany",
    "Karlsruhe" => "germany", "Kassel" => "germany", "Kiel" => "germany",
    "Koblenz" => "germany", "Koeln" => "germany", "Konstanz" => "germany",
    "Leipzig" => "germany", "Luebeck" => "germany", "Magdeburg" => "germany",
    "Mainz" => "germany", "Mannheim" => "germany", "Moenchengladbach" => "germany",
    "Muenchen" => "germany", "Muenster" => "germany", "Nuernberg" => "germany",
    "Oldenburg" => "germany", "Oranienburg" => "germany", "Osnabrueck" => "germany",
    "Paderborn" => "germany", "Potsdam" => "germany", "Regensburg" => "germany",
    "Rostock" => "germany", "Ruegen" => "germany", "Saarbruecken" => "germany",
    "Schwerin" => "germany", "Stuttgart" => "germany", "Ulm" => "germany",
    "Usedom" => "germany", "WarenMueritz" => "germany", "Wuerzburg" => "germany",
    "Wuppertal" => "germany",
    "Wien" => "austria", "Graz" => "austria", "Innsbruck" => "austria",
    "Linz" => "austria", "Salzburg" => "austria",
    "Zuerich" => "switzerland", "Basel" => "switzerland", "Bern" => "switzerland",
    "Genf" => "switzerland", "Lausanne" => "switzerland",
    "Paris" => "france", "Bordeaux" => "france", "ClermontFerrand" => "france",
    "Colmar" => "france", "Corsica" => "france", "Lyon" => "france",
    "Marseille" => "france", "Montpellier" => "france", "Strassburg" => "france",
    "Toulouse" => "france",
    "London" => "united-kingdom", "Birmingham" => "united-kingdom",
    "Bristol" => "united-kingdom", "Cambridge" => "united-kingdom",
    "Edinburgh" => "united-kingdom", "Glasgow" => "united-kingdom",
    "Leeds" => "united-kingdom", "Liverpool" => "united-kingdom",
    "Manchester" => "united-kingdom", "Sheffield" => "united-kingdom",
    "Dublin" => "ireland-and-northern-ireland", "Cork" => "ireland-and-northern-ireland",
    "Amsterdam" => "netherlands", "Arnhem" => "netherlands", "DenHaag" => "netherlands",
    "Eindhoven" => "netherlands", "Groningen" => "netherlands",
    "Hertogenbosch" => "netherlands", "Maastricht" => "netherlands",
    "Rotterdam" => "netherlands", "Tilburg" => "netherlands", "Utrecht" => "netherlands",
    "Antwerpen" => "belgium", "Bruegge" => "belgium", "Bruessel" => "belgium",
    "Gent" => "belgium",
    "Luxemburg" => "luxembourg",
    "Barcelona" => "spain", "Madrid" => "spain", "Palma" => "spain",
    "Lisbon" => "portugal", "Porto" => "portugal",
    "LakeGarda" => "italy", "Turin" => "italy",
    "Aarhus" => "denmark", "Copenhagen" => "denmark",
    "Goeteborg" => "sweden", "Malmoe" => "sweden", "Stockholm" => "sweden",
    "Oslo" => "norway", "Trondheim" => "norway",
    "Helsinki" => "finland",
    "Cracow" => "poland", "Gdansk" => "poland", "Gliwice" => "poland",
    "Katowice" => "poland", "Lodz" => "poland", "Poznan" => "poland",
    "Szczecin" => "poland", "Warsaw" => "poland", "Wroclaw" => "poland",
    "Brno" => "czech-republic", "Ostrava" => "czech-republic", "Prag" => "czech-republic",
    "Budapest" => "hungary", "Balaton" => "hungary",
    "Ljubljana" => "slovenia",
    "Zagreb" => "croatia",
    "Sarajewo" => "bosnia-herzegovina",
    "Sofia" => "bulgaria",
    "Tallinn" => "estonia", "Riga" => "latvia", "Kaunas" => "lithuania",
    "Minsk" => "belarus", "Kiew" => "ukraine",
    "Moscow" => "russia", "SanktPetersburg" => "russia",
    "Istanbul" => "turkey",
    "Albuquerque" => "us", "Austin" => "us", "Berkeley" => "us", "Boulder" => "us",
    "CambridgeMa" => "us", "Chicago" => "us", "Corvallis" => "us", "CraterLake" => "us",
    "Dallas" => "us", "Davis" => "us", "Denver" => "us", "Eugene" => "us",
    "FortCollins" => "us", "Huntsville" => "us", "LosAngeles" => "us", "Madison" => "us",
    "Memphis" => "us", "Miami" => "us", "NewOrleans" => "us", "NewYork" => "us",
    "Orlando" => "us", "PaloAlto" => "us", "Philadelphia" => "us", "Portland" => "us",
    "PortlandME" => "us", "Providence" => "us", "Sacramento" => "us", "SanFrancisco" => "us",
    "SanJose" => "us", "SantaBarbara" => "us", "SantaCruz" => "us", "Seattle" => "us",
    "Stockton" => "us", "Tucson" => "us", "WashingtonDC" => "us",
    "Calgary" => "canada", "Halifax" => "canada", "Montreal" => "canada",
    "Ottawa" => "canada", "Toronto" => "canada", "Vancouver" => "canada",
    "Victoria" => "canada", "Waterloo" => "canada",
    "MexicoCity" => "mexico",
    "Curitiba" => "brazil", "PortoAlegre" => "brazil", "RiodeJaneiro" => "brazil",
    "BuenosAires" => "argentina", "LaPlata" => "argentina",
    "Montevideo" => "uruguay", "Santiago" => "chile",
    "Cusco" => "peru", "Lima" => "peru", "LaPaz" => "bolivia", "Sucre" => "bolivia",
    "Bogota" => "colombia",
    "Tokyo" => "japan", "Beijing" => "china", "Seoul" => "south-korea",
    "Bombay" => "india", "NewDelhi" => "india",
    "Bangkok" => "thailand", "Saigon" => "vietnam", "PhnomPenh" => "cambodia",
    "Singapore" => "malaysia-singapore-brunei", "UlanBator" => "mongolia",
    "Baku" => "azerbaijan", "Tehran" => "iran", "Baghdad" => "iraq",
    "Beirut" => "lebanon", "Damaskus" => "syria", "Jerusalem" => "israel-and-palestine",
    "Cairo" => "egypt", "Alexandria" => "egypt",
    "CapeTown" => "south-africa", "Johannesburg" => "south-africa",
    "Adelaide" => "australia", "Brisbane" => "australia", "Canberra" => "australia",
    "Melbourne" => "australia", "Perth" => "australia", "Sydney" => "australia",
    "Auckland" => "new-zealand"
  }

  @doc "List of BBBike city names → catalog entries."
  def from_bbbike(cities) when is_list(cities) do
    Enum.map(cities, fn city ->
      {parent, cc} =
        case Map.get(@bbbike_city_country, city) do
          nil -> {nil, nil}
          country_id -> {"gf:" <> country_id, Map.get(@country_cc, country_id)}
        end

      %{
        "name" => "bbbike:" <> String.downcase(city),
        "label" => city,
        "kind" => "city",
        "source" => "bbbike",
        "parent" => parent,
        "country_code" => cc,
        "iso" => [],
        "pbf_url" => "https://download.bbbike.org/osm/bbbike/#{city}/#{city}.osm.pbf",
        "pbf_bytes" => nil
      }
    end)
  end

  @doc """
  Fill `pbf_bytes` for each entry using `head_fun.(url) -> {:ok, bytes} | {:error, _}`.
  Runs concurrently with a cap; failures leave `pbf_bytes: nil`.
  """
  def enrich_sizes(entries, head_fun) do
    entries
    |> Task.async_stream(
      fn e ->
        case head_fun.(e["pbf_url"]) do
          {:ok, bytes} when is_integer(bytes) -> Map.put(e, "pbf_bytes", bytes)
          _ -> Map.put(e, "pbf_bytes", nil)
        end
      end,
      max_concurrency: 4,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.zip(entries)
    |> Enum.map(fn
      {{:ok, enriched}, _orig} -> enriched
      {{:exit, _}, orig} -> Map.put(orig, "pbf_bytes", nil)
    end)
  end

  @doc "Assemble the full catalog: geofabrik + bbbike, size-enriched, sorted."
  def build(geofabrik_index, bbbike_cities, head_fun) do
    (from_geofabrik(geofabrik_index) ++ from_bbbike(bbbike_cities))
    |> reconcile_parents()
    |> enrich_sizes(head_fun)
    |> Enum.sort_by(& &1["name"])
  end

  @doc """
  Null out any `parent` that doesn't resolve to an existing entry so the entry
  becomes a selectable root instead of an integrity-breaking orphan. Guards
  against BBBike override slugs and Geofabrik id drift that reference an absent
  parent.
  """
  def reconcile_parents(entries) do
    names = MapSet.new(entries, & &1["name"])

    Enum.map(entries, fn e ->
      if e["parent"] && not MapSet.member?(names, e["parent"]),
        do: Map.put(e, "parent", nil),
        else: e
    end)
  end

  @doc "Validate referential integrity before writing. `:ok | {:error, msg}`."
  def validate(entries) do
    names = Enum.map(entries, & &1["name"])
    dups = names -- Enum.uniq(names)
    name_set = MapSet.new(names)

    orphans =
      entries
      |> Enum.filter(fn e -> e["parent"] && not MapSet.member?(name_set, e["parent"]) end)
      |> Enum.map(& &1["name"])

    missing_url = Enum.filter(entries, &(is_nil(&1["pbf_url"]) or &1["pbf_url"] == ""))

    cond do
      dups != [] -> {:error, "duplicate names: #{Enum.join(Enum.uniq(dups), ", ")}"}
      orphans != [] -> {:error, "unresolved parent for: #{Enum.join(orphans, ", ")}"}
      missing_url != [] -> {:error, "missing pbf_url for: #{length(missing_url)} entries"}
      true -> :ok
    end
  end

  @doc "Write entries as pretty JSON to `path`. Validates first."
  def write(entries, path) do
    case validate(entries) do
      :ok -> File.write(path, Jason.encode!(entries, pretty: true) <> "\n")
      {:error, msg} -> {:error, msg}
    end
  end
end
