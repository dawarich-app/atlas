defmodule Atlas.Control.Onboarding do
  @moduledoc "Persistent setup draft and installation coordinator, independent of the browser."
  use GenServer

  alias Atlas.Control.{
    DockerCompose,
    Preflight,
    RegionApplier,
    RegionCatalog,
    Safe,
    Service,
    ServiceState
  }

  alias Atlas.{Repo, Settings}

  @topic "control:onboarding"
  @capabilities ~w(search places routing transit)

  def capabilities, do: @capabilities
  def topic, do: @topic
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def install(draft), do: GenServer.call(__MODULE__, {:install, draft})
  def retry_service(name), do: GenServer.call(__MODULE__, {:retry_service, name})

  def first_run? do
    services = Repo.all(Service)

    Settings.get("setup_dismissed") != "true" and Settings.get("setup_job") == nil and
      Settings.get("applied_regions") == nil and length(services) >= 8 and
      Enum.all?(
        services,
        &(!&1.enabled and &1.disk_bytes == 0 and &1.status in [:unknown, :stopped])
      )
  end

  def dismiss, do: Settings.set("setup_dismissed", "true")

  def draft do
    read("setup_draft", %{
      "capabilities" => ["search", "routing"],
      "regions" => [],
      "backend" => Settings.transit_backend(),
      "step" => 1
    })
  end

  def save_draft(draft), do: Settings.set("setup_draft", Jason.encode!(draft))
  def job, do: read("setup_job", nil)

  def services(draft) do
    Enum.flat_map(draft["capabilities"], fn
      "search" -> ["photon"]
      "places" -> ["photon", "overpass"]
      "routing" -> ["photon", "valhalla"]
      "transit" -> ["photon", draft["backend"]]
    end)
    |> Enum.uniq()
  end

  def validate(draft, catalog \\ RegionCatalog.all()) do
    selected = Enum.filter(catalog, &(&1.name in draft["regions"]))

    cond do
      draft["capabilities"] == [] ->
        {:error, "Choose at least one capability."}

      Enum.any?(draft["capabilities"], &(&1 not in @capabilities)) ->
        {:error, "Unknown capability."}

      draft["backend"] not in ~w(motis otp) ->
        {:error, "Choose MOTIS or OpenTripPlanner."}

      draft["regions"] == [] ->
        {:error, "Choose at least one region."}

      length(selected) != length(Enum.uniq(draft["regions"])) ->
        {:error, "A selected region is no longer available."}

      true ->
        :ok
    end
  end

  @doc "Regions lacking catalog timetables; missing coverage is advisory, not a validation error."
  def missing_transit_regions(draft, catalog) do
    if "transit" in draft["capabilities"] do
      selected = Enum.filter(catalog, &(&1.name in draft["regions"]))

      if Atlas.Control.TransitSources.configured?() do
        covered = Atlas.Control.TransitSources.enabled() |> Enum.flat_map(&(&1["regions"] || []))
        Enum.reject(selected, &(&1.name in covered))
      else
        Enum.filter(selected, &(&1.gtfs_url in [nil, ""]))
      end
    else
      []
    end
  end

  defp read(key, fallback) do
    case Jason.decode(Settings.get(key, "null")) do
      {:ok, nil} -> fallback
      {:ok, value} -> value
      _ -> fallback
    end
  end

  @impl true
  def init(opts) do
    Phoenix.PubSub.subscribe(Atlas.PubSub, RegionApplier.topic())
    Phoenix.PubSub.subscribe(Atlas.PubSub, "control:status")

    state = %{
      apply: Keyword.get(opts, :apply, &RegionApplier.start/2),
      enable: Keyword.get(opts, :enable, &enable/1),
      snapshot: Keyword.get(opts, :snapshot, &Safe.snapshot/1),
      preflight: Keyword.get(opts, :preflight, &Preflight.results/0),
      job: job(),
      worker: nil
    }

    state =
      if state.job && state.job["status"] in ~w(preparing starting),
        do:
          persist(
            state,
            Map.merge(state.job, %{
              "status" => "failed",
              "error" =>
                "Setup was interrupted by an Atlas restart. Retry to reuse downloaded files."
            })
          ),
        else: state

    {:ok, state}
  end

  @impl true
  def handle_call({:install, draft}, _from, state) do
    cond do
      state.worker != nil or (state.job && state.job["status"] in ~w(preparing starting waiting)) ->
        {:reply, {:error, "An installation is already in progress."}, state}

      validate(draft) != :ok ->
        {:reply, validate(draft), state}

      state.preflight.() == [] or not Preflight.healthy?(state.preflight.()) ->
        {:reply,
         {:error, "Installation checks are not ready or have failed. Check the details below."},
         state}

      true ->
        start_install(state, draft)
    end
  end

  def handle_call({:retry_service, name}, _from, state) do
    if ((state.worker == nil and state.job) && name in services(state.job["draft"])) and
         state.job["status"] in ~w(waiting complete) do
      {:reply, :ok, launch(state, [name])}
    else
      {:reply, {:error, "This service cannot be retried yet."}, state}
    end
  end

  defp start_install(state, draft) do
    job = %{"draft" => draft, "status" => "preparing", "error" => nil, "id" => nil}
    names = services(draft)

    if Enum.any?(names, &(&1 in ~w(valhalla overpass motis otp))) do
      case state.apply.(draft["regions"], services: names) do
        {:ok, id} ->
          save_draft(Map.put(draft, "step", 4))
          dismiss()
          search_result = start_search(state)
          job = Map.put(job, "error", startup_error(search_result))
          {:reply, :ok, persist(state, Map.put(job, "id", id))}

        {:error, reason} ->
          {:reply, {:error, "Could not start installation: #{inspect(reason)}"}, state}
      end
    else
      save_draft(Map.put(draft, "step", 4))
      dismiss()
      {:reply, :ok, state |> persist(job) |> launch(names)}
    end
  end

  @impl true
  def handle_info(
        {:apply_done, %{job_id: id}},
        %{job: %{"id" => id, "status" => "preparing"}} = state
      ) do
    {:noreply, launch(state, List.delete(services(state.job["draft"]), "photon"))}
  end

  def handle_info({:apply_error, %{job_id: id, reason: reason}}, %{job: %{"id" => id}} = state) do
    {:noreply, persist(state, Map.merge(state.job, %{"status" => "failed", "error" => reason}))}
  end

  def handle_info({:services_started, result}, state) do
    job = Map.merge(state.job, %{"status" => "waiting", "error" => result || state.job["error"]})
    {:noreply, state |> persist(job) |> check_ready()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{worker: ref} = state) do
    state = %{state | worker: nil}

    if reason == :normal do
      {:noreply, state}
    else
      {:noreply,
       persist(
         state,
         Map.merge(state.job, %{
           "status" => "failed",
           "error" => "Service startup was interrupted. Retry installation."
         })
       )}
    end
  end

  def handle_info(:status_changed, state), do: {:noreply, check_ready(state)}
  def handle_info(_, state), do: {:noreply, state}

  defp launch(state, names) do
    parent = self()
    enable = state.enable

    {_pid, ref} =
      :erlang.spawn_opt(
        fn ->
          errors = Enum.flat_map(names, &start_service(&1, enable))

          send(
            parent,
            {:services_started, if(errors == [], do: nil, else: Enum.join(errors, "; "))}
          )
        end,
        [:link, :monitor]
      )

    persist(
      %{state | worker: ref},
      Map.put(state.job, "status", "starting")
    )
  end

  defp start_search(state) do
    Safe.call(fn -> state.enable.("photon") end, {:error, :startup_failed})
  end

  defp startup_error(:ok), do: nil
  defp startup_error({:ok, _}), do: nil
  defp startup_error(error), do: "Search could not start: #{inspect(error)}"

  defp start_service(name, enable) do
    case enable.(name) do
      :ok -> []
      {:ok, _} -> []
      error -> ["#{name}: #{inspect(error)}"]
    end
  end

  defp check_ready(%{job: %{"status" => "waiting"}} = state) do
    ready =
      Enum.all?(services(state.job["draft"]), fn name ->
        match?(%{ready?: true, enabled?: true}, state.snapshot.(name))
      end)

    if ready,
      do: persist(state, Map.merge(state.job, %{"status" => "complete", "error" => nil})),
      else: state
  end

  defp check_ready(state), do: state

  defp persist(state, job) do
    {:ok, _} = Settings.set("setup_job", Jason.encode!(job))
    Phoenix.PubSub.broadcast(Atlas.PubSub, @topic, {:setup_job, job})
    %{state | job: job}
  end

  defp enable(name) when name in ~w(motis otp), do: DockerCompose.select_transit(name)
  defp enable(name), do: ServiceState.enable(name)
end
