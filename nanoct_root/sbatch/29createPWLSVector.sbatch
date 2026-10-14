#!/bin/bash
#SBATCH --time=0-23:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/29createPWLSVector-%N-%j.out
#SBATCH --error=log/29createPWLSVector-%N-%j.err
#SBATCH --partition=allgpu

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
OUTPUT_IS_DEN=false
INPUT_IS_DEN=false
DELETE_INPUT=false
FORCE=false
#Program parameters
ODX=""
ODY=""
ODZ=""
RADIUS=""
RADIAL_CENTER_X=""
RADIAL_CENTER_Y=""
RADIAL_CENTER_OFFSET_X=""
RADIAL_CENTER_OFFSET_Y=""

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

TMPDIR=$(mktemp -d -p . "tmp_29createPWLSVector_XXXXX")
dentk-calc1 --double-softplus $INPUT $TMPDIR/double_softplus.den

#ARG=()
#ARG+=(--square)
#if [[ "$FORCE" == "true" ]]; then
#    ARG+=(--force)
#fi
#dentk-calc1 "${ARG[@]}" $TMPDIR/double_softplus.den $OUTPUT
cp $TMPDIR/double_softplus.den $OUTPUT

rm -rf $TMPDIR

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
