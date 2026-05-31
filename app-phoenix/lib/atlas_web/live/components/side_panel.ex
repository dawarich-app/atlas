defmodule AtlasWeb.SidePanel do
  @moduledoc """
  The icon-rail + tab body + attribution side panel rendered by
  `MapLive`. Pure function component — all state lives in the parent
  LiveView's assigns and is passed through here.
  """

  use Phoenix.Component

  import AtlasWeb.IconHelpers

  attr :active_tab, :string, required: true
  attr :search_query, :string, required: true
  attr :search_results, :list, required: true
  attr :directions, :any, required: true
  attr :mode, :string, required: true
  attr :route_from, :string, default: ""
  attr :route_to, :string, default: ""
  attr :route_options, :map, default: %{}
  attr :places, :list, required: true
  attr :tiles_url, :string, required: true
  attr :theme, :string, required: true
  attr :service_status, :map, required: true
  attr :tiles_download, :any, default: nil

  def side_panel(assigns) do
    ~H"""
    <aside class="flex flex-col flex-none">
      <div class="apo-brand px-2.5 py-3 flex items-center gap-2.5 flex-shrink-0">
        <span class="w-2.5 h-2.5 rounded-full bg-primary shadow-sm flex-shrink-0"></span>
        <span class="apo-brand-text font-display font-semibold text-[15px] leading-none tracking-tight whitespace-nowrap text-base-content">
          Dawarich Atlas
        </span>
      </div>

      <div class="flex flex-1 min-h-0">
        <nav class="flex flex-col gap-1 p-1.5 flex-shrink-0">
          <.tab_button active={@active_tab} tab="search" icon="search" label="Search" />
          <.tab_button active={@active_tab} tab="route" icon="route" label="Directions" />
          <.tab_button active={@active_tab} tab="places" icon="map-pin" label="Places" />
          <.tab_button active={@active_tab} tab="settings" icon="settings" label="Settings" />
          <div class="flex-1"></div>
          <button
            type="button"
            class="btn btn-square btn-sm btn-ghost"
            aria-label="Toggle light/dark"
            title="Toggle light/dark"
            onclick="window.atlasToggleTheme()"
          >
            {icon("moon", class: "w-4 h-4")}
          </button>
        </nav>

        <div class="w-[min(85vw,380px)] flex flex-col overflow-hidden">
          <div class={tab_visible_class(@active_tab, "search")}>
            <AtlasWeb.SearchCard.search_card
              id="search-card"
              query={@search_query}
              results={@search_results}
            />
          </div>
          <div class={tab_visible_class(@active_tab, "route")}>
            <AtlasWeb.DirectionsCard.directions_card
              id="directions-card"
              directions={@directions}
              mode={@mode}
              route_from={@route_from}
              route_to={@route_to}
              route_options={@route_options}
            />
          </div>
          <div class={tab_visible_class(@active_tab, "places")}>
            <.live_component module={AtlasWeb.PlacesCard} id="places-card" places={@places} />
          </div>
          <div class={tab_visible_class(@active_tab, "settings")}>
            <.live_component
              module={AtlasWeb.SettingsPanel}
              id="settings-panel"
              tiles_url={@tiles_url}
              theme={@theme}
              service_status={@service_status}
              tiles_download={@tiles_download}
            />
          </div>
        </div>
      </div>

      <div class="apo-brand-text px-2.5 py-2 text-[11px] leading-none text-base-content/50 flex-shrink-0">
        Made by
        <a
          href="https://dawarich.app?utm_source=atlas-map&utm_medium=referral&utm_campaign=atlas-map"
          target="_blank"
          rel="noopener noreferrer"
          class="font-medium text-base-content/70 hover:text-primary transition-colors"
        >
          Dawarich
        </a>
        people
      </div>
    </aside>
    """
  end

  attr :active, :string, required: true
  attr :tab, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      type="button"
      class={"btn btn-square btn-sm " <> tab_class(@active, @tab)}
      phx-click="select_tab"
      phx-value-tab={@tab}
      aria-label={@label}
      title={@label}
    >
      {icon(@icon, class: "w-5 h-5")}
    </button>
    """
  end

  defp tab_class(active, tab) when active == tab, do: "btn-primary"
  defp tab_class(_active, _tab), do: "btn-ghost"

  defp tab_visible_class(active, tab) when active == tab, do: "flex-1 min-h-0"
  defp tab_visible_class(_active, _tab), do: "hidden flex-1 min-h-0"
end
