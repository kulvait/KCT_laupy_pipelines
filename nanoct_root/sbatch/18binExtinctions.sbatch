#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=18binExtinctions
#SBATCH --output=log/18binExtinctions-%N-%j.out
#SBATCH --error=log/18binExtinctions-%N-%j.err
cd $1
echo "Processing $1"
source initGanrec
source sourcePath
cd $1
THREADS=$(nproc --all)
ARG="--force -j $THREADS"

function binExtinctions()
{
if [[ ! -f $1 ]]; then
    echo "File $1 does not exist."
else
    echo "START $1 bin."
	rm -f ${1}_bin
	binDenFile --force --median --bin-x 2 --bin-y 2 ${1} ${1}_bin
	mv ${1}_bin ${2}
	rm ${1}	
    echo "END $1 destar."
fi
}

mkdir -p extb2
#binExtinctions ext_dc.den extb2/ext.den
#binExtinctions ext_ALPHA.den extb2/ext_AVGEXT20.den
#binExtinctions ext_BETA.den extb2/ext_VARIMG20.den
binExtinctions ext_ALPHA.den extb2/ext_ALPHA.den
binExtinctions ext_BETA.den extb2/ext_BETA.den
