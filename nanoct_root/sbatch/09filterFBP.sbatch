#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allgpu
#SBATCH --job-name=09filterFBP
#SBATCH --output=log/09filterFBP-%N-%j.out
#SBATCH --error=log/09filterFBP-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR 
echo "START ${jobname} $*"
start_time=$(date +%s)

# === Default values ===
BINNING=2
PADDING=""
WD=""
IN=""
OUT=""

# === Usage ===

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <IN> <OUT>

  --binning VALUE          Binning factor (default: 2)

Base filter options (mutually exclusive):
  --filter-ideal-ramp
  --filter-ram-lak (default)

Window options (mutually exclusive):
  --window-ramp (default)
  --window-shepp-logan
  --window-cosine
  --window-hanning
  --window-hamming
  --window-kaiser
  --window-kaiser-beta VALUE   Only valid with --window-kaiser

Padding options (mutually exclusive):
  --pad-none
  --pad-symm (default)
  --pad-symm-zero
  --pad-zero

Positional arguments:
  WD              Working directory
  IN              Input .den file
  OUT             Output .den file

EOF
}

FILTER="--filter-ram-lak"
WINDOW="--window-ramp"
KAISER_BETA=9

while [[ $# -gt 0 ]]; do
	case "$1" in
		--binning)
			if [[ -z "$2" || "$2" == -* ]]; then
				echo "Error: --binning requires a value"
				usage error
			fi
	           #It must be a positive integer
		    if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
				echo "Error: --binning requires a positive integer value"
				usage error
		    fi
			BINNING="$2"
			shift 2
			;;
		--pad-none)
			[[ -n "$PADDING" ]] && { echo "Error: padding options are mutually exclusive"; usage; }
			PADDING="--pad-none"
			shift
			;;
		--pad-symm)
			[[ -n "$PADDING" ]] && { echo "Error: padding options are mutually exclusive"; usage; }
			PADDING="--pad-symm"
			shift
			;;
		--pad-symm-zero)
			[[ -n "$PADDING" ]] && { echo "Error: padding options are mutually exclusive"; usage; }
			PADDING="--pad-symm-zero"
			shift
			;;
		--pad-zero)
			[[ -n "$PADDING" ]] && { echo "Error: padding options are mutually exclusive"; usage; }
			PADDING="--pad-zero"
			shift
			;;
		--filter-ideal-ramp)
		    [[ "$FILTER" != "--filter-ram-lak" ]] && { echo "Error: filter options are mutually exclusive"; usage; }
		    FILTER="--filter-ideal-ramp"
		    shift
		    ;;
		--filter-ram-lak)
		    [[ "$FILTER" != "--filter-ideal-ramp" ]] && { echo "Error: filter options are mutually exclusive"; usage; }
		    FILTER="--filter-ram-lak"
		    shift
		    ;;
		--window-ramp)
		    [[ "$WINDOW" != "--window-ramp" ]] && { echo "Error: window options are mutually exclusive"; usage; }
		    WINDOW="--window-ramp"
		    shift
		    ;;
		--window-shepp-logan)
		    [[ "$WINDOW" != "--window-ramp" ]] && { echo "Error: window options are mutually exclusive"; usage; }
		    WINDOW="--window-shepp-logan"
		    shift
		    ;;
		--window-cosine)
		    [[ "$WINDOW" != "--window-ramp" ]] && { echo "Error: window options are mutually exclusive"; usage; }
		    WINDOW="--window-cosine"
		    shift
		    ;;
		--window-hanning)
		    [[ "$WINDOW" != "--window-ramp" ]] && { echo "Error: window options are mutually exclusive"; usage; }
		    WINDOW="--window-hanning"
		    shift
		    ;;
		--window-hamming)
		    [[ "$WINDOW" != "--window-ramp" ]] && { echo "Error: window options are mutually exclusive"; usage; }
		    WINDOW="--window-hamming"
		    shift
		    ;;
		--window-kaiser)
		    [[ "$WINDOW" != "--window-ramp" ]] && { echo "Error: window options are mutually exclusive"; usage; }
		    WINDOW="--window-kaiser"
		    shift
			;;	
		--window-kaiser-beta)
		    if [[ -z "$2" || "$2" == -* ]]; then
		        echo "Error: --window-kaiser-beta requires a value"
		        usage error
		    fi
		    KAISER_BETA="$2"
		    shift 2
		    ;;
		-h|--help)
	    	usage
			exit 0
	    	;;
        -*)
            echo "Unknown option: $1"
            usage error
			exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# === Positional argument checks ===
if [[ ${#POSITIONAL_ARGS[@]} -ne 3 ]]; then
    echo "Error: Missing required arguments <WD> <IN> <OUT>"
    usage
fi

WD="${POSITIONAL_ARGS[0]}"
IN="${POSITIONAL_ARGS[1]}"
OUT="${POSITIONAL_ARGS[2]}"

if [[ -z "$PADDING" ]]; then
	PADDING="--pad-symm"
fi

# === Load environment ===
source initGanrec

# === Enter working directory ===
cd "$WD" || { echo "Error: Cannot enter working directory $WD"; exit 1; }


THREADS=$(nproc --all)

# === Parse arguments ===
POSITIONAL_ARGS=()
if [[ $FILTER == "--filter-ideal-ramp" ]]; then
    POSITIONAL_ARGS+=("--filter-ideal-ramp")
else
    POSITIONAL_ARGS+=("--filter-ram-lak")
fi
if [[ $WINDOW == "--window-ramp" ]]; then
    POSITIONAL_ARGS+=("--window-ramp")
elif [[ $WINDOW == "--window-shepp-logan" ]]; then
    POSITIONAL_ARGS+=("--window-shepp-logan")
elif [[ $WINDOW == "--window-cosine" ]]; then
    POSITIONAL_ARGS+=("--window-cosine")
elif [[ $WINDOW == "--window-hanning" ]]; then
    POSITIONAL_ARGS+=("--window-hanning")
elif [[ $WINDOW == "--window-hamming" ]]; then
    POSITIONAL_ARGS+=("--window-hamming")
elif [[ $WINDOW == "--window-kaiser" ]]; then
    POSITIONAL_ARGS+=("--window-kaiser")
	POSITIONAL_ARGS+=("--window-kaiser-beta" "$KAISER_BETA")
fi

if [[ -n "$PADDING" ]]; then
    POSITIONAL_ARGS+=("$PADDING")
else
    POSITIONAL_ARGS+=("--pad-symm")
fi

# === Load params inside WD ===
source params
#Pixel sizes in mm shall be set if not set to 1.0 mm
if [[ -z "${pixel_size_x:-}" ]]; then
    pixel_size_x=1.0
    echo "Warning: pixel_size_x not set in params, defaulting to 1.0 mm"
fi
if [[ -z "${pixel_size_y:-}" ]]; then
    pixel_size_y=1.0
    echo "Warning: pixel_size_y not set in params, defaulting to 1.0 mm"
fi
PXBIN=$( calc "${BINNING}*${pixel_size_x}" )
PYBIN=$( calc "${BINNING}*${pixel_size_y}" )

POSITIONAL_ARGS+=("--pixel-sizex" "${PXBIN}")
POSITIONAL_ARGS+=("--pixel-sizey" "${PYBIN}")

POSITIONAL_ARGS+=("--force")
POSITIONAL_ARGS+=("-j" "-1")



# === Function ===
filterExtinctions() {
    local EXT=${1}
    local OUTFILE=${2}


	dentk-filter \
	"${POSITIONAL_ARGS[@]}" \
	"${EXT}" \
	"${OUTFILE}"
#    local PXBIN=$( calc "2*${pixel_size_x}" )
#    local PYBIN=$( calc "2*${pixel_size_y}" )

#    dentk-filter \
#        -j -1 \
#        --force \
#        ${PADDING} \
#        --pixel-sizex "${PXBIN}" \
#        --pixel-sizey "${PYBIN}" \
#        ${EXT} \
#        "${OUTFILE}"
}

# === Execute ===
filterExtinctions "$IN" "$OUT"

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
