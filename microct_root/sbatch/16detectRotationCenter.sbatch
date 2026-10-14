#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=16detectRotationCenter
#SBATCH --output=log/16detectRotationCenter-%N-%j.out
#SBATCH --error=log/16detectRotationCenter-%N-%j.err
source initGanrec
source sourcePath
cd $1
echo "Processing $1"
#detectRotationCenter.py --store-sinograms sinograms.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 1 --sinogram-consistency ext.den h5 --log-file rotationaxis_l1_sinogram.log
#Normally --override-magnification 9.951541635473134 would be omitted but here it applies
#to compute more metrics can be used the following
#detectRotationCenter.py ext.den h5 --force --override-magnification 9.951541635473134 --angle-count 1800 --load-sinograms sinograms.den --log-file rotationaxis_l1_svd.log --ord 1 --svd
detectRotationCenter.py --force --input-h5 h5 --store-sinograms sinogramsALPHA.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency ext_ALPHA.den --log-file rotationaxis_ALPHA_poisson.log
detectRotationCenter.py --force --input-h5 h5 --store-sinograms sinogramsBETA.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency ext_BETA.den --log-file rotationaxis_BETA_poisson.log
#detectRotationCenter.py --force --input-h5 h5 --store-sinograms sinogramsEXT.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency ext_dc.den --log-file rotationaxis_EXT_poisson.log

createSinograms.py --force --input-h5 h5 --override-magnification 9.951541635473134 --angle-count 0 --sample-count 1 ext_ALPHA.den ext_ALPHA_centersinogram.den
createSinograms.py --force --input-h5 h5 --override-magnification 9.951541635473134 --angle-count 0 --sample-count 1 ext_BETA.den ext_BETA_centersinogram.den
#createSinograms.py --force --input-h5 h5 --override-magnification 9.951541635473134 --angle-count 0 --sample-count 1 ext_dc.den ext_dc_centersinogram.den
