#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=12createUnbinnedAlpha
#SBATCH --output=log/12createUnbinnedAlpha-%N-%j.out
#SBATCH --error=log/12createUnbinnedAlpha-%N-%j.err
SCRIPTNAME=$(basename "$0")
echo "$SCRIPTNAME $@"

source initGanrec
source sourcePath
cd $1
THREADS=`nproc --all`
ARG="--force -j ${THREADS}"
rm -f ALPHA_IMG.den

function createLowSumMask()
{
	COM=${1%.den}
	OUT=${2%.den}
	QNT=${3}
	dentk-framecalc1 --force --sum ${COM}.den ${COM}_sum
	dentk-alpha $ARG --lower-quantile ${QNT} ${COM}_sum ${OUT}.den
	rm -f ${COM}_sum
}

function createHiSumMask()
{
	COM=${1%.den}
	OUT=${2%.den}
	QNT=${3}
	dentk-framecalc1 --force --sum ${COM}.den ${COM}_sum
	dentk-alpha $ARG --upper-quantile ${QNT} ${COM}_sum ${OUT}.den
	rm -f ${COM}_sum
}

function createLowVarianceMask()
{
	COM=${1%.den}
	OUT=${2%.den}
	QNT=${3}
	dentk-framecalc1 --force --sample-variance ${COM}.den ${COM}_sv
	dentk-alpha $ARG --lower-quantile ${QNT} ${COM}_sv ${OUT}.den
	rm -f ${COM}_sv
}

function createHiVarianceMask()
{
	COM=${1%.den}
	OUT=${2%.den}
	QNT=${3}
	dentk-framecalc1 --force --sample-variance ${COM}.den ${COM}_sv
	dentk-alpha $ARG --upper-quantile ${QNT} ${COM}_sv ${OUT}.den
	rm -f ${COM}_sv
}

createLowSumMask ext_dc.den ALPHA.den 0.1
createHiVarianceMask ref_dc.den GAMMA.den 0.01
dentk-calc --force --max ALPHA.den GAMMA.den BETA.den
#createLowVarianceMask ext_dc.den BETA_EXT.den 0.2 
#createHiSumMask img_dc.den ALPHA_IMG.den 0.2 
#createLowVarianceMask img_dc.den BETA_IMG.den 0.2 
