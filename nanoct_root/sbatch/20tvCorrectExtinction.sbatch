#!/bin/bash
#SBATCH --time=1-10:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=20tvCorrectExtinction
#SBATCH --output=log/20tvCorrectExtinction-%N-%j.out
#SBATCH --error=log/20tvCorrectExtinction-%N-%j.err
source initGanrec
source sourcePath
cd $1
echo "Processing $1"
unset LD_LIBRARY_PATH
estimateTVExtinctionEpsilon.py --verbose --force extb2/ext_avg.den extb2/ref_logepsilon_v.den extb2/ext_tv.den
