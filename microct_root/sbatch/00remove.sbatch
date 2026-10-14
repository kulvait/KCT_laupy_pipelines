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
FILE=""
# Initialize optional argument
RECURSIVE=false
FORCE=false


# Function to print usage and exit
usage() {
    echo "Usage: $0 [-r] [-f] <WD> <FILE>" >&2
    echo
    echo "Options:"
    echo "  -r                          Remove recursively"
    echo "  -f                          Force removal"
    echo
    echo "Positional arguments:"
    echo "  WD                          Working directory"
    echo "  FILE                         Input file extension or name"
    exit 1
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -f)
            FORCE=true
            shift
            ;;
        -r)
            RECURSIVE=true
            shift
            ;;
        -*)
            echo "Unknown option $1" >&2
            usage
            ;;
        *)
            if [ -z "$WD" ]; then
                WD="$1"
            elif [ -z "$FILE" ]; then
                FILE="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage
            fi
            shift
            ;;
    esac
done


# Check if the number of parameters is 2
if [ -z "$WD" ] || [ -z "$FILE" ]; then
    usage
fi

# Check if WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

cd $WD

# Check if FILE is a file or Directory or a wildcard pattern
if [[ "$FILE" == *"*"* ]]; then
    # If it's a wildcard pattern, check if it matches any files
    if ! ls $FILE 1> /dev/null 2>&1; then
		echo "Warning: No files match the pattern $FILE" >&2
		exit 0 # Exit with success since there's nothing to remove
    fi
else
    # If it's not a wildcard pattern, check if it's a file or directory
    if [ -d "$FILE" ]; then
	    true
    elif [ -f "$FILE" ]; then
	    true
    else
	    echo "Error: $FILE is not a file or directory" >&2
	    exit 1
    fi
fi

CMD="rm"
if [ "$FORCE" = true ]; then
    CMD="$CMD -f"
fi
if [ "$RECURSIVE" = true ]; then
    CMD="$CMD -r"
fi

# Execute the command
echo "Executing: $CMD $FILE"
$CMD $FILE
