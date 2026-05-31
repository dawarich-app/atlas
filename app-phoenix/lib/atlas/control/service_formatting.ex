defmodule Atlas.Control.ServiceFormatting do
  @moduledoc """
  Presentation-layer helpers that map a `ServiceState` snapshot's
  `:status` atom onto Tailwind / DaisyUI class strings and a human
  label.

  Shared between `SettingsPanel`, `ServiceCard`, and any future surface
  that renders service status so the badge palette stays consistent.
  """

  @doc "Short text label for a snapshot's status."
  def status_label(nil), do: "—"
  def status_label(%{status: status}) when is_atom(status) and not is_nil(status), do: Atom.to_string(status)
  def status_label(%{status: status}) when is_binary(status), do: status
  def status_label(_), do: "—"

  @doc "Tailwind classes for the colored left-edge bar in service rows."
  def status_bar_class(%{status: :ready}), do: "bg-success"
  def status_bar_class(%{status: status}) when status in [:starting, :downloading, :building],
    do: "bg-warning animate-pulse"

  def status_bar_class(%{status: status}) when status in [:error, :unhealthy], do: "bg-error"
  def status_bar_class(%{status: :stopped}), do: "bg-base-300"
  def status_bar_class(_), do: "bg-base-300/60"

  @doc "DaisyUI badge class for the service status pill."
  def badge_class(%{status: :ready}), do: "badge-success"
  def badge_class(%{status: status}) when status in [:starting, :downloading, :building],
    do: "badge-warning"

  def badge_class(%{status: status}) when status in [:error, :unhealthy], do: "badge-error"
  def badge_class(_), do: "badge-ghost"

  @doc "Service is considered enabled when its DB row says so."
  def enabled?(%{enabled?: true}), do: true
  def enabled?(_), do: false

  @doc "Count snapshots whose status is `:ready`."
  def ready_count(status_map) when is_map(status_map) do
    Enum.count(status_map, fn {_name, snap} -> match?(%{status: :ready}, snap) end)
  end

  def ready_count(_), do: 0
end
