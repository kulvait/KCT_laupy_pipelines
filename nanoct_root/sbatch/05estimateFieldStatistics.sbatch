#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/05estimateFieldStatistics-%N-%j.out
#SBATCH --error=log/05estimateFieldStatistics-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

IMG="img_clean_darksub.den"
REF="ref_clean_darksub.den"
WD=""

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD>

Options:
  --img <file>                Input dark-subtracted image file (default: img_clean_darksub.den)
  --ref <file>                Input dark-subtracted reference file (default: ref_clean_darksub.den)
  -h, --h, --help                  Show this help message and exit.

Arguments:
  WD                          Working directory
EOF
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --img)
            IMG="$2"
            shift 2
            ;;
        --ref)
            REF="$2"
            shift 2
            ;;
        -h|--h|--help)
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
            else
                echo "Unexpected argument: $1" >&2
                usage error
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "${WD:-}" ]]; then
    echo "Error: Missing required positional argument WD." >&2
    usage error
    exit 1
fi

if [[ ! -d "$WD" ]]; then
    echo "Error: Working directory does not exist: $WD" >&2
    exit 1
fi

cd "$WD" || { echo "Failed to cd into $WD"; exit 1; }

ARG="--force -j -1"

testExistence() {
    if [[ ! -f "$1" ]]; then
        echo "File $1 does not exist."
        exit 1
    fi
}

binProjections() {
    local FILE_INPUT="$1"
    local DIR_OUTPUT="$2"
    local FILE_OUTPUT="$3"
    if [[ ! -d "$DIR_OUTPUT" ]]; then
        mkdir -p "$DIR_OUTPUT"
    fi
    binDenFile --force --median --bin-x 2 --bin-y 2 "$FILE_INPUT" "${DIR_OUTPUT}/${FILE_OUTPUT}"
}

mkdir -p log

testExistence "$IMG"
testExistence "$REF"

TMPDIR=$(mktemp -d -p . "tmp_05estimateFieldStatistics_XXXXXX")

IMGBASE="${IMG%.*}"
REFBASE="${REF%.*}"

echo "Estimating field statistics and SNR from $IMG and $REF"

dentk-framecalc1 $ARG --avg "$IMG" "${IMGBASE}_avg.den"
dentk-framecalc1 $ARG --sample-standard-deviation "$IMG" "${IMGBASE}_sd.den"

dentk-framecalc1 $ARG --avg "$REF" "${REFBASE}_avg.den"
dentk-cat $ARG -k 2 "$REF" "${TMPDIR}/ref_odd.den"
dentk-cat $ARG -f 1-end -k 2 "$REF" "${TMPDIR}/ref_even.den"
dentk-calc $ARG --subtract "${TMPDIR}/ref_odd.den" "${TMPDIR}/ref_even.den" "${TMPDIR}/ref_diff.den"
dentk-framecalc1 $ARG --sample-variance "${TMPDIR}/ref_diff.den" "${TMPDIR}/ref_var_two.den"
dentk-calc1 $ARG --double-softplus "${TMPDIR}/ref_var_two.den" "${TMPDIR}/ref_var_two_softplus.den"
dentk-calc1 $ARG --multiply 0.5 "${TMPDIR}/ref_var_two_softplus.den" "${REFBASE}_var.den"
dentk-calc1 $ARG --square "${REFBASE}_avg.den" "${REFBASE}_avg_sq.den"
dentk-calc $ARG --divide "${REFBASE}_avg_sq.den" "${REFBASE}_var.den" "${REFBASE}_N_snr.den"
dentk-calc1 $ARG --sqrt "${REFBASE}_N_snr.den" "${REFBASE}_SNR.den"

binProjections "${REFBASE}_N_snr.den" extb2 "$(basename "${REFBASE}_N_snr.den")"
binProjections "${REFBASE}_SNR.den" extb2 "$(basename "${REFBASE}_SNR.den")"

rm -rf "$TMPDIR"

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
