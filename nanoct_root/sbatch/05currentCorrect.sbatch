#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=05currentCorrect
#SBATCH --output=log/05currentCorrect-%N-%j.out
#SBATCH --error=log/05currentCorrect-%N-%j.err

set -Eeuo pipefail

scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"

trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

echo "START ${jobname} $*"
echo "Date: $(date '+%d.%m.%Y %H:%M:%S')"
start_time=$(date +%s)

print_end() {
    local status=$?
    local elapsed=$(( $(date +%s) - start_time ))
    printf 'END %s in %02d:%02d:%02d (exit=%d)\n' "$jobname" \
        $(( elapsed / 3600 )) $(( (elapsed % 3600) / 60 )) $(( elapsed % 60 )) "$status"
}
trap print_end EXIT

# === Defaults ===
KEEP_INPUT_FILES=true
FIX_CORRUPTED_H5=false
FORCE=false

NANO_LOG_FILE=""
NANO_IMAGE_DIR=""
H5_FILE=""
TIME_GAP=""

# Time-offset options are recorded as supplied, then validated per mode.
TIME_OFFSET_OPTIONS=()

IMG="img_clean_darksub.den"
REF="ref_clean_darksub.den"
SUFFIX="_curcor"
WD=""

usage() {
    local out=1
    [[ "${1:-help}" == "error" ]] && out=2
    cat >&"$out" <<EOF
Usage: $scriptname [options] <WD>

Metadata source (choose at most one; default: WD/h5):
  --nano-log-file FILE       NanoCT log. Must exist; no H5 fallback.
  --h5-file FILE             MicroCT H5 file. Must exist.

NanoCT only:
  --nano-image-dir DIR       Original TIFF directory for log matching.

MicroCT only (at most one; default --correct-insertion-offset):
  --correct-insertion-offset Use time_insertion_offset_sec from params.
  --correct-time-offset      Use time_offset_sec from params.
  --no-time-offset           Apply no current time offset.
  --fix-corrupted-h5         Copy input uncorrected on H5 metadata failure.

General:
  --img FILE                 Projection DEN (default: img_clean_darksub.den)
  --ref FILE                 Reference DEN (default: ref_clean_darksub.den)
  --suffix TEXT              Output suffix (default: _curcor)
  --time-gap SECONDS         Segmentation threshold passed to currentCorrect
  --force                    Allow overwriting existing outputs
  --remove-input-files       Delete inputs after all corrections succeed
  -h, --help                 Show this help

Positional arguments:
  WD                         Working directory

Relative paths are resolved inside WD.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_value() {
    if [[ $# -lt 2 || -z "${2:-}" || "$2" == --* ]]; then
        usage error
        die "Option $1 requires a value."
    fi
}

set_once() {
    # set_once VARNAME OPTION VALUE: reject repeated options.
    local var="$1" opt="$2" value="$3"
    [[ -z "${!var}" ]] || die "$opt was supplied more than once."
    printf -v "$var" '%s' "$value"
}

# === Parse arguments ===
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nano-log-file)
            require_value "$@"; set_once NANO_LOG_FILE "$1" "$2"; shift 2 ;;
        --h5-file)
            require_value "$@"; set_once H5_FILE "$1" "$2"; shift 2 ;;
        --nano-image-dir)
            require_value "$@"; set_once NANO_IMAGE_DIR "$1" "$2"; shift 2 ;;
        --time-gap)
            require_value "$@"; set_once TIME_GAP "$1" "$2"; shift 2 ;;
        --img)
            require_value "$@"; IMG="$2"; shift 2 ;;
        --ref)
            require_value "$@"; REF="$2"; shift 2 ;;
        --suffix)
            require_value "$@"; SUFFIX="$2"; shift 2 ;;
        --correct-insertion-offset|--correct-time-offset|--no-time-offset)
            TIME_OFFSET_OPTIONS+=("$1"); shift ;;
        --fix-corrupted-h5)
            FIX_CORRUPTED_H5=true; shift ;;
        --force)
            FORCE=true; shift ;;
        --remove-input-files)
            KEEP_INPUT_FILES=false; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift; POSITIONAL_ARGS+=("$@"); break ;;
        -*)
            usage error; die "Unknown option: $1" ;;
        *)
            POSITIONAL_ARGS+=("$1"); shift ;;
    esac
done

if [[ ${#POSITIONAL_ARGS[@]} -ne 1 ]]; then
    usage error
    die "Exactly one working directory is required, got ${#POSITIONAL_ARGS[@]}."
fi
WD="${POSITIONAL_ARGS[0]}"

[[ -d "$WD" ]] || die "Working directory does not exist: $WD"
[[ "$SUFFIX" != */* ]] || die "--suffix must not contain '/'."

if [[ -n "$TIME_GAP" ]]; then
    [[ "$TIME_GAP" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] \
        || die "--time-gap must be a positive number, got '$TIME_GAP'."
fi

# === Validate source-independent option conflicts before cd ===
if [[ -n "$NANO_LOG_FILE" && -n "$H5_FILE" ]]; then
    die "Use either --nano-log-file or --h5-file, not both."
fi

if [[ -n "$NANO_LOG_FILE" ]]; then
    MODE="nano"
else
    MODE="micro"
fi

if [[ "$MODE" == "nano" ]]; then
    if [[ ${#TIME_OFFSET_OPTIONS[@]} -gt 0 ]]; then
        die "Time-offset options (${TIME_OFFSET_OPTIONS[*]}) are invalid with" \
            "--nano-log-file: NanoCT frames and currents share log timestamps." \
            "Remove them upstream."
    fi
    if [[ "$FIX_CORRUPTED_H5" == true ]]; then
        die "--fix-corrupted-h5 is invalid with --nano-log-file. Remove it upstream."
    fi
else
    if [[ -n "$NANO_IMAGE_DIR" ]]; then
        die "--nano-image-dir requires --nano-log-file."
    fi
    if [[ ${#TIME_OFFSET_OPTIONS[@]} -gt 1 ]]; then
        die "Supply at most one time-offset option, got: ${TIME_OFFSET_OPTIONS[*]}"
    fi
fi

# Retain the existing environment initialization.
source initGanrec

cd -- "$WD"
echo "Working directory: $PWD"

command -v currentCorrect >/dev/null 2>&1 \
    || die "currentCorrect is not available in PATH."

# Fail early if the installed currentCorrect predates the new interface.
if ! currentCorrect --help 2>/dev/null | grep -q -- '--nano-log-file'; then
    die "Installed currentCorrect does not support --nano-log-file/--input-h5." \
        "Install the updated version."
fi

# === Resolve metadata source; no fallback between explicit sources ===
METADATA_ARGS=()

if [[ "$MODE" == "nano" ]]; then
    [[ -f "$NANO_LOG_FILE" ]] \
        || die "NanoCT log does not exist: $PWD/$NANO_LOG_FILE (no H5 fallback)."
    METADATA_ARGS=(--nano-log-file "$NANO_LOG_FILE")

    if [[ -n "$NANO_IMAGE_DIR" ]]; then
        [[ -d "$NANO_IMAGE_DIR" ]] \
            || die "Nano image directory does not exist: $NANO_IMAGE_DIR"
        METADATA_ARGS+=(--nano-image-dir "$NANO_IMAGE_DIR")
    fi
    echo "Metadata: NanoCT log $NANO_LOG_FILE (no time offset)"
else
    if [[ -n "$H5_FILE" ]]; then
        [[ -f "$H5_FILE" ]] || die "H5 file does not exist: $H5_FILE"
        echo "Metadata: explicit H5 $H5_FILE"
    else
        H5_FILE="h5"
        [[ -f "$H5_FILE" ]] \
            || die "No metadata source supplied and default '$PWD/h5' does not exist." \
                   "Use --h5-file or --nano-log-file."
        echo "Metadata: default H5 $PWD/h5"
    fi

    METADATA_ARGS=(--input-h5 "$H5_FILE")

    if [[ ${#TIME_OFFSET_OPTIONS[@]} -eq 0 ]]; then
        TIME_OFFSET_OPTIONS=(--correct-insertion-offset)
        echo "Time offset: --correct-insertion-offset (default)"
    else
        echo "Time offset: ${TIME_OFFSET_OPTIONS[0]}"
    fi

    # --no-time-offset is a script-level choice: pass nothing to Python.
    if [[ "${TIME_OFFSET_OPTIONS[0]}" != "--no-time-offset" ]]; then
        METADATA_ARGS+=("${TIME_OFFSET_OPTIONS[0]}")
    fi

    if [[ "$FIX_CORRUPTED_H5" == true ]]; then
        METADATA_ARGS+=(--fix-corrupted-h5)
    fi
fi

LOGDIR="log/currentCorrect"
mkdir -p -- "$LOGDIR"

# === Correction function ===
functionCurrentCorrect() {
    local typeid="$1" inputFile="$2" outputFile="$3"
    local base_out timestamp logFile infoFile figFile

    base_out="$(basename -- "$outputFile")"
    base_out="${base_out%.den}"
    timestamp="$(date +%d%m%Y_%H%M%S)_${SLURM_JOB_ID:-local}_$$"

    logFile="${LOGDIR}/${base_out}_curcorinfo_${timestamp}.log"
    infoFile="${LOGDIR}/${base_out}_curcorinfo_${timestamp}.den"
    figFile="${LOGDIR}/${base_out}_curcorinfo_${timestamp}.pdf"

    local args=(
        "$inputFile" "$outputFile"
        "${METADATA_ARGS[@]}"
        --type "$typeid"
        --saveinfo "$infoFile"
        --savefig "$figFile"
        --tv-denoise
    )

    case "$typeid" in
        IMG) args+=(--connect-gaps --detrend-exponential --remove-short-term-noise 0.1) ;;
        REF) args+=(--detrend-data) ;;
        *)   echo "ERROR: Unknown type: $typeid" >&2; return 1 ;;
    esac

    [[ -n "$TIME_GAP" ]] && args+=(--time-gap "$TIME_GAP")
    [[ "$FORCE" == true ]] && args+=(--force)

    echo "[$timestamp] $MODE correction: $inputFile ($typeid) -> $outputFile"
    echo "  Log: $logFile"
    printf '%q ' currentCorrect "${args[@]}"
    printf '\n'

    # pipefail makes a Python or tee failure fail this pipeline.
    if ! currentCorrect "${args[@]}" 2>&1 | tee "$logFile"; then
        echo "ERROR: currentCorrect failed for $inputFile (see $logFile)" >&2
        return 1
    fi

    if [[ ! -s "$outputFile" ]]; then
        echo "ERROR: Output missing or empty: $outputFile" >&2
        return 1
    fi
    echo "Success: $inputFile -> $outputFile"
}

# === Select inputs and preflight outputs ===
inputs=("$IMG" "$REF")
input_types=(IMG REF)
selected_inputs=()
selected_types=()
selected_outputs=()

for i in "${!inputs[@]}"; do
    input="${inputs[$i]}"
    typeid="${input_types[$i]}"

    if [[ ! -f "$input" ]]; then
        echo "Input '$input' does not exist; skipping $typeid."
        continue
    fi

    output="${input%.den}${SUFFIX}.den"

    if [[ "$input" == "$output" || "$input" -ef "$output" ]]; then
        die "Output would overwrite input: $input"
    fi
    if [[ -e "$output" || -L "$output" ]]; then
        [[ "$FORCE" == true ]] || die "Output exists: $output; use --force to overwrite."
        [[ ! -d "$output" ]] || die "Output is a directory: $output"
    fi

    selected_inputs+=("$input")
    selected_types+=("$typeid")
    selected_outputs+=("$output")
done

[[ ${#selected_inputs[@]} -gt 0 ]] || die "Neither requested input DEN exists."

for i in "${!selected_outputs[@]}"; do
    for j in "${!selected_inputs[@]}"; do
        if [[ "${selected_outputs[$i]}" == "${selected_inputs[$j]}" ||
              "${selected_outputs[$i]}" -ef "${selected_inputs[$j]}" ]]; then
            die "Output conflicts with a selected input: ${selected_outputs[$i]}"
        fi
    done
    for j in "${!selected_outputs[@]}"; do
        if (( j > i )) && [[ "${selected_outputs[$i]}" == "${selected_outputs[$j]}" ]]; then
            die "Selected output paths conflict: ${selected_outputs[$i]}"
        fi
    done
done

# === Execute; stop on the first failure ===
for i in "${!selected_inputs[@]}"; do
    functionCurrentCorrect "${selected_types[$i]}" "${selected_inputs[$i]}" "${selected_outputs[$i]}"
done

if [[ "$KEEP_INPUT_FILES" == false ]]; then
    for input in "${selected_inputs[@]}"; do
        echo "Removing processed input: $input"
        rm -f -- "$input"
    done
fi
