#!/bin/bash
#SBATCH --time=0-23:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/00TVregularize-%N-%j.out
#SBATCH --error=log/00TVregularize-%N-%j.err
#SBATCH --partition=allgpu

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Initialize positional arguments
WD=""
INPUT=""
OUTPUT=""
# Initialize optional arguments with default values
MAX_ITERATIONS_PDHG=300
CHUNK_SIZE=20
PDHG_MU=-0.02
PDHG_SIGMA=-0.2
PDHG_TAU=-0.2
DEFAULT_GRADIENT="--gradient-forward-3point"  # Default gradient
GRADIENT="$DEFAULT_GRADIENT"
PLATFORM_ID=""
KEEP_DEN=false
DEN_OUTPUT=false
FORCE=false

# Function to print usage and exit
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <INPUT> <OUTPUT>

Positional arguments:
  WD                         Existing working directory.
  INPUT                      Directory containing .tif files, or a single DEN file.
  OUTPUT                     TIFF output directory, or DEN output file ending in .den.


Relative INPUT and OUTPUT paths are interpreted from WD.

Options:
  -i MAX_ITERATIONS           Set maximum iterations (default: $MAX_ITERATIONS_PDHG)
  -c, --chunk-size CHUNK_SIZE Set chunk size (default: $CHUNK_SIZE)
  -m MU                       Set PDHG mu value (default: $PDHG_MU)
  -s SIGMA                    Set PDHG sigma value (default: $PDHG_SIGMA)
  -t TAU                      Set PDHG tau value (default: $PDHG_TAU)
  -p PLATFORM_ID              Set OpenCL platform ID (default: auto)
  -g, --gradient FLAG         Set gradient type (default: $DEFAULT_GRADIENT)
                              Leading '--' is optional.
			     Available options:
			     --gradient-forward-2point
			     --gradient-forward-3point
			     --gradient-forward-4point
			     --gradient-forward-5point
			     --gradient-forward-6point
			     --gradient-forward-7point
			     --gradient-central-3point
			     --gradient-central-5point
                              A gradient flag may also be supplied directly.
  --keep-den                  With TIFF output, also save OUTPUT.den (default: false)
  --force                     Force overwrite of existing output (default: false)
   -h, --h, --help             Show this help message and exit successfully
EOF
}

require_value() {
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Error: $1 requires a value." >&2
        usage error
        exit 1
    fi
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -i)
			require_value "$1" "${2:-}"
            MAX_ITERATIONS_PDHG="$2"
            shift 2
            ;;
        -c|--chunk-size)
			require_value "$1" "${2:-}"
            CHUNK_SIZE="$2"
            shift 2
            ;;
        -m)
			require_value "$1" "${2:-}"
            PDHG_MU="$2"
            shift 2
            ;;
        -s)
			require_value "$1" "${2:-}"
            PDHG_SIGMA="$2"
            shift 2
            ;;
        -t)
			require_value "$1" "${2:-}"
            PDHG_TAU="$2"
            shift 2
            ;;
        -p)
			require_value "$1" "${2:-}"
            PLATFORM_ID="$2"
            shift 2
            ;;
        -g|--gradient)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "Error: $1 requires a gradient type." >&2
                usage error
                exit 1
            fi
            GRADIENT="$2"
            shift 2
            ;;
        --gradient-forward-*|--gradient-central-*)
            GRADIENT="$1"
            shift
            ;;
		--keep-den)
			KEEP_DEN=true
			shift
			;;
		--force)
			FORCE=true
			shift
			;;
		-h|--h|--help)
	    	usage help
	    	exit 0
	    	;;
        -*)
            echo "Unknown option $1" >&2
            usage error
			exit 1
            ;;
        *)
            if [ -z "$WD" ]; then
                WD="$1"
            elif [ -z "$INPUT" ]; then
                INPUT="$1"
			elif [ -z "$OUTPUT" ]; then
				OUTPUT="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done

# Check if the number of parameters is correct (2)
if [ -z "$WD" ] || [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
    echo "Error: Missing required positional arguments." >&2
    usage error
    exit 1
fi

# Assign parameters to variables
PATH=$PATH:$PWD/bin

# Accept either gradient-forward-2point or --gradient-forward-2point.
GRADIENT="--${GRADIENT#--}"

VALID_GRADIENTS=(
    "--gradient-forward-2point"
    "--gradient-forward-3point"
    "--gradient-forward-4point"
    "--gradient-forward-5point"
    "--gradient-forward-6point"
    "--gradient-forward-7point"
    "--gradient-central-3point"
    "--gradient-central-5point"
)

gradient_valid=false
for candidate in "${VALID_GRADIENTS[@]}"; do
    if [[ "$GRADIENT" == "$candidate" ]]; then
        gradient_valid=true
        break
    fi
done

if [[ "$gradient_valid" != true ]]; then
    echo "Error: Unsupported gradient type: $GRADIENT" >&2
    usage error
    exit 1
fi

# Run kct-rof with the given parameters
echo "WD=$WD"
echo "INPUT=$INPUT"
echo "OUTPUT=$OUTPUT"
echo "--max-iterations-pdhg $MAX_ITERATIONS_PDHG"
echo "--chunk-size $CHUNK_SIZE"
echo "--pdhg-mu $PDHG_MU"
echo "--pdhg-sigma $PDHG_SIGMA"
echo "--pdhg-tau $PDHG_TAU"
echo "$GRADIENT"

if [[ -d "$WD" ]]; then
    cd "$WD"
else
    echo "Error: Working directory $WD does not exist!" >&2
    exit 1
fi

unset LD_PRELOAD
source initGanrec

if [[ -z "$PLATFORM_ID" ]]; then
	PLATFORM_ID=$(platformID)  # Fetch the platformID using the program
fi

# Record the start time
start_time=$(date +%s)
#Start of the body of the script


function LoadModule()
{
    if module list 2>&1| grep -qw $1; then
        echo "Module $1 already loaded."
    else
        echo "Loading module $1."
        module load $1
    fi  
}

LoadModule maxwell
LoadModule cuda/11.8

TMPDIR=$(mktemp -d -p . "tmp_00TVregularize_XXXXXX")
TIFPREFIX=""
if [ ! -d "${INPUT}" ]; then
	#Assume that it is file in DEN format
	if [ ! -f "${INPUT}" ]; then
		echo "Error: ${INPUT} does not exist!"
		exit 1
	else
		INPUT_FILE="${INPUT}"
        TIFPREFIX=$(basename "${INPUT}" .den)
	fi
else
	INPUT_FILE="${TMPDIR}/input.den"
    mapfile -t TIF_FILES < <(find "${INPUT}" -maxdepth 1 -type f -name '*.tif' -printf '%f\n' | sort)
    # Ensure we found files
	if [ ${#TIF_FILES[@]} -eq 0 ]; then
	    echo "No .tif files found in ${INPUT}!" >&2
	    exit 1
	fi
	#Compute common prefix
	TIFPREFIX=${TIF_FILES[0]}
	for file in "${TIF_FILES[@]}"; do
	    while [[ "${file#$TIFPREFIX}" == "${file}" ]]; do
	        TIFPREFIX="${TIFPREFIX%?}"
	    done
	done
	# Optional: strip .tif if prefix ends with it
	TIFPREFIX="${TIFPREFIX%.tif}"

	# Build full paths for command
	FULL_PATHS=()
	for file in "${TIF_FILES[@]}"; do
	    FULL_PATHS+=("${INPUT}/${file}")
	done
    tiffImagesToDenStack.py --float32 "${FULL_PATHS[@]}" "$INPUT_FILE"
fi

# If OUTPUT ends with .den, we will save output as single DEN file, otherwise we will save as TIFF stack in the specified directory
if [[ "$OUTPUT" == *.den ]]; then
	OUTPUT_FILE="$OUTPUT"
	DEN_OUTPUT=true
    OUTPUT=
elif [[ "$KEEP_DEN" == true ]]; then
	# Output file is output dir with .den suffix
	OUTPUT_FILE="${OUTPUT}.den"
	DEN_OUTPUT=true
else
	OUTPUT_FILE="${TMPDIR}/output_mu${PDHG_MU}.den"
	DEN_OUTPUT=false
fi

if [[ -f "$OUTPUT_FILE" ]] && [[ "$FORCE" != true ]]; then
	echo "Error: Output file $OUTPUT_FILE already exists! Use --force to overwrite." >&2
	exit 1
elif [[ -f "$OUTPUT_FILE" ]] && [[ "$FORCE" == true ]]; then
	rm -f "$OUTPUT_FILE"
fi

if [[ -n "$OUTPUT" ]]; then
    if [[ -e "$OUTPUT" || -L "$OUTPUT" ]]; then
        if [[ "$FORCE" != true ]]; then
            echo "Error: Output path $OUTPUT already exists! Use --force to overwrite." >&2
            exit 1
        fi
        rm -rf "$OUTPUT"
    fi
    mkdir -p -- "$OUTPUT"
fi

CMD=(
    kct-rof
    --relaxed
    --force
    --max-iterations-pdhg "$MAX_ITERATIONS_PDHG"
    --chunk-size "$CHUNK_SIZE"
    --pdhg-mu "$PDHG_MU"
    -p "$PLATFORM_ID"
    "$GRADIENT"
    --pdhg-sigma "$PDHG_SIGMA"
    --pdhg-tau "$PDHG_TAU"
    "$INPUT_FILE"
    "$OUTPUT_FILE"
)

# Print a shell-escaped representation for reproducible logging.
printf 'Executing:'
printf ' %q' "${CMD[@]}"
printf '\n'

# Execute directly; no eval or string splitting.
"${CMD[@]}"

#If output dir is specified, convert the output DEN file to TIFF stack
if [[ -n "$OUTPUT" ]]; then
	denFilesToTifFiles.py --prefix "$TIFPREFIX" "$OUTPUT_FILE" "$OUTPUT"
fi

rm -rf -- "$TMPDIR"

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
