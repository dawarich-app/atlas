defmodule Atlas.Maps do
  use Boundary,
    deps: [Req, Cachex, Logger, Task],
    exports: [Result]
end
