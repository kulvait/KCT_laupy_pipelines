#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu
#SBATCH --output=log/00bin-%N-%j.out
#SBATCH --error=log/00bin-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

unset LD_PRELOAD
source initGanrec

# Positional arguments
WD=""
IN=""
OUT=""

# Arguments with defaults
AVERAGE=false
BNX=""
BNY=""
BIN=2

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <IN> <OUT>

Bin a DEN file. Median binning is used unless --average is specified.

Options:
  --bin FACTOR                Default binning factor for both axes (default: 2).
  --bin-x FACTOR              Override the X-axis factor (default: --bin value).
  --bin-y FACTOR              Override the Y-axis factor (default: --bin value).
  --average                   Use average instead of median binning.
  -h,--h,--help              Show this help message and exit successfully.

Positional arguments:
  WD                          Existing working directory.
  IN                          Input DEN file.
  OUT                         Output DEN file; existing output is overwritten.

Relative IN and OUT paths are interpreted from WD.
Missing output parent directories are created automatically.
EOF
}

require_value() {
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Error: $1 requires a value." >&2
        usage error
        exit 1
    fi
}


# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --bin-x)
			require_value "$1" "${2:-}"
	    	BNX="$2"
            shift 2
            ;;
        --bin-y)
			require_value "$1" "${2:-}"
	    	BNY="$2"
            shift 2
            ;;
        --bin)
			require_value "$1" "${2:-}"
            BIN="$2"
            shift 2
            ;;
		--average)
		    AVERAGE=true
	    	shift
	    	;;
		-h|--h|--help)
	    	usage help
		    exit 0
		    ;;
        -*)
            echo "Unknown option: $1" >&2
            usage error
	    	exit 1
            ;;

        *)
            # Positional arguments detected in order
            if [ -z "$WD" ]; then
                WD="$1"
                echo "WD=$WD"
            elif [ -z "$IN" ]; then
                IN="$1"
                echo "IN=$IN"
            elif [ -z "$OUT" ]; then
                OUT="$1"
                echo "OUT=$OUT"
            else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$BNX" ]]; then
    BNX="$BIN"
fi

if [[ -z "$BNY" ]]; then
    BNY="$BIN"
fi

# Validate presence of 3 required positionals
if [[ -z "$WD" || -z "$IN" || -z "$OUT" ]]; then
    echo "Error: missing required positional arguments" >&2
    usage error
    exit 1
fi

cd $WD || exit 1

if [ ! -f "$IN" ]; then
    echo "Error: $IN is not a file" >&2
    exit 1
fi

if [ -f "$OUT" ]; then
    echo "Warning: $OUT already exists, it will be overwritten" >&2
    rm -f "$OUT"
fi

echo "START $scriptname $WD $IN $OUT" | tee /dev/stderr


ARG=(--force)
ARG+=("--bin-x" "$BNX")
ARG+=("--bin-y" "$BNY")
if [ "$AVERAGE" = true ]; then
    ARG+=("--average")
else
    ARG+=("--median")
fi

# Create the output directory if it doesn't exist
mkdir -p "$(dirname "$OUT")"

binDenFile "${ARG[@]}" "$IN" "$OUT"

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
