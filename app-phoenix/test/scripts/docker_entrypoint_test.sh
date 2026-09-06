#!/bin/sh
# Tests rel/overlays/bin/docker-entrypoint without needing root or a daemon:
# `id`, `chown` and `setpriv` are replaced by stubs on PATH that record how
# they were called.
set -eu

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd)"
ENTRYPOINT="$SCRIPT_DIR/../../rel/overlays/bin/docker-entrypoint"

failures=0
tests=0

fail() {
  failures=$((failures + 1))
  printf '  ✗ %s\n' "$1"
  [ $# -gt 1 ] && printf '    %s\n' "$2"
  return 0
}

pass() { printf '  ✓ %s\n' "$1"; }

assert_contains() {
  tests=$((tests + 1))
  if printf '%s' "$2" | grep -qF -- "$3"; then
    pass "$1"
  else
    fail "$1" "expected to contain: $3"
    printf '    actual: %s\n' "$2"
  fi
}

assert_not_contains() {
  tests=$((tests + 1))
  if printf '%s' "$2" | grep -qF -- "$3"; then
    fail "$1" "expected NOT to contain: $3"
    printf '    actual: %s\n' "$2"
  else
    pass "$1"
  fi
}

# Exact whole-line match. Use this instead of assert_contains whenever the
# expected string is a complete line: grep -F treats a newline inside the
# pattern as a pattern separator, so an embedded one silently matches anything.
assert_line() {
  tests=$((tests + 1))
  if printf '%s\n' "$2" | grep -qxF -- "$3"; then
    pass "$1"
  else
    fail "$1" "expected a line exactly equal to: $3"
    printf '    actual: %s\n' "$2"
  fi
}

assert_status() {
  tests=$((tests + 1))
  if [ "$2" -eq "$3" ]; then
    pass "$1"
  else
    fail "$1" "expected exit $3, got $2"
  fi
}

# Build a sandbox: stub bin dir on PATH, a fake data dir, and a recorded log.
# $1 = uid reported by `id -u`; $2 = groups reported by `id -G`
setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  BIN="$SANDBOX/bin"
  DATA="$SANDBOX/data"
  WORK_DATA="$SANDBOX/work-data"
  LOG="$SANDBOX/calls.log"
  mkdir -p "$BIN" "$DATA"
  # The region pipeline's bind mounts, which the app writes through /work/data.
  mkdir -p "$WORK_DATA/osm" "$WORK_DATA/gtfs" "$WORK_DATA/otp" "$WORK_DATA/tiles"
  : > "$LOG"

  # Stand-in for the bind-mounted docker socket. $SOCKET_GID is what `stat`
  # reports for it; empty means "no socket mounted".
  SOCKET="$SANDBOX/docker.sock"
  : > "$SOCKET"
  # Reset explicitly: `VAR=x some_function` PERSISTS in POSIX sh (it only
  # scopes to the call for external commands), so without this a test that
  # sets SOCKET_GID silently changes every test after it.
  SOCKET_GID=""

  cat > "$BIN/id" <<EOF
#!/bin/sh
case "\$1" in
  -u) echo "$1" ;;
  -G) echo "$2" ;;
  *)  echo "$1" ;;
esac
EOF

  cat > "$BIN/chown" <<EOF
#!/bin/sh
echo "chown \$*" >> "$LOG"
EOF

  # setpriv records its args, then runs the trailing command so the rest of
  # the entrypoint still executes under the "dropped" identity.
  cat > "$BIN/setpriv" <<EOF
#!/bin/sh
echo "setpriv \$*" >> "$LOG"
while [ "\$1" != "--" ] && [ \$# -gt 0 ]; do shift; done
[ "\$1" = "--" ] && shift
exec "\$@"
EOF

  cat > "$BIN/stat" <<EOF
#!/bin/sh
# Only the -c %g form is used. Empty by default so tests that say nothing
# about the socket behave as if none were mounted; tests that care set
# SOCKET_GID explicitly.
echo "\${SOCKET_GID:-}"
EOF

  chmod +x "$BIN/id" "$BIN/chown" "$BIN/setpriv" "$BIN/stat"
}

teardown_sandbox() { rm -rf "$SANDBOX"; }

# Run the entrypoint in the sandbox. Echoes stdout+stderr; sets RUN_STATUS.
run_entrypoint() {
  set +e
  RUN_OUTPUT="$(PATH="$BIN:$PATH" ATLAS_DATA_DIR="$DATA" ATLAS_WORK_DATA_DIR="$WORK_DATA" \
    DOCKER_SOCKET="$SOCKET" SOCKET_GID="${SOCKET_GID:-}" "$@" \
    "$ENTRYPOINT" /bin/echo "app-started" 2>&1)"
  RUN_STATUS=$?
  set -e
  RUN_CALLS="$(cat "$LOG")"
  # The environment the wrapped command is exec'd with, for assertions about
  # what the entrypoint exports.
  set +e
  RUN_ENV="$(PATH="$BIN:$PATH" ATLAS_DATA_DIR="$DATA" ATLAS_WORK_DATA_DIR="$WORK_DATA" \
    DOCKER_SOCKET="$SOCKET" SOCKET_GID="${SOCKET_GID:-}" "$@" \
    "$ENTRYPOINT" /usr/bin/env 2>&1)"
  set -e
}

printf '\n== running as root ==\n'
setup_sandbox 0 "0 999"
run_entrypoint env
assert_status "starts the app" "$RUN_STATUS" 0
assert_contains "execs the wrapped command" "$RUN_OUTPUT" "app-started"
assert_contains "chowns the data dir to the default uid" "$RUN_CALLS" "65534:65534"
assert_contains "drops privileges with setpriv" "$RUN_CALLS" "--reuid=65534"
assert_contains "drops to the matching gid" "$RUN_CALLS" "--regid=65534"
assert_contains "preserves the docker socket group" "$RUN_CALLS" "--groups=999"
teardown_sandbox

printf '\n== the region pipeline bind mounts are prepared too ==\n'
setup_sandbox 0 "0 999"
run_entrypoint env
for sub in osm gtfs otp tiles; do
  assert_contains "chowns /work/data/$sub" "$RUN_CALLS" "$WORK_DATA/$sub"
done
teardown_sandbox

printf '\n== database and secret-key dirs are resolved independently ==\n'
setup_sandbox 0 "0 999"
# Three genuinely distinct locations, so each one's contribution is visible:
# bin/server defaults the secret key to /data no matter where the DB lives.
mkdir -p "$SANDBOX/dbdir" "$SANDBOX/secretdir"
run_entrypoint env \
  DATABASE_PATH="$SANDBOX/dbdir/atlas.sqlite3" \
  SECRET_KEY_BASE_PATH="$SANDBOX/secretdir/.secret_key_base"
assert_line "prepares the relocated database dir" "$RUN_CALLS" "chown -R 65534:65534 $SANDBOX/dbdir"
assert_line "prepares the secret-key dir too" "$RUN_CALLS" "chown -R 65534:65534 $SANDBOX/secretdir"
teardown_sandbox

printf '\n== DOCKER_GID=0 (macOS/OrbStack) survives the gid-0 strip ==\n'
setup_sandbox 0 "0"
run_entrypoint env DOCKER_GID=0
assert_contains "keeps the socket group the operator asked for" "$RUN_CALLS" "--groups=0"
assert_not_contains "does not discard it as root's own gid" "$RUN_CALLS" "--clear-groups"
teardown_sandbox

printf '\n== the socket group survives WITHOUT DOCKER_GID in the environment ==\n'
# The deployment shape that actually ships. compose's `group_add:` puts the
# gid in the container's supplementary groups and NOWHERE else — DOCKER_GID is
# a compose-level substitution and is never exported into the container. So the
# entrypoint cannot read it, and on macOS (socket gid 0) the gid-0 strip
# removed the only group that reaches the daemon. The group has to come from
# the socket itself.
setup_sandbox 0 "0"
SOCKET_GID=0
run_entrypoint env
assert_contains "keeps the socket's own group" "$RUN_CALLS" "--groups=0"
assert_not_contains "does not drop every group" "$RUN_CALLS" "--clear-groups"
teardown_sandbox

printf '\n== a wrong DOCKER_GID does not mask the real socket group ==\n'
# compose.yml exports `DOCKER_GID: ${DOCKER_GID:-999}` into the app container,
# so the variable IS set for every self-hoster who did not override it. If that
# value wins, the default 999 is granted on a macOS host whose socket is gid 0
# and the control plane stays degraded — the exact bug this is meant to fix.
setup_sandbox 0 "0"
SOCKET_GID=0
run_entrypoint env DOCKER_GID=999
assert_contains "grants the real socket group, not the DOCKER_GID default" "$RUN_CALLS" "--groups=0"
teardown_sandbox

printf '\n== a non-zero socket group (Linux) is preserved too ==\n'
setup_sandbox 0 "0 999"
SOCKET_GID=999
run_entrypoint env
assert_contains "keeps the docker group" "$RUN_CALLS" "999"
assert_not_contains "still does not carry root's gid 0" "$RUN_CALLS" "--groups=0,"
teardown_sandbox

printf '\n== no socket mounted: nothing extra is granted ==\n'
setup_sandbox 0 "0"
rm -f "$SOCKET"
run_entrypoint env
assert_contains "drops to no supplementary groups" "$RUN_CALLS" "--clear-groups"
teardown_sandbox

printf '\n== the docker CLI can load its plugins as the dropped user ==\n'
# HOME stays /root after the drop, and an UNREADABLE config path (as opposed to
# a merely absent one) makes the docker CLI abort plugin loading entirely:
# `docker compose` stops being a known subcommand and the control plane reports
# "docker compose unavailable".
setup_sandbox 0 "0"
run_entrypoint env
assert_not_contains "does not leave DOCKER_CONFIG under root's home" "$RUN_ENV" "/root/.docker"
assert_contains "exports a reachable DOCKER_CONFIG" "$RUN_ENV" "DOCKER_CONFIG="
teardown_sandbox

printf '\n== remediation advice names the app data dir, not the whole ./data tree ==\n'
setup_sandbox 65534 "65534 999"
chmod 500 "$DATA"
run_entrypoint env
chown_line="$(printf '%s' "$RUN_OUTPUT" | grep 'chown -R' | head -1)"
assert_contains "the suggested chown targets the app data dir" "$chown_line" "./data/app"
assert_not_contains "the suggested chown does not target the whole tree" \
  "$(printf '%s' "$chown_line" | sed 's|\./data/[a-z]*||g')" "./data"
assert_contains "warns about sibling services before widening it" "$RUN_OUTPUT" "whosonfirst"
assert_contains "names PUID as the remedy" "$RUN_OUTPUT" "PUID"
chmod 700 "$DATA"
teardown_sandbox

printf '\n== root, but chown fails (NFS root_squash / userns-remap) ==\n'
setup_sandbox 0 "0 999"
cat > "$BIN/chown" <<EOF
#!/bin/sh
echo "chown \$*" >> "$LOG"
exit 1
EOF
chmod +x "$BIN/chown"
run_entrypoint env PUID=99 PGID=100
assert_status "refuses to start rather than crash-looping" "$RUN_STATUS" 1
assert_contains "explains the data dir is unusable" "$RUN_OUTPUT" "not writable"
assert_contains "points at the PUID/PGID knob" "$RUN_OUTPUT" "PUID"
assert_contains "reports the uid the app will run as, not root" "$RUN_OUTPUT" "99"
assert_not_contains "does not advise chowning to root" "$RUN_OUTPUT" "chown -R 0:0"
assert_not_contains "does not start the app" "$RUN_OUTPUT" "app-started"
teardown_sandbox

printf '\n== every unwritable mount is named, not just the last one ==\n'
setup_sandbox 0 "0 999"
cat > "$BIN/chown" <<EOF
#!/bin/sh
echo "chown \$*" >> "$LOG"
exit 1
EOF
chmod +x "$BIN/chown"
run_entrypoint env
assert_contains "names the app data dir" "$RUN_OUTPUT" "$DATA"
assert_contains "names a failing region dir too" "$RUN_OUTPUT" "$WORK_DATA/osm"
teardown_sandbox

printf '\n== privilege drop does not carry root gid 0 forward ==\n'
setup_sandbox 0 "0 999"
run_entrypoint env
assert_not_contains "gid 0 is not in the supplementary groups" "$RUN_CALLS" "--groups=0,"
assert_contains "the docker socket group survives" "$RUN_CALLS" "--groups=999"
teardown_sandbox

printf '\n== root with no extra groups beyond gid 0 ==\n'
setup_sandbox 0 "0"
run_entrypoint env
assert_status "still starts" "$RUN_STATUS" 0
assert_contains "clears supplementary groups rather than passing an empty list" "$RUN_CALLS" "--clear-groups"
teardown_sandbox

printf '\n== running as root with PUID/PGID (Unraid/Synology) ==\n'
setup_sandbox 0 "0 999"
run_entrypoint env PUID=99 PGID=100
assert_status "starts the app" "$RUN_STATUS" 0
assert_contains "chowns the data dir to PUID:PGID" "$RUN_CALLS" "chown -R 99:100"
assert_contains "drops to PUID" "$RUN_CALLS" "--reuid=99"
assert_contains "drops to PGID" "$RUN_CALLS" "--regid=100"
teardown_sandbox

printf '\n== already running as a non-root user (compose `user:`) ==\n'
setup_sandbox 65534 "65534 999"
run_entrypoint env
assert_status "starts the app" "$RUN_STATUS" 0
assert_contains "execs the wrapped command" "$RUN_OUTPUT" "app-started"
assert_not_contains "does not try to chown" "$RUN_CALLS" "chown"
assert_not_contains "does not try to drop privileges again" "$RUN_CALLS" "setpriv"
teardown_sandbox

printf '\n== non-root with an unwritable data dir (issue #23) ==\n'
setup_sandbox 65534 "65534 999"
chmod 500 "$DATA"
run_entrypoint env
assert_status "fails fast instead of crash-looping" "$RUN_STATUS" 1
assert_contains "names the unwritable path" "$RUN_OUTPUT" "$DATA"
assert_contains "explains it is an ownership problem" "$RUN_OUTPUT" "not writable"
assert_contains "points at the PUID/PGID knob" "$RUN_OUTPUT" "PUID"
assert_not_contains "does not start the app" "$RUN_OUTPUT" "app-started"
chmod 700 "$DATA"
teardown_sandbox

printf '\n%s tests, %s failures\n' "$tests" "$failures"
[ "$failures" -eq 0 ] || exit 1
