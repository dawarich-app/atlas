defmodule AtlasWeb.AdminErrorComponents do
  @moduledoc """
  User-facing error views for admin LiveViews when the Atlas Control sidecar
  (the docker-compose layer that runs photon/valhalla/etc.) is unreachable
  or returns an error, and when a configured region is not present in the
  catalog.

  Mirrors the Rails `app/views/admin/errors/*` templates.

  ## Usage

  In a LiveView's `render/1`:

      <%= if @error_view do %>
        <.sidecar_unavailable details={@error_details} />
      <% end %>

  Or call the helpers directly from a controller action that wants to render
  a standalone error page.
  """

  use Phoenix.Component
  use AtlasWeb, :verified_routes

  @doc """
  Human-readable text for control-plane error terms. Templates must never
  render raw `inspect/1` output to operators.
  """
  def format_error(:busy), do: "An apply is already running — wait for it to finish."
  def format_error(:unavailable), do: "The control plane is not running on this build."

  def format_error({:region_not_found, name}),
    do: "Region “#{name}” is not in the catalog."

  def format_error({:http_status, status}), do: "The server responded with HTTP #{status}."

  def format_error({code, output}) when is_integer(code) and is_binary(output),
    do: "Command failed (exit #{code}): #{String.trim(output)}"

  def format_error(%{__exception__: true} = e), do: Exception.message(e)
  def format_error(reason) when is_binary(reason), do: reason
  def format_error(reason), do: inspect(reason)

  @doc """
  Atlas Control (docker-compose) is unreachable. Shown when `DockerCompose`
  returns a connection failure or the manage script is missing.
  """
  attr :details, :string, default: nil

  def sidecar_unavailable(assigns) do
    ~H"""
    <div class="alert alert-warning my-4 max-w-2xl" role="alert" data-error="sidecar_unavailable">
      <div>
        <h3 class="font-semibold">Atlas Control is unreachable</h3>
        <p class="text-sm mt-1">
          The control plane (Docker Compose layer) is not responding. Service
          toggles, downloads, and region applies are temporarily unavailable.
        </p>
        <ul class="text-xs mt-2 list-disc pl-4">
          <li>Verify the host docker daemon is running</li>
          <li>
            Run <code class="font-mono">make status</code>
            in the Atlas repo to inspect the compose stack
          </li>
          <li>Check the container logs for the most-recently-restarted service</li>
        </ul>
        <%= if @details do %>
          <pre class="text-xs mt-2 bg-base-200 p-2 rounded whitespace-pre-wrap">{@details}</pre>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Atlas Control returned a non-zero status. Shown when a DockerCompose
  invocation exits with an error.
  """
  attr :details, :string, default: nil
  attr :command, :string, default: nil

  def sidecar_error(assigns) do
    ~H"""
    <div class="alert alert-error my-4 max-w-2xl" role="alert" data-error="sidecar_error">
      <div>
        <h3 class="font-semibold">Atlas Control returned an error</h3>
        <%= if @command do %>
          <p class="text-sm mt-1">
            Command: <code class="font-mono">{@command}</code>
          </p>
        <% end %>
        <%= if @details do %>
          <pre class="text-xs mt-2 bg-base-200 p-2 rounded whitespace-pre-wrap">{@details}</pre>
        <% end %>
        <p class="text-xs mt-2">
          The most common cause is a missing PBF file or out-of-disk on the
          host. Inspect the container logs for the failing service.
        </p>
      </div>
    </div>
    """
  end

  @doc """
  A configured region is not found in the catalog (priv/regions/*.env).
  Shown by ApplyLive when projection or apply references an unknown region.
  """
  attr :name, :string, required: true
  attr :available, :list, default: []

  def region_not_found(assigns) do
    ~H"""
    <div class="alert alert-warning my-4 max-w-2xl" role="alert" data-error="region_not_found">
      <div>
        <h3 class="font-semibold">Region not available</h3>
        <p class="text-sm mt-1">
          The region <code class="font-mono">{@name}</code>
          is not in the catalog. Available presets:
        </p>
        <%= if @available == [] do %>
          <p class="text-xs mt-1">No region presets are configured.</p>
        <% else %>
          <ul class="text-xs mt-1 list-disc pl-4">
            <li :for={name <- @available}>{name}</li>
          </ul>
        <% end %>
        <p class="text-xs mt-2">
          <.link navigate={~p"/admin/regions"} class="link">Manage regions →</.link>
        </p>
      </div>
    </div>
    """
  end
end
