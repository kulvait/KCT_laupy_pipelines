#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=09darkFieldCorrect
#SBATCH --output=log/09darkFieldCorrect-%N-%j.out
#SBATCH --error=log/09darkFieldCorrect-%N-%j.err
source initGanrec
source sourcePath
cd $1
darkFieldCorrect DAR.den REF.den IMG.den ref_cor_df.den img_cor_df.den
rm DAR.den REF.den IMG.den
