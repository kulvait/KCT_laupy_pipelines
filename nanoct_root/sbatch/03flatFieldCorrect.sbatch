#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --chdir=/home/kulvaitv/gpfs_can_access/p05_2023_11017784Amber/scratch_cc/kulvait
#SBATCH --job-name=flatFieldCorrect
#SBATCH --output=log/flatFieldCorrect-%N-%j.out
#SBATCH --error=log/flatFieldCorrect-%N-%j.err
source initGanrec
source sourcePath
#./reconstructSlice.py $1 --force --gpu --cgls --verbose --savetiff --output-folder $2
cd $1
03flatFieldCorrect DAR.den REF.den IMG.den tra.den ext.den
rm tra.den
