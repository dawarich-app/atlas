defmodule Atlas.Maps.WhatsHere do
  alias Atlas.Maps.{Result, Reverse, Upstream.Overpass}

  def lookup(opts) do
    %{lat: lat, lon: lon} = Map.new(opts)
    radius = opts[:radius] || 200
    lang = opts[:lang]

    reverse_task = Task.async(fn -> Reverse.lookup(lat: lat, lon: lon, lang: lang) end)
    overpass_task = Task.async(fn -> Overpass.around(lat: lat, lon: lon, radius: radius) end)

    case Task.await(reverse_task, 5_000) do
      {:ok, %Result{} = reverse_result} ->
        nearby =
          case Task.await(overpass_task, 25_000) do
            {:ok, %{"elements" => elements}} -> Enum.map(elements, &poi_feature/1)
            _ -> []
          end

        {:ok,
         %Result{
           features: %{
             here: reverse_result.features.here,
             admin: reverse_result.features.admin,
             nearby: nearby
           },
           upstream_status: reverse_result.upstream_status
         }}

      {:error, _e} = err ->
        # cancel still-running overpass task to avoid leaking work
        Task.shutdown(overpass_task, :brutal_kill)
        err
    end
  end

  defp poi_feature(el) do
    center = el["center"] || %{"lat" => el["lat"], "lon" => el["lon"]}

    %{
      id: "#{el["type"]}/#{el["id"]}",
      coords: %{lon: center["lon"], lat: center["lat"]},
      tags: el["tags"] || %{}
    }
  end
end
