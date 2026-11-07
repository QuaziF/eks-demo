// Demo service for the containerization and orchestration demo.
//
// It is deliberately small and has no third-party dependencies. Each endpoint exists to
// support one part of the demo:
//
//	/            who answered (pod, node, version), shows load spreading
//	/healthz     liveness probe
//	/readyz      readiness probe (can be flipped to fail)
//	/work?ms=N   burns CPU for N milliseconds, drives the HPA
//	/alloc?mb=N  holds N MB of memory, drives OOMKilled drills
//	/config      shows ConfigMap-sourced settings
//	/secret-check reports whether the Secret is mounted, never its value
//	/version     build version and commit
package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// Set at build time: go build -ldflags "-X main.version=1.2.3 -X main.commit=abc1234".
var (
	version = "dev"
	commit  = "none"
)

const (
	maxWorkMS  = 5000
	maxAllocMB = 2048
)

type app struct {
	log      *slog.Logger
	ready    atomic.Bool
	mu       sync.Mutex
	held     [][]byte
	greeting string
	mode     string
	podName  string
	nodeName string
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getenvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func main() {
	healthcheck := flag.Bool("healthcheck", false, "probe /healthz on localhost and exit 0 or 1 (used by Docker HEALTHCHECK)")
	flag.Parse()

	port := getenv("PORT", "8080")

	if *healthcheck {
		client := &http.Client{Timeout: 2 * time.Second}
		resp, err := client.Get("http://127.0.0.1:" + port + "/healthz")
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		os.Exit(0)
	}

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	// Required setting: the process refuses to start without it. This gives a clean,
	// repeatable "container exits immediately" and CrashLoopBackOff drill.
	mode := os.Getenv("APP_MODE")
	if mode == "" {
		log.Error("missing required environment variable", "name", "APP_MODE")
		os.Exit(1)
	}

	a := &app{
		log:      log,
		mode:     mode,
		greeting: getenv("APP_GREETING", "hello"),
		podName:  getenv("POD_NAME", func() string { h, _ := os.Hostname(); return h }()),
		nodeName: getenv("NODE_NAME", "unknown"),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", a.handleRoot)
	mux.HandleFunc("/healthz", a.handleHealthz)
	mux.HandleFunc("/readyz", a.handleReadyz)
	mux.HandleFunc("/toggle-ready", a.handleToggleReady)
	mux.HandleFunc("/work", a.handleWork)
	mux.HandleFunc("/alloc", a.handleAlloc)
	mux.HandleFunc("/free", a.handleFree)
	mux.HandleFunc("/config", a.handleConfig)
	mux.HandleFunc("/secret-check", a.handleSecretCheck)
	mux.HandleFunc("/version", a.handleVersion)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           a.logRequests(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// Readiness: not ready until the optional startup delay has passed. FORCE_NOT_READY
	// keeps it failing so the "Running but not Ready" drill is one config change.
	startupDelay := time.Duration(getenvInt("STARTUP_DELAY_SECONDS", 0)) * time.Second
	forceNotReady := getenv("FORCE_NOT_READY", "false") == "true"
	go func() {
		time.Sleep(startupDelay)
		if !forceNotReady {
			a.ready.Store(true)
		}
	}()

	errCh := make(chan error, 1)
	go func() {
		log.Info("starting", "port", port, "version", version, "commit", commit, "mode", mode, "pod", a.podName)
		errCh <- srv.ListenAndServe()
	}()

	// Graceful shutdown. On SIGTERM go unready first, wait so the endpoint is removed from
	// Services and load balancers, then drain in-flight requests. This is what makes
	// rolling updates drop no requests.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)

	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "error", err)
			os.Exit(1)
		}
	case sig := <-stop:
		log.Info("shutdown signal received", "signal", sig.String())
		a.ready.Store(false)
		time.Sleep(time.Duration(getenvInt("SHUTDOWN_DELAY_SECONDS", 5)) * time.Second)
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Error("graceful shutdown failed", "error", err)
			os.Exit(1)
		}
		log.Info("shutdown complete")
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// logRequests writes one JSON log line per request, skipping the noisy probe paths.
func (a *app) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		a.log.Info("request", "method", r.Method, "path", r.URL.RequestURI(), "status", rec.status,
			"duration_ms", time.Since(start).Milliseconds())
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (a *app) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"message": a.greeting,
		"pod":     a.podName,
		"node":    a.nodeName,
		"version": version,
	})
}

func (a *app) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok\n"))
}

func (a *app) handleReadyz(w http.ResponseWriter, _ *http.Request) {
	if !a.ready.Load() {
		http.Error(w, "not ready\n", http.StatusServiceUnavailable)
		return
	}
	_, _ = w.Write([]byte("ready\n"))
}

// handleToggleReady flips readiness at runtime, for live "Running but not Ready" demos.
func (a *app) handleToggleReady(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "use POST\n", http.StatusMethodNotAllowed)
		return
	}
	now := !a.ready.Load()
	a.ready.Store(now)
	writeJSON(w, http.StatusOK, map[string]bool{"ready": now})
}

func (a *app) handleWork(w http.ResponseWriter, r *http.Request) {
	ms := clamp(r.URL.Query().Get("ms"), 25, 1, maxWorkMS)
	deadline := time.Now().Add(time.Duration(ms) * time.Millisecond)
	buf := []byte("demo")
	for time.Now().Before(deadline) {
		sum := sha256.Sum256(buf)
		buf = sum[:]
	}
	writeJSON(w, http.StatusOK, map[string]any{"burned_ms": ms, "pod": a.podName})
}

func (a *app) handleAlloc(w http.ResponseWriter, r *http.Request) {
	mb := clamp(r.URL.Query().Get("mb"), 50, 1, maxAllocMB)
	chunk := make([]byte, mb*1024*1024)
	for i := 0; i < len(chunk); i += 4096 { // touch every page so the memory is really resident
		chunk[i] = 1
	}
	a.mu.Lock()
	a.held = append(a.held, chunk)
	total := len(a.held)
	a.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]int{"allocated_mb": mb, "chunks_held": total})
}

func (a *app) handleFree(w http.ResponseWriter, _ *http.Request) {
	a.mu.Lock()
	a.held = nil
	a.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]string{"status": "released"})
}

func (a *app) handleConfig(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"APP_MODE":              a.mode,
		"APP_GREETING":          a.greeting,
		"STARTUP_DELAY_SECONDS": getenv("STARTUP_DELAY_SECONDS", "0"),
		"FORCE_NOT_READY":       getenv("FORCE_NOT_READY", "false"),
	})
}

func (a *app) handleSecretCheck(w http.ResponseWriter, _ *http.Request) {
	_, present := os.LookupEnv("DEMO_API_KEY")
	writeJSON(w, http.StatusOK, map[string]bool{"DEMO_API_KEY_present": present})
}

func (a *app) handleVersion(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"version": version, "commit": commit})
}

func clamp(raw string, fallback, lo, hi int) int {
	n := fallback
	if raw != "" {
		if v, err := strconv.Atoi(raw); err == nil {
			n = v
		}
	}
	if n < lo {
		return lo
	}
	if n > hi {
		return hi
	}
	return n
}
