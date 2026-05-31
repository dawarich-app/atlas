defmodule Atlas.Maps.Upstream.Otp do
  alias Atlas.Maps.Upstream.Client

  @default_modes "TRANSIT,WALK"

  def default_modes, do: @default_modes

  def default do
    Client.build_from_env("OTP", "http://localhost:8080",
                          timeout: 15_000, open_timeout: 2_000)
  end

  def plan(req \\ default(), opts) do
    %{from: from, to: to} = Map.new(opts)
    modes = opts[:modes] || @default_modes
    num = opts[:num]

    params = [
      {"fromPlace", "#{from[:lat]},#{from[:lon]}"},
      {"toPlace", "#{to[:lat]},#{to[:lon]}"},
      {"mode", modes}
    ]
    |> maybe_add("date", opts[:date])
    |> maybe_add("time", opts[:time])
    |> maybe_add("numItineraries", num)
    |> maybe_add("arriveBy", opts[:arrive_by])

    Client.get(req, "/otp/routers/default/plan", params)
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, val), do: params ++ [{key, to_string(val)}]
end
