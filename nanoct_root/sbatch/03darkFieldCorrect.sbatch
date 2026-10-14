#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/03darkFieldCorrect-%N-%j.out
#SBATCH --error=log/03darkFieldCorrect-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# === Default values ===
KEEP_INPUT_FILES=true  # Default: keep input files
ESTIMATE_SNR=false    # Default: do not estimate SNR
IMG="img_clean.den"
REF="ref_clean.den"
DARK="dar_clean.den"
WD=""

# === Usage function ===
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD>

Options:
  --img <file>                Input image file (default: img_clean.den)
  --ref <file>                Input reference file (default: ref_clean.den)
  --dar <file>                Input dark field file (default: dar_clean.den)
  --remove-input-files        Delete input files after successful processing
  --estimate-snr              Estimate SNR after processing
  -h, --help                  Show this help message and exit.

Arguments:
  WD                          Working directory
EOF
}


# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --remove-input-files)
			KEEP_INPUT_FILES=false
            shift
            ;;
		--estimate-snr)
			ESTIMATE_SNR=true
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
		--dar)
			DARK="$2"
			shift 2
			;;
		--h|--help)
	    	usage help
	    	exit 0
	    	;;
        -*)
            echo "Unknown option $1" >&2
            usage error
	    	exit 1
            ;;
        *)
            if [[ -z "${WD:-}" ]]; then
                WD="$1"
                echo "WD=$WD"
            else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done

# Check required args
if [[ -z "${WD:-}" ]]; then
    echo "Error: Missing required positional arguments." >&2
    usage error
    exit 1
fi

# Check working directory exists
if [[ ! -d "$WD" ]]; then
    echo "Error: Working directory does not exist: $WD" >&2
    exit 1
fi

cd "$WD" || { echo "Failed to cd into $WD"; exit 1; }

#Start script
ARG="--force -j -1"

source initGanrec

function testExistence() {
    if [[ ! -f $1 ]]; then
        echo "File $1 does not exist."
        exit 1
    fi
}

function darkFieldCorrect() {
    local darkfield="$1"
    shift
    local inputs=("${!1}")
    shift
    local outputs=("${!1}")

    testExistence "$darkfield"

    if [[ ${#inputs[@]} -ne ${#outputs[@]} ]]; then
        echo "Number of inputs and outputs must match."
        exit 1
    fi

    # Create temporary working directory
    tmpdir=$(mktemp -d -p . darkfield_temp_XXXX)
    echo "Using temporary directory: $tmpdir"
    dark_med="$tmpdir/dark_med.den"
    dentk-framecalc1 $ARG --median "$darkfield" "$dark_med"

    # Loop through input/output pairs
    for ((i=0; i<${#inputs[@]}; i++)); do
        input="${inputs[$i]}"
        output="${outputs[$i]}"
		filename_in="$(basename "$input")"
		filename_out="$(basename "$output")"
		base_in="${filename_in%.den}"
		base_out="${filename_out%.den}"
        
		testExistence "$input"
        echo "Processing $input to produce $output"

        input_sub="$tmpdir/${base_in}_sub.den"
		dentk-framecalc ${ARG} --subtract "$input" "$dark_med" "$input_sub"
		dentk-calc1 ${ARG} --double-softplus "$input_sub" "$output"
    done

    # Clean up temporary directory
    echo "Cleaning up temporary directory: $tmpdir"
    rm -rf "$tmpdir"
}

function binProjections()
{
	local FILE_INPUT="$1"
	local DIR_OUTPUT="$2"
	local FILE_OUTPUT="$3"
	if [ ! -d "$DIR_OUTPUT" ]; then
		mkdir -p "$DIR_OUTPUT"
	fi
	binDenFile --force --median --bin-x 2 --bin-y 2 ${FILE_INPUT} "${DIR_OUTPUT}/${FILE_OUTPUT}"
}

mkdir -p log

# Add _clean suffix to the input files
inputs=("$IMG" "$REF")
suffix="_darksub"
darkfield="$DARK"

outputs=()

for input in "${inputs[@]}"; do
    base="${input%.*}"            # Remove .den extension
    ext="${input##*.}"            # Get extension (den)
    output="${base}${suffix}.${ext}"  # Append suffix before extension
    outputs+=("$output")
done

darkFieldCorrect "$darkfield" inputs[@] outputs[@]
all_succeeded=$?



if [[ $all_succeeded == false ]]; then
    echo "Error: One or more dark fiel correction operations failed. Check the log files for details."
    exit 1
fi

if [[ $ESTIMATE_SNR == true ]]; then
	TMPDIR=$(mktemp -d -p . "tmp_03darkFieldCorrect_XXXXXX")
    echo "Estimating SNR for outputs..."
	# Estimate avg of ref_clean_darksub.den
	IMGBASE="${IMG%.*}"
	REFBASE="${REF%.*}"
	IMG_DARKSUB="${IMGBASE}${suffix}.den"
	REF_DARKSUB="${REFBASE}${suffix}.den"
	dentk-framecalc1 $ARG --avg "$IMG_DARKSUB" "${IMGBASE}${suffix}_avg.den"
	dentk-framecalc1 $ARG --sample-standard-deviation "$IMG_DARKSUB" "${IMGBASE}${suffix}_sd.den"
	dentk-framecalc1 $ARG --avg "$REF_DARKSUB" "${REFBASE}${suffix}_avg.den"
	dentk-cat $ARG -k 2 "$REF_DARKSUB" "${TMPDIR}/ref_clean_darksub_odd.den"
	dentk-cat $ARG -f 1-end -k 2 "$REF_DARKSUB" "${TMPDIR}/ref_clean_darksub_even.den"
	dentk-calc $ARG --subtract "${TMPDIR}/ref_clean_darksub_odd.den" "${TMPDIR}/ref_clean_darksub_even.den" "${TMPDIR}/ref_clean_darksub_diff.den"
	dentk-framecalc1 $ARG --sample-variance "${TMPDIR}/ref_clean_darksub_diff.den" "${TMPDIR}/ref_clean_darksub_var_two.den"
	dentk-calc1 $ARG --double-softplus "${TMPDIR}/ref_clean_darksub_var_two.den" "${TMPDIR}/ref_clean_darksub_var_two_softplus.den"
	dentk-calc1 $ARG --multiply 0.5 "${TMPDIR}/ref_clean_darksub_var_two_softplus.den" "${REFBASE}${suffix}_var.den"
	dentk-calc1 $ARG --square "${REFBASE}${suffix}_avg.den" "${REFBASE}${suffix}_avg_sq.den"
	dentk-calc $ARG --divide "${REFBASE}${suffix}_avg_sq.den" "${REFBASE}${suffix}_var.den" ${REFBASE}${suffix}_N_snr.den
	dentk-calc1 $ARG --sqrt ${REFBASE}${suffix}_N_snr.den ${REFBASE}${suffix}_SNR.den
	binProjections ${REFBASE}${suffix}_N_snr.den extb2 ${REFBASE}${suffix}_N_snr.den
	binProjections ${REFBASE}${suffix}_SNR.den extb2 ${REFBASE}${suffix}_SNR.den
	rm -rf "$TMPDIR"
	
#Legacy code for SNR estimation (commented out)
#	dentk-framecalc1 $ARG --avg img_clean_darksub.den img_clean_darksub_avg.den
#	dentk-framecalc1 $ARG --sample-standard-deviation img_clean_darksub.den img_clean_darksub_sd.den
#	dentk-framecalc1 $ARG --avg ref_clean_darksub.den ref_clean_darksub_avg.den
#	dentk-cat $ARG -k 2 ref_clean_darksub.den ${TMPDIR}/ref_clean_darksub_odd.den
#	dentk-cat $ARG -f 1-end -k 2 ref_clean_darksub.den ${TMPDIR}/ref_clean_darksub_even.den
#	dentk-calc $ARG --subtract ${TMPDIR}/ref_clean_darksub_odd.den ${TMPDIR}/ref_clean_darksub_even.den ${TMPDIR}/ref_clean_darksub_diff.den
#	dentk-framecalc1 $ARG --sample-variance ${TMPDIR}/ref_clean_darksub_diff.den ${TMPDIR}/ref_clean_darksub_var_two.den
#	dentk-calc1 $ARG --double-softplus ${TMPDIR}/ref_clean_darksub_var_two.den ${TMPDIR}/ref_clean_darksub_var_two_softplus.den
#	dentk-calc1 $ARG --multiply 0.5 ${TMPDIR}/ref_clean_darksub_var_two_softplus.den ref_clean_darksub_var.den
#	dentk-calc1 $ARG --square ref_clean_darksub_avg.den ref_clean_darksub_avg_sq.den
#	dentk-calc $ARG --divide ref_clean_darksub_avg_sq.den ref_clean_darksub_var.den N_snr.den
#	dentk-calc1 $ARG --sqrt N_snr.den SNR.den
#	binProjections N_snr.den extb2 N_snr.den
#	binProjections SNR.den extb2 SNR.den
fi




if [[ $KEEP_INPUT_FILES == false ]]; then
	for input in "${inputs[@]}"; do
		if [[ -f $input ]]; then
			rm "$input"
			echo "Deleted input file: $input"
		fi
	done
    rm "$darkfield"
fi

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
