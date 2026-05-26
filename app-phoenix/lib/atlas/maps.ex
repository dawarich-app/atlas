defmodule Atlas.Maps do
  use Boundary,
    deps: [Req, Cachex, Logger, Task],
    exports: [Result, Search, Reverse, Route, Transit, WhatsHere, Poi, Geocode]
end
