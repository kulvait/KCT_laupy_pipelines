#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=15svdCorrectedExtinctions
#SBATCH --output=log/15svdCorrectedExtinctions-%N-%j.out
#SBATCH --error=log/15svdCorrectedExtinctions-%N-%j.err
SCRIPTNAME=$(basename "$0")
echo "Executing $SCRIPTNAME $@"

source initGanrec
source sourcePath
cd $1
THREADS=$(nproc --all)
ARG="--force -j $THREADS"

function svdFieldCorrect()
{
	FLAT=${1%%.den}
	IMG=${2%%.den}
	EXTSVD=${3%%.den}
	MINFLAT=1.0
	rm -f ${FLAT}_max
	rm -f ${EXTSVD}_exp
	rm -f ${EXTSVD}
	dentk-calc1 $ARG --force --max $MINFLAT ${FLAT}.den ${FLAT}_max
	dentk-calc $ARG --divide ${FLAT}_max ${IMG}.den ${EXTSVD}_exp
	dentk-calc1 $ARG --force --log ${EXTSVD}_exp ${EXTSVD}.den 
	rm -f ${FLAT}_max
	rm -f ${EXTSVD}_exp
	if [ -f ${EXTSVD}.den ]; then
		echo "rm ${FLAT}.den"
		rm ${FLAT}.den
	fi
}

if  [ -f FF_ALPHA.den ]; then
svdFieldCorrect FF_ALPHA.den img_dc.den ext_ALPHA.den
fi
if [ -f FF_BETA.den ]; then
svdFieldCorrect FF_BETA.den img_dc.den ext_BETA.den
fi
