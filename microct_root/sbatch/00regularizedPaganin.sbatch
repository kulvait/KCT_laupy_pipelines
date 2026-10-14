#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu
#SBATCH --output=log/00regularizedPaganin-%N-%j.out
#SBATCH --error=log/00regularizedPaganin-%N-%j.err
scriptname=$(basename $0)
# Function to print usage and exit
#This is basically Paganin with ad-hoc regularization factor
usage() {
    echo "Usage: $0 <WD> REGULARIZATION <EXT> <PAG>" >&2
    exit 1
}

# Check if the number of parameters is 2
if [ "$#" -ne 4 ]; then
    usage
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
PAGIN=${EXTBASE}_nt.den


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

TMP=$(mktemp -d -p . "tmp_PAG_XXXXX")

function createPagInput()
{
	local EXT=$1
	local TMP=$2
	local REG=$3
	dentk-calc1 --exp ${EXT} ${TMP}/ext_exp.den
	dentk-calc1 --inv ${TMP}/ext_exp.den ${TMP}/ext_exp_inv.den
	dentk-calc1 --multiply -${REG} ${TMP}/ext_exp_inv.den ${TMP}/neg_tra.den
	if [[ -f ${TMP}/neg_tra.den ]]; then
		echo "Created ${TMP}/neg_tra.den"
	else
		echo "Error creating ${PAGIN} check directory ${TMP}" | tee /dev/stderr
		exit - 1
	fi
}

createPagInput ${EXT} ${TMP} ${REGULARIZATION}
cp ${TMP}/neg_tra.den ${PAGIN}
dentk-poisson --epsilon ${REGULARIZATION} --bc-neumann --force -j 0 ${PAGIN} ${TMP}/ext_exp_pag.den
dentk-calc1 --log ${TMP}/ext_exp_pag.den ${TMP}/ext_neg_pag.den
dentk-calc1 --multiply -1 ${TMP}/ext_neg_pag.den ${TMP}/ext_pos_pag.den
dentk-framenormalize --zero-at-quantile --quantile 0.01 ${TMP}/ext_pos_pag.den ${PAG}
rm -rf ${TMP}

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))


# Convert elapsed time to hours, minutes, and seconds
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))

# Format the elapsed time as HH:MM:SS
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)

# Echo END message to stdout and stderr with the formatted elapsed time
echo "END $scriptname $formatted_time" | tee /dev/stderr
