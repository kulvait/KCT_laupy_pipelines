#!/bin/bash
#SBATCH --time=0-1:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/00move-%N-%j.out
#SBATCH --error=log/00move-%N-%j.err
#SBATCH --partition=allcpu

set -euo pipefail
scriptname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${scriptname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Initialize positional arguments
WD=""
SOURCE=""
TARGET=""
# Initialize optional argument


# Function to print usage and exit
usage() {
    echo "Usage: $0 <WD> <SOURCE> <TARGET>" >&2
    echo
    echo "Options:"
    echo
    echo "Positional arguments:"
    echo "  WD                          Working directory"
    echo "  FILE                        Source to rename"
    echo "  TARGET                      Target name"
    exit 1
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -*)
            echo "Unknown option $1" >&2
            usage
            ;;
        *)
            if [ -z "$WD" ]; then
                WD="$1"
                echo "WD=$WD"
            elif [ -z "$SOURCE" ]; then
                SOURCE="$1"
            elif [ -z "$TARGET" ]; then
		        TARGET="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage
            fi
            shift
            ;;
    esac
done


# Check if the number of parameters is 3
if [ -z "$WD" ] || [ -z "SOURCE" ] || [ -z "$TARGET" ]; then
    usage
fi

# Check if WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

cd $WD

# Execute the command
echo "Executing: mv $SOURCE $TARGET"
mv $SOURCE $TARGET
