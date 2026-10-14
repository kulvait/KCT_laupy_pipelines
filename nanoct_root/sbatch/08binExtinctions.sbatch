#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=08binExtinctions
#SBATCH --output=log/08binExtinctions-%N-%j.out
#SBATCH --error=log/08binExtinctions-%N-%j.err

# === Defaults ===
INFILE="ext.den"
OUTFILE="extb2/ext.den"
B2DIR=""         # will be parsed from OUTFILE later

usage() {
    echo "Usage: $scriptname [options] <WD>"
    echo ""
    echo "Options:"
    echo "  --in <file>                 Input file      (default: $INFILE)"
    echo "  --out <file>                Output file     (default: $OUTFILE)"
    echo ""
    echo "Arguments:"
    echo "  WD                          Working directory"
    exit 1
}

# === Parse command line arguments ===
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in

        --in)
            if [[ -z $2 || $2 =~ ^- ]]; then
                echo "Error: --in requires a file argument"
                usage
            fi
            INFILE="$2"
            shift 2
            ;;

        --out)
            if [[ -z $2 || $2 =~ ^- ]]; then
                echo "Error: --out requires a file argument"
                usage
            fi
            OUTFILE="$2"
            shift 2
            ;;

        -*)
            echo "Unknown option: $1"
            usage
            ;;

        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL_ARGS[@]} -ne 1 ]]; then
    echo "Error: Missing required argument <WD>"
    usage
fi

WD="${POSITIONAL_ARGS[0]}"



# === Now the modified beginning of your script ===

cd "$WD" || { echo "Cannot cd into $WD"; exit 1; }
echo "Processing $WD"

source initGanrec
source sourcePath

THREADS=$(nproc --all)
ARG="--force -j $THREADS"

if [[ ! -f ${INFILE} ]]; then
    FILEPATH=$(realpath ${INFILE})
	echo "File $INFILE with ${FILEPATH} does not exist, exiting!"
	exit -1
fi

# === Parse B2DIR from OUTFILE ===
OUTFILE=$(printf "%s" "$OUTFILE")   # strip weird characters

# Extract directory part of OUTFILE safely
B2DIR="$(dirname "$OUTFILE")"

# If directory part is "." then there is no directory to create
if [[ "$B2DIR" == "." ]]; then
    echo "No directory creation needed (path has no directory component)."
else
    if [[ -d "$B2DIR" ]]; then
        echo "Directory already exists: $B2DIR"
    else
        echo "Directory does not exist, creating: $B2DIR"
        mkdir -p "$B2DIR" || {
            echo "Failed to create directory: $B2DIR"
            exit 1
        }
        echo "Directory created: $B2DIR"
    fi
fi

removeIfExistsSecondFile()
{
	TOREMOVE=$1
	TOTEST=$2
	if [[ -f ${TOTEST} ]]; then
		rm -rf ${TOREMOVE}
	else
		echo "File $TOTEST does not exist, exiting!"
		exit -1
	fi
}

#Produces files  ${OUT}/ext_avg.den to be corrected and ${OUT}/ref_logepsilon_v.den to be used for TVFFC
preprocessBinnedAnalysisAvgExt()
{
OUT=${1}
IMG=${2%%.den}
REF=${3%%.den}

mkdir -p ${OUT}
binDenFile --force --median --bin-x 2 --bin-y 2 ${IMG}.den ${OUT}/IMG_bin
binDenFile --force --median --bin-x 2 --bin-y 2 ${REF}.den ${OUT}/REF_bin
dentk-calc1 $ARG --softplus ${OUT}/IMG_bin ${OUT}/img.den
removeIfExistsSecondFile ${OUT}/IMG_bin ${OUT}/img.den
dentk-calc1 $ARG --softplus ${OUT}/REF_bin ${OUT}/ref.den
removeIfExistsSecondFile ${OUT}/REF_bin ${OUT}/ref.den
dentk-framecalc1 $ARG --avg ${OUT}/ref.den ${OUT}/ref_avg.den
dentk-framecalc $ARG --divide ${OUT}/ref.den ${OUT}/ref_avg.den ${OUT}/ref_epsilon.den
dentk-calc1 $ARG --log ${OUT}/ref_epsilon.den ${OUT}/ref_logepsilon.den
removeIfExistsSecondFile ${OUT}/ref_epsilon.den ${OUT}/ref_logepsilon.den
dentk-svd ${OUT}/ref_logepsilon.den ${OUT}/ref_logepsilon_s.den --max_s_vals 100 --vectorsV ${OUT}/ref_logepsilon_v.den
dentk-framecalc $ARG --flipped-divide ${OUT}/img.den ${OUT}/ref_avg.den ${OUT}/exp_ext_avg.den
dentk-calc1 $ARG --log ${OUT}/exp_ext_avg.den ${OUT}/ext_avg.den
removeIfExistsSecondFile ${OUT}/exp_ext_avg.den ${OUT}/ext_avg.den
#Normally I would use median for these

#The following can be removed
#rm -f ${OUT}/img.den
#rm -f ${OUT}/img.den
#rm -f ${OUT}/ref_avg.den
#rm -f ${OUT}/ref_logepsilon.den

}

preprocessBinnedAnalysisMedianExt()
{
OUT=${1}
IMG=${2%%.den}
REF=${3%%.den}

mkdir -p ${OUT}
binDenFile --force --median --bin-x 2 --bin-y 2 ${IMG}.den ${OUT}/IMG_bin
binDenFile --force --median --bin-x 2 --bin-y 2 ${REF}.den ${OUT}/REF_bin
dentk-calc1 $ARG --softplus ${OUT}/IMG_bin ${OUT}/img.den
removeIfExistsSecondFile ${OUT}/IMG_bin ${OUT}/img.den
dentk-calc1 $ARG --softplus ${OUT}/REF_bin ${OUT}/ref.den
removeIfExistsSecondFile ${OUT}/REF_bin ${OUT}/ref.den
dentk-framecalc1 $ARG --median ${OUT}/ref.den ${OUT}/ref_med.den
dentk-framecalc $ARG --flipped-divide ${OUT}/img.den ${OUT}/ref_med.den ${OUT}/exp_ext_med.den
dentk-calc1 $ARG --log ${OUT}/exp_ext_med.den ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/IMG_bin ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/ref_avg.den ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/exp_ext_med.den ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/img.den ${OUT}/ext.den
removeIfExistsSecondFile ${OUT}/ref.den ${OUT}/ext.den
}



function postprocess()
{
	IN=${1%.den}
	dentk-svd --force ${IN}.den ${IN}_s.den --vectorsV ${IN}_v.den
	dentk-framecalc1 --force --avg  ${IN}.den ${IN}_avg.den
	dentk-framecalc1 --force --standard-deviation  ${IN}.den ${IN}_sd.den
}

#postprocess ${OUT}/ext_avg.den
#postprocess ${OUT}/ref.den

#preprocessBinnedAnalysisMedianExt ${B2DIR} IMG_DC.den REF_DC.den 

#Just bin ext_legacy.den without any further processing
#binDenFile --force --median --bin-x 2 --bin-y 2 ext_legacy.den ${B2DIR}/ext_legacy.den

binDenFile --force --median --bin-x 2 --bin-y 2 ${INFILE} ${OUTFILE}
