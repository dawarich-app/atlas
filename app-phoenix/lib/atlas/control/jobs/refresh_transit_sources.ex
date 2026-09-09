defmodule Atlas.Control.Jobs.RefreshTransitSources do
  @moduledoc "Daily opt-in refresh of connected timetables through the serialized region installer."
  use Oban.Worker, queue: :control, unique: [period: 3600]
  alias Atlas.Control.TransitSources

  @impl true
  def perform(_) do
    if Atlas.Settings.get("transit_sources_auto_update") == "true" and
         TransitSources.enabled() != [] do
      case TransitSources.refresh() do
        {:ok, _} -> :ok
        {:error, :busy} -> {:snooze, 300}
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
