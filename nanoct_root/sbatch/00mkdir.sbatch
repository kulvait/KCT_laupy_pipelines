#!/bin/bash
#SBATCH --time=0-1:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/00mkdir-%N-%j.out
#SBATCH --error=log/00mkdir-%N-%j.err
#SBATCH --partition=allcpu

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Initialize positional arguments
WD=""
DIR=""
# Initialize optional argument
PARENTS=false


# Function to print usage and exit
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <DIR>

Create a directory.

Options:
  -p                          Create missing parent directories; allow DIR to exist.
  -h, --h, --help              Show this help message and exit successfully.

Positional arguments:
  WD                          Existing working directory.
  DIR                         Directory to create, relative to WD or absolute.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -p)
            PARENTS=true
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
            elif [ -z "$DIR" ]; then
                DIR="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done


# Check if the number of parameters is 2
if [ -z "$WD" ] || [ -z "$DIR" ]; then
    echo "Error: Missing required arguments" >&2
    usage
fi

# Check if WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

cd $WD

# Check if FILE is a file or Directory or a wildcard pattern

# Execute the command
if [ "$PARENTS" = true ]; then
    CMD="mkdir -p"
else
    CMD="mkdir"
fi
echo "Executing: $CMD $DIR"
$CMD $DIR
