#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=05currentCorrect
#SBATCH --output=log/05currentCorrect-%N-%j.out
#SBATCH --error=log/05currentCorrect-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# === Default values ===
KEEP_INPUT_FILES=true  # Default: keep input files
FIX_CORRUPTED_H5=false  # Default: do not fix corrupted HDF5 files
IMG="img_clean_darksub.den"
REF="ref_clean_darksub.den"
WD=""

# === Usage function ===
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: $scriptname [options] <WD>

Options:
  --img <file>                Input image file (default: img_clean_darksub.den)
  --ref <file>                Input reference file (default: ref_clean_darksub.den)
  --remove-input-files        Delete input files after successful processing
  --fix-corrupted-h5          Pass this flag to currentCorrect.py to fix corrupted HDF5 files
  -h, --help                  Show this help message and exit

Positional arguments:
  WD                          Working directory
EOF
}
# === Parse command line arguments ===
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
	--remove-input-files)
	    KEEP_INPUT_FILES=false
	    shift
	    ;;
	--fix-corrupted-h5)
	    FIX_CORRUPTED_H5=true
	    shift
	    ;;
	--img)
	    IMG="$2"
	    shift 2
	    ;;
	--ref)
	    REF="$2"
	    shift 2
	    ;;
	-h|--help)
	    usage help
	    exit 0
	    ;;
	-*)
	    echo "Unknown option: $1"
	    usage error
	    exit 1
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
else
    WD="${POSITIONAL_ARGS[0]}"
fi

#Start script
source initGanrec


cd "$WD" || { echo "Failed to cd into $1"; exit 1; }

LOGDIR="log/currentCorrect"
mkdir -p "$LOGDIR"

# === Start of actual execution ===
functionCurrentCorrect() {
	local typeid=$1
	local inputFile=$2
	local outputFile=$3
	local filenameInput=$(basename $inputFile)
	local filenameOutput=$(basename $outputFile)
	local base_in="${filenameInput%.den}"
	local base_out="${filenameOutput%.den}"


    local timestamp=$(date +%d%m%Y_%H%M%S)  # <-- Add timestamp here

    local logFile="${LOGDIR}/${base_out}_curcorinfo_${timestamp}.log"
    local infoFile="${LOGDIR}/${base_out}_curcorinfo_${timestamp}.den"
    local figFile="${LOGDIR}/${base_out}_curcorinfo_${timestamp}.pdf"

    local args=(
        h5 "$inputFile" "$outputFile"
        --type "$typeid"
        --saveinfo "$infoFile"
        --savefig "$figFile"
        --correct-insertion-offset
        --tv-denoise
    )
    
    if [[ "$typeid" == "IMG" ]]; then
        args+=(
            --connect-gaps
            --detrend-exponential
            --remove-short-term-noise 0.1
        )
    elif [[ "$typeid" == "REF" ]]; then
        args+=(
            --detrend-data
        )
    else
        echo "Unknown type: $typeid"
        return 1
    fi
    
    if [[ "$FIX_CORRUPTED_H5" == "true" ]]; then
        args+=(--fix-corrupted-h5)
    fi
    
	echo "[$timestamp] Starting currentCorrect for $inputFile (type: $typeid) → $outputFile log: $logFile"
	#Print the command to be executed for logging purposes with arguments separated by spaces
	printf '%q ' currentCorrect.py "${args[@]}"
	printf '\n'
    currentCorrect.py "${args[@]}" 2>&1 | tee "$logFile"
	
	if [[ -f "$outputFile" ]]; then
		return 0
	else
		echo "[$(date +%d%m%Y_%H%M%S)] currentCorrect failed: $inputFile → $outputFile"
		return 1
	fi
}

# Current correct
inputs=("$IMG" "$REF")
input_type=(IMG REF)
suffix="_curcor"

for i in "${!inputs[@]}"; do
	input=${inputs[$i]}
	type=${input_type[$i]}
	
	# Check if the input file exists
	if [[ ! -f $input ]]; then
		echo "Input file $input does not exist. Skipping current correction for $type."
		continue
	fi
	
	# Generate output file name
	output="${input%.den}${suffix}.den"
	
	# Call the function to perform current correction
	functionCurrentCorrect "$type" "$input" "$output"
	
	# Check if the output file was created successfully
	if [[ $? -ne 0 ]]; then
		echo "Current correction for file $input of $type failed. Exiting."
		exit 1
	fi
done
# Remove the input files if the flag is set
if [[ $KEEP_INPUT_FILES == false ]]; then
	for input in "${inputs[@]}"; do
		if [[ -f $input ]]; then
			rm -f "$input"
		fi
	done
fi


#currentCorrect.py --fix-corrupted-h5 --type IMG h5 IMG_DF.den IMG_DC.den --saveinfo out/IMG_DC_curcorinfo.den --savefig out/IMG_DC_curcorinfo.pdf
#if [[ -f "IMG_DC.den" ]]; then
#	rm -f IMG_DF.den
#else
#	echo "Current correct IMG_DF.den failed!"
#fi
#currentCorrect.py --fix-corrupted-h5 --type REF h5 REF_DF.den REF_DC.den --saveinfo out/REF_DC_curcorinfo.den --savefig out/REF_DC_curcorinfo.pdf
#if [[ -f "REF_DC.den" ]]; then
#	rm -f REF_DF.den
#else
#	echo "Current correct REF_DF.den failed!"
#fi
#

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
