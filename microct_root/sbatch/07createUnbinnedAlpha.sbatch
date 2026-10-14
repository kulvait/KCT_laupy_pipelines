#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --chdir=/home/kulvaitv/gpfs_can_access/p05_2023_11017784Amber/scratch_cc/kulvait
#SBATCH --job-name=createUnbinnedAlpha
#SBATCH --output=log/createUnbinnedAlpha-%N-%j.out
#SBATCH --error=log/createUnbinnedAlpha-%N-%j.err
SCRIPTNAME=$(basename "$0")
echo "Executing $SCRIPTNAME $@"
source initGanrec
source sourcePath
cd $1
ARG="--force -j 10"
rm -f PRE_ALPHA_U.den ALPHA_U.den img_cor_sv BETA_U.den
dentk-alpha $ARG --frame-lower-quantile 0.9 ext.den PRE_ALPHA_U.den
dentk-framecalc1 --min PRE_ALPHA_U.den ALPHA_U.den
dentk-framecalc1 --sample-variance img_cor.den img_cor_sv
dentk-alpha $ARG --lower-quantile 0.2 img_cor_sv BETA_U.den
rm img_cor_sv PRE_ALPHA_U.den
