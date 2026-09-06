#!/bin/sh
# Run in a separate VM: the normal ExUnit suite has already started Atlas and
# cannot detect an accidental app.start in the build-time generator.
set -eu
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
echo '{"features":[]}' > "$scratch/geofabrik.json"
echo '<a href="Berlin/">Berlin/</a>' > "$scratch/bbbike.html"
mix run --no-start -e '
  Mix.Task.run("atlas.gen_catalog", System.argv())
  if Process.whereis(Atlas.Repo), do: raise("catalog generation started the database")
  if Process.whereis(Atlas.Control.Supervisor), do: raise("catalog generation started the control plane")
' -- --geofabrik-file "$scratch/geofabrik.json" --bbbike-file "$scratch/bbbike.html" --no-sizes --out "$scratch/catalog.json"
test -s "$scratch/catalog.json"
