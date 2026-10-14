#!/bin/bash
#SBATCH --time=0-23:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=09preprocessAdvancedFFC
#SBATCH --output=log/09preprocessAdvancedFFC-%N-%j.out
#SBATCH --error=log/09preprocessAdvancedFFC-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Arguments
WD=""
INPUT_REF="ref_clean_darksub_curcor.den"
INPUT_IMG="img_clean_darksub_curcor.den"
BINNING_FACTOR=2
OUTPUT_DIR=""   # <-- empty means "not user-specified"
OUTPUT_SUFFIX=""

# Function to print usage and exit
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD>

Options:
  --input-ref FILE            Path to reference input file (default: ref_clean_darksub_curcor.den)
  --input-img FILE            Path to image input file (default: img_clean_darksub_curcor.den)
  --binning-factor FACTOR     Binning factor (default: 2)
  --output-dir DIR            Output directory (default: extb{binning-factor})
  --output-suffix SUFFIX      Suffix to append to output files (default: "")
  --h, --help                 Show this help message and exit.

Positional Arguments:
  WD                          Working directory
EOF
}


# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input-ref)
            INPUT_REF="$2"
            shift 2
            ;;
        --input-img)
            INPUT_IMG="$2"
            shift 2
            ;;
        --binning-factor)
            BINNING_FACTOR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --output-suffix)
	        OUTPUT_SUFFIX="$2"
	        shift 2
	        ;;
		--h|--help)
	    	usage help
	    	exit 0
	    	;;
        *)
            if [[ -z "$WD" ]]; then
                WD="$1"
            else
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done

# Validate positional argument
if [[ -z "$WD" ]]; then
    usage error
	exit 1
fi

# Ensure WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

unset LD_PRELOAD
source initGanrec
# Initialize environment and cd into WD
cd "$WD"

if ! [[ "$BINNING_FACTOR" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: binning factor must be a positive integer" >&2
    exit 1
fi

# If output directory was not explicitly specified, derive from binning factor
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="extb${BINNING_FACTOR}"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "START 09preprocessAdvancedFFC.sbatch"

#Produces files  ${OUT}/ext_avg.den to be corrected and ${OUT}/ref_logepsilon_v.den to be used for TVFFC
function computeAvgExtinction()
{
	local FLAT_IN="$1"
	local IMG_IN="$2"
	local EXT_OUT="$3"
    local PHASECONTRAST="${4:-false}"  # Default to false if not provided

	 # Base names only for temp file naming (no path, no extension)
	local FLAT_BASE=$(basename "${FLAT_IN}" .den)
	local IMG_BASE=$(basename "${IMG_IN}" .den)
	# Create a unique temporary directory in the current working directory
	local TMPDIR=$(mktemp -d -p . "tmp_09preprocessAdvancedFFC_XXXXXX")
    trap 'rm -rf "$TMPDIR"' RETURN
	# Check if the directory was created successfully
	if [ ! -d "$TMPDIR" ]; then
    	echo "Failed to create temporary directory."
    	exit 1
	fi
	dentk-framecalc1 --avg "${FLAT_IN}" "${TMPDIR}/${FLAT_BASE}_avg"
	#Calculate double softplus of average flatfield to make it positive
	dentk-calc1 --double-softplus "${TMPDIR}/${FLAT_BASE}_avg" "${TMPDIR}/${FLAT_BASE}_cor"
	#Calculate double softplus of average img data to make it positive
	dentk-calc1 --double-softplus "${IMG_IN}" "${TMPDIR}/${IMG_BASE}_softplus"
	if [ "$PHASECONTRAST" = true ]; then
		mv "${TMPDIR}/${IMG_BASE}_softplus" "${TMPDIR}/${IMG_BASE}_cor"
	else
	    #START does not apply for phase contrast
	    dentk-framecalc --min "${TMPDIR}/${IMG_BASE}_softplus" "${TMPDIR}/${FLAT_BASE}_cor" "${TMPDIR}/${IMG_BASE}_cor"
	    #END does not apply for phase contrast
	fi
	dentk-framecalc --flipped-divide "${TMPDIR}/${IMG_BASE}_cor" "${TMPDIR}/${FLAT_BASE}_cor" "${TMPDIR}/tra_inv"
	dentk-calc1 --log "${TMPDIR}/tra_inv" "${EXT_OUT}"
}

#B2DIR=extb2_curcor
#mkdir -p $B2DIR
#binDenFile --force --median --bin-x 2 --bin-y 2 ref_clean_darksub_curcor.den ${B2DIR}/ref.den
#binDenFile --force --median --bin-x 2 --bin-y 2 img_clean_darksub_curcor.den ${B2DIR}/img.den
##Create img_avg.den
#dentk-framecalc1 --force --avg ${B2DIR}/img.den ${B2DIR}/img_avg.den
##Create SVD of first 100 components of ${B2DIR}/ref.den
#dentk-svd --force ${B2DIR}/ref.den ${B2DIR}/ref_s.den --max_s_vals 100 --vectorsV ${B2DIR}/ref_v_orig.den
#normalizeSingularVectors.py --force ${B2DIR}/ref_v_orig.den ${B2DIR}/ref_v.den
#rm -f ${B2DIR}/ref_v_orig.den
##Create RSVD basis
#dentk-rsvd.py --max-s-vals 100 --vectorsV ${B2DIR}/ref_v.den ${B2DIR}/ref.den ${B2DIR}/ref_rsvd_v.den
#dentk-orthogonalize --force ${B2DIR}/ref_rsvd_v.den ${B2DIR}/ref_rsvd_v_og.den
#rm -f ${B2DIR}/ref_rsvd_v.den
#normalizeSingularVectors.py --force ${B2DIR}/ref_rsvd_v_og.den ${B2DIR}/ref_rsvd_v.den
#rm -f ${B2DIR}/ref_rsvd_v_og.den

########################################
# Processing Steps
########################################

echo "Binning reference and image data using factor ${BINNING_FACTOR} ..."
binDenFile --force --median --bin-x "$BINNING_FACTOR" --bin-y "$BINNING_FACTOR" "$INPUT_REF" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}.den"
binDenFile --force --median --bin-x "$BINNING_FACTOR" --bin-y "$BINNING_FACTOR" "$INPUT_IMG" "${OUTPUT_DIR}/img${OUTPUT_SUFFIX}.den"

echo "Computing average extinction ..."
computeAvgExtinction "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/img${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/ext_avg${OUTPUT_SUFFIX}.den" true

echo "Creating img${OUTPUT_SUFFIX}_avg.den ..."
dentk-framecalc1 --force --avg "${OUTPUT_DIR}/img${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/img${OUTPUT_SUFFIX}_avg.den"

echo "Creating ref${OUTPUT_SUFFIX}_avg.den ..."
dentk-framecalc1 --force --avg "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_avg.den"

echo "Creating TV mask GAMMA based on transmission ..."
dentk-framecalc --force --divide "${OUTPUT_DIR}/img${OUTPUT_SUFFIX}_avg.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_avg.den" "${OUTPUT_DIR}/tra${OUTPUT_SUFFIX}.den"
dentk-framecalc1 --force --avg "${OUTPUT_DIR}/tra${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/tra${OUTPUT_SUFFIX}_avg.den"
dentk-alpha --force --upper-quantile 0.9 "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_avg.den" "${OUTPUT_DIR}/ALPHA${OUTPUT_SUFFIX}.den"
dentk-alpha --force --geq 0.9 --leq 1.1 "${OUTPUT_DIR}/tra${OUTPUT_SUFFIX}_avg.den" "${OUTPUT_DIR}/BETA${OUTPUT_SUFFIX}.den"
dentk-calc --force --multiply "${OUTPUT_DIR}/ALPHA${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/BETA${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/GAMMA${OUTPUT_SUFFIX}.den"
rm -f "${OUTPUT_DIR}/tra${OUTPUT_SUFFIX}.den"

echo "Computing SVD of first 100 components of ref.den ..."
dentk-svd --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_s.den" --max_s_vals 100 --vectorsV "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_v_orig.den"

echo "Creating orthonormal set of SVD-based flat-field vectors: ${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_v.den ..."
normalizeSingularVectors.py --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_v_orig.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_v.den"
rm -f "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_v_orig.den"

echo "Creating orthonormal set of RSVD-based flat-field vectors: ${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v.den ..."
dentk-rsvd.py --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_s.den" --max-s-vals 100 --vectorsV "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v.den"
dentk-orthogonalize --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v_og.den"
rm -f "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v.den"
normalizeSingularVectors.py --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v_og.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v.den"
rm -f "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v_og.den"

echo "Creating avg centered SVD vectors"
dentk-framecalc --force --subtract "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_avg.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered.den"
dentk-rsvd.py --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_s.den" --max-s-vals 100 --vectorsV "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v.den"
dentk-svd --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_s.den" --max_s_vals 100 --vectorsV "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v.den"
dentk-merge --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v_with_avg.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_avg.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v.den"
dentk-merge --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v_with_avg.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_avg.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v.den"
dentk-orthogonalize --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v_with_avg.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v_with_avg_og.den"
dentk-orthogonalize --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v_with_avg.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v_with_avg_og.den"
rm -f "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v_with_avg.den"
rm -f "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v_with_avg.den"
normalizeSingularVectors.py --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v_with_avg_og.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v_with_avg.den"
normalizeSingularVectors.py --force "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v_with_avg_og.den" "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v_with_avg.den"
rm -f "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_rsvd_v_with_avg_og.den"
rm -f "${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_centered_v_with_avg_og.den"

########################################
# Final message
########################################

echo
echo "Written binned files (factor=${BINNING_FACTOR}):"
echo "  ${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}.den"
echo "  ${OUTPUT_DIR}/img${OUTPUT_SUFFIX}.den"
echo
echo "Computed:"
echo "  mean flat fields: ${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_avg.den and ${OUTPUT_DIR}/img${OUTPUT_SUFFIX}_avg.den"
echo "  orthonormal SVD-based flat-field vectors (100 comps): ${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_v.den"
echo "  orthonormal RSVD-based flat-field vectors (100 comps): ${OUTPUT_DIR}/ref${OUTPUT_SUFFIX}_rsvd_v.den"

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
