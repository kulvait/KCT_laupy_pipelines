#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=13svd
#SBATCH --output=log/13svd-%N-%j.out
#SBATCH --error=log/13svd-%N-%j.err
source initGanrec
source sourcePath
cd $1
rm -f ref_dc_s.den
rm -f ref_dc_v.den
dentk-svd --max_s_vals 100 extb2_curcor/ref.den extb2_curcor/ref_s.den --vectorsV extb2_curcor/ref_v.den
