defmodule AtlasWeb.DirectionsStatus do
  @moduledoc "Compact routing service readiness, using the existing control-plane snapshots."
  use Phoenix.Component

  attr :services, :map, default: %{}
  attr :backend, :string, default: "motis"
  attr :switching, :string, default: nil

  def directions_status(assigns) do
    backend = assigns.switching || assigns.backend

    assigns =
      assign(assigns,
        entries: [
          entry("valhalla", "Roads", "Valhalla", assigns.services["valhalla"]),
          entry(
            backend,
            "Transit",
            if(backend == "otp", do: "OpenTripPlanner", else: "MOTIS"),
            assigns.services[backend],
            assigns.switching != nil
          )
        ]
      )

    ~H"""
    <div id="directions-service-status" role="status" aria-live="polite" aria-label="Routing service status"
      class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-[11px] text-base-content/65">
      <button :for={entry <- @entries} type="button" data-service={entry.id}
        phx-click="open_services"
        title={entry.title} aria-label={entry.title}
        class="inline-flex items-center gap-1.5 rounded py-0.5 transition-colors hover:text-base-content focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary">
        <span aria-hidden="true" class={["h-1.5 w-1.5 shrink-0 rounded-full", entry.color, entry.busy && "motion-safe:animate-pulse"]}></span>
        <span>{entry.label} <span aria-hidden="true">·</span> {entry.status}</span>
      </button>
    </div>
    """
  end

  defp entry(id, label, engine, snapshot, switching \\ false) do
    {status, color, busy} =
      if switching, do: {"Switching", "bg-warning", true}, else: state(snapshot)

    scope =
      if id == "valhalla",
        do: "Driving, cycling and walking.",
        else: "Public transport. Realtime feed health is not monitored."

    %{
      id: id,
      label: label,
      status: status,
      color: color,
      busy: busy,
      title: "#{engine}: #{status}. #{scope} Coverage depends on installed data. Open Settings."
    }
  end

  defp state(nil), do: {"Unknown", "bg-base-content/30", false}
  defp state(%{enabled?: false}), do: {"Off", "bg-base-content/30", false}

  defp state(%{status: status}) when status in [:error, :unhealthy],
    do: {"Unavailable", "bg-error", false}

  defp state(%{status: :stopped}), do: {"Stopped", "bg-base-content/30", false}
  defp state(%{status: :downloading}), do: {"Downloading", "bg-warning", true}
  defp state(%{status: :building}), do: {"Building", "bg-warning", true}
  defp state(%{status: :starting}), do: {"Starting", "bg-warning", true}
  defp state(%{status: :ready}), do: {"Ready", "bg-success", false}
  defp state(_), do: {"Unknown", "bg-base-content/30", false}
end
