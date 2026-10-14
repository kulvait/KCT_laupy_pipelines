#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=11computeExtinction
#SBATCH --output=log/11computeExtinction-%N-%j.out
#SBATCH --error=log/11computeExtinction-%N-%j.err
source initGanrec
source sourcePath
cd $1
THREADS=`nproc --all`
ARG="--force -j ${THREADS}"
PHASECONTRAST=true
MINFLAT=1.0
MINIMG=$(awk 'BEGIN {print 1.0/1024.0}')

function computeExtinction()
{
	FLAT=${1%.den}
	IMG=${2%.den}
	EXT=${3%.den}
	dentk-framecalc1 --force --median ${FLAT}.den ${FLAT}_med
	dentk-calc1 ${ARG} --max ${MINFLAT} ${FLAT}_med ${FLAT}_cor
	dentk-calc1 ${ARG} --max ${MINIMG} ${IMG}.den ${IMG}_max
	if [ "$PHASECONTRAST" = true ]; then
	    mv ${IMG}_max ${IMG}_cor
	else
	    #START does not apply for phase contrast
	    dentk-framecalc ${ARG} --min ${IMG}_max ${FLAT}_cor ${IMG}_cor
	    #END does not apply for phase contrast
	fi
	dentk-framecalc ${ARG} --divide ${IMG}_cor ${FLAT}_cor ${IMG}_tra
	dentk-calc1 ${ARG} --inv ${IMG}_tra ${EXT}_exp
	dentk-calc1 ${ARG} --log ${EXT}_exp ${EXT}.den
	rm -f ${FLAT}_med
	rm -f ${FLAT}_cor
	rm -f ${IMG}_max
	rm -f ${IMG}_cor
	rm -f ${IMG}_tra
	rm -f ${EXT}_exp
}

computeExtinction ref_dc.den img_dc.den ext_dc.den
