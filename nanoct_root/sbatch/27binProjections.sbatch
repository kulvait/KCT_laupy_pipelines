#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=27binProjections-amber
#SBATCH --output=log/27binProjections-%N-%j.out
#SBATCH --error=log/27binProjections-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${scriptname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

cd $1

echo "Processing $1"
source initGanrec

THREADS=$(nproc --all)
ARG="--force -j $THREADS"

if [[ ! -f EXT.den ]]; then
	EXTPATH=$(realpath ${EXT})
	echo "File $EXTPATH does not exist, exiting!"
	exit -1
fi

B2DIR=extb2
mkdir -p $B2DIR

removeIfExistsSecondFile()
{
	TOREMOVE=$1
	TOTEST=$2
	if [[ -f ${TOTEST} ]]; then
		rm -rf ${TOREMOVE}
	else
		echo "File $TOTEST does not exist, exiting!"
		exit -1
	fi
}

#Produces files  ${OUT}/ext_avg.den to be corrected and ${OUT}/ref_logepsilon_v.den to be used for TVFFC
preprocessBinnedAnalysisAvgExt()
{
OUT=${1}
IMG=${2%%.den}
REF=${3%%.den}

mkdir -p ${OUT}
binDenFile --force --median --bin-x 2 --bin-y 2 ${IMG}.den ${OUT}/IMG_bin
binDenFile --force --median --bin-x 2 --bin-y 2 ${REF}.den ${OUT}/REF_bin
dentk-calc1 $ARG --softplus ${OUT}/IMG_bin ${OUT}/img.den
removeIfExistsSecondFile ${OUT}/IMG_bin ${OUT}/img.den
dentk-calc1 $ARG --softplus ${OUT}/REF_bin ${OUT}/ref.den
removeIfExistsSecondFile ${OUT}/REF_bin ${OUT}/ref.den
dentk-framecalc1 $ARG --avg ${OUT}/ref.den ${OUT}/ref_avg.den
dentk-framecalc $ARG --divide ${OUT}/ref.den ${OUT}/ref_avg.den ${OUT}/ref_epsilon.den
dentk-calc1 $ARG --log ${OUT}/ref_epsilon.den ${OUT}/ref_logepsilon.den
removeIfExistsSecondFile ${OUT}/ref_epsilon.den ${OUT}/ref_logepsilon.den
dentk-svd ${OUT}/ref_logepsilon.den ${OUT}/ref_logepsilon_s.den --max_s_vals 100 --vectorsV ${OUT}/ref_logepsilon_v.den
dentk-framecalc $ARG --flipped-divide ${OUT}/img.den ${OUT}/ref_avg.den ${OUT}/exp_ext_avg.den
dentk-calc1 $ARG --log ${OUT}/exp_ext_avg.den ${OUT}/ext_avg.den
removeIfExistsSecondFile ${OUT}/exp_ext_avg.den ${OUT}/ext_avg.den
#Normally I would use median for these

#The following can be removed
#rm -f ${OUT}/img.den
#rm -f ${OUT}/img.den
#rm -f ${OUT}/ref_avg.den
#rm -f ${OUT}/ref_logepsilon.den

}

preprocessBinnedAnalysisMedianExt()
{
OUT=${1}
IMG=${2%%.den}
REF=${3%%.den}

mkdir -p ${OUT}
binDenFile --force --median --bin-x 2 --bin-y 2 ${IMG}.den ${OUT}/IMG_bin
binDenFile --force --median --bin-x 2 --bin-y 2 ${REF}.den ${OUT}/REF_bin
dentk-calc1 $ARG --softplus ${OUT}/IMG_bin ${OUT}/img.den
removeIfExistsSecondFile ${OUT}/IMG_bin ${OUT}/img.den
dentk-calc1 $ARG --softplus ${OUT}/REF_bin ${OUT}/ref.den
removeIfExistsSecondFile ${OUT}/REF_bin ${OUT}/ref.den
dentk-framecalc1 $ARG --median ${OUT}/ref.den ${OUT}/ref_med.den
dentk-framecalc $ARG --flipped-divide ${OUT}/img.den ${OUT}/ref_med.den ${OUT}/exp_ext_med.den
dentk-calc1 $ARG --log ${OUT}/exp_ext_med.den ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/IMG_bin ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/ref_avg.den ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/exp_ext_med.den ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/img.den ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/ref.den ${OUT}/ext.den
}


preprocessBinnedAnalysisMedianExt ${B2DIR} IMG_DC.den REF_DC.den 

function postprocess()
{
	IN=${1%.den}
	dentk-svd --force ${IN}.den ${IN}_s.den --vectorsV ${IN}_v.den
	dentk-framecalc1 --force --avg  ${IN}.den ${IN}_avg.den
	dentk-framecalc1 --force --standard-deviation  ${IN}.den ${IN}_sd.den
}

#postprocess ${OUT}/ext_avg.den
#postprocess ${OUT}/ref.den





















# binDenFile --force --median --bin-x 2 --bin-y 2 EXT.den ${B2DIR}/ext.den
