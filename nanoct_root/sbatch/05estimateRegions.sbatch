#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/05estimateRegions-%N-%j.out
#SBATCH --error=log/05estimateRegions-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# === Default values ===
WD=""

# === Usage function ===
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD>

Options:
  --img <file>                Input image file (default: img_clean.den)
  --ref <file>                Input reference file (default: ref_clean.den)
  -h, --help                  Show this help message and exit.

Arguments:
  WD                          Working directory
EOF
}

IMG="img_clean_darksub.den"
REF="ref_clean_darksub.den"

# Parse options
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
if [[ -z "${WD:-}" ]]; then
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

source initGanrec

REF_BASE=$(basename "$REF" .den)
IMG_BASE=$(basename "$IMG" .den)

estimateSampleRegion.py "${REF_BASE}_avg.den" "${IMG_BASE}_avg.den" "${IMG_BASE}_sd.den" --snr "${REF_BASE}_SNR.den" --snr-threshold 50 --out-pdf "${REF_BASE}_sampleRegion.pdf" --out-json "${REF_BASE}.json" --buckets 10

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
