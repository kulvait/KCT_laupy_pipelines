#!/bin/bash
#SBATCH --time=0-23:00:00
#SBATCH --nodes=1
#SBATCH --requeue

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Arguments
WD=""
INPUT_FILE=""
OUTPUT_FILE=""
FORCE=false
DELETE_INPUT_DEN=false

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <INPUT_FILE> <OUTPUT_FILE>

Options:
  --force                     Overwrite existing output file if it exists.
  --delete-input-den          Delete the input .den file after successful conversion.
  --h, --help                 Show this help message and exit.

Positional Arguments:
  WD                          Working directory where the conversion will be performed.
  INPUT_FILE                  Path to the input .den file to be converted.
  OUTPUT_FILE                 Path where the output .zarr file will be saved.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --delete-input-den)
            DELETE_INPUT_DEN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
		--h|--help)
	    	usage help
	    	exit 0
	    	;;
        -*)
            echo "Unknown option $1" >&2
            usage error
	    	exit 1
            ;;
        *)
            if [[ -z "${WD:-}" ]]; then
                WD="$1"
                echo "WD=$WD"
            elif [[ -z "${INPUT_FILE:-}" ]]; then
                INPUT_FILE="$1"
                echo "INPUT_FILE=$INPUT_FILE"
            elif [[ -z "${OUTPUT_FILE:-}" ]]; then
                OUTPUT_FILE="$1"
                echo "OUTPUT_FILE=$OUTPUT_FILE"
            else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done

# Check required args
if [[ -z "${WD:-}" || -z "${INPUT_FILE:-}" || -z "${OUTPUT_FILE:-}" ]]; then
    echo "Error: Missing required positional arguments." >&2
    usage error
    exit 1
fi

# Check working directory exists
if [[ ! -d "$WD" ]]; then
    echo "Error: Working directory does not exist: $WD" >&2
    exit 1
fi

cd "$WD" || { echo "Failed to cd into $WD"; exit 1; }

# Check input file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file does not exist: $INPUT_FILE" >&2
    exit 1
fi

# Ensure output directory exists
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

unset LD_PRELOAD
source initZarr

ARG="--zip --verbose --zarrv3 -j 0"
if [[ "$FORCE" == true ]]; then
    echo "Force option enabled: existing output will be overwritten."
    ARG="$ARG --force"
fi

# Run conversion
denToZarr.py $ARG "$INPUT_FILE" "$OUTPUT_FILE"

# Optionally delete input
if [[ "$DELETE_INPUT_DEN" == true ]]; then
    echo "Deleting input .den file: $INPUT_FILE"
    rm -f -- "$INPUT_FILE"
fi

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
