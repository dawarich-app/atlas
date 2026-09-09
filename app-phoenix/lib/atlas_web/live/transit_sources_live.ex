defmodule AtlasWeb.TransitSourcesLive do
  use AtlasWeb, :live_view
  alias Atlas.Control.{RegionApplier, Safe, TransitSources}
  alias AtlasWeb.Layouts

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Atlas.PubSub, RegionApplier.topic())

    {:ok,
     socket
     |> assign(
       page_title: "Transport data",
       query: "",
       form: to_form(%{}, as: :source),
       editing: nil,
       adding: false,
       error: nil,
       message: nil,
       return_to: return_path(params)
     )
     |> load(), layout: false}
  end

  defp return_path(%{"from" => "setup", "step" => step}) when step in ~w(1 2 3),
    do: "/setup?step=" <> step

  defp return_path(%{"from" => "setup"}), do: "/setup"
  defp return_path(_), do: "/"

  defp load(socket) do
    status = Safe.call(&RegionApplier.status/0, nil)

    assign(socket,
      sources: TransitSources.all(),
      legacy_files: legacy_files(),
      pending: TransitSources.pending?(),
      catalog: TransitSources.catalog(),
      statuses: TransitSources.statuses(),
      auto_update: Atlas.Settings.get("transit_sources_auto_update") == "true",
      busy: status != nil and not Map.has_key?(status, :error)
    )
  end

  defp legacy_files do
    if TransitSources.configured?() do
      []
    else
      Path.wildcard("/work/data/otp/*.gtfs.zip") |> Enum.map(&Path.basename/1)
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket),
    do: {:noreply, assign(socket, query: query)}

  def handle_event("add", _, socket),
    do: {:noreply, assign(socket, adding: true, editing: nil, form: to_form(%{}, as: :source))}

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, adding: false, error: nil, form: to_form(%{}, as: :source))}

  def handle_event("connect", %{"id" => id}, socket),
    do: result(socket, TransitSources.connect(id))

  def handle_event("toggle", %{"id" => id, "field" => field}, socket)
      when field in ~w(enabled realtime),
      do: result(socket, TransitSources.toggle(id, field))

  def handle_event("edit", %{"id" => id}, socket) do
    source = Enum.find(socket.assigns.sources, &(&1["id"] == id))

    if source,
      do:
        {:noreply,
         assign(socket,
           adding: true,
           editing: id,
           form: to_form(Map.delete(source, "header_value"), as: :source)
         )},
      else: {:noreply, socket}
  end

  def handle_event("save", %{"source" => params}, socket) do
    result =
      if socket.assigns.editing,
        do: TransitSources.update(socket.assigns.editing, params),
        else: TransitSources.add(params)

    case result do
      :ok ->
        result(assign(socket, adding: false, editing: nil, form: to_form(%{}, as: :source)), :ok)

      {:error, message} ->
        {:noreply,
         assign(socket,
           error: message,
           form: to_form(Map.delete(params, "header_value"), as: :source)
         )}
    end
  end

  def handle_event("refresh", _, socket) do
    case TransitSources.refresh() do
      {:ok, _} ->
        {:noreply,
         socket
         |> load()
         |> assign(
           error: nil,
           message:
             "Downloading timetables. The selected transport engine will rebuild if it is enabled and street data is installed."
         )}

      {:error, :busy} ->
        {:noreply, assign(socket, error: "An installation is already in progress.")}

      {:error, message} ->
        {:noreply, assign(socket, error: to_string(message))}
    end
  end

  def handle_event("auto_update", _, socket) do
    Atlas.Settings.set("transit_sources_auto_update", to_string(!socket.assigns.auto_update))
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({:apply_done, _}, socket),
    do:
      {:noreply,
       socket
       |> load()
       |> assign(
         message:
           "Timetable update finished. Check each source below for download warnings. Engine readiness is shown in Settings → Services."
       )}

  def handle_info({:apply_error, _}, socket),
    do:
      {:noreply,
       socket
       |> load()
       |> assign(
         error:
           "Installation failed. Check Installation details in Settings; previous downloads are kept."
       )}

  def handle_info(_, socket), do: {:noreply, load(socket)}

  defp result(socket, :ok),
    do:
      {:noreply,
       socket
       |> load()
       |> assign(
         error: nil,
         message:
           "Selection saved. Choose Download & apply, or continue the setup wizard, to apply it."
       )}

  defp result(socket, {:error, message}), do: {:noreply, assign(socket, error: message)}

  defp matches?(source, query) do
    String.contains?(
      String.downcase(Enum.join([source["name"], source["coverage"], source["country"]], " ")),
      String.downcase(String.trim(query))
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main id="transport-data" class="fixed inset-0 overflow-y-auto bg-base-200 px-4 py-8 sm:py-12">
        <div class="mx-auto max-w-3xl">
          <.link navigate={@return_to} class="btn btn-ghost btn-sm">← {if String.starts_with?(@return_to, "/setup"), do: "Back to setup", else: "Back to map"}</.link>
          <h1 class="mt-5 font-display text-4xl font-extrabold">Transport data</h1>
          <p class="mt-3 text-base-content/70">Connect timetables for the places you travel. Live updates are optional; routes can still use the schedule.</p>
          <p class="mt-2 text-sm text-base-content/65">Street data is installed separately in Settings or the setup wizard. A source may cover only some operators in a region.</p>
          <div :if={@error} role="alert" class="alert alert-error mt-4">{@error}</div>
          <div :if={@message} role="status" class="mt-4 rounded-xl bg-base-100 p-4">{@message}</div>

          <section class="mt-6 rounded-2xl bg-base-100 p-5 sm:p-7" aria-label="Connected sources">
            <h2 class="text-xl font-bold">Connected sources</h2>
            <p :if={@pending} class="mt-3 font-semibold text-warning">Source selection has unapplied changes.</p>
            <p :if={@sources == []} class="mt-3 text-base-content/65">No sources connected here yet. Existing region timetables continue to work until you apply a source selection.</p>
            <div :if={@legacy_files != []} class="mt-3 rounded-xl border border-base-300 p-4">
              <h3 class="font-semibold">Existing region timetables</h3>
              <p :for={file <- @legacy_files} class="text-sm mt-1">{file}</p>
              <p class="mt-2 text-xs text-base-content/65">Files on disk used by the existing region setup; filenames do not confirm coverage or graph readiness. To manage updates here, connect the matching provider below and apply. Applying replaces the timetable selection, not street data.</p>
            </div>
            <article :for={s <- @sources} id={"source-" <> s["id"]} class="mt-4 rounded-xl border border-base-300 p-4">
              <div class="flex flex-wrap items-center justify-between gap-3">
                <h3 class="font-bold">{s["name"]}</h3>
                <button phx-click="toggle" phx-value-id={s["id"]} phx-value-field="enabled" disabled={@busy}
                  aria-pressed={to_string(s["enabled"])} class="btn btn-sm btn-outline">{if s["enabled"], do: "Enabled", else: "Disabled"}</button>
              </div>
              <p class="mt-1 text-sm text-base-content/65">{s["coverage"]}</p>
              <p class="mt-3 text-sm">
                <%= if timestamp = get_in(@statuses, [s["id"], "downloaded_at"]) do %>
                  Last successful download: <time id={"source-#{s["id"]}-downloaded"} datetime={timestamp} phx-hook="LocalTime">{timestamp}</time>
                <% else %>Not downloaded yet<% end %>
              </p>
              <p :if={@statuses[s["id"]] && @statuses[s["id"]]["error"]} class="mt-2 text-sm text-warning" role="status">{@statuses[s["id"]]["error"]}</p>
              <div class="mt-3 flex flex-wrap items-center gap-3">
                <button :if={s["realtime_url"] not in [nil, ""]} phx-click="toggle" phx-value-id={s["id"]} phx-value-field="realtime"
                  disabled={@busy or not s["enabled"]} aria-pressed={to_string(s["realtime"])} class="btn btn-sm btn-ghost">{cond do
                    not s["enabled"] -> "Live updates inactive · source disabled"
                    s["realtime"] -> "Live updates configured"
                    true -> "Live updates off"
                  end}</button>
                <span :if={s["realtime_url"] in [nil, ""]} class="badge badge-ghost">Schedule only</span>
                <.link :if={s["license_url"] not in [nil, ""]} href={s["license_url"]} target="_blank" rel="noopener noreferrer" class="link text-sm">{s["license"]}</.link>
                <button phx-click="edit" phx-value-id={s["id"]} disabled={@busy} class="btn btn-sm btn-ghost">Edit source</button>
                <span :if={s["header_value"] not in [nil, ""]} class="text-sm">API key saved</span>
              </div>
              <p :if={s["realtime"]} class="mt-2 text-xs text-base-content/60">Live updates are configured when applied. This does not confirm a healthy feed or live coverage for every journey.</p>
              <p :if={s["notice"]} class="mt-2 text-sm text-base-content/70">{s["notice"]}</p>
              <p :if={s["attribution"]} class="mt-2 text-xs text-base-content/60">Data: {s["attribution"]}</p>
            </article>
            <div class="mt-5 flex flex-wrap items-center gap-3">
              <button phx-click="refresh" disabled={@busy or @sources == []} class="btn btn-primary">{if @busy, do: "Installation in progress…", else: "Download & apply"}</button>
              <button phx-click="auto_update" aria-pressed={to_string(@auto_update)} class="btn btn-ghost btn-sm">{if @auto_update, do: "Daily updates on", else: "Daily updates off"}</button>
            </div>
            <p class="mt-2 text-xs text-base-content/65">Daily timetable updates run at 03:00 UTC and may rebuild the transport engine. Failed downloads keep the last valid file.</p>
            <p class="mt-2 text-sm text-base-content/65">Overlapping providers can duplicate routes. Enable only the sources you need.</p>
          </section>

          <section class="mt-6 rounded-2xl bg-base-100 p-5 sm:p-7" aria-label="Find a provider">
            <h2 class="text-xl font-bold">Find a provider</h2>
            <form phx-change="search" phx-submit="search" class="mt-4">
              <.input name="query" id="provider-search" value={@query} type="search" label="Country, region or operator" placeholder="Berlin, Brandenburg, Germany…" phx-debounce="150" />
            </form>
            <p :if={Enum.all?(@catalog, &(not matches?(&1, @query)))} class="my-4">No verified source in this catalog yet. You can add a provider URL below.</p>
            <article :for={s <- Enum.filter(@catalog, &matches?(&1, @query))} class="mt-4 rounded-xl border border-base-300 p-4">
              <h3 class="font-bold">{s["name"]}</h3>
              <p class="mt-1 text-sm">{s["coverage"]}</p>
              <p class="mt-2 text-sm">Free · No registration · Commercial use allowed · Schedule + live updates</p>
              <p class="mt-2 text-sm text-base-content/65">{s["notice"]}</p>
              <div class="mt-3 flex flex-wrap items-center gap-4">
                <button phx-click="connect" phx-value-id={s["id"]} class="btn btn-primary btn-sm" disabled={@busy or Enum.any?(@sources, &(&1["id"] == s["id"]))}>{if Enum.any?(@sources, &(&1["id"] == s["id"])), do: "Connected", else: "Connect source"}</button>
                <.link href={s["website"]} target="_blank" rel="noopener noreferrer" class="link text-sm">Provider & license</.link>
              </div>
            </article>
            <button :if={!@adding} phx-click="add" disabled={@busy} class="btn btn-outline mt-5">Add your own source</button>
            <.form :if={@adding} for={@form} id="custom-source" phx-submit="save" phx-mounted={JS.focus(to: "#source_name")} class="mt-5 border-t border-base-300 pt-5">
              <h3 class="mb-4 text-lg font-bold">Add your own source</h3>
              <.input field={@form[:name]} label="Source name" required />
              <.input field={@form[:coverage]} label="Coverage" placeholder="City, region or operators covered" />
              <.input field={@form[:url]} type="url" label="GTFS timetable ZIP URL" required />
              <.input field={@form[:realtime_url]} type="url" label="GTFS-RT TripUpdates URL (optional)" />
              <p class="mb-4 text-sm text-base-content/65">Use realtime data that matches this exact timetable. Vehicle positions alone cannot update arrival times.</p>
              <.input field={@form[:license_url]} type="url" label="Provider license URL (optional)" />
              <.input field={@form[:header_name]} label="API key header (optional)" placeholder="Authorization or X-API-Key" />
              <.input name="source[header_value]" value="" id="source-key" type="password" label="API key value (optional; leave blank to keep saved key)" autocomplete="new-password" />
              <.input :if={@editing} name="source[clear_key]" value="false" type="checkbox" label="Remove saved API key" />
              <p class="mb-4 text-sm text-base-content/65">The header is used for this source's timetable and live updates. Credentials are stored on your Atlas server. Check the provider's terms before using its data.</p>
              <div class="flex gap-3"><button class="btn btn-primary" disabled={@busy}>Save source</button><button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button></div>
            </.form>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
