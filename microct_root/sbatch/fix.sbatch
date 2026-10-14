#!/bin/bash
#SBATCH --time=0-23:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/fix-%N-%j.out
#SBATCH --error=log/fix-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${scriptname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

WD=""

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        *)
            if [ -z "$WD" ]; then
                WD="$1"
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done


# Check if the number of parameters is 1 and WD is directory
if [ -z "$WD" ] || [ ! -d "$WD" ]; then
    echo "Error: WD is required and must be a directory" >&2
    exit 1
fi

cd $WD

#mv recb2_cgls_bro_v20_0.0005_tv recb2_cgls_bro_v20_0.0005_tv.den
#denFilesToTifFiles.py recb2_cgls_bro_v20_0.0005_tv.den recb2_cgls_bro_v20_0.0005_tv
rm -rf tmp_*
rm -rf dump.rdb
