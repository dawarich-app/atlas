# MOTIS feasibility and Berlin prototype

Evaluated on 2026-09-06 against Atlas commit `90eeb08`.

**Recommendation:** add MOTIS as an optional transit backend, then compare journey
quality before changing the default. The prototype runs successfully on our existing
Berlin OSM and VBB feed. It has lower observed memory use and HTTP latency than the
current OTP instance, but it does not consistently produce better journeys.

## Scope and reproducibility

The prototype is in [`experiments/motis`](../experiments/motis/README.md). It runs
as `atlas-motis-experiment`, with its API on `127.0.0.1:8485`. Atlas Directions
continues to use OTP; no production routing or service-control code was changed.
The experiment mounts input data read-only and stores a separate graph.

- MOTIS: **2.11.2**, official ARM64 image, pinned by digest.
- OTP: **2.10.0_2026-05-18T08-51**, existing Atlas container.
- Runtime: Linux ARM64 in OrbStack, approximately 15.66 GiB VM RAM.
- MOTIS limit: 4 CPUs and 4 GiB RAM; server configured with 4 threads.
- OTP: existing JVM `-Xmx4g`, no container CPU or memory limit.
- OSM: the identical 98,908,382-byte Berlin PBF used for OTP.
- GTFS: the identical 75,376,540-byte VBB ZIP; calendars cover 2026-08-04–2026-12-12.
- MOTIS imports that timetable interval, street routing, shapes and routed footpaths.
  Geocoding, tiles and real-time feeds are disabled.

Input SHA-256 hashes, image versions and measurements are saved in
[`results-2026-09-06.json`](../experiments/motis/results-2026-09-06.json).
Raw HTTP responses and import logs are available locally in the ignored
`data/motis-benchmark/` directory; comparable responses are in `comparable-results/`.

## Import, memory and disk

| Observation | MOTIS | Existing OTP |
|---|---:|---:|
| Initial import container lifetime | 12.07 s, exit 0 | Not remeasured |
| Memory after first transit smoke query | ~300 MiB | ~3.97 GiB |
| Memory after all transit and street queries | 638.7 MiB | ~3.98 GiB |
| Imported graph disk allocation | ~594 MiB | `graph.obj` ~305 MiB |

Import duration comes from container start/finish timestamps and includes command
startup. This was a new MOTIS output directory, but input files could already be
cached by the host. MOTIS import peak RAM was not captured. The reported memory is
Docker's `stats` working-set metric, not maximum RAM required for installation.
The final MOTIS figure includes growth after the additional direct CAR query.

OTP had been running for several hours and is not tuned specifically for this
experiment. The two implementations, JVM/native allocation strategies, concurrency
limits and search preferences differ. These observations are useful for selecting
a candidate, not a general claim of a fixed performance or memory advantage.

## Comparable HTTP timings

Each scenario has one excluded warmup and five timed requests per engine. Requests
are sequential with alternating engine order, from curl in the same `atlas-app`
container. Timings use curl `time_total`, excluding Docker exec startup but including
network transfer and JSON response delivery.

Both engines request a **one-hour window** and **up to 100 alternatives**. MOTIS
uses `timetableView=true`, `numItineraries=1`, `maxItineraries=100`,
`searchWindow=3600`; OTP uses `first: 100`, `searchWindow: "PT1H"`.
Walking plus public transport is enabled. MOTIS requests routed transfers and leg
geometry. Other preference defaults are engine-specific. Returned counts and exact
window boundaries can differ; these are not identical search workloads.

| Scenario | MOTIS median | OTP median | Transit alternatives, MOTIS / OTP |
|---|---:|---:|---:|
| Treptower Park → Schöneweide | 44.6 ms | 184.3 ms | 20 / 18 |
| Alexanderplatz → Hauptbahnhof | 49.0 ms | 281.0 ms | 24 / 19 |
| Treptower Park → Zoologischer Garten | 99.8 ms | 331.8 ms | 21 / 15 |
| Same journey at night | 31.8 ms | 335.8 ms | 5 / 8 |
| Arrive by a specified time | 11.1 ms | 347.5 ms | 1 / 12 |
| Origin outside Berlin OSM coverage | 4.6 ms | 30.2 ms | 0 / 0 |
| Date outside the GTFS calendar | 0.7 ms | 146.6 ms | 0 / 0 |

Normal queries depart after **2026-09-07 10:00 Europe/Berlin** (08:00 UTC).
Night queries use **2026-09-08 02:00 local** (00:00 UTC). The arrive-by query
uses 2026-09-07 10:00 local as its deadline. Negative queries use Munich as the
origin, or 2027-01-15 as the date.

The initial trial used each engine's default search window and different response
limits. Its raw output is retained under `data/motis-benchmark/results/`, but those
latencies are deliberately excluded from the comparison above.

## Journey quality and functional results

All five positive scenarios returned public-transport legs on every measured
request. Returned transit itineraries had decodable leg geometry in the Berlin
area, and satisfied the requested departure/arrival constraint. This validates
API data suitable for drawing, not whether every path is usable on the ground.

Selected differences, using earliest arrival among the returned itineraries:

| Departure at 10:00 local | MOTIS earliest arrival | OTP earliest arrival |
|---|---|---|
| Park → Schöneweide | 10:26:00 | 10:27:13 |
| Alexanderplatz → Hauptbahnhof | 10:13:00 | 10:15:59 |
| Park → Zoologischer Garten | 10:45:00 | 10:38:06 |

For Park → Zoo, MOTIS is almost seven minutes worse by this criterion despite its
faster HTTP response. For arrive-by, MOTIS returns one option departing 09:19 local;
OTP returns twelve, with latest departure 09:21:06. Walking access, stop/platform
matching, transfer preferences and timetable-search semantics need investigation
before choosing a default. No engine is declared universally more accurate.

Negative cases differ in API semantics:

- Outside road coverage: both return HTTP 200 with no transit itineraries.
- Outside timetable coverage: MOTIS returns HTTP 400 with an explicit timetable
  window error. OTP returns HTTP 200 with a walking-only alternative. Atlas must
  distinguish “no public transport” from a transport itinerary or service outage.

Direct MOTIS smoke checks also passed for WALK, BIKE and CAR, including nonempty
geometry. For Park → Schöneweide they returned about 69.7, 23.3 and 9.4 minutes,
respectively. These were single requests, not a Valhalla quality/performance
comparison. WALK initially returned an empty `direct` array with the default
30-minute cap; explicitly setting `maxDirectTime=7200` returned the route.

## Follow-up: why the Park → Zoo arrival differs

A controlled follow-up isolated the cause to walking access time at Treptower
Park and the resulting missed S9 departure, rather than a missing rail connection.
All times below are Europe/Berlin on 2026-09-07.

- OTP walks **940.32 m in 12 min 18 s**, reaches the platform at **10:13:24**,
  takes S9 immediately and arrives at the destination at **10:38:06**.
- MOTIS estimates **949 m in 14 min** to the same GTFS platform
  (`de:11000:900190001:2:53`, track 4). Starting no earlier than 10:00 makes
  its **10:13 S9** unreachable. It instead selects S85 + S7 and arrives at 10:45.
- Changing only MOTIS's query time to **09:59** makes that same S9 available,
  with arrival at 10:37. The walking estimate remains 14 minutes.
- Keeping the original **10:00** query time but setting only
  **`pedestrianSpeed=1.33` m/s** reduces MOTIS's walking estimate to 12 minutes.
  It then catches S9 and again arrives at 10:37.

Thus the seven-minute arrival disadvantage in the original trial is explained
by a roughly two-minute difference in access-time modeling at a timetable
threshold. The path lengths differ by only about nine meters. The default
walking preferences were not equivalent, even with matching search windows.

This is not proof that the faster walking setting is more realistic. Neither
experiment verifies actual station access on the ground. A fair integration
should explicitly align walking speed and boarding/transfer allowances.
Residual timing differences also remain: MOTIS reports minute-resolution rail
and walking times here, while OTP retains seconds; the final walking legs are
86 m / 120 s and 159.45 m / 138 s respectively.

The original table remains an accurate measurement of the original settings,
but should not be read as evidence that MOTIS cannot find the earlier S9.
Raw follow-up responses are in `data/motis-benchmark/cause/`.

## Integration implications

1. Add a MOTIS HTTP adapter behind the existing `Atlas.Maps.Transit.plan/1`
   interface and a backend setting, keeping `/api/v1/transit` stable.
2. Normalize MOTIS `itineraries` separately from `direct`; map modes, stop names,
   `displayName`/`routeShortName`, durations and ISO timestamps into Atlas's model.
   OTP timestamps in these responses are epoch milliseconds.
3. Respect `legGeometry.precision`: MOTIS's tested API uses **6**, whereas the
   existing OTP adapter uses **5**. Preserve actual transit shapes and routed
   walking transfers instead of joining stops with straight lines.
4. Set explicit access/egress and direct-route duration limits. For transit mode,
   decide deliberately how a faster walking-only route affects transport results.
5. Add departure/arrival time selection and alternative itineraries to Directions;
   choosing only the shortest duration can miss an earlier arrival with a little
   more travel time. Existing A/B markers and route rendering can be reused.
6. Integrate MOTIS import, calendar bounds, graph invalidation, ready-state checks
   and service logs with the regional apply workflow. Reuse existing OSM/GTFS
   downloads, but derive MOTIS's calendar from the feed instead of the prototype's
   fixed dates. Keep an explicit return path to OTP during evaluation.
7. Validate platform access, transfers and arrival-time quality on a broader set
   of Berlin routes, then repeat resource measurements on a larger region.

Valhalla remains necessary for the existing `/api/v1/map-match` GPS trace API until
an equivalent replacement has been validated. MOTIS geocoding and tiles were not
evaluated, so this experiment does not justify replacing Photon or the basemap.

Sources:
[MOTIS 2.11.2](https://github.com/motis-project/motis/releases/tag/v2.11.2),
[versioned API](https://github.com/motis-project/motis/blob/v2.11.2/openapi.yaml),
[configuration](https://github.com/motis-project/motis/blob/v2.11.2/docs/setup.md).
