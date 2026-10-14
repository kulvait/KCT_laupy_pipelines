#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=00tifftoden
#SBATCH --output=log/00tifftoden-%N-%j.out
#SBATCH --error=log/00tifftoden-%N-%j.err

set -euo pipefail
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

source initGanrec
#source sourcePath
cd $1
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
