defmodule Atlas.Maps.WhatsHere do
  alias Atlas.Maps.{Result, Reverse, Upstream.Overpass}

  @doc """
  Returns `{:ok, %Result{}}` when both reverse and Overpass succeed. If either
  upstream fails, returns `{:error, %Client.Unavailable{} | %Client.BadResponse{}}`
  to match Rails behavior of 503 on partial failure.
  """
  def lookup(opts) do
    %{lat: lat, lon: lon} = Map.new(opts)
    radius = opts[:radius] || 200
    lang = opts[:lang]

    reverse_task = Task.async(fn -> Reverse.lookup(lat: lat, lon: lon, lang: lang) end)
    overpass_task = Task.async(fn -> Overpass.around(lat: lat, lon: lon, radius: radius) end)

    with {:ok, %Result{} = reverse_result} <- Task.await(reverse_task, 5_000),
         {:ok, %{"elements" => elements}} <- Task.await(overpass_task, 25_000) do
      {:ok,
       %Result{
         features: %{
           here: reverse_result.features.here,
           admin: reverse_result.features.admin,
           nearby: Enum.map(elements, &poi_feature/1)
         },
         upstream_status: reverse_result.upstream_status
       }}
    else
      {:error, _e} = err ->
        Task.shutdown(reverse_task, :brutal_kill)
        Task.shutdown(overpass_task, :brutal_kill)
        err

      _other ->
        Task.shutdown(reverse_task, :brutal_kill)
        Task.shutdown(overpass_task, :brutal_kill)
        {:error, %Atlas.Maps.Upstream.Client.Unavailable{message: "overpass returned unexpected shape"}}
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
