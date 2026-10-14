#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=17removeJunkFiles
#SBATCH --output=log/17removeJunkFiles-%N-%j.out
#SBATCH --error=log/17removeJunkFiles-%N-%j.err
cd $1
echo "Processing $1"
#Here put files to remove
#rm -f extb2/ext_AVGEXT20.den
#rm -rf extb2/ref_fit
#rm -f extb2/img_avg.den
#rm -f extb2/img.den  
#rm -f extb2/ONE.den
#rm -f extb2/ref.den  
#rm -f extb2/bro_v20_0.0005.den
#rm -rf recb2_cgls_bro_v20_0.0005
#rm -rf recb2_cgls_bro_v20_0.0005_dir
#rm -rf recb2_cgls_bro_v20_0.0005_per
#rm -rf recb2_cgls_bro_v20_0.0005_neu
rm -rf tmp_*
rm -rf *.den
rm -rf raw_zarr
rm -rf raw_zarr.zip
rm -rf extb2
rm -rf recb2_cgls_ext_ref_v20
rm -f dump.rdb
if [ -f ext_rotationcenter180.log ]; then
	mv ext_rotationcenter180.log ext_rotationcenter180.log.old
fi
if [ -f ext_rotationcenter.log ]; then
	mv ext_rotationcenter.log ext_rotationcenter.log.old
fi
#rm -rf recb2_cgls_ext_ref_v20

