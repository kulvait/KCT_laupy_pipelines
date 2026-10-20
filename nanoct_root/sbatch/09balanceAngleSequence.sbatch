#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu
#SBATCH --output=log/09balanceAngleSequence-%N-%j.out
#SBATCH --error=log/09balanceAngleSequence-%N-%j.err

set -euo pipefail

scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

echo "START ${jobname} $*"
start_time=$(date +%s)

NANO_LOG_FILE="LogScan.log"
JSON_FILE=""
CROP="both"
EXTRA_REMOVALS=2
MAX_SPAN_DEG=200
FORCE=false
POSITIONAL=()

usage() {
    cat <<EOF
Usage: ${scriptname} [OPTIONS] <WD> <INPUT_DEN> <OUTPUT_DEN> <OUTPUT_TICK>

Select an FBP angular range and create matching projection and tick files.

Options:
  --nano-log-file FILE    NanoCT metadata file (default: LogScan.log).
  --json FILE             Save the generated selection JSON (default: temporary).
  --crop start|end|both    Selector crop preference (default: both).
  --extra-removals N      Selector additional endpoint removals (default: 2).
  --max-span-deg DEG      Selector processing limit (default: 200).
  --force                 Replace existing output files.
  -h, --help              Show this help.

All relative file paths are interpreted from WD.

INPUT_DEN must contain the full imaging sequence in metadata order.
Angles are neither normalized nor interpolated.
EOF
}

require_value() {
    if (($# < 2)) || [[ -z "$2" || "$2" == --* ]]; then
        echo "Error: $1 requires a value." >&2
        exit 2
    fi
}

while (($#)); do
    case "$1" in
        --nano-log-file|--json|--crop|--extra-removals|--max-span-deg)
            require_value "$1" "${2:-}"
            case "$1" in
                --nano-log-file) NANO_LOG_FILE="$2" ;;
                --json) JSON_FILE="$2" ;;
                --crop) CROP="$2" ;;
                --extra-removals) EXTRA_REMOVALS="$2" ;;
                --max-span-deg) MAX_SPAN_DEG="$2" ;;
            esac
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            POSITIONAL+=("$@")
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if ((${#POSITIONAL[@]} != 4)); then
    usage >&2
    exit 2
fi

WD="${POSITIONAL[0]}"
INPUT_DEN="${POSITIONAL[1]}"
OUTPUT_DEN="${POSITIONAL[2]}"
OUTPUT_TICK="${POSITIONAL[3]}"

if [[ ! -d "$WD" ]]; then
    echo "Error: working directory does not exist: $WD" >&2
    exit 2
fi

cd "$WD"
unset LD_PRELOAD
source initGanrec

for command in python selectAngleSequenceForFBP createTickFile dentk-cat; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: command not found: $command" >&2
        exit 2
    fi
done

# Validate input/output paths before running the selector.
python - \
    "$INPUT_DEN" "$NANO_LOG_FILE" \
    "$OUTPUT_DEN" "$OUTPUT_TICK" "$JSON_FILE" "$FORCE" <<'PY'
from pathlib import Path
import sys

input_den, metadata, output_den, output_tick, report, force = sys.argv[1:]
inputs = [Path(input_den), Path(metadata)]
outputs = [Path(output_den), Path(output_tick)]
if report:
    outputs.append(Path(report))

for path in inputs:
    if not path.is_file():
        raise SystemExit(f"Error: input file not found: {path}")

resolved_inputs = {p.resolve() for p in inputs}
resolved_outputs = [p.resolve() for p in outputs]

if len(set(resolved_outputs)) != len(resolved_outputs):
    raise SystemExit("Error: output paths must be distinct")

for path in outputs:
    if path.resolve() in resolved_inputs:
        raise SystemExit(f"Error: output would overwrite an input: {path}")
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise SystemExit(f"Error: output must be a regular file path: {path}")
    if path.exists() and force != "true":
        raise SystemExit(f"Error: output exists: {path}; use --force")
PY

TMPDIR_JOB=$(mktemp -d .balanceAngleSequence.XXXXXX)
cleanup() {
    rm -rf -- "$TMPDIR_JOB"
}
trap cleanup EXIT

SELECTION_JSON="$TMPDIR_JOB/selection.json"
RANGE_FILE="$TMPDIR_JOB/range.txt"
STAGED_DEN="$TMPDIR_JOB/projections.den"
STAGED_TICK="$TMPDIR_JOB/geometry.tck"

# 1. Select once. The installed selector should rank starts by RMS,
#    after choosing the endpoint-optimal count for each start.
selectAngleSequenceForFBP nano "$NANO_LOG_FILE" \
    --crop "$CROP" \
    --extra-removals "$EXTRA_REMOVALS" \
    --max-span-deg "$MAX_SPAN_DEG" \
    --score rms \
    --output "$SELECTION_JSON"

# 2. Validate the JSON and agreement between metadata and projection counts.
#    Write a simple machine-readable range for Bash.
python - "$SELECTION_JSON" "$INPUT_DEN" > "$RANGE_FILE" <<'PY'
import json
import sys
from denpy import DEN

with open(sys.argv[1], encoding="utf-8") as stream:
    report = json.load(stream)

def integer_field(name):
    value = report.get(name)
    if type(value) is not int:
        raise SystemExit(f"Error: JSON field {name!r} must be an integer")
    return value

start = integer_field("selected_range_fromidx")
count = integer_field("selected_range_count")
total = integer_field("input_frame_count")

if total <= 0 or start < 0 or count <= 0 or start + count > total:
    raise SystemExit("Error: invalid selected frame range")

dims = DEN.readHeader(sys.argv[2])["dimspec"]
if len(dims) != 3:
    raise SystemExit("Error: projection input must be a 3D DEN file")
if dims[2] != total:
    raise SystemExit(
        f"Error: projection count {dims[2]} differs from metadata count {total}"
    )

print(start, count, start + count - 1)
PY

read -r FROM_IDX FRAME_COUNT LAST_IDX < "$RANGE_FILE"

echo "Selected --from $FROM_IDX --frame-count $FRAME_COUNT"
echo "Copying inclusive projection frames ${FROM_IDX}-${LAST_IDX}"

# 3. Copy the selected projections. dentk-cat ranges include both endpoints.
dentk-cat \
    --frames "${FROM_IDX}-${LAST_IDX}" \
    "$INPUT_DEN" "$STAGED_DEN"

# 4. Generate matching ticks directly from the same original metadata.
#    No normalization flags: preserve original measured angular coordinates.
createTickFile nano "$NANO_LOG_FILE" "$STAGED_TICK" \
    --from "$FROM_IDX" \
    --frame-count "$FRAME_COUNT"

# 5. Verify output dimensions before publishing.
python - "$INPUT_DEN" "$STAGED_DEN" "$STAGED_TICK" "$FRAME_COUNT" <<'PY'
import sys
from denpy import DEN

input_dims = DEN.readHeader(sys.argv[1])["dimspec"]
output_dims = DEN.readHeader(sys.argv[2])["dimspec"]
tick_shape = DEN.readHeader(sys.argv[3])["shape"]
count = int(sys.argv[4])

expected_dims = tuple(input_dims[:2]) + (count,)
if tuple(output_dims) != expected_dims:
    raise SystemExit(
        f"Error: cropped DEN dimensions {output_dims}, expected {expected_dims}"
    )

if tuple(tick_shape) != (3, count):
    raise SystemExit(
        f"Error: tick shape {tick_shape}, expected (3, {count})"
    )
PY

mkdir -p -- "$(dirname -- "$OUTPUT_DEN")"
mkdir -p -- "$(dirname -- "$OUTPUT_TICK")"
if [[ -n "$JSON_FILE" ]]; then
    mkdir -p -- "$(dirname -- "$JSON_FILE")"
fi

# All generation/validation has succeeded before replacing any outputs.
# Publication of these separate files is not a multi-file atomic transaction.
mv -f -- "$STAGED_DEN" "$OUTPUT_DEN"
mv -f -- "$STAGED_TICK" "$OUTPUT_TICK"
if [[ -n "$JSON_FILE" ]]; then
    mv -f -- "$SELECTION_JSON" "$JSON_FILE"
fi

elapsed_time=$(( $(date +%s) - start_time ))
printf -v formatted_time '%02d:%02d:%02d' \
    "$((elapsed_time / 3600))" \
    "$(((elapsed_time % 3600) / 60))" \
    "$((elapsed_time % 60))"

echo "END ${jobname} ${formatted_time}"
echo "Projections: $OUTPUT_DEN"
echo "Ticks:       $OUTPUT_TICK"
if [[ -n "$JSON_FILE" ]]; then
    echo "Selection:   $JSON_FILE"
fi
