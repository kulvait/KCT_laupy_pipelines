#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=02destar
#SBATCH --output=log/02destar-%N-%j.out
#SBATCH --error=log/02destar-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# === Default values ===
KEEP_INPUT_FILES=true
WD=""
THREADS=-1
SUFFIX="_clean"
zarInputFile=raw_zarr.zar

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
  --remove-input-files        Delete input files after successful processing
  --zar-input-file FILE       Specify the input Zarr file (default: $zarInputFile)
  --suffix S                  Suffix to append to output files (default: $SUFFIX)
  --threads N                 Number of threads to use (default: -1, automatic)

Arguments:
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
        --threads)
            if [[ -n $2 && $2 != -* ]]; then
                THREADS="$2"
                shift 2
            else
                echo "Error: --threads requires a numeric argument"
                usage
            fi
            ;;
        --suffix)
            if [[ -n $2 && $2 != -* ]]; then
                SUFFIX="$2"
                shift 2
            else
                echo "Error: --suffix requires a string argument"
                usage
            fi
            ;;
		--zar-input-file)
		    if [[ -n $2 && $2 != -* ]]; then
				zarInputFile="$2"
				shift 2
		    else
				echo "Error: --zar-input-file requires a string argument"
				usage
	    	fi
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


cd "$WD" || { echo "Failed to cd into $1"; exit 1; }


# === Function to destar files ===
# destarFile processes a single file using destar.py
# Arguments:
# 1. inputfile: The input file to be processed
# 2. outputfile: The output file to save the result
# 3. [filtersize]: Optional. Filter size to apply (default: 3)
# 4. [iterationcount]: Optional. Number of iterations (default: 3)
# 5. [threads]: Optional number of threads (default: -1)
destarFile() {
    local default_filter_size=3
    local default_iteration_count=3
    local default_threads=-1

    if [[ $# -lt 2 || $# -gt 6 ]]; then
        echo "Error: destarFile requires 2 to 5 arguments: inputfile, outputfile, [filtersize], [iterationcount], [threads]"
        return 1
    fi

    local inputfile=$1
    local outputfile=$2
    # Initialize filter size and iteration count
    if [[ -z $3 ]]; then
    	local filtersize=$default_filter_size
        echo "Filter size not specified. Using default: $filtersize"
	else
		local filtersize=$3
    fi
    if [[ -z $4 ]]; then
		local iterationcount=$default_iteration_count
		echo "Iteration count not specified. Using default: $iterationcount"
    else
		local iterationcount=$4
    fi
    if [[ -z $5 ]]; then
		local threshold=$default_threshold
		echo "Threashold for --filter-threshold-rel-sigma not specified. Using default: $threshold"
    else
		local threshold=$5
    fi
    if [[ -z $6 ]]; then
		local zinger=false
    else
		local zinger=$6
    fi
	if [[ -z $7 ]]; then
		local outputMaskFile="zarr_destar_mask.zar"
    else
		local outputMaskFile=$7
    fi

    local inputFilePrefix=${inputfile%.*}
    local logfile="log/${inputFilePrefix}_destar.log"
    local tempfile="${inputFilePrefix}_destar"
	local threads=${8:-$default_threads}
	local outputMask="${outputMaskFile}:${inputFilePrefix}"

    # Check for input file existence
    if [[ ! -f $inputfile ]]; then
        echo "File $inputfile does not exist."
        return 1
    fi

	# Remove tempfile if it exists
	if [[ -f $tempfile ]]; then
		rm "$tempfile"
	fi
	local inputarray="${inputFilePrefix}"

	ARG=()
	if [[ "$zinger" == true ]]; then
		echo "Zinger removal enabled for $inputfile with threshold $threshold"
		local ARG+=(--zinger-algorithm)
    fi
	ARG+=(--output-mask "${outputMask}")
	ARG+=(--filter-threshold-loc-sigma "${threshold}")
	ARG+=(--filter-size "${filtersize}")
	ARG+=(--filter-iterations "${iterationcount}")
	ARG+=(-j "${threads}")
	ARG+=("${inputfile}")
	ARG+=("${tempfile}")

	echo "START removeHotPixels ${ARG[*]}" | tee "$logfile"
	removeHotPixels "${ARG[@]}" >> "${logfile}"
    local status=$?

    if [[ $status -eq 0 && -f $tempfile ]]; then
        mv "${tempfile}" "${outputfile}"
    else
        >&2 echo "Error: destar.py failed with status $status. Check the log file ${logfile} for details."
        return 1
    fi

    echo "END destar: $inputfile" | tee -a "$logfile"
}

destarZarr() {
    local default_threshold=3.0
    local default_filter_size=5
    local default_threads=-1

    if [[ $# -lt 3 || $# -gt 9 ]]; then
		echo "Error: destarZarr requires 3 to 8 arguments: inputfile, inputarray, outputfile, [filtersize], [iterationcount], [threshold], [zinger], [threads]"
	    >&2 echo "Error: destarZarr requires 3 to 8 arguments: inputfile, inputarray, outputfile, [filtersize], [iterationcount], [threshold], [zinger], [threads]"
		return 1
    fi

    local inputfile=$1
    local inputarray=$2
    local outputfile=$3
    if [[ -z $4 ]]; then
    	local filtersize=$default_filter_size
        echo "Filter size not specified. Using default: $filtersize"
	else
		local filtersize=$4
    fi
    if [[ -z $5 ]]; then
		local iterationcount=$default_iteration_count
		echo "Iteration count not specified. Using default: $iterationcount"
    else
		local iterationcount=$5
    fi
    if [[ -z $6 ]]; then
		local threshold=$default_threshold
		echo "Threashold for --filter-threshold-rel-sigma not specified. Using default: $threshold"
    else
		local threshold=$6
    fi
    if [[ -z $7 ]]; then
		local zinger=false
    else
		local zinger=$7
    	echo "Zinger removal enabled for $inputfile with threshold $threshold"
    fi
	if [[ -z $8 ]]; then
		local outputMaskFile="zarr_destar_mask.zar"
		echo "Output mask file not specified. Using default: $outputMaskFile"
	else		
		local outputMaskFile=$8
    fi
	local threads=${9:-$default_threads}
	ARG=()	
	if [[ "$zinger" == true ]]; then
		echo "Zinger removal enabled for $inputfile with threshold $threshold"
		local ARG+=(--zinger-algorithm)
    fi
    local logfile="log/${inputarray}_destar.log"
	local inputZarr="${inputfile}:${inputarray}"
	local outputMask="${outputMaskFile}:${inputarray}"
	ARG+=(--output-mask "${outputMask}")
	ARG+=(--filter-threshold-loc-sigma "${threshold}")
	ARG+=(--filter-size "${filtersize}")
	ARG+=(--filter-iterations "${iterationcount}")
	ARG+=(-j "${threads}")
	ARG+=("${inputZarr}")
	ARG+=("${outputfile}")

	echo "START removeHotPixels ${ARG[*]}" | tee "$logfile"
    removeHotPixels "${ARG[@]}" >> "${logfile}"
	local status=$?

	if [[ $status -eq 0 ]]; then
		echo "removeHotPixels completed successfully for ${inputZarr}. Output saved to ${outputfile}."
	else
		>&2 echo "Error: removeHotPixels failed with status $status. Check the log file ${logfile} for details."
		return 1
	fi

	echo "END removeHotPixels: $inputZarr" | tee -a "$logfile"
}


echo "START 02destar.sbatch $PWD"
mkdir -p log

# Add _clean suffix to the input files
inputs=(dar.den ref.den img.den)
actions=(destar destar destar)

zarInputBase="${zarInputFile%.*}"  # Remove .zar extension
zarDestarMask="${zarInputBase}_destar_mask.zar"
rm -f "$zarDestarMask"
zarArrays=(dar ref img)
actions=(zarrdestar zarrdestar zarrdestar)

filtersize=(5 5 5)
iterationcount=(1 1 1)
#For zinger action
default_threshold=3.0
thresholds=(5.0 5.0 5.0)

outputs=()
zarInputFiles=()

default_action="destar"
default_filtersize=5
default_iterationcount=1

# Generate outputs
for ((i=0; i<${#inputs[@]}; i++)); do
	action="${actions[$i]:-$default_action}"
	if [[ "$action" == "zarrdestar" ]]; then
		input=${zarInputFile}
		array=${zarArrays[$i]}
		base=$array
		ext="zar"
		inputs[$i]="${input}"
	else
		input="${inputs[$i]}"
		base="${input%.*}"            # Remove .den extension
		ext="${input##*.}"            # Get extension (den)
	fi
	output="${base}${SUFFIX}.den"  # Append suffix before extension
    outputs+=("$output")
done

all_succeeded=true

# Main processing loop
for i in "${!inputs[@]}"; do
    input="${inputs[$i]}"
    output="${outputs[$i]}"
    
    # Assign defaults safely
    action="${actions[$i]:-$default_action}"
    filter="${filtersize[$i]:-$default_filtersize}"
    iterations="${iterationcount[$i]:-$default_iterationcount}"
	threshold="${thresholds[$i]:-$default_threshold}"

    if [[ "$action" == "destar" ]]; then
		zinger=false
        destarFile "$input" "$output" "$filter" "$iterations" "$threshold" "$zinger" "$zarDestarMask" "$THREADS"
	elif [[ "$action" == "zinger" ]]; then
		zinger=true
        destarFile "$input" "$output" "$filter" "$iterations" "$threshold" "$zinger" "$zarDestarMask" "$THREADS"
	elif [[ "$action" == "zarrdestar" ]]; then
		zinger=false
		zarrArray="${zarArrays[$i]}"
		destarZarr $zarInputFile "$zarrArray" "$output" "$filter" "$iterations" "$threshold" "$zinger" "$zarDestarMask" "$THREADS"
    elif [[ "$action" == "copy" ]]; then
        echo "Copying $input to $output"
        cp "$input" "$output"
    else
        echo "Error: Unsupported action '$action' for file $input"
        all_succeeded=false
        continue
    fi

    if [[ $? -ne 0 ]]; then
        all_succeeded=false
    fi
done

if [[ $all_succeeded == false ]]; then
    echo "Error: One or more destar operations failed. Check the log files for details."
    exit 1
elif [[ $KEEP_INPUT_FILES == false ]]; then
	for input in "${inputs[@]}"; do
		if [[ -f $input ]]; then
			rm "$input"
			echo "Deleted input file: $input"
		fi
	done
fi

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
