#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=00tifftoden
#SBATCH --output=log/00tifftoden-%N-%j.out
#SBATCH --error=log/00tifftoden-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} <WD>
       ${scriptname} -h|--h|--help

Convert the raw TIFF structure in WD to DEN files.

Options:
  -h, --h, --help              Show this help message and exit successfully.

Positional arguments:
  WD                          Existing working directory containing h5 and raw/.

If dar.den, img.den, and ref.den all exist, exit successfully without conversion.
Otherwise, remove img_cor.den, ref_cor.den, ext.den, dar.den, img.den, and ref.den
before running rawTiffStructureToDen.py h5 . --raw-dir raw --force.
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h|--h|--help)
            usage help
            exit 0
            ;;
    esac
done

if [[ $# -ne 1 || -z "${1:-}" ]]; then
    echo "Error: Expected one working-directory argument." >&2
    usage error
    exit 1
fi

WD="$1"
if [[ ! -d "$WD" ]]; then
    echo "Error: Working directory does not exist: $WD" >&2
    exit 1
fi

source initGanrec
cd "$WD"

#Remove previsous
#Exit if dar.den and img.den and ref.den exist
if [[ -f dar.den ]] && [[ -f img.den ]] && [[ -f ref.den ]]; then
    echo "dar.den and img.den and ref.den exist"
    exit 0
fi
rm -f img_cor.den
rm -f ref_cor.den
rm -f ext.den
rm -f dar.den
rm -f img.den
rm -f ref.den
rawTiffStructureToDen.py h5 . --raw-dir raw --force

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
