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

cd $1
LOGDIR="ScanDiagnostics"
mkdir -p $LOGDIR
# Use multithrading and optimal CPU number
ARG="--force --verbose -j -1"
# In params will be created time_offset_sec entry
tiffScanInfoForNanotomography ${ARG} LogScan.log ${LOGDIR}/inf_img.den --raw-dir raw --type IMG --savefig ${LOGDIR}/inf_img.pdf
tiffScanInfoForNanotomography ${ARG} LogScan.log ${LOGDIR}/inf_img.den --raw-dir raw --type REF --savefig ${LOGDIR}/inf_ref.pdf
# If there is dar folder or simlink
if [ -d dar ] || [ -L dar ]; then
    tiffScanInfoForNanotomography ${ARG} dar/LogScan.log ${LOGDIR}/inf_dar.den --raw-dir dar/raw --type DAR --ref-is-dar --savefig ${LOGDIR}/inf_dar.pdf
fi
