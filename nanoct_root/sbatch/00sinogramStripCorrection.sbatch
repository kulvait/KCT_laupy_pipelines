#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu
#SBATCH --output=log/00sinogramStripCorrection-%N-%j.out
#SBATCH --error=log/00sinogramStripCorrection-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)


# Positional arguments
WD=""
EXT=""
OUT=""

# Arguments with defaults
GAUSS_FLAG=""
SNR_VALUE="3.0"
LA_SIZE="51"
SM_SIZE="21"
# Stripe-fitting defaults
STRIPE_FITTING_FLAG=""
STRIPE_FITTING_ORDER="2"
STRIPE_FITTING_SIGMA="10"
STRIPE_FITTING_CHUNKS="1"
STRIPE_FITTING_SORT_FLAG=""

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <EXT> <OUT>

Apply sinogram stripe correction to a DEN file.

Options:
  --gauss                         Enable Gaussian smoothing.
  --snr SNR                       Signal-to-noise ratio (default: 3.0).
  --la-size SIZE                  Large filter size (default: 51).
  --sm-size SIZE                  Small filter size (default: 21).
  --stripe-fitting                Enable stripe-fitting correction.
  --stripe-fitting-order ORDER    Polynomial order (default: 2).
  --stripe-fitting-sigma SIGMA    Gaussian sigma for stripe fitting (default: 10).
  --stripe-fitting-chunks COUNT   Number of processing chunks (default: 1).
  --stripe-fitting-sort           Enable sorting during stripe fitting.
  -h, --h, --help                  Show this help message and exit successfully.

Positional arguments:
  WD                              Existing working directory.
  EXT                             Input extinction DEN file.
  OUT                             Output corrected DEN file; existing output is overwritten.

Relative EXT and OUT paths are interpreted from WD.
Stripe-fitting parameters are passed only when --stripe-fitting is enabled.
EOF
}


# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --gauss)
            GAUSS_FLAG="--gauss"
            shift
            ;;

        --snr)
            SNR_VALUE="$2"
            shift
            shift
            ;;

        --la-size)
            LA_SIZE="$2"
            shift
            shift
            ;;

        --sm-size)
            SM_SIZE="$2"
            shift
            shift
            ;;

        --stripe-fitting)
            STRIPE_FITTING_FLAG="--stripe-fitting"
            shift
            ;;

        --stripe-fitting-order)
            STRIPE_FITTING_ORDER="$2"
            shift
            shift
            ;;

        --stripe-fitting-sigma)
            STRIPE_FITTING_SIGMA="$2"
            shift
            shift
            ;;

        --stripe-fitting-chunks)
            STRIPE_FITTING_CHUNKS="$2"
            shift
            shift
            ;;

        --stripe-fitting-sort)
            STRIPE_FITTING_SORT_FLAG="--stripe-fitting-sort"
            shift
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
            elif [ -z "$EXT" ]; then
                EXT="$1"
                echo "EXT=$EXT"
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

# Validate presence of 3 required positionals
if [[ -z "$WD" || -z "$EXT" || -z "$OUT" ]]; then
    echo "Error: missing required positional arguments" >&2
    usage error
    exit 1
fi

unset LD_PRELOAD
source initGanrec
cd $WD || exit 1

if [ ! -f "$EXT" ]; then
    echo "Error: $EXT is not a file" >&2
    exit 1
fi

if [ -f "$OUT" ]; then
    echo "Warning: $OUT already exists, it will be overwritten" >&2
    rm -f "$OUT"
fi

echo "START $scriptname $WD $EXT $OUT" | tee /dev/stderr

THREADS=$(nproc --all)
ARG="--force -j $THREADS"

sinogramStripCorrection() {
    local EXTIN=$1
    local OUT=$2

    if [[ ! -f $EXTIN ]]; then
        echo "File $EXTIN does not exist"
        exit 1
    fi

    EXTINFULL=$(realpath "$EXTIN")
    echo "Processing $EXTINFULL"

    local TMP
    TMP=$(mktemp -d -p . "tmp_00sinogramStripCorrection_XXXXX")

    rm -f "${OUT}"

	STRIPEARGS=""
	if [[ -n "$STRIPE_FITTING_FLAG" ]]; then
    	STRIPEARGS="$STRIPE_FITTING_FLAG \
                --stripe-fitting-order $STRIPE_FITTING_ORDER \
                --stripe-fitting-sigma $STRIPE_FITTING_SIGMA \
                --stripe-fitting-chunks $STRIPE_FITTING_CHUNKS"
    	# add --stripe-fitting-sort only if requested
    	if [[ -n "$STRIPE_FITTING_SORT_FLAG" ]]; then
        	STRIPEARGS="$STRIPEARGS $STRIPE_FITTING_SORT_FLAG"
    	fi
	fi


    dentk-swapaxes $ARG "$EXTIN" "${TMP}/ext_swap.den"
    echo "Removing sinogram strips from ${EXTIN} with parameters: --force $GAUSS_FLAG $STRIPEARGS --snr $SNR_VALUE --la-size $LA_SIZE --sm-size $SM_SIZE"
    removeSinogramStrips.py \
        --force \
        $GAUSS_FLAG \
		$STRIPEARGS \
        --snr "$SNR_VALUE" \
        --la-size "$LA_SIZE" \
        --sm-size "$SM_SIZE" \
        "${TMP}/ext_swap.den" \
        "${TMP}/ext_swap_ssc.den"
    echo "Re-swapping axes to create ${OUT}"
    dentk-swapaxes $ARG "${TMP}/ext_swap_ssc.den" "${OUT}"

    if [[ -f "${OUT}" ]]; then
        rm -rf "${TMP}"
    else
        echo "Failed to create ${OUT} check $(realpath "${TMP}")"
        exit 1
    fi
}

sinogramStripCorrection "$EXT" "$OUT"

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
