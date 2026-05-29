defmodule AtlasWeb.IconHelpers do
  @moduledoc """
  Inline Lucide SVG icon helper.

  Reads SVGs from `priv/icons/` at compile time and exposes `icon/1` and
  `icon/2` for HEEx templates. Pass a `:class` opt to apply a Tailwind
  class string to the root `<svg>` element.

  Usage in a HEEx template:

      {icon("search", class: "w-5 h-5")}
  """

  # Resolve at compile time relative to the source file so we don't depend on
  # `Application.app_dir/2` (which points at `_build/.../priv/` and isn't
  # populated yet during the initial compile).
  @icons_dir Path.expand("../../priv/icons", __DIR__)

  @external_resource @icons_dir

  # Public entry points: `icon/1` and `icon/2`.
  def icon(name), do: icon(name, [])

  for file <- Path.wildcard(Path.join(@icons_dir, "*.svg")) do
    name = Path.basename(file, ".svg")
    @external_resource file
    contents = File.read!(file)

    def icon(unquote(name), opts) when is_list(opts) do
      class = Keyword.get(opts, :class, "")
      svg = String.replace(unquote(contents), "<svg", ~s(<svg class="#{class}"), global: false)
      Phoenix.HTML.raw(svg)
    end
  end

  def icon(_unknown, _opts), do: Phoenix.HTML.raw("")
end
