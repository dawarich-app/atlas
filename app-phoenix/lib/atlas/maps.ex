defmodule Atlas.Maps do
  @moduledoc """
  Boundary for the map-data context.

  Everything that answers a question about the world — geocoding, reverse
  geocoding, routing, transit, POIs — lives under here and reaches the outside
  only through the upstream HTTP clients in `Atlas.Maps.Upstream`.
  """

  use Boundary,
    deps: [Atlas.Settings, Req, Cachex, Logger, Task],
    exports: [Result, Search, Reverse, Route, Transit, WhatsHere, Poi, Geocode]
end
