#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
JOBS="$WORK_DIR/jobs"
mkdir -p "$JOBS"

write_state() {
  local unit="$1" state="$2"
  cat > "$JOBS/$unit.state" <<EOF
schema_version=1
unit=$unit
target=all-systems
state=$state
started_at=2026-01-01T00:00:00Z
finished_at=2026-01-01T00:00:01Z
exit_code=0
type=check
message=
source=
EOF
}

write_state ultimate-updater-check-existing completed

state_value_function=$(awk '/^state_value\(\) \{/{copy=1} copy{print} copy && /^\}/{exit}' "$ROOT_DIR/job-runner.sh")
normal=$(bash -c "$state_value_function; state_value \"\$1\" state" _ "$JOBS/ultimate-updater-check-existing.state")
[[ "$normal" == completed ]]

missing_stderr="$WORK_DIR/missing.stderr"
if bash -c "$state_value_function; state_value \"\$1\" state" _ "$JOBS/does-not-exist.state" \
  >"$WORK_DIR/missing.stdout" 2>"$missing_stderr"; then
  echo 'missing state unexpectedly succeeded' >&2
  exit 1
fi
[[ ! -s "$missing_stderr" ]]

for number in $(seq -w 1 60); do
  write_state "ultimate-updater-check-race-$number" completed
done

errors="$WORK_DIR/errors"
: > "$errors"
for _ in $(seq 1 12); do
  UU_JOB_STATE_DIR="$JOBS" UU_MAX_COMPLETED_JOBS=50 \
    bash "$ROOT_DIR/job-runner.sh" list >/dev/null 2>>"$errors" &
done
wait
if grep -Fq 'awk: cannot open' "$errors"; then
  echo 'retention race emitted an awk missing-file error' >&2
  exit 1
fi

echo 'job state missing-file and retention race tests: PASS'
