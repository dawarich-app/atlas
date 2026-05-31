# M5 Golden Capture Procedure

The byte-diff parity harness in `test/atlas_web/api_parity_test.exs` compares
Phoenix output against captured Rails goldens. This is the cutover gate that
must pass before the M4 §Task 9 destructive swap (Rails → Phoenix in
`docker-compose.yml`).

Until goldens are captured, `GoldenHelper.assert_byte_diff/2` is a no-op
against `nil` and the parity tests only check structural envelope shape.
Once goldens exist under `test/fixtures/goldens/*.json`, the harness asserts
full JSON equality (modulo volatile `meta.timestamp` and `meta.request_id`).

## Prerequisites

- Rails app at `app/` boots clean (`cd app && bin/rails console` works).
- Docker sidecars up: `photon`, `valhalla`, `overpass`, `otp`, `libpostal`,
  `placeholder`.
- `jq` and `curl` installed locally.

## Steps

1. **Boot sidecars + Rails** from the atlas repo root:

   ```bash
   docker compose up -d photon valhalla overpass otp libpostal placeholder
   cd app && bin/rails server -p 3000 &
   sleep 10
   cd ../app-phoenix
   ```

2. **Run the capture script** — hits the 10 reference `/api/v1/*` endpoints
   and writes byte-stable JSON via `jq -S`:

   ```bash
   bash scripts/capture_rails_goldens.sh http://localhost:3000
   ```

3. **Verify all 10 fixtures landed** under `test/fixtures/goldens/`:

   ```bash
   ls -la test/fixtures/goldens/
   # expect: search-berlin.json, search-with-bbox.json,
   #         reverse-brandenburg.json, reverse-batch-two.json,
   #         route-auto.json, transit-default.json,
   #         whats-here-default.json, pois-food.json,
   #         pois-categories.json, geocode-berlin.json
   ```

4. **Run the parity harness against the new goldens**:

   ```bash
   mix test --only parity
   ```

5. **Expected outcome:** every endpoint passes byte-diff parity.

6. **If diffs surface** — the Phoenix code has remaining parity gaps. Do
   NOT edit the goldens; file an M5.1 patch task for the offending
   endpoint and fix Phoenix to match.

7. **Commit the captured goldens** (only after the harness is green):

   ```bash
   git add app-phoenix/test/fixtures/goldens/
   git commit -m "test(atlas-phoenix): capture Rails goldens for byte-diff parity gate"
   ```

## Notes

- The capture script uses `jq -S` so JSON keys are sorted deterministically.
  This avoids spurious diffs from upstream Ruby hash-ordering changes.
- Volatile fields (`meta.timestamp`, `meta.request_id`) are stripped by
  `GoldenHelper.drop_volatile/1` before comparison — leave them in the
  goldens as-is, they're filtered at assert time.
- Rerun the capture whenever the Rails API envelope intentionally changes;
  treat the goldens as a moving cutover gate, not eternal truth.
