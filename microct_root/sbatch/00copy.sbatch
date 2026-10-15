#!/bin/bash
#SBATCH --time=0-1:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/00copy-%N-%j.out
#SBATCH --error=log/00copy-%N-%j.err
#SBATCH --partition=allcpu

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Initialize positional arguments
WD=""
SOURCE=""
TARGET=""

# Options
RECURSIVE=false


# Function to print usage and exit
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <SOURCE> <TARGET>

Copy files or directories.

Options:
  -r                          Copy directories recursively.
  -h, --h, --help              Show this help message and exit successfully.

Positional arguments:
  WD                          Existing working directory.
  SOURCE                      Source file, directory, or quoted wildcard pattern.
  TARGET                      Destination file or directory.
                              For multiple sources, TARGET must be a directory.

Relative SOURCE and TARGET paths are interpreted from WD.
Quote wildcard patterns to defer their expansion until after changing to WD.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
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
            elif [ -z "$SOURCE" ]; then
				SOURCE="$1"
	    	elif [ -z "$TARGET" ]; then
				TARGET="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done


# Check arguments
if [ -z "$WD" ] || [ -z "$SOURCE" ] || [ -z "$TARGET" ]; then
    echo "Error: Missing required arguments" >&2
    usage error
    exit 1
fi

# Check working directory exists
if [[ ! -d "$WD" ]]; then
    echo "Error: Working directory does not exist: $WD" >&2
    exit 1
fi

cd "$WD" || { echo "Failed to cd into $WD"; exit 1; }

# Check if SOURCE is a file or Directory or a wildcard pattern
if [[ "$SOURCE" == *"*"* ]]; then
    # If it's a wildcard pattern, check if it matches any files
    if ! ls $SOURCE 1> /dev/null 2>&1; then
		echo "Error: No files match the pattern $SOURCE" >&2
		exit 1
    fi
else
    # If it's not a wildcard pattern, check if it's a file or directory
    if [ -d "$SOURCE" ]; then
	    true
    elif [ -f "$SOURCE" ]; then
	    true
    else
	    echo "Error: $SOURCE is not a file or directory" >&2
	    exit 1
    fi
fi

CMD="cp -v"
if [ "$RECURSIVE" = true ]; then
    CMD="$CMD -r"
fi

# Execute the command
echo "Executing: $CMD $SOURCE $TARGET"
$CMD $SOURCE $TARGET

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
