#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=01scanTimingDiagnostics
#SBATCH --output=log/01scanTimingDiagnostics-%N-%j.out
#SBATCH --error=log/01scanTimingDiagnostics-%N-%j.err

set -euo pipefail
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

source initGanrec
cd $1
LOGDIR="log/ScanDiagnostics"
mkdir -p $LOGDIR
# Use multithrading and optimal CPU number
ARG="--force --verbose -j -1"
# In params will be created time_offset_sec entry
tiffImagesInfo.py ${ARG} h5 ${LOGDIR}/inf_img.den --type IMG --savefig ${LOGDIR}/inf_img.pdf --estimate-insertion-offset
tiffImagesInfo.py ${ARG} h5 ${LOGDIR}/inf_ref.den --type REF --savefig ${LOGDIR}/inf_ref.pdf --correct-insertion-offset
tiffImagesInfo.py ${ARG} h5 ${LOGDIR}/inf_dar.den --type DAR --savefig ${LOGDIR}/inf_dar.pdf --correct-insertion-offset
