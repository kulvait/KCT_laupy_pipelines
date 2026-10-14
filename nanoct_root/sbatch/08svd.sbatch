#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/08svd-%N-%j.out
#SBATCH --error=log/08svd-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Default values
#I/0 parameters
WD=""
INPUT=""
OUTPUTS=""
OUTPUTV=""
MAX_S_VALS=100
CENTER=false
FORCE=false
AUGMENTV=""

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: $0 [OPTIONS] <WD> <INPUT> <OUTPUTS> <OUTPUTV>

Positional arguments:
  WD                          Working directory (required)
  INPUT                       Input file (required)
  OUTPUTS                     Output file with Singular Values (required)
  OUTPUTV                     Output file with Singular Vectors (required)

Options:
  --augment-vectors           Additional vectors (e.g., mean) to include in the V basis. These vectors are normalized 
                              and placed first; computed SVD vectors are then orthogonalized with respect to them. 
                              (default: none)
  --max_s_vals N              Maximum number of singular values/vectors to compute, for all put N=0 (default: 100)
  --center		    	      Center the data before performing SVD by sutracting mean of frames from each frame (default: false)
  --force                     Overwrite existing OUTPUT if it exists and is specified
  -h, --help                  Show this help message and exit
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --center)
	    	CENTER=true
	    	shift
	    	;;

        --force)
            FORCE=true
            shift
            ;;
		--augment-vectors)
	    	AUGMENTV="$2"
	    	shift 2
	    	;;
		--max_s_vals)
		    MAX_S_VALS="$2"
	    	shift 2
	    	;;
		-h|--help)
	        usage help
	        exit 0
	        ;;
        -*)
            echo "Unknown option: $1" >&2
            usage error
	    	exit 1
            ;;
        *)
            # Positional arguments: WD and INPUT
            if [ -z "$WD" ]; then
                WD="$1"
            elif [ -z "$INPUT" ]; then
                INPUT="$1"
            elif [ -z "$OUTPUTS" ]; then
				OUTPUTS="$1"
	    	elif [ -z "$OUTPUTV" ]; then
				OUTPUTV="$1"
			else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done


# Check if the number of positional arguments is correct (both WD and INPUT must be set)
if [ -z "$WD" ] || [ -z "$INPUT" ] || [ -z "$OUTPUTS" ] || [ -z "$OUTPUTV" ]; then
    echo "Error: Missing required positional arguments" >&2
    usage error
    exit 1
fi

# Check if WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

cd $WD
source initGanrec

TMPDIR=$(mktemp -d -p . "tmp_08svd_XXXXX")

INPUTSVD=""
if [[ "$CENTER" == true ]]; then
	INPUTSVD="${TMPDIR}/centered.den"
	dentk-framecalc1 --avg ${INPUT} ${TMPDIR}/mean.den
	dentk-framecalc --subtract ${INPUT} ${TMPDIR}/mean.den ${INPUTSVD}
else
	INPUTSVD="${INPUT}"
fi

OUTPUTSVD="${TMPDIR}/svd_output_v.den"
arg=(--vectorsV "$OUTPUTSVD")
if [[ "$MAX_S_VALS" -gt 0 ]]; then
	arg+=(--max_s_vals "$MAX_S_VALS")
fi
if [[ "$FORCE" == true ]]; then
	arg+=(--force)
fi
arg+=($INPUTSVD "$OUTPUTS")
dentk-svd "${arg[@]}"

AUGMENTED=""
arg=()
if [[ "$FORCE" == true ]]; then
	arg+=(--force)
fi
if [[ "$AUGMENTV" != "" ]]; then
	dentk-merge "${TMPDIR}/augmented.den" "$AUGMENTV" "$OUTPUTSVD"
    dentk-orthogonalize "${TMPDIR}/augmented.den" "${TMPDIR}/augmented_og.den"
    normalizeSingularVectors.py "${arg[@]}" "${TMPDIR}/augmented_og.den" "${OUTPUTV}"
else
	normalizeSingularVectors.py "${arg[@]}" "${OUTPUTSVD}" "${OUTPUTV}"
fi

rm -rf $TMPDIR

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
