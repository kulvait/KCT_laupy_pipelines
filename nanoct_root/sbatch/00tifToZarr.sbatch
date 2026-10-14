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
INPUT_DIR=""
OUTPUT_FILE=""
FORCE=false
DELETE_INPUT_DIR=false
ZIP=false

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <INPUT_DIR> <OUTPUT_FILE>

Options:
  --force                     Overwrite existing output file if it exists.
  --delete-input-dir          Delete the input directory after successful conversion.
  --zip                       Create a zip archive of the output Zarr file.
  --h, --help                 Show this help message and exit.

Positional Arguments:
  WD                          Working directory where the conversion will be performed.
  INPUT_DIR                   Path to the input directory containing .tif files to be converted.
  OUTPUT_FILE                 Path where the output .zarr file will be saved.
EOF
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --delete-input-dir)
            DELETE_INPUT_DIR=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
		--zip)
			ZIP=true
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
            elif [[ -z "${INPUT_DIR:-}" ]]; then
                INPUT_DIR="$1"
                echo "INPUT_DIR=$INPUT_DIR"
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
if [[ -z "${WD:-}" || -z "${INPUT_DIR:-}" || -z "${OUTPUT_FILE:-}" ]]; then
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

# Check input directory exists
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Input directory $INPUT_DIR does not exist." >&2
    exit 1
fi

# Ensure output directory exists
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

#Check if input dir contains .tif files
if ! ls "$INPUT_DIR"/*.tif &> /dev/null; then
    echo "Error: No .tif files found in input directory $INPUT_DIR." >&2
    exit 1
fi

unset LD_PRELOAD
source initZarr

ARG="--zip --verbose --zarrv3 -j 0"
if [[ "$FORCE" == true ]]; then
    echo "Force option enabled: existing output will be overwritten."
    ARG="$ARG --force"
fi

# Run conversion
tiffImagesToZarr.py $ARG $(find "$INPUT_DIR" -name "*.tif" | sort) "$OUTPUT_FILE"

# Optionally delete input
if [[ "$DELETE_INPUT_DIR" == true ]]; then
    echo "Deleting input directory: $INPUT_DIR"
    rm -rf "$INPUT_DIR"
fi

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
