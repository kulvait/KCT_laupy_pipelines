#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=08detectNewCenter
#SBATCH --output=log/08detectNewCenter-%N-%j.out
#SBATCH --error=log/08detectNewCenter-%N-%j.err
source initGanrec
source sourcePath
cd $1
echo "Processing $1"
detectRotationCenterNew.py --force --input-h5 h5 --store-sinograms sinograms360_EXT.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency --log-file rotationaxis_EXT_360.log EXT.den
#detectRotationCenterNew.py --force --input-h5 h5 --store-sinograms EXT_sinogram.den --angle-count 1800 --ord 0 --sinogram-consistency ext_dc.den
#Normally --override-magnification 9.951541635473134 would be omitted but here it applies
#to compute more metrics can be used the following
#detectRotationCenter.py ext.den h5 --force --override-magnification 9.951541635473134 --angle-count 1800 --load-sinograms sinograms.den --log-file rotationaxis_l1_svd.log --ord 1 --svd
#detectRotationCenter.py --force --input-h5 h5 --store-sinograms sinogramsALPHA.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency ext_ALPHA.den --log-file rotationaxis_ALPHA_poisson.log
#detectRotationCenter.py --force --input-h5 h5 --store-sinograms sinogramsBETA.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency ext_BETA.den --log-file rotationaxis_BETA_poisson.log
#detectRotationCenter.py --force --input-h5 h5 --store-sinograms sinogramsEXT.den --override-magnification 9.951541635473134 --angle-count 1800 --ord 0 --sinogram-consistency ext_dc.den --log-file rotationaxis_EXT_poisson.log

#createSinograms.py --force --input-h5 h5 --angle-count 0 --sample-count 5 --store-sinograms EXT_sinogram5.den EXT.den
#createSinograms.py --force --input-h5 h5 --override-magnification 9.951541635473134 --angle-count 0 --sample-count 1 ext_BETA.den ext_BETA_centersinogram.den
#createSinograms.py --force --input-h5 h5 --override-magnification 9.951541635473134 --angle-count 0 --sample-count 1 ext_dc.den ext_dc_centersinogram.den
