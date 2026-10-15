#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu
#SBATCH --output=log/00regularizedBronikov-%N-%j.out
#SBATCH --error=log/00regularizedBronikov-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Function to print usage and exit
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} <WD> <REGULARIZATION> <EXT> <PAG>
       ${scriptname} -h|--h|--help

Apply regularized Bronikov processing.

Options:
  -h, --h, --help              Show this help message and exit successfully.

Positional arguments:
  WD                          Existing working directory.
  REGULARIZATION              Regularization coefficient passed as --epsilon.
  EXT                         Input extinction DEN file.
  PAG                         Output processed DEN file; output is forced.

Relative EXT and PAG paths are interpreted from WD.
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

if [[ $# -ne 4 ]]; then
    echo "Error: Expected WD, REGULARIZATION, EXT, and PAG." >&2
    usage error
    exit 1
fi

# Assign parameters to variables
WD=$1
REGULARIZATION=$2
EXT=$3
PAG=$4

# Check if WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

cd $WD

# Check if EXT exists
if [ ! -f "$EXT" ]; then
    echo "Error: $EXT is not a file" >&2
    exit 1
fi

PAGBASE=${PAG%.den}
EXTBASE=${EXT%.den}
PAGIN=${EXTBASE}_trn.den

TMP=$(mktemp -d -p . "tmp_PAG_XXXXX")
PAGIN=${TMP}/tra_minus_one.den

# Check if REGULARIZATION is positive float
if ! [[ "$REGULARIZATION" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    echo "Error: REGULARIZATION is not a positive float" >&2
    exit 1
	if [ "$REGULARIZATION" -le 0 ]; then
		echo "Error: REGULARIZATION is not a positive float" >&2
		exit 1
	fi
fi

echo "START $scriptname $WD $EXT" | tee /dev/stderr

# Record the start time
start_time=$(date +%s)

#Start of the body of the script


function createPagInput()
{
	local EXT=$1
	local PAGIN=$2
	local TMP=$3
	dentk-calc1 --exp ${EXT} ${TMP}/ext_exp.den
	dentk-calc1 --inv ${TMP}/ext_exp.den ${TMP}/ext_exp_inv.den
	dentk-calc1 --add -1.0 ${TMP}/ext_exp_inv.den ${PAGIN}
}

createPagInput ${EXT} ${PAGIN} ${TMP}

dentk-poisson --epsilon ${REGULARIZATION} --bc-neumann --force -j 0 ${PAGIN} ${PAG}
#dentk-poisson --epsilon ${REGULARIZATION} --bc-dirichlet --force -j 0 ${PAGIN} ${PAGBASE}_dir.den
#dentk-poisson --epsilon ${REGULARIZATION} --bc-periodic --force -j 0 ${PAGIN} ${PAGBASE}_per.den
if [[ ! -f ${PAG} ]]; then
	echo "Error creating ${PAG}" | tee -a /dev/stderr
	exit -1
else
	echo "Created ${PAG}"
	rm -rf ${TMP}
fi

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
