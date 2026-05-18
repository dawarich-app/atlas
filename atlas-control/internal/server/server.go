package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/dawarich-app/atlas/atlas-control/internal/dockerexec"
	"github.com/dawarich-app/atlas/atlas-control/internal/osmium"
	"github.com/dawarich-app/atlas/atlas-control/internal/regions"
	"github.com/dawarich-app/atlas/atlas-control/internal/state"
	"github.com/go-chi/chi/v5"
)

type Config struct {
	ComposeFile    string
	HostProjectDir string
	EnvFile        string
	StateDir       string
	DataDir        string
	RegionsDir     string
	ListenAddr     string
}

func New(cfg Config) http.Handler {
	return NewWithStore(cfg, state.New(), dockerexec.ShellRunner{})
}

func NewWithStore(cfg Config, store *state.Store, runner dockerexec.Runner) http.Handler {
	compose := &dockerexec.DockerCompose{File: cfg.ComposeFile, ProjectDir: cfg.HostProjectDir, EnvFile: cfg.EnvFile, Runner: runner}
	h := &handlers{
		cfg:      cfg,
		store:    store,
		runner:   runner,
		compose:  compose,
		follower: NewLogFollower(compose, store).WithDataDir(cfg.DataDir),
		updates:  map[string]*updateRun{},
	}
	r := chi.NewRouter()
	r.Get("/healthz", h.healthz)
	r.Get("/status", h.status)
	r.Get("/logs/{name}", h.logs)
	r.Post("/actions/services/{name}/enable", h.enable)
	r.Post("/actions/services/{name}/disable", h.disable)
	r.Post("/actions/services/{name}/update", h.updateService)
	r.Get("/actions/services/{name}/update", h.updateStatus)
	r.Post("/actions/regions", h.applyRegions)
	r.Post("/actions/tiles", h.tiles)
	r.Get("/tiles/status", h.tilesStatus)
	return r
}

type handlers struct {
	cfg      Config
	store    *state.Store
	runner   dockerexec.Runner
	compose  *dockerexec.DockerCompose
	follower *LogFollower

	tilesMu sync.Mutex
	tilesDl *tilesDownload

	updatesMu sync.RWMutex
	updates   map[string]*updateRun
}

// tilesDownload tracks the latest tiles-download attempt so the UI can render
// progress. Nil when no download has run since the sidecar started.
type tilesDownload struct {
	URL        string    `json:"url"`
	Status     string    `json:"status"` // downloading | complete | error
	StartedAt  time.Time `json:"started_at"`
	FinishedAt time.Time `json:"finished_at,omitempty"`
	BytesDone  int64     `json:"bytes_done"`
	BytesTotal int64     `json:"bytes_total"` // 0 when server didn't send Content-Length
	Error      string    `json:"error,omitempty"`
}

func (h *handlers) healthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprintln(w, "ok")
}

func (h *handlers) status(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(h.store.Snapshot())
}

// Returns the last N log lines for a service, clamped to [10, 2000].
func (h *handlers) logs(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")
	tail := 200
	if v := r.URL.Query().Get("tail"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			tail = n
		}
	}
	if tail < 10 {
		tail = 10
	}
	if tail > 2000 {
		tail = 2000
	}

	args := h.compose.LogsArgs(name, tail)
	out, err := h.runner.Run(r.Context(), "docker", args...)
	if err != nil {
		// Surface stderr together with the partial stdout — compose puts the
		// "no such service" / "no container" error on stderr and the runner
		// already merges them.
		writeError(w, http.StatusBadGateway, "LOGS_FAILED", err.Error())
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte(out))
}

var profileFor = map[string]string{
	"photon":      "geocoding",
	"placeholder": "geocoding",
	"libpostal":   "geocoding",
	"valhalla":    "routing",
	"overpass":    "pois",
	"otp":         "transit",
}

func (h *handlers) enable(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")
	profile, ok := profileFor[name]
	if !ok {
		writeError(w, http.StatusBadRequest, "UNKNOWN_SERVICE", "unknown service: "+name)
		return
	}
	if _, err := h.compose.Up(r.Context(), profile, name); err != nil {
		writeError(w, http.StatusBadGateway, "DOCKER_COMPOSE_FAILED", err.Error())
		return
	}
	h.store.Update(name, state.Update{ContainerState: "running", Phase: "starting"})
	if h.follower != nil {
		h.follower.Start(name)
	}
	w.WriteHeader(http.StatusAccepted)
}

func (h *handlers) disable(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")
	if _, err := h.compose.Stop(r.Context(), name); err != nil {
		writeError(w, http.StatusBadGateway, "DOCKER_COMPOSE_FAILED", err.Error())
		return
	}
	if h.follower != nil {
		h.follower.Stop(name)
	}
	h.store.Update(name, state.Update{ContainerState: "stopped", Phase: "stopped"})
	w.WriteHeader(http.StatusAccepted)
}

type regionsBody struct {
	Regions []string `json:"regions"`
}

func (h *handlers) applyRegions(w http.ResponseWriter, r *http.Request) {
	var body regionsBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
		return
	}
	if len(body.Regions) == 0 {
		writeError(w, http.StatusBadRequest, "BAD_REQUEST", "regions cannot be empty")
		return
	}

	// Validate region names upfront so callers get fast feedback on bad input.
	for _, name := range body.Regions {
		if _, err := regions.Load(h.cfg.RegionsDir, name); err != nil {
			writeError(w, http.StatusUnprocessableEntity, "REGION_NOT_FOUND", err.Error())
			return
		}
	}

	// Acknowledge immediately; the actual downloads + merge run in the background
	// using a context that survives client disconnect.
	go h.runApplyRegions(context.Background(), body.Regions)
	w.WriteHeader(http.StatusAccepted)
}

func (h *handlers) runApplyRegions(ctx context.Context, names []string) {
	osmDir := filepath.Join(h.cfg.DataDir, "osm")
	sourcesDir := filepath.Join(osmDir, "sources")
	if err := os.MkdirAll(sourcesDir, 0755); err != nil {
		log.Printf("[apply] mkdir %s: %v", sourcesDir, err)
		return
	}

	gtfsDir := filepath.Join(h.cfg.DataDir, "gtfs")
	_ = os.MkdirAll(gtfsDir, 0755)

	var sources []string
	for _, name := range names {
		region, err := regions.Load(h.cfg.RegionsDir, name)
		if err != nil {
			log.Printf("[apply] load region %s: %v", name, err)
			return
		}
		for _, url := range region.PBFURLs {
			target := filepath.Join(sourcesDir, filepath.Base(url))
			if _, err := os.Stat(target); err == nil {
				sources = append(sources, target)
				continue
			}
			log.Printf("[apply] downloading %s -> %s", url, target)
			if err := downloadFile(ctx, url, target); err != nil {
				log.Printf("[apply] download %s: %v", url, err)
				return
			}
			sources = append(sources, target)
		}

		if region.GTFSURL != "" {
			gtfsName := region.GTFSName
			if gtfsName == "" {
				gtfsName = filepath.Base(region.GTFSURL)
			}
			gtfsTarget := filepath.Join(gtfsDir, gtfsName)
			if _, err := os.Stat(gtfsTarget); err == nil {
				log.Printf("[apply] gtfs %s already present", gtfsName)
			} else {
				log.Printf("[apply] downloading gtfs %s -> %s", region.GTFSURL, gtfsTarget)
				if err := downloadFile(ctx, region.GTFSURL, gtfsTarget); err != nil {
					log.Printf("[apply] gtfs download %s: %v", region.GTFSURL, err)
					// Non-fatal: the rest of the apply continues without transit.
				}
			}
		}
	}

	// Host-side osm dir is what `docker run -v` needs, not the sidecar's view.
	hostOsmDir := osmDir
	hostSourcesDir := sourcesDir
	if h.cfg.HostProjectDir != "" {
		hostOsmDir = filepath.Join(h.cfg.HostProjectDir, "data", "osm")
		hostSourcesDir = filepath.Join(hostOsmDir, "sources")
	}

	// Materialise data/osm/current.osm.pbf (symlink or merged file).
	current := filepath.Join(osmDir, "current.osm.pbf")
	switch len(sources) {
	case 1:
		_ = os.Remove(current)
		// Relative symlink so consumers (valhalla, overpass, otp) can follow
		// it from their own /osm mount.
		rel := filepath.Join("sources", filepath.Base(sources[0]))
		if err := os.Symlink(rel, current); err != nil {
			log.Printf("[apply] symlink: %v", err)
			return
		}
	default:
		merger := osmium.Osmium{Runner: h.runner}
		relSources := make([]string, len(sources))
		for i, s := range sources {
			relSources[i] = filepath.Base(s)
		}
		if _, err := merger.Merge(ctx, hostSourcesDir, relSources, "../current.osm.pbf.partial"); err != nil {
			log.Printf("[apply] merge: %v", err)
			return
		}
		_ = os.Rename(current+".partial", current)
	}

	// Produce the bzip2'd OSM XML overpass-api expects. PBF isn't accepted.
	// Write to .partial first so overpass never reads a truncated file.
	merger := osmium.Osmium{Runner: h.runner}
	bz2 := filepath.Join(osmDir, "current.osm.bz2")
	log.Printf("[apply] converting pbf -> osm.bz2 for overpass")
	if _, err := merger.ConvertToOsmBz2(ctx, hostOsmDir, "current.osm.pbf", "current.osm.bz2.partial"); err != nil {
		log.Printf("[apply] osmium pbf->bz2: %v", err)
	} else if err := os.Rename(bz2+".partial", bz2); err != nil {
		log.Printf("[apply] rename osm.bz2: %v", err)
	} else {
		log.Printf("[apply] wrote %s", bz2)
	}

	// Stage OTP build inputs. OTP scans its root for *.osm.pbf + *.gtfs.zip.
	otpDir := filepath.Join(h.cfg.DataDir, "otp")
	if err := os.MkdirAll(otpDir, 0755); err == nil {
		pbfDst := filepath.Join(otpDir, "region.osm.pbf")
		_ = os.Remove(pbfDst)
		if err := copyFile(current, pbfDst); err != nil {
			log.Printf("[apply] stage otp pbf: %v", err)
		}
		entries, _ := os.ReadDir(gtfsDir)
		for _, e := range entries {
			if e.IsDir() || filepath.Ext(e.Name()) != ".zip" {
				continue
			}
			src := filepath.Join(gtfsDir, e.Name())
			dst := filepath.Join(otpDir, e.Name())
			if _, err := os.Stat(dst); err == nil {
				continue
			}
			if err := copyFile(src, dst); err != nil {
				log.Printf("[apply] stage otp gtfs %s: %v", e.Name(), err)
			}
		}
		_ = os.Remove(filepath.Join(otpDir, "graph.obj"))
	}

	if _, err := h.compose.Restart(ctx, "valhalla", "overpass", "otp"); err != nil {
		log.Printf("[apply] restart: %v", err)
	}
	log.Printf("[apply] regions=%v applied", names)
}

type tilesBody struct {
	URL string `json:"url"`
}

func (h *handlers) tilesStatus(w http.ResponseWriter, _ *http.Request) {
	target := filepath.Join(h.cfg.DataDir, "tiles", "basemap.pmtiles")
	body := map[string]any{"exists": false}
	if info, err := os.Stat(target); err == nil {
		body["exists"] = true
		body["size_bytes"] = info.Size()
		body["modified_at"] = info.ModTime().UTC().Format("2006-01-02T15:04:05Z")
	}

	h.tilesMu.Lock()
	if h.tilesDl != nil {
		body["download"] = *h.tilesDl
	}
	h.tilesMu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(body)
}

func (h *handlers) tiles(w http.ResponseWriter, r *http.Request) {
	var body tilesBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
		return
	}
	target := filepath.Join(h.cfg.DataDir, "tiles", "basemap.pmtiles")
	if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
		writeError(w, http.StatusInternalServerError, "MKDIR_FAILED", err.Error())
		return
	}
	// Reset progress state and kick off the background download.
	h.tilesMu.Lock()
	h.tilesDl = &tilesDownload{URL: body.URL, Status: "downloading", StartedAt: time.Now().UTC()}
	tracker := h.tilesDl
	h.tilesMu.Unlock()

	go func() {
		log.Printf("[tiles] downloading %s -> %s", body.URL, target)
		err := h.downloadWithProgress(context.Background(), body.URL, target, tracker)
		h.tilesMu.Lock()
		tracker.FinishedAt = time.Now().UTC()
		if err != nil {
			tracker.Status = "error"
			tracker.Error = err.Error()
			log.Printf("[tiles] download %s: %v", body.URL, err)
		} else {
			tracker.Status = "complete"
			log.Printf("[tiles] wrote %s (%d bytes)", target, tracker.BytesDone)
		}
		h.tilesMu.Unlock()
	}()
	w.WriteHeader(http.StatusAccepted)
}

// downloadWithProgress streams an HTTP body to disk while updating the supplied
// tracker every 512 KB. Writes to <target>.partial first and atomically renames
// to <target> on success so Caddy never serves a half-written file.
func (h *handlers) downloadWithProgress(ctx context.Context, url, target string, tracker *tilesDownload) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", res.StatusCode)
	}

	h.tilesMu.Lock()
	tracker.BytesTotal = res.ContentLength // -1 when unknown
	if tracker.BytesTotal < 0 {
		tracker.BytesTotal = 0
	}
	h.tilesMu.Unlock()

	out, err := os.OpenFile(target+".partial", os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer func() { _ = out.Close(); _ = os.Remove(target + ".partial") }()

	buf := make([]byte, 64*1024)
	const progressEvery = 512 * 1024
	var sinceLastReport int64
	for {
		n, rerr := res.Body.Read(buf)
		if n > 0 {
			if _, werr := out.Write(buf[:n]); werr != nil {
				return werr
			}
			sinceLastReport += int64(n)
			if sinceLastReport >= progressEvery {
				h.tilesMu.Lock()
				tracker.BytesDone += sinceLastReport
				h.tilesMu.Unlock()
				sinceLastReport = 0
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			return rerr
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
	}
	if sinceLastReport > 0 {
		h.tilesMu.Lock()
		tracker.BytesDone += sinceLastReport
		h.tilesMu.Unlock()
	}

	if err := out.Close(); err != nil {
		return err
	}
	if err := os.Rename(target+".partial", target); err != nil {
		return err
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer out.Close()
	if _, err := io.Copy(out, in); err != nil {
		return err
	}
	return nil
}

func downloadFile(ctx context.Context, url, target string) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", res.StatusCode)
	}
	out, err := os.OpenFile(target+".partial", os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, res.Body); err != nil {
		out.Close()
		os.Remove(target + ".partial")
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(target + ".partial")
		return err
	}
	return os.Rename(target+".partial", target)
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]string{"code": code, "message": msg},
	})
}
