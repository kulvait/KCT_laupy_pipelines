#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/31computeConsecutiveDifferences-%N-%j.out
#SBATCH --error=log/31computeConsecutiveDifferences-%N-%j.err

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
OUTPUT=""
SCALE=false

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: $0 [OPTIONS] <WD> <INPUT> <OUTPUT>

Positional arguments:
  WD                          Working directory (required)
  INPUT                       Input file (required)
  OUTPUT                      Output file (required)

Options:
  --force                     Overwrite existing OUTPUT if it exists and is specified
  --scale                     Scale input by its average
  -h, --help                  Show this help message and exit
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --force)
            FORCE=true
            shift
            ;;
        --scale)
			SCALE=true
			shift
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
                echo "WD=$WD"
            elif [ -z "$INPUT" ]; then
                INPUT="$1"
                echo "INPUT=$INPUT"
            elif [ -z "$OUTPUT" ]; then
                OUTPUT="$1"
                echo "OUTPUT=$OUTPUT"
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
if [ -z "$WD" ] || [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
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

TMPDIR=$(mktemp -d -p . "tmp_31computeConsecutiveDifferences_XXXXX")

INPUTPROCESSED=${INPUT}
if [[ "$SCALE" == true ]]; then
	dentk-framecalc1 --avg ${INPUT} ${TMPDIR}/avg.den
	dentk-calc1 --double-softplus ${TMPDIR}/avg.den ${TMPDIR}/avg_sp.den
	dentk-framecalc --divide ${INPUT} ${TMPDIR}/avg_sp.den ${TMPDIR}/scaled.den
	INPUTPROCESSED=${TMPDIR}/scaled.den
fi


DIMX=$(dentk-info --dim ${INPUTPROCESSED} | cut -f1)
DIMY=$(dentk-info --dim ${INPUTPROCESSED} | cut -f2)
DIMZ=$(dentk-info --dim ${INPUTPROCESSED} | cut -f3)

dentk-empty --force $DIMX $DIMY 1 ${TMPDIR}/empty.den
dentk-merge --force ${TMPDIR}/plus.den ${INPUTPROCESSED} ${TMPDIR}/empty.den
dentk-merge --force ${TMPDIR}/minus.den ${TMPDIR}/empty.den ${INPUTPROCESSED}
dentk-calc --force --subtract ${TMPDIR}/plus.den ${TMPDIR}/minus.den ${TMPDIR}/diff.den
#Remove first and last frames from diff.den and save as output
DIMSIZE=$(calc "$DIMZ - 1")
arg=()
if [[ "$FORCE" == true ]]; then
	arg+=(--force)
fi
arg+=(-f 1-$DIMSIZE)
arg+=(${TMPDIR}/diff.den)
arg+=(${OUTPUT})
dentk-cat "${arg[@]}"

rm -rf $TMPDIR

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
