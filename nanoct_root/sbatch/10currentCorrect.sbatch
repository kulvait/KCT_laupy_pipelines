#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=10currentCorrect
#SBATCH --output=log/10currentCorrect-%N-%j.out
#SBATCH --error=log/10currentCorrect-%N-%j.err
source initGanrec
cd $1
mkdir -p out
currentCorrect.py --type IMG h5 img_cor_df.den img_dc.den --saveinfo out/inf_img_dc.den --savefig out/inf_img_dc.pdf
currentCorrect.py --type REF h5 ref_cor_df.den ref_dc.den --saveinfo out/inf_ref_dc.den --savefig out/inf_ref_dc.pdf
rm -f img_cor_df.den ref_cor_df.den
