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
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <FILE>

Remove files or directories.

Options:
  -r                          Remove directories recursively.
  -f                          Force removal; ignore nonexistent files.
  -h, --h, --help              Show this help message and exit successfully.

Positional arguments:
  WD                          Existing working directory.
  FILE                        File, directory, or quoted wildcard pattern to remove.

Relative FILE paths are interpreted from WD.
Quote wildcard patterns to defer their expansion until after changing to WD.
An unmatched wildcard pattern produces a warning and exits successfully.
EOF
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
            elif [ -z "$FILE" ]; then
                FILE="$1"
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
		if [ "$FORCE" = true ]; then
			echo "Warning: $FILE does not exist, but force option is set. Proceeding." >&2
         	exit 0 # Exit with success since there's nothing to remove	
		else
	    	echo "Error: $FILE is not a file or directory" >&2
	    	exit 1
		fi
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
