defmodule Atlas.Control.ServiceFormatting do
  @moduledoc """
  Presentation-layer helpers that map a `ServiceState` snapshot's
  `:status` atom onto Tailwind / DaisyUI class strings and a human
  label.

  Shared between `SettingsPanel`, `ServiceCard`, and any future surface
  that renders service status so the badge palette stays consistent.
  """

  @doc """
  Short text label for a snapshot's status. A service that has never been
  observed reads as "off" — "unknown" tells an operator nothing.
  """
  def status_label(nil), do: "off"
  def status_label(%{status: :unknown}), do: "off"

  def status_label(%{status: status}) when is_atom(status) and not is_nil(status),
    do: Atom.to_string(status)

  def status_label(%{status: status}) when is_binary(status), do: status
  def status_label(_), do: "off"

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

  @doc "True when a snapshot is mid-install (downloading/building/starting)."
  def installing?(%{status: status}) when status in [:starting, :downloading, :building], do: true
  def installing?(_), do: false

  @doc "True when a snapshot is fully ready."
  def running?(%{status: :ready}), do: true
  def running?(_), do: false

  @doc "Integer percent (0–100) for a snapshot's install progress."
  def progress_pct(%{progress: p}) when is_number(p), do: p |> Kernel.*(100) |> round() |> min(100) |> max(0)
  def progress_pct(_), do: 0

  @doc "Lowercased phase label for a snapshot, or `nil`."
  def phase_label(%{phase: phase}) when is_binary(phase) and phase != "", do: phase
  def phase_label(_), do: nil

  @doc "Human disk size from a snapshot's `disk_bytes`."
  def disk_label(%{disk_bytes: b}) when is_integer(b) and b > 0, do: format_bytes(b)
  def disk_label(_), do: "—"

  @doc "Sum of `disk_bytes` across running snapshots, formatted GB/TB. `—` when zero."
  def total_disk_label(status_map) when is_map(status_map) do
    bytes =
      Enum.reduce(status_map, 0, fn
        {_name, %{status: :ready, disk_bytes: b}}, acc when is_integer(b) -> acc + b
        {_name, _snap}, acc -> acc
      end)

    if bytes > 0, do: format_bytes(bytes), else: "—"
  end

  def total_disk_label(_), do: "—"

  defp format_bytes(b) when b >= 1_000_000_000_000, do: "#{round1(b / 1_000_000_000_000)} TB"
  defp format_bytes(b) when b >= 1_000_000_000, do: "#{round1(b / 1_000_000_000)} GB"
  defp format_bytes(b) when b >= 1_000_000, do: "#{round1(b / 1_000_000)} MB"
  defp format_bytes(b), do: "#{round1(b / 1_000)} KB"

  defp round1(f), do: :erlang.float_to_binary(Float.round(f * 1.0, 1), decimals: 1)
end
