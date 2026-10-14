#!/bin/bash
#SBATCH --time=0-1:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/00remove-%N-%j.out
#SBATCH --error=log/00remove-%N-%j.err
#SBATCH --partition=allcpu

set -euo pipefail
scriptname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${scriptname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Initialize positional arguments
WD=""
DIR=""
# Initialize optional argument
PARENTS=false


# Function to print usage and exit
usage() {
    echo "Usage: $0 [-r] [-f] <WD> <FILE>" >&2
    echo
    echo "Options:"
    echo "  -p      		Create parent directories as needed"
    echo
    echo "Positional arguments:"
    echo "  WD                          Working directory"
    echo "  DIR                         Directory to create"
    exit 1
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -p)
            PARENTS=true
            shift
            ;;
        -h|--help)
	        usage
	    	;;
        -*)
            echo "Unknown option $1" >&2
            usage
            ;;
        *)
            if [ -z "$WD" ]; then
                WD="$1"
            elif [ -z "$DIR" ]; then
                DIR="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage
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
