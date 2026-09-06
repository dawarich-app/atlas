defmodule AtlasWeb.SearchCard do
  @moduledoc """
  The search input card and its result list.
  """

  use Phoenix.Component

  import AtlasWeb.IconHelpers
  import AtlasWeb.Settings.Atoms

  alias Atlas.Control.ServiceFormatting, as: SF
  alias AtlasWeb.PlaceIcons

  attr :id, :string, required: true
  attr :query, :string, required: true
  attr :results, :list, required: true
  attr :status, :string, default: "ok"
  attr :service, :string, default: "photon"
  attr :snapshot, :any, default: nil
  attr :active, :integer, default: -1
  attr :searched, :boolean, default: false

  def search_card(assigns) do
    assigns =
      assigns
      |> assign(:state, state(assigns))
      |> assign(:service_name, String.capitalize(assigns.service))
      |> assign(:install_pct, SF.progress_pct(assigns.snapshot))

    ~H"""
    <div id={@id} class="flex flex-col h-full">
      <header class="px-4 pt-4">
        <.eyebrow>Geocoding</.eyebrow>
        <h2 class="mt-1 font-display text-3xl font-extrabold leading-none tracking-tight">
          Search
        </h2>
      </header>

      <div class="flex flex-col gap-4 px-4 py-4 overflow-y-auto flex-1 min-h-0">
        <form phx-change="search" phx-submit="search" class="relative">
          <input
            type="search"
            name="q"
            id="search-input"
            value={@query}
            placeholder="Places, addresses…"
            autocomplete="off"
            spellcheck="false"
            phx-debounce="200"
            phx-hook="SearchKeys"
            data-has-active={to_string(@active >= 0)}
            class="w-full rounded-2xl border-2 border-base-content/10 bg-base-300/40 px-4 py-3 pr-11 text-[15px] text-base-content outline-none transition focus:border-base-content"
          />
          <span class="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-base-content/55">
            {icon("search", class: "w-[18px] h-[18px]")}
          </span>
        </form>

        <div
          :if={@state == :not_installed}
          class="rounded-2xl bg-base-200/60 px-4 py-5 text-sm text-base-content/70"
        >
          <div class="font-semibold text-base-content">{@service_name} is not installed</div>
          <p class="mt-1 leading-relaxed">
            Search needs the {@service_name} geocoder and its dataset. Install it from
            <.link navigate="/admin/services" class="link link-hover font-medium">services</.link>.
          </p>
        </div>

        <div
          :if={@state == :installing}
          class="rounded-2xl bg-base-200/60 px-4 py-5 text-sm text-base-content/70"
        >
          <div class="font-semibold text-base-content">
            {@service_name} is still installing — {@install_pct}%
          </div>
          <p class="mt-1 leading-relaxed">
            Its dataset is still downloading. Search will work once it finishes.
          </p>
        </div>

        <div
          :if={@state == :failing}
          class="rounded-2xl bg-base-200/60 px-4 py-5 text-sm text-base-content/70"
        >
          <div class="font-semibold text-base-content">{@service_name} is not responding</div>
          <p class="mt-1 leading-relaxed">
            It is installed and running, so this is a fault rather than a missing dataset. Its
            <.link navigate="/admin/services" class="link link-hover font-medium">logs</.link>
            should say why.
          </p>
        </div>

        <div
          :if={@state == :empty}
          class="rounded-2xl bg-base-200/60 px-4 py-5 text-sm text-base-content/70"
        >
          No results for <span class="font-medium text-base-content">{@query}</span>.
        </div>

        <div :if={@state == :results}>
          <div class="mb-1.5 font-mono text-[11px] uppercase tracking-[0.2em] text-base-content/55">
            Results
          </div>
          <ul
            id="search-results"
            class="flex max-h-[60vh] flex-col gap-1 overflow-y-auto overflow-x-hidden list-none"
          >
            <li :for={{result, idx} <- Enum.with_index(@results)} class="list-none">
              <button
                type="button"
                phx-click="select_result"
                phx-value-id={result.id}
                data-active={to_string(idx == @active)}
                class={[
                  "flex w-full items-start gap-2.5 rounded-xl px-3 py-2.5 text-left transition",
                  if(idx == @active, do: "bg-primary/10", else: "hover:bg-base-100")
                ]}
              >
                <span class="mt-0.5 flex-shrink-0 text-base-content/40">
                  {icon(elem(PlaceIcons.for(result[:type]), 0), class: "w-4 h-4")}
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-sm font-medium leading-tight">
                    {result.label}
                  </span>
                  <span class="mt-0.5 block truncate font-mono text-[10.5px] uppercase tracking-[0.14em] text-base-content/45">
                    {elem(PlaceIcons.for(result[:type]), 1)}
                  </span>
                </span>
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  # The outcomes the panel must tell apart. Before this existed the card
  # rendered only `:results`, so a geocoder that was never installed, one that
  # had crashed, and a misspelt place name were all the same empty panel —
  # indistinguishable from a button that does nothing.
  #
  # `:not_installed` vs `:failing` is the distinction that matters most: the
  # first is the normal state of a fresh instance and the user fixes it by
  # turning the service on, the second is a fault they should read logs for.
  #
  # `:idle` keys off whether a search actually ran, not off an empty box: a
  # query below the minimum length is never sent, so answering it with
  # "No results" would be a claim we never checked.
  defp state(%{results: [_ | _]}), do: :results
  defp state(%{searched: false}), do: :idle
  defp state(%{status: "ok"}), do: :empty
  defp state(%{snapshot: snapshot}), do: SF.unavailable_reason(snapshot) || :failing
end
