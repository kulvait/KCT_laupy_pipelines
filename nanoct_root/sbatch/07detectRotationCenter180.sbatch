#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=07detectRotationCenter180_marius
#SBATCH --output=log/07detectRotationCenter180-%N-%j.out
#SBATCH --error=log/07detectRotationCenter180-%N-%j.err
# --- Default ext filename ---

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

#Arguments
CROP_PERCENT=20
FIX_CORRUPTED_H5=false
WD=""
EXT=""
LOGFILE=""
ANGLE_COUNT=1800
NANO_LOG_FILE=""
REGIONS_JSON=""

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <EXT>

Options:
  --log ext_filename          Specify the input .den file to be processed (default: ext_legacy.den).
  --crop-percent PERCENT      Percentage of the image to crop from the edges (default: 20).
  --angle-count COUNT         Number of angles to use for detection (default: 1800).
  --fix-corrupted-h5          Pass --fix-corrupted-h5 to the Python script to attempt to fix corrupted HDF5 files.
  --nano-log-file FILE        Specify a log file for the Python script
  --regions-json FILE         Specify a JSON file containing regions for the Python script.
  --h, --help                 Show this help message and exit.

Positional Arguments:
  WD                          Working directory where the conversion will be performed.
  EXT                         Input .den file to be processed.
  
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
		--log)
		    LOGFILE="$2"
			shift 2
			;;
		--crop-percent)
			CROP_PERCENT="$2"
			shift 2
			;;
		--fix-corrupted-h5)
			FIX_CORRUPTED_H5=true
			shift
			;;
		--angle-count)
			ANGLE_COUNT="$2"
			shift 2
			;;
		--nano-log-file)
			NANO_LOG_FILE="$2"
			shift 2
			;;
		--regions-json)
			REGIONS_JSON="$2"
			shift 2
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
            elif [[ -z "${EXT:-}" ]]; then
				EXT="$1"
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
if [[ -z "${WD:-}" || -z "${EXT:-}" ]]; then
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


# --- Load environment ---
source initGanrec


# --- Prepare output directories and filenames ---
LOGDIR="log/detectRotationCenter"
mkdir -p "${LOGDIR}"

PYTHON_SCRIPT_BASENAME="detectRotationCenter180"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
PDF_PATH="${LOGDIR}/${PYTHON_SCRIPT_BASENAME}_${TIMESTAMP}.pdf"

EXT_BASE=$(basename "$EXT" .den)
if [[ -z "$LOGFILE" ]]; then
	LOGFILE="${EXT_BASE}_rotationcenter180.log"
fi
SINOGRAMS="${EXT_BASE}_sinograms180.den"

ARG=(
    --force
    --store-sinograms "$SINOGRAMS"
    --angle-count "$ANGLE_COUNT"
    --fourier
    --log-file "$LOGFILE"
)
# Check that h5 file or symlink exists
H5_FILE="h5"
if [[ -n "$NANO_LOG_FILE" ]]; then
	TICK_FILE=$(basename "$NANO_LOG_FILE" .log)
	TICK_FILE="${TICK_FILE}.tck"
	createTickFile nano "$NANO_LOG_FILE" "$TICK_FILE"
    ARG+=(--input-tick "$TICK_FILE")
elif [[ -f "$H5_FILE" ]]; then
    ARG+=(--input-h5 "$H5_FILE")
else
	ARG+=(--input-linspace)
    echo "Warning: Expected HDF5 file not found: $H5_FILE, not adding --input-linspace provided to detectRotationCenter180.py"
fi
if [[ -n "$CROP_PERCENT" ]]; then
    ARG+=(--crop-percent "$CROP_PERCENT")
fi
if [[ "$FIX_CORRUPTED_H5" == true ]]; then
    ARG+=(--fix-corrupted-h5)
fi

# --- Run detection ---
#estimateSampleRegion.py ref_clean_darksub_avg.den img_clean_darksub_avg.den img_clean_darksub_sd.den --snr SNR.den --snr-threshold 50 --buckets 10 --out-pdf buckets.pdf --out-json buckets.json
#ARG+=(--regions-json buckets.json)
if [[ -n "$REGIONS_JSON" ]]; then
    ARG+=(--regions-json "$REGIONS_JSON")
fi
detectRotationCenter180.py "${ARG[@]}" "$EXT"

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time, results in $LOGFILE and plots in $PDF_PATH."
