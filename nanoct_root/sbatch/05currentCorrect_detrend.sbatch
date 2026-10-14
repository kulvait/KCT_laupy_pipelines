#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=05currentCorrect
#SBATCH --output=log/05currentCorrect-%N-%j.out
#SBATCH --error=log/05currentCorrect-%N-%j.err
scriptname=$(basename "$0")

# === Default values ===
KEEP_INPUT_FILES=true  # Default: keep input files
WD=""

# === Usage function ===
usage() {
    echo "Usage: $scriptname [options] <WD>"
    echo ""
    echo "Options:"
    echo "  --remove-input-files        Delete input files after successful processing"
    echo ""
    echo "Arguments:"
    echo "  WD                          Working directory"
    exit 1
}
# === Parse command line arguments ===
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
	--remove-input-files)
	    KEEP_INPUT_FILES=false
	    shift
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
else
    WD="${POSITIONAL_ARGS[0]}"
fi

#Start script
source initGanrec
source sourcePath


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
	local logFile="${LOGDIR}/${base_out}_curcorinfo.log"
	
	CMD="currentCorrect.py --fix-corrupted-h5 --correct-time-offset --remove-short-term-noise 0.1 --remove-long-term-trend 10.0 --type $typeid h5 $inputFile $outputFile --saveinfo $LOGDIR/${base_out}_curcorinfo.den --savefig ${LOGDIR}/${base_out}_curcorinfo.pdf 2>&1 | tee \"$logFile\""
	CMD="currentCorrect.py --correct-insertion-offset --remove-short-term-noise 0.1 --remove-long-term-trend 10.0 --type $typeid h5 $inputFile $outputFile --saveinfo $LOGDIR/${base_out}_curcorinfo.den --savefig ${LOGDIR}/${base_out}_curcorinfo.pdf 2>&1 | tee \"$logFile\""
echo "$CMD"
	if [[ "$typeid" == "IMG" ]]; then
		#currentCorrect.py --correct-time-offset --remove-short-term-noise 0.1 --remove-long-term-trend 10.0 --type $typeid h5 $inputFile $outputFile --saveinfo $LOGDIR/${base_out}_curcorinfo.den --savefig ${LOGDIR}/${base_out}_curcorinfo.pdf 2>&1 | tee "$logFile"
#		currentCorrect.py --correct-insertion-offset --tv-denoise --remove-short-term-noise 0.1 --remove-long-term-trend 60 --type $typeid h5 $inputFile $outputFile --saveinfo $LOGDIR/${base_out}_curcorinfo.den --savefig ${LOGDIR}/${base_out}_curcorinfo.pdf 2>&1 | tee "$logFile"
		currentCorrect.py --correct-insertion-offset --tv-denoise --detrend-exponential --type $typeid h5 $inputFile ${outputFile} --saveinfo $LOGDIR/${base_out}_curcorinfo.den --savefig ${LOGDIR}/${base_out}_curcorinfo.pdf 2>&1 | tee "$logFile"
	elif [[ "$typeid" == "REF" ]]; then
		currentCorrect.py --correct-insertion-offset --tv-denoise --detrend-data --type $typeid h5 $inputFile $outputFile --saveinfo $LOGDIR/${base_out}_curcorinfo.den --savefig ${LOGDIR}/${base_out}_curcorinfo.pdf 2>&1 | tee "$logFile"
	else
		echo "Unknown type: $typeid"
		return 1
	fi
#eval $CMD
	if [[ -f "$3" ]]; then
		return 0
	else
		echo "Current correct $2 failed!"
		return 1
	fi
}

# Current correct
inputs=(img_clean_darksub.den ref_clean_darksub.den)
input_type=(IMG REF)
suffix="_curcor_detrend"

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

