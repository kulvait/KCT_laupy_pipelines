#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --chdir=/home/kulvaitv/gpfs_can_access/p05_2023_11017784Amber/scratch_cc/kulvait
#SBATCH --job-name=darkFieldCorrect
#SBATCH --output=log/darkFieldCorrect-%N-%j.out
#SBATCH --error=log/darkFieldCorrect-%N-%j.err
source initGanrec
source sourcePath
cd $1
darkFieldCorrect DAR.den REF.den IMG.den ref_cor.den img_cor.den
rm DAR.den REF.den IMG.den
