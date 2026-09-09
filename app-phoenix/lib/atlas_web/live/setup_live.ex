defmodule AtlasWeb.SetupLive do
  use AtlasWeb, :live_view

  alias AtlasWeb.Layouts

  alias Atlas.Control.{ApplyTimeline, Onboarding, Preflight, RegionCatalog, Safe}

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, Onboarding.topic())
      Phoenix.PubSub.subscribe(Atlas.PubSub, "control:status")
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())
    end

    job = Onboarding.job()
    draft = Onboarding.draft()

    step =
      cond do
        job && job["status"] in ~w(preparing starting waiting) -> 4
        params["step"] in ~w(1 2 3) -> String.to_integer(params["step"])
        job && job["status"] == "failed" -> 4
        true -> draft["step"]
      end

    {:ok,
     assign(socket,
       page_title: "Set up Atlas",
       draft: draft,
       transport_sources: Atlas.Control.TransitSources.enabled(),
       step: step,
       regions: RegionCatalog.all(),
       query: "",
       job: job,
       error: nil,
       checks: Preflight.results(),
       checking: false,
       timeline: Safe.call(&ApplyTimeline.current/0, nil),
       installation_details_open: false,
       statuses: snapshots()
     ), layout: false}
  end

  @impl true
  def handle_event("capability", %{"name" => name}, socket) do
    if name in Onboarding.capabilities() and socket.assigns.step == 1 do
      values = toggle(socket.assigns.draft["capabilities"], name)
      {:noreply, save(socket, "capabilities", values)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("region_search", %{"query" => query}, socket),
    do: {:noreply, assign(socket, query: query)}

  def handle_event("region", %{"name" => name}, socket) do
    if socket.assigns.step == 2 and Enum.any?(socket.assigns.regions, &(&1.name == name)) do
      {:noreply, save(socket, "regions", toggle(socket.assigns.draft["regions"], name))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("backend", %{"backend" => backend}, socket) when backend in ~w(motis otp),
    do: {:noreply, save(socket, "backend", backend)}

  def handle_event("next", _, socket) do
    error =
      cond do
        socket.assigns.step == 1 and socket.assigns.draft["capabilities"] == [] ->
          "Choose at least one capability."

        socket.assigns.step == 2 ->
          case Onboarding.validate(socket.assigns.draft, socket.assigns.regions) do
            :ok -> nil
            {:error, message} -> message
          end

        true ->
          nil
      end

    if error,
      do: {:noreply, assign(socket, error: error)},
      else: {:noreply, step(socket, min(socket.assigns.step + 1, 3))}
  end

  def handle_event("back", _, socket) do
    if socket.assigns.step in [2, 3] or
         (socket.assigns.job && socket.assigns.job["status"] in ~w(failed complete)),
       do: {:noreply, step(socket, max(socket.assigns.step - 1, 1))},
       else: {:noreply, socket}
  end

  def handle_event("skip", _, socket) do
    Onboarding.dismiss()
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("install", _, socket) do
    case Safe.call(
           fn -> Onboarding.install(socket.assigns.draft) end,
           {:error, "Setup service is unavailable. Restart Atlas and try again."}
         ) do
      :ok -> {:noreply, assign(socket, step: 4, job: Onboarding.job(), error: nil)}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("retry_service", %{"name" => name}, socket) do
    case Safe.call(
           fn -> Onboarding.retry_service(name) end,
           {:error, "Setup service is unavailable."}
         ) do
      :ok -> {:noreply, assign(socket, error: nil)}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("recheck", _, socket),
    do: {:noreply, socket |> assign(checking: true) |> start_async(:checks, &Preflight.refresh/0)}

  def handle_event("toggle_installation_details", _, socket) do
    {:noreply,
     assign(socket,
       installation_details_open: not Map.get(socket.assigns, :installation_details_open, false)
     )}
  end

  def handle_event("dismiss_timeline", _, socket), do: {:noreply, assign(socket, timeline: nil)}

  @impl true
  def handle_async(:checks, {:ok, checks}, socket),
    do: {:noreply, assign(socket, checks: checks, checking: false)}

  def handle_async(:checks, {:exit, _}, socket),
    do: {:noreply, assign(socket, checking: false, error: "Could not run installation checks.")}

  @impl true
  def handle_info({:setup_job, job}, socket),
    do: {:noreply, assign(socket, job: job, statuses: snapshots())}

  def handle_info(:status_changed, socket),
    do: {:noreply, assign(socket, statuses: snapshots(), checks: Preflight.results())}

  def handle_info({:timeline, timeline}, socket),
    do: {:noreply, assign(socket, timeline: timeline)}

  def handle_info(_, socket), do: {:noreply, socket}

  defp step(socket, number),
    do: socket |> save("step", number) |> assign(step: number, error: nil)

  defp save(socket, key, value) do
    draft = Map.put(socket.assigns.draft, key, value)
    Onboarding.save_draft(draft)
    assign(socket, draft: draft, error: nil)
  end

  defp toggle(values, value),
    do: if(value in values, do: List.delete(values, value), else: values ++ [value])

  defp snapshots, do: Map.new(~w(photon valhalla overpass motis otp), &{&1, Safe.snapshot(&1)})
  defp selected(draft, regions), do: Enum.filter(regions, &(&1.name in draft["regions"]))

  defp visible(regions, query) do
    query = String.downcase(String.trim(query))

    regions
    |> Enum.filter(fn r ->
      if query == "",
        do: r.name in ~w(berlin germany france london new-york),
        else: String.contains?(String.downcase(r.label <> " " <> r.name), query)
    end)
    |> Enum.sort_by(& &1.label)
    |> Enum.take(40)
  end

  defp label("search"), do: "Search addresses"
  defp label("places"), do: "Explore places"
  defp label("routing"), do: "Plan street routes"
  defp label("transit"), do: "Use public transport"
  defp description("search"), do: "Find addresses and named places on the map."

  defp description("places"),
    do: "Discover cafés, shops and other places by category. Includes search."

  defp description("routing"), do: "Walk, cycle or drive between addresses. Includes search."

  defp description("transit"),
    do: "Combine trains, buses and walking using local timetables. Includes search."

  defp service_label("photon"), do: "Address and place search"
  defp service_label("valhalla"), do: "Walking, cycling and driving"
  defp service_label("overpass"), do: "Places by category"
  defp service_label(_), do: "Public transport"
  defp service_state(nil), do: "Waiting to start"
  defp service_state(%{ready?: true, enabled?: true}), do: "Ready"
  defp service_state(%{enabled?: false}), do: "Waiting to start"
  defp service_state(%{status: status}), do: status |> to_string() |> String.capitalize()
  defp retryable?(nil), do: true
  defp retryable?(s), do: s.status in [:error, :unhealthy, :stopped] or not s.enabled?

  defp regional_data?(draft), do: Enum.any?(draft["capabilities"], &(&1 != "search"))

  defp download_size(regions) do
    known = Enum.filter(regions, &is_integer(&1.pbf_bytes))
    bytes = Enum.sum(Enum.map(known, & &1.pbf_bytes))

    if known == [],
      do: "Size unavailable",
      else:
        RegionCatalog.format_bytes(bytes) <>
          if(length(known) < length(regions), do: " + unknown sizes", else: "")
  end

  defp timetable_label(region, sources, configured?) do
    covered =
      if configured?,
        do: Enum.any?(sources, &(region.name in (&1["regions"] || []))),
        else: region.gtfs_url not in [nil, ""]

    if covered, do: "Timetable configured", else: "Timetable not connected"
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        missing_transit: Onboarding.missing_transit_regions(assigns.draft, assigns.regions),
        sources_configured: Atlas.Control.TransitSources.configured?()
      )

    assigns = assign_new(assigns, :installation_details_open, fn -> false end)

    ~H"""
    <Layouts.app flash={@flash}>
      <main id="setup-wizard" class="fixed inset-0 overflow-y-auto overscroll-contain bg-base-200 px-4 py-8 sm:py-12">
        <div class="mx-auto max-w-3xl">
          <header class="mb-8 flex items-start justify-between gap-4">
            <div>
              <p class="text-sm font-semibold uppercase tracking-widest text-primary">Atlas · Getting started</p>
              <h1 class="mt-2 font-display text-3xl font-extrabold sm:text-4xl">Your map, your way</h1>
              <p class="mt-3 text-base-content/65">Choose what you need. Atlas will prepare the services behind it.</p>
            </div>
            <button phx-click="skip" class="btn btn-ghost btn-sm shrink-0">{if @step == 4, do: "Use map", else: "Set up later"}</button>
          </header>
          <ol class="mb-6 grid grid-cols-4 gap-2" aria-label="Setup progress">
            <li :for={{title, n} <- [{"Features", 1}, {"Regions", 2}, {"Review", 3}, {"Install", 4}]}
                aria-current={if @step == n, do: "step"}
                class={["border-t-4 pt-2 text-sm", if(@step >= n, do: "border-primary font-semibold", else: "border-base-300 text-base-content/50")]}>
              {n}. {title}
            </li>
          </ol>
          <section class="rounded-2xl bg-base-100 p-5 shadow-sm sm:p-8">
            <div :if={@step == 1}>
              <h2 id="setup-step-title" tabindex="-1" class="text-2xl font-bold focus:outline-none">What would you like to do?</h2>
              <p class="mt-2 mb-6 text-base-content/65">Choose any combination. You can add more later.</p>
              <div class="grid gap-3 sm:grid-cols-2">
                <button :for={name <- Onboarding.capabilities()} phx-click="capability" phx-value-name={name}
                  aria-pressed={to_string(name in @draft["capabilities"])}
                  class={["rounded-xl border-2 p-5 text-left transition-colors", if(name in @draft["capabilities"], do: "border-primary bg-primary/5", else: "border-base-300 hover:border-primary/50")] }>
                  <span class="block font-semibold">{if name in @draft["capabilities"], do: "✓ ", else: "+ "}{label(name)}</span>
                  <span class="mt-2 block text-sm text-base-content/65">{description(name)}</span>
                </button>
              </div>
            </div>
            <div :if={@step == 2}>
              <h2 id="setup-step-title" tabindex="-1" class="text-2xl font-bold focus:outline-none">Where will you use Atlas?</h2>
              <p class="mt-2 text-base-content/65">Start with a city or small region for a quicker installation.</p>
              <p class="mt-3 rounded-lg bg-base-200 p-3 text-sm">This selection sets coverage for routes and places by category. Address search uses a separate Photon index, configured for this Atlas installation.</p>
              <div class="my-4 flex flex-wrap gap-2" aria-label="Selected regions">
                <button :for={r <- selected(@draft, @regions)} phx-click="region" phx-value-name={r.name} class="btn btn-primary btn-sm" aria-label={"Remove #{r.label}"}>{r.label} ×</button>
                <span :if={@draft["regions"] == []} class="text-sm text-base-content/60">No regions selected</span>
              </div>
              <form phx-change="region_search" phx-submit="region_search">
                <.input type="search" id="setup-region-search" name="query" label="Find a region" value={@query} placeholder="Search cities, regions or countries" phx-debounce="150" />
              </form>
              <p :if={visible(@regions, @query) == []} class="py-4">No matching regions. Try a country or a nearby city.</p>
              <div class="mt-3 max-h-80 overflow-y-auto rounded-xl border border-base-300">
                <button :for={r <- visible(@regions, @query)} phx-click="region" phx-value-name={r.name}
                  aria-pressed={to_string(r.name in @draft["regions"])} class="flex w-full items-center justify-between gap-3 border-b border-base-200 p-3 text-left hover:bg-base-200">
                  <span>{if r.name in @draft["regions"], do: "✓ ", else: "+ "}{r.label}<span class="mt-1 block text-xs text-base-content/60">{RegionCatalog.source_label(r)} · {RegionCatalog.size_label(r)}</span></span>
                  <span class="text-right text-xs text-base-content/60">{timetable_label(r, @transport_sources, @sources_configured)}</span>
                </button>
              </div>
              <p class="mt-2 text-xs text-base-content/55">Up to 40 matches shown. Narrow your search to find more.</p>
            </div>
            <div :if={@step == 3}>
              <h2 id="setup-step-title" tabindex="-1" class="text-2xl font-bold focus:outline-none">Ready to install</h2>
              <p class="mt-2 text-base-content/65">Check the coverage and services before starting.</p>
              <dl class="mt-5 space-y-4">
                <div><dt class="font-semibold">Features</dt><dd>{Enum.map_join(@draft["capabilities"], ", ", &label/1)}</dd></div>
                <div><dt class="font-semibold">Regional data</dt><dd>{if regional_data?(@draft), do: Enum.map_join(selected(@draft, @regions), ", ", & &1.label), else: "Not needed for search alone"}</dd></div>
                <div><dt class="font-semibold">Map source download</dt><dd>{if regional_data?(@draft), do: download_size(selected(@draft, @regions)), else: "No regional map download"}</dd><dd class="text-sm text-base-content/60">Excludes search indexes, timetables and container images. Prepared data needs additional disk space. Installation can take minutes to hours.</dd></div>
              </dl>
              <form :if={"transit" in @draft["capabilities"]} phx-change="backend" class="mt-5">
                <fieldset><legend class="font-semibold">Public transport engine</legend>
                  <p class="mb-3 text-sm text-base-content/65">Only one engine can run. Atlas stops the other when switching.</p>
                  <label :for={{value, title} <- [{"motis", "MOTIS"}, {"otp", "OpenTripPlanner"}]} class="mr-5 inline-flex items-center gap-2">
                    <input type="radio" name="backend" value={value} checked={@draft["backend"] == value} class="radio radio-primary" />{title}
                  </label>
                </fieldset>
              </form>
              <div class="mt-5 rounded-xl bg-base-200 p-4 text-sm">
                <p>Atlas will enable: <strong>{Enum.join(Onboarding.services(@draft), ", ")}</strong>.</p>
                <p class="mt-2">Existing services stay enabled, except the other public transport engine. Selected regional services receive updated inputs; already downloaded source files are reused.</p>
                <p class="mt-2">Search coverage follows the separately configured Photon index. Selecting a smaller region here does not reduce its download.</p>
              </div>
              <details class="mt-4 text-sm"><summary class="cursor-pointer font-semibold">Advanced installation details</summary>
                <p class="mt-2">Photon's country is configured by COUNTRY_CODE in the deployment .env file (Germany by default). Change it before installing search if you need another country. An existing index keeps its own coverage.</p>
                <p class="mt-2">The map background keeps your current basemap configuration.</p>
              </details>
              <div class="mt-5 border-t border-base-300 pt-4">
                <p class="font-semibold">Installation checks</p>
                <p :if={@checks == []} class="text-sm">Checks are not ready yet.</p>
                <p :if={@checks != [] and Preflight.healthy?(@checks)} class="text-sm text-success">Installation environment is ready.</p>
                <p :for={check <- Preflight.failures(@checks)} class="mt-2 text-sm text-error">{check.remedy || check.detail}</p>
                <button phx-click="recheck" disabled={@checking} class="btn btn-ghost btn-sm mt-2">{if @checking, do: "Checking…", else: "Check again"}</button>
              </div>
            </div>
            <div :if={@step == 4} aria-live="polite">
              <h2 id="setup-step-title" tabindex="-1" class="text-2xl font-bold focus:outline-none">{if @job && @job["status"] == "complete", do: "Atlas is ready", else: "Preparing your Atlas"}</h2>
              <p class="mt-2 text-base-content/65">{if @job && @job["status"] == "complete", do: "Your selected features are ready to use. You can add more from Settings.", else: "You can use ready features now. Installation continues when you leave this page."}</p>
              <div :if={@job && @job["error"]} role="alert" class="mt-4 rounded-lg bg-error/10 p-3 text-sm text-error">{@job["error"]}</div>
              <p :if={@job && @job["status"] == "preparing"} class="mt-4 font-semibold"><span class="loading loading-spinner loading-xs mr-2"></span>Downloading and preparing regional data</p>
              <div :if={@job} class="mt-5 space-y-3">
                <div :for={name <- Onboarding.services(@job["draft"])} class="rounded-xl border border-base-300 p-4">
                  <div class="flex items-center justify-between gap-3"><span class="font-semibold">{service_label(name)}</span><span class="text-sm">{service_state(@statuses[name])}</span></div>
                  <p class="mt-1 text-xs text-base-content/55">{name}</p>
                  <p :if={@statuses[name] && @statuses[name].phase} class="mt-2 text-sm text-base-content/65">{@statuses[name].phase}</p>
                  <progress :if={@statuses[name] && is_number(@statuses[name].progress) && not @statuses[name].ready?}
                    class="progress progress-primary mt-2 w-full" max="1" value={@statuses[name].progress} aria-label={service_label(name) <> " progress"}></progress>
                  <p :if={@statuses[name] && @statuses[name].last_error} class="mt-2 break-words text-sm text-error">{@statuses[name].last_error}</p>
                  <button :if={@job["status"] in ~w(waiting complete) and retryable?(@statuses[name])} phx-click="retry_service" phx-value-name={name} class="btn btn-outline btn-sm mt-3">Retry {service_label(name)}</button>
                </div>
              </div>
              <section :if={@timeline && @job && @timeline.job_id == @job["id"]} id="installation-details" class="mt-5">
                <button id="installation-details-toggle" type="button" phx-click="toggle_installation_details"
                  aria-expanded={to_string(@installation_details_open)} aria-controls="installation-details-content"
                  class="flex items-center gap-2 text-sm font-semibold">
                  <span aria-hidden="true">{if @installation_details_open, do: "▾", else: "▸"}</span>
                  Installation details
                </button>
                <div id="installation-details-content" hidden={!@installation_details_open} class="mt-3">
                  <AtlasWeb.Components.ApplyTimelineComponent.timeline timeline={@timeline} />
                </div>
              </section>
              <button :if={@job && @job["status"] == "failed"} phx-click="install" class="btn btn-primary mt-5" phx-disable-with="Starting…">Retry installation</button>
              <p :if={@job && @job["status"] == "failed"} class="mt-2 text-sm text-base-content/60">Downloaded files are reused. Data preparation may need to run again.</p>
            </div>
            <aside :if={@step in [2, 3] and "transit" in @draft["capabilities"]} class="mt-5 rounded-xl border border-base-300 p-4">
              <h3 class="font-bold">Transport data sources</h3>
              <p class="mt-2 text-sm">Connect a provider for your region or add your own GTFS timetable. Live updates are optional. Connected sources are downloaded during installation.</p>
              <p :if={@transport_sources != []} class="mt-2 text-sm font-semibold">Selected: {Enum.map_join(@transport_sources, ", ", & &1["name"])}</p>
              <.link navigate={~p"/transport-data?from=setup&step=#{@step}"} class="btn btn-outline btn-sm mt-3">Choose transport sources</.link>
            </aside>
            <aside :if={@step in [2, 3] and @missing_transit != []}
              role="status" aria-live="polite" data-role="coverage-warning"
              class="mt-5 rounded-xl border border-warning/40 bg-warning/10 p-4 text-sm">
              <p class="font-semibold">Check public transport coverage</p>
              <p class="mt-2">Timetable coverage is not confirmed for: <strong>{Enum.map_join(@missing_transit, ", ", & &1.label)}</strong>.</p>
              <p class="mt-2">You can continue installing your selected features. Check whether your connected transport sources cover these regions. Without a suitable timetable, public transport routes will be unavailable. Other features can still be used where their data is available.</p>
            </aside>
            <p :if={@error} role="alert" class="mt-5 text-sm text-error">{@error}</p>
            <footer id="setup-actions" class="sticky bottom-0 z-10 mt-8 flex items-center justify-between gap-3 border-t border-base-300 bg-base-100 py-4">
              <button :if={@step in [2, 3] or (@step == 4 and @job && @job["status"] in ~w(failed complete))} id="setup-back" phx-click={JS.push("back") |> JS.focus(to: "#setup-step-title")} class="btn btn-ghost">Back</button>
              <span :if={@step == 1}></span>
              <button :if={@step < 3} phx-click="next" class="btn btn-primary">Continue</button>
              <button :if={@step == 3} phx-click="install" phx-disable-with="Starting…" disabled={@checks == [] or not Preflight.healthy?(@checks)} class="btn btn-primary">Install selected features</button>
              <button :if={@step == 4} phx-click="skip" class="btn btn-primary">Open map</button>
            </footer>
          </section>
          <p class="mt-5 text-center text-sm text-base-content/55">Your choices are saved automatically. Reopen this wizard in Settings.</p>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
