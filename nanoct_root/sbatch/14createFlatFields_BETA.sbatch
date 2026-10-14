#!/bin/bash
#SBATCH --time=2-12:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=14createFlatFields
#SBATCH --output=log/14createFlatFields-%N-%j.out
#SBATCH --error=log/14createFlatFields-%N-%j.err
SCRIPTNAME=$(basename "$0")
echo "Executing $SCRIPTNAME $@"

source initGanrec
source sourcePath
cd $1
THREADS=$(nproc --all)
ARG="--force -j $THREADS"
#dentk-svd ref_cor.den ref_cor_s.den --vectorsV ref_cor_v.den
rm -f VPRODUCT_ALPHA.den VPRODUCT_BETA.den IPRODUCT_ALPHA.den IPRODUCT_BETA.den FIT_ALPHA.den FIT_BETA.den INVPRODUCT_ALPHA.den INVPRODUCT_BETA.den


createFlatField() {
IMG=${1%%.den}
SVD=${2%%.den}
ALPHA=${3%%.den}
OUT=$4
VECCOUNT=$5
VALPHA=${SVD}_times_${ALPHA}
ALPHAPRODUCT=${VALPHA}_product
INVALPHAPRODUCT=${VALPHA}_invproduct
VALPHAPRODUCTIMG=${VALPHA}_product_${IMG}
ALPHAFIT=${ALPHA}_FIT
rm -f ${VALPHA}
rm -f ${ALPHAPRODUCT}
rm -f ${INVALPHAPRODUCT}
rm -f ${VALPHAPRODUCTIMG}
rm -f ${ALPHAFIT}
rm -f ${OUT}
dentk-framecalc $ARG --multiply ${SVD}.den ${ALPHA}.den ${VALPHA}
createProductMatrix.py --verbose --count-left ${VECCOUNT} --count-right ${VECCOUNT}  --inverse ${INVALPHAPRODUCT} ${VALPHA} ${VALPHA} ${ALPHAPRODUCT}
createProductMatrix.py --verbose --count-left ${VECCOUNT} ${VALPHA} ${IMG}.den ${VALPHAPRODUCTIMG}
matrixMultiplication.py ${INVALPHAPRODUCT} ${VALPHAPRODUCTIMG} ${ALPHAFIT}.den
synthetizeFlatFields.py ${SVD}.den ${ALPHAFIT}.den $OUT
rm -f ${VALPHA}
rm -f ${ALPHAPRODUCT}
rm -f ${INVALPHAPRODUCT}
rm -f ${VALPHAPRODUCTIMG}
#rm -f ${ALPHAFIT}.den
}

createFlatField img_dc.den ref_dc_v.den BETA.den FF_BETA.den 30
