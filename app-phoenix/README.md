# Atlas

To start your Phoenix server:

* Run `npm --prefix assets ci` to install the PMTiles browser packages
* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

The Basemap settings tab lists completed `.pmtiles` files in `data/tiles/`. Select
one there, or enter its `/tiles/<filename>.pmtiles` URL. Atlas reads the archive
with HTTP range requests through Caddy and builds a Protomaps v4 MapLibre style
in the browser. Hosted MapLibre style JSON URLs continue to work directly.
Remote PMTiles URLs must support browser CORS and HTTP range requests.
Fonts and sprites for Protomaps styles currently load from
`protomaps.github.io`; a fully offline setup must host those assets locally.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
