#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=21updateRotationCenter
#SBATCH --output=log/21updateRotationCenter-%N-%j.out
#SBATCH --error=log/21updateRotationCenter-%N-%j.err
source initGanrec
source sourcePath
cd $1
echo "Processing $1"
#detectRotationCenter.py --store-sinograms sinograms.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 1 --sinogram-consistency ext.den h5 --log-file rotationaxis_l1_sinogram.log
#Normally --override-magnification 9.951541635473134 would be omitted but here it applies
#to compute more metrics can be used the following
#detectRotationCenter.py ext.den h5 --force --override-magnification 9.951541635473134 --angle-count 1800 --load-sinograms sinograms.den --log-file rotationaxis_l1_svd.log --ord 1 --svd
detectRotationCenter.py --force --input-h5 h5 --load-sinograms sinogramsALPHA.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency img_dc.den --log-file rotationaxis_ALPHA_poisson.log
detectRotationCenter.py --force --input-h5 h5 --load-sinograms sinogramsBETA.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency img_dc.den --log-file rotationaxis_BETA_poisson.log
detectRotationCenter.py --force --input-h5 h5 --load-sinograms sinogramsEXT.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency img_dc.den --log-file rotationaxis_EXT_poisson.log
