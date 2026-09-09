# First-run setup

Atlas opens `/setup` on a fresh seeded installation with no enabled services,
installed data, applied region selection, previous setup job or dismissal.
Existing installations open the map as before. **Settings → Setup wizard**
reopens setup; **Set up later** suppresses automatic entry.

The four steps select capabilities, select regions, review installation and
show progress. Capability dependencies are explicit: search uses Photon,
street routes add Valhalla, categories add Overpass, and transit adds exactly
one of MOTIS or OpenTripPlanner. Missing catalog timetables produce a region-specific warning on the region
and review steps, without blocking navigation or installation. Transit coverage
remains unavailable there until suitable timetable data is added. Changing the radio selection only edits the draft;
the existing exclusive transit coordinator switches engines at installation.

The setup draft and job are persisted separately in Settings (`setup_draft`,
`setup_job`, `setup_dismissed`). Editing setup does not change the ordinary
Settings region draft. Regional preparation uses RegionApplier, limited to
selected services; unrelated transit inputs and Overpass conversion are left
alone. Source downloads are reused by the existing downloader. Photon starts as soon as setup is accepted, alongside regional downloads.
Regional services start after their preparation succeeds. PBFs and GTFS use
a shared pool of at most three concurrent downloads. Each file reports its
own progress and completion; duplicate sources are downloaded once. All
active downloads settle before an apply failure permits a retry. Search-only installation does not
need a regional PBF download.

Onboarding is a supervised coordinator, independent of the LiveView. Leaving
or reloading the page does not cancel work. Data-preparation failures can be
retried using cached downloads; service failures can be retried individually.
A server restart during preparation/startup marks the job interrupted and
requires an explicit retry. Setup reports completion only when every selected
service is enabled and reports ready; container creation alone is insufficient.

## Coverage and estimates

Photon's index remains controlled by the deployment's `COUNTRY_CODE` (Germany
by default), independently of regional routing/Overpass inputs. Changing the
wizard's region does not replace an existing Photon index. This distinction is
shown in both the region and review steps. The displayed size is known PBF
source size only, not a promised total storage requirement; images, search
indexes, timetables and preparation output require additional space. Unknown
sizes are displayed as unknown. Basemap configuration is retained.

## Validation

Tests cover first-run detection, skip, saved drafts, timetable validation,
dependency mapping, exclusive engine selection in the draft, duplicate start
rejection, prepare-before-start ordering, interrupted jobs, isolated service
retry, environment checks, completion based on readiness, and scoped regional
preparation. Browser checks cover navigation, validation, reload persistence,
engine selection, a real search-only installation using the existing index,
completion, return to map and re-entry from Settings.
