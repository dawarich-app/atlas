defmodule AtlasWeb.MapLive.ApplyFlash do
  @moduledoc false

  import AtlasWeb.AdminErrorComponents, only: [format_error: 1]

  @doc """
  Flash for the Settings "Save & apply" action: `{level, message}` derived
  from the number of service toggles and the `RegionApplier.start/1` result.
  Failures surface as `:error` — never as an optimistic "Applying…".
  """
  def message(0, :no_region, _names), do: {:info, "Nothing to apply"}

  def message(tool_count, :no_region, _names),
    do: {:info, "Applied #{tool_count} tool change#{plural(tool_count)}"}

  def message(tool_count, :unavailable, _names) when tool_count > 0,
    do: {:info, "Applied #{tool_count} tool change#{plural(tool_count)}; region apply unavailable"}

  def message(_, :unavailable, _names),
    do: {:error, "The control plane is not running on this build"}

  def message(0, {:ok, _job_id}, names),
    do: {:info, "Applying #{summary(names)}…"}

  def message(tool_count, {:ok, _job_id}, names),
    do:
      {:info,
       "Applied #{tool_count} tool change#{plural(tool_count)}; applying #{summary(names)}…"}

  def message(_tool_count, {:error, reason}, _names),
    do: {:error, "Region apply not started: #{format_error(reason)}"}

  def message(tool_count, _other, names),
    do: message(tool_count, :unavailable, names)

  defp summary([name]), do: "region #{name}"
  defp summary(names), do: "#{length(names)} regions (#{Enum.join(names, ", ")})"

  defp plural(1), do: ""
  defp plural(_), do: "s"
end
