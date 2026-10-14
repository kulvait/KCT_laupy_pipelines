#!/bin/bash
#SBATCH --time=0-23:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/43SVD-%N-%j.out
#SBATCH --error=log/43SVD-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Arguments
WD=""
#For reference these were choices of the FITBASIS
FITBASIS="extb2/ref_rsvd_v.den"
FITBASIS="extb2/ref_centered_rsvd_v_with_avg.den"
FITBASIS="extb2/ref_centered_v_with_avg.den"
FITBASIS=""
FITCOUNT=20

# Function to print usage and exit
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} <WD> <OGBASIS>

Arguments:
   --fit-count <N>              Number of basis vectors to fit (default: 20)

Positional arguments:
  WD                          Working directory
  FITBASIS                    Basis vectors to fit, commonly the V matrix from SVD of the flat fields. This should be a .den file containing orthonormal basis vectors as projection frames.
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
		--fit-count)
	    if [[ -n "$2" && "$2" != --* ]]; then
			FITCOUNT="$2"
			shift 2
	    else
			echo "Error: --fit-count requires a value" >&2
			usage error
			exit 1
	    fi
	    ;;
        -h|--help)
	    	usage help
	    	exit 0
	    ;;
        *)
            if [[ -z "$WD" ]]; then
                WD="$1"
			elif [[ -z "$FITBASIS" ]]; then
				FITBASIS="$1"
            else
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done

# Validate positional arguments
if [[ -z "$WD" ]] || [[ -z "$FITBASIS" ]]; then
    usage error
    exit 1
fi

# Ensure WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

cd "$WD"

if [ ! -f "$FITBASIS" ]; then
    echo "Error: FITBASIS file $FITBASIS does not exist" >&2
    exit 1
fi

unset LD_PRELOAD
source initGanrec

THREADS=$(nproc --all)
ARG="--force -j $THREADS"
#dentk-svd ref_cor.den ref_cor_s.den --vectorsV ref_cor_v.den

function createFlatFields()
{
	set -x
	local FILE=$1
	local ALPHA=$2
	local FFVSVD=$3
	local OUTFF=$4
	local TMP=$(mktemp -d -p . "tmp_43SVD_XXXXX")
	rm -f ${OUTFF}
	local ENDFIT=$(calc "$FITCOUNT - 1")
	dentk-framecalc $ARG --frames 0-$ENDFIT --multiply $FFVSVD $ALPHA ${TMP}/V_ALPHA.den
	dentk-frameproduct $ARG --a-count ${FITCOUNT} --b-count ${FITCOUNT} ${TMP}/V_ALPHA.den ${TMP}/V_ALPHA.den ${TMP}/VPRODUCT_ALPHA.den
	#VPRODUCT_ALPHA.den is of dimensions FITCOUNT x FITCOUNT
	invertMatrix.py --force ${TMP}/VPRODUCT_ALPHA.den ${TMP}/INVPRODUCT_ALPHA.den
	#INVPRODUCT_ALPHA.den is of dimensions FITCOUNT x FITCOUNT
	dentk-frameproduct $ARG --b-count ${FITCOUNT} ${FILE} ${TMP}/V_ALPHA.den ${TMP}/IPRODUCT_ALPHA.den
	#FIT_ALPHA.den, IPRODUCT_ALPHA.den columns=xdim=PRJCOUNT, rows=ydim=FITCOUNT  
	matrixMultiplication.py ${TMP}/INVPRODUCT_ALPHA.den ${TMP}/IPRODUCT_ALPHA.den ${TMP}/FIT_ALPHA.den
	synthetizeFlatFields.py ${FFVSVD} ${TMP}/FIT_ALPHA.den ${OUTFF}
	set +x
	if [[ -f ${OUTFF} ]]; then
		rm -rf ${TMP}
	else
		echo "Failed to create ${OUTFF}"
		exit 1
	fi
}

function subtractCorrection()
{
	local FILE=$1
	local SUB=$2
	local OUT=$3
	if [[ ! -f $FILE || ! -f $SUB ]]; then
		echo "Error Subtracting Missing file $FILE or $SUB"
		exit 1
	fi
	rm -f $OUT
	local THREADS=$(nproc --all)
	local ARG="--force -j $THREADS"
	dentk-calc $ARG --subtract $FILE $SUB $OUT
}

function divideCorrection()
{
	local FILE=$1
	local DIV=$2
	local OUT=$3
	if [[ ! -f ${FILE} ]]; then
		echo "Error dividing: Missing file $FILE"
		exit 1
	fi
	if [[ ! -f ${DIV} ]]; then
		echo "Error dividing: Missing file $DIV"
		exit 1
	fi
	rm -f ${OUT}
	local TMP=$(mktemp -d -p . "tmp_33SVDFFNonlinear_XXXXX")
	local THREADS=$(nproc --all)
	local ARG="--force -j $THREADS"
	dentk-calc $ARG --divide $FILE $DIV ${TMP}/fraction.den
	dentk-calc1 $ARG --log ${TMP}/fraction.den $OUT
	rm -f ${TMP}/fraction.den
	rmdir ${TMP}
}

function log()
{
	local FILE=$1
	local OUT=$2
	if [[ ! -f $OUT ]]; then
		dentk-calc1 $ARG --log $FILE $OUT
	else
		echo "File $OUT already exists"
	fi
}

function svd()
{
	local FILE=$1
	local V=$2
	local S=$3
	if [[ ! -f $V || ! -f $S ]]; then
		dentk-svd --force $FILE $S --vectorsV $V
	else
		echo "Files $V or $S already exist"
	fi
}

function fitAndDivide()
{
	local FILE=$1
	local REF=$2
	local ALPHA=$3
	local FITCOUNT=$4
	local OUTCOR=$5
	local SCALE=$6
	if [[ ! -f $FILE || ! -f $REF || ! -f $ALPHA ]]; then
		echo "Error fitting Missing file $FILE or $REF or $ALPHA"
		exit 1
	fi
	FILE=$(realpath $FILE)
	local FILEDIR=$(dirname $FILE)
	FITDIR=${FILEDIR}/ref_fit
	ALPHANAME=$(basename $ALPHA)
	ALPHANAME=${ALPHANAME%.*}
	REFNAME=$(basename $REF)
	REFNAME=${REFNAME%.*}
	mkdir -p ${FITDIR}
	local OUTREF=${FITDIR}/${REFNAME}_${FITCOUNT}_${ALPHANAME}_l1_div.den
	rm -f ${OUTREF} ${OUTCOR}
	if [[ -n $SCALE ]]; then
		local ARG="--scale-basis $SCALE"
	else
		local ARG=""
	fi
	nonlinearBasisWithSlopeFit_div.py --force $ARG $FILE $REF $OUTREF --alpha $ALPHA --basis-size ${FITCOUNT}  --l1 --verbose --lbfgs
	divideCorrection $OUTREF $FILE $OUTCOR
	rm -f ${OUTREF}
}

function fitOnesAndDivide()
{
	local FILE=$1
	local REF=$2
	local ALPHA=$3
	local FITCOUNT=$4
	local OUTCOR=$5
	local SCALE=$6
	if [[ ! -f $FILE || ! -f $REF || ! -f $ALPHA ]]; then
		echo "Error fitting Missing file $FILE or $REF or $ALPHA"
		exit 1
	fi
	FILE=$(realpath $FILE)
	local FILEDIR=$(dirname $FILE)
	FITDIR=${FILEDIR}/ref_fit
	ALPHANAME=$(basename $ALPHA)
	ALPHANAME=${ALPHANAME%.*}
	REFNAME=$(basename $REF)
	REFNAME=${REFNAME%.*}
	mkdir -p ${FITDIR}
	local OUTREF=${FITDIR}/${REFNAME}_${FITCOUNT}_${ALPHANAME}_onesl1_div.den
	rm -f ${OUTREF} ${OUTCOR}
	if [[ -n $SCALE ]]; then
		local ARG="--scale-basis $SCALE"
	else
		local ARG=""
	fi
#I have to create artificial vector of ones
	local DIMX=$(dentk-info --dim $FILE  | cut -f1)
	local DIMY=$(dentk-info --dim $FILE  | cut -f2)
	local TMP=$(mktemp -d -p . "tmp_32SVDFlatFields_XXXXX")
	dentk-empty --value 1 --force $DIMX $DIMY 1 ${TMP}/ones.den
	dentk-merge --force ${TMP}/ones_ref.den $TMP/ones.den $REF
	local FITCOUNTINC=$(calc "$FITCOUNT + 1")
	nonlinearBasisWithSlopeFit_div.py --force $ARG $FILE ${TMP}/ones_ref.den $OUTREF --alpha $ALPHA --basis-size ${FITCOUNTINC}  --l1 --verbose --lbfgs
	divideCorrection $OUTREF $FILE $OUTCOR
	#rm -f ${OUTREF}
}


function fitSlopeAndDivide()
{
	local FILE=$1
	local REF=$2
	local ALPHA=$3
	local FITCOUNT=$4
	local OUTCOR=$5
	local SCALE=$6
	if [[ ! -f $FILE || ! -f $REF || ! -f $ALPHA ]]; then
		echo "Error fitting Missing file $FILE or $REF or $ALPHA"
		exit 1
	fi
	FILE=$(realpath $FILE)
	local FILEDIR=$(dirname $FILE)
	FITDIR=${FILEDIR}/ref_fit
	ALPHANAME=$(basename $ALPHA)
	ALPHANAME=${ALPHANAME%.*}
	REFNAME=$(basename $REF)
	REFNAME=${REFNAME%.*}
	mkdir -p ${FITDIR}
	local OUTREF=${FITDIR}/${REFNAME}_${FITCOUNT}_${ALPHANAME}_slopel1_div.den
	rm -f ${OUTREF} ${OUTCOR}
	if [[ -n $SCALE ]]; then
		local ARG="--scale-basis $SCALE"
	else
		local ARG=""
	fi
	nonlinearBasisWithSlopeFit_div.py --force $ARG $FILE $REF $OUTREF --alpha $ALPHA --basis-size ${FITCOUNT}  --l1 --verbose --fit-slope --lbfgs
	divideCorrection $OUTREF $FILE $OUTCOR
	rm -f ${OUTREF}
}

function fitTVSlopeAndDivide()
{
	local FILE=$1
	local REF=$2
	local ALPHA=$3
	local FITCOUNT=$4
	local OUTCOR=$5
	local SCALE=$6
	if [[ ! -f $FILE || ! -f $REF || ! -f $ALPHA ]]; then
		echo "Error fitting Missing file $FILE or $REF or $ALPHA"
		exit 1
	fi
	FILE=$(realpath $FILE)
	local FILEDIR=$(dirname $FILE)
	FITDIR=${FILEDIR}/ref_fit
	ALPHANAME=$(basename $ALPHA)
	ALPHANAME=${ALPHANAME%.*}
	REFNAME=$(basename $REF)
	REFNAME=${REFNAME%.*}
	mkdir -p ${FITDIR}
	local OUTREF=${FITDIR}/${REFNAME}_${FITCOUNT}_${ALPHANAME}_slopetv.den
	rm -f ${OUTREF} ${OUTCOR}
	if [[ -n $SCALE ]]; then
		local ARG="--scale-basis $SCALE"
	else
		local ARG=""
	fi
	nonlinearBasisWithSlopeFit_div.py --force $ARG $FILE $REF $OUTREF --alpha $ALPHA --basis-size ${FITCOUNT}  --tv --verbose --fit-slope --lbfgs
	divideCorrection $OUTREF $FILE $OUTCOR
}

function alphaGammaFit()
{
	local IMGIN=$1
	local REFSVDV=$2
	local ALPHA=$3
	local GAMMA=$4
	local FITCOUNT=$5
	local OUTCOR=$6
	local ONES=$7
	local SCALE=$8
	if [[ ! -f $IMGIN || ! -f $REFSVDV || ! -f $ALPHA || ! -f $GAMMA ]]; then
		echo "Error fitting Missing file $IMGIN or $REFSVDV or $ALPHA or $GAMMA"
		exit 1
	fi
	local IMGIN=$(realpath $IMGIN)
	local IMGINDIR=$(dirname $IMGIN)
	local FITDIR=${IMGINDIR}/ref_fit
	local ALPHANAME=$(basename $ALPHA)
	local ALPHANAME=${ALPHANAME%.*}
	local GAMMANAME=$(basename $GAMMA)
	local GAMMANAME=${GAMMANAME%.*}
	local REFSVDVNAME=$(basename $REFSVDV)
	local REFSVDVNAME=${REFSVDVNAME%.*}
	mkdir -p ${FITDIR}
	local OUTREF=${FITDIR}/${REFSVDVNAME}_${FITCOUNT}_${ALPHANAME}_${GAMMANAME}.den
	local OUTTRA=${FITDIR}/TRAX_${REFSVDVNAME}_${FITCOUNT}_${ALPHANAME}_${GAMMANAME}.den
	local OUTEXT=${FITDIR}/EXTX_${REFSVDVNAME}_${FITCOUNT}_${ALPHANAME}_${GAMMANAME}.den
	rm -f ${OUTREF} ${OUTCOR}
	if [[ -n $SCALE ]]; then
		local ARG="--scale-basis $SCALE"
	else
		local ARG=""
	fi
	local TMP=$(mktemp -d -p . "tmp_AGC_XXXXX")
	echo "Created temporary directory ${TMP}"
	if [[ ${ONES} == true ]]; then
		local DIMX=$(dentk-info --dim $IMGIN  | cut -f1)
		local DIMY=$(dentk-info --dim $IMGIN  | cut -f2)
		local value=$(calc "1/sqrt($DIMX*$DIMY)")
		local FITMAX=$(calc "$FITCOUNT - 1")
		dentk-cat -f 0-$FITMAX $REFSVDV ${TMP}/ref.den
		dentk-empty --value $value --force $DIMX $DIMY 1 ${TMP}/ones.den
		dentk-merge --force ${TMP}/ones_ref.den ${TMP}/ref.den $TMP/ones.den
		local FITCOUNT=$(calc "$FITCOUNT + 1")
		local FITVEC=${TMP}/ones_ref.den
	else
		local FITVEC=${REFSVDV}
	fi

	alphaGammaFitSimplify.py --force $ARG $IMGIN $FITVEC $OUTREF --alpha $ALPHA --gamma $GAMMA --basis-size ${FITCOUNT}  --l1 --verbose --lbfgs --report-transmission ${OUTTRA} --report-extinction ${OUTEXT} --fit-slope
	divideCorrection $OUTREF $IMGIN $OUTCOR
	rm -f ${TMP}
}

function l2ofaverage()
{
	DENIN=$1
	local TMP=$(mktemp -d -p . "tmp_AVG_XXXXX")
	if [[ ! -f $DENIN ]]; then
		echo "Error calculating L2 norm: Missing file $DENIN"
		exit 1
	fi
	dentk-framecalc1 --avg $DENIN ${TMP}/avg.den &> /dev/null
    # Extract L2 norm using dentk-info
    local L2=$(dentk-info --l2norm ${TMP}/avg.den | grep -oP 'Global l2 norm is \K[0-9.]+')
    
    if [[ -z $L2 ]]; then
        echo "Error: Could not extract L2 norm."
        exit 1
    fi
	rm -rf ${TMP}
    # Print the L2 norm with 6 decimal places precision
    printf "%.6f\n" $L2
}

function alphaGammaFitToAverage()
{
	local IMGIN=$1
	local REFSVDV=$2
	local ALPHA=$3
	local GAMMA=$4
	local FITCOUNT=$5
	local OUTCOR=$6
	local ONES=$7
	local FITEXT=$8
	local L2NORM=${9:-1.0}
	local SCALE=${10:-}
    # Check if L2NORM is a valid float
    if [[ ! "$L2NORM" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Error: Invalid L2NORM value '$L2NORM'. Must be a valid float."
        exit 1
    fi
	if [[ ! -f $IMGIN || ! -f $REFSVDV || ! -f $ALPHA || ! -f $GAMMA ]]; then
		echo "Error fitting Missing file $IMGIN or $REFSVDV or $ALPHA or $GAMMA"
		exit 1
	fi
	local IMGIN=$(realpath $IMGIN)
	local IMGINDIR=$(dirname $IMGIN)
	local FITDIR=${IMGINDIR}/ref_fit
	local ALPHANAME=$(basename $ALPHA)
	local ALPHANAME=${ALPHANAME%.*}
	local GAMMANAME=$(basename $GAMMA)
	local GAMMANAME=${GAMMANAME%.*}
	local REFSVDVNAME=$(basename $REFSVDV)
	local REFSVDVNAME=${REFSVDVNAME%.*}
	local FITEXTNAME=$(basename $FITEXT)
	local FITEXTNAME=${FITEXTNAME%.*}
	mkdir -p ${FITDIR}
	local OUTREF=${FITDIR}/${REFSVDVNAME}_${FITCOUNT}_${ALPHANAME}_${GAMMANAME}_${FITEXTNAME}.den
	local OUTTRA=${FITDIR}/TRA_${REFSVDVNAME}_${FITCOUNT}_${ALPHANAME}_${GAMMANAME}_${FITEXTNAME}.den
	local OUTEXT=${FITDIR}/EXT_${REFSVDVNAME}_${FITCOUNT}_${ALPHANAME}_${GAMMANAME}_${FITEXTNAME}.den
	local OUTFIRSTEXT=${FITDIR}/EXT_FIRST_${REFSVDVNAME}_${FITCOUNT}_${ALPHANAME}_${GAMMANAME}_${FITEXTNAME}.den
	local FITCOUNTORIG=$FITCOUNT
	rm -f ${OUTREF} ${OUTCOR}
	if [[ -n $SCALE ]]; then
		local ARG="--scale-basis $SCALE"
	else
		local ARG=""
	fi
	local TMP=$(mktemp -d -p . "tmp_AGC_XXXXX")
	echo "Created temporary directory ${TMP}"
	if [[ ${ONES} == true ]]; then
		local DIMX=$(dentk-info --dim $IMGIN  | cut -f1)
		local DIMY=$(dentk-info --dim $IMGIN  | cut -f2)
		local value=$(calc "1/sqrt($DIMX*$DIMY)")
		local FITMAX=$(calc "$FITCOUNT - 1")
		dentk-cat -f 0-$FITMAX $REFSVDV ${TMP}/ref.den
		dentk-empty --value $value --force $DIMX $DIMY 1 ${TMP}/ones.den
		dentk-merge --force ${TMP}/ones_ref.den ${TMP}/ref.den $TMP/ones.den
#		echo dentk-orthogonalize --force ${TMP}/ones_ref.den ${TMP}/ones_ref_og.den
#		dentk-orthogonalize --force ${TMP}/ones_ref.den ${TMP}/ones_ref_og.den
		local FITCOUNT=$(calc "$FITCOUNT + 1")
		local FITVEC=${TMP}/ones_ref.den
	else
		local FITVEC=${REFSVDV}
	fi

	REPORTARGS="--report-transmission ${OUTTRA} --report-extinction ${OUTEXT} --report-first-extinction ${OUTFIRSTEXT} --verbose"
	RELEASE=false
	if [[ ${RELEASE} == true ]]; then
		REPORTARGS=""
	fi
	alphaGammaFitSimplifyParalelizeNew.py --force $ARG $IMGIN $FITVEC $OUTREF --alpha $ALPHA --gamma $GAMMA --basis-size ${FITCOUNT} --target-l2 $L2NORM --tv --lbfgs --first-fit ${FITEXT} --first-fit-size ${FITCOUNTORIG} ${REPORTARGS}
	divideCorrection $OUTREF $IMGIN $OUTCOR
	rm -fr ${TMP}
}

#For division
#createFlatFields extb2/img.den extb2/ALPHA.den extb2/ref_v.den extb2/ref_alpha.den
#dentk-framecalc1 $ARG --avg extb2/img.den extb2/img_avg.den

#fitAndDivide extb2/img.den extb2/ref_v.den extb2/ALPHA.den ${FITCOUNT} extb2/ext_s1alpha.den
#fitAndDivide extb2/img.den extb2/ref_v.den extb2/BETA.den ${FITCOUNT} extb2/ext_s1beta.den
#fitAndDivide extb2/img.den extb2/ref_v.den extb2/GAMMA.den ${FITCOUNT} extb2/ext_s1gamma.den
#fitSlopeAndDivide extb2/img.den extb2/ref_v.den extb2/ALPHA.den ${FITCOUNT} extb2/ext_s1slopealpha.den
#fitSlopeAndDivide extb2/img.den extb2/ref_v.den extb2/BETA.den ${FITCOUNT} extb2/ext_s1slopebeta.den
#fitSlopeAndDivide extb2/img.den extb2/ref_v.den extb2/GAMMA.den ${FITCOUNT} extb2/ext_s1slopegamma.den
#fitOnesAndDivide extb2/img.den extb2/ref_v.den extb2/ALPHA.den ${FITCOUNT} extb2/ext_s${FITCOUNT}onesalpha.den
#fitOnesAndDivide extb2/img.den extb2/ref_v.den extb2/BETA.den ${FITCOUNT} extb2/ext_s{FITCOUNT}onesbeta.den
#fitOnesAndDivide extb2/img.den extb2/ref_v.den extb2/GAMMA.den ${FITCOUNT} extb2/ext_s{FITCOUNT}onesgamma.den

ONES=false
#alphaGammaFit extb2/img.den extb2/ref_v.den extb2/ALPHA.den extb2/GAMMA.den ${FITCOUNT} extb2/ext_ref_v${FITCOUNT}_ALPHA_GAMMA.den ${ONES}
#alphaGammaFitToAverage extb2/img.den extb2/ref_v.den extb2/ALPHA5.den extb2/GAMMA.den ${FITCOUNT} extb2/ext_ref_v${FITCOUNT}_ALPHA5_GAMMAMED_SLOONE.den ${ONES} extb2/img_avg.den
#
ONES=false
L2NORM=$(l2ofaverage extb2/ref.den)


echo "L2 norm of average is ${L2NORM}"
ONEMASK="extb2/ONE.den"
GAMMAMASK="extb2/GAMMA.den"
if [[ ! -f ${GAMMAMASK} ]]; then
	dentk-alpha --upper-quantile 0.9 --force extb2/img_avg.den ${GAMMAMASK}
fi
#if [[ ! -f ${GAMMAMASK} ]]; then
#    GAMMAMASK=$ONEMASK
#fi

FITBASISNAME=$(basename $FITBASIS)
FITBASISNAME=${FITBASISNAME%.*}
FITBASISPATH=$(dirname $FITBASIS)

OUT="${FITBASISPATH}/ext_${FITBASISNAME}_v${FITCOUNT}.den"
# Run the command and capture the output into a variable
dims=$(dentk-info --dim $FITBASIS)
# Parse the output into dimx, dimy, and dimz
IFS=$'\t' read -r dimx dimy dimz <<< "$dims"
dentk-empty --value 1 --force $dimx $dimy 1 ${ONEMASK}
alphaGammaFitToAverage extb2/img.den ${FITBASIS} ${ONEMASK} ${GAMMAMASK} ${FITCOUNT} ${OUT} ${ONES} extb2/ONE.den ${L2NORM}

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
