defmodule Atlas.Maps.Transit do
  alias Atlas.Maps.{Result, Upstream.Otp, Upstream.Client}
  require Logger

  def plan(opts) do
    case Otp.plan(opts) do
      {:ok, body} ->
        {:ok, %Result{features: %{plan: body["plan"]}, upstream_status: "ok"}}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("otp unavailable: #{Exception.message(e)}")
        {:error, e}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("otp bad response: #{Exception.message(e)}")
        {:error, e}
    end
  end
end
