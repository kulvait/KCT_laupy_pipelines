#!/bin/bash
#SBATCH --time=0-1:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/00move-%N-%j.out
#SBATCH --error=log/00move-%N-%j.err
#SBATCH --partition=allcpu

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Initialize positional arguments
WD=""
SOURCE=""
TARGET=""
# Initialize optional argument


# Function to print usage and exit
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <SOURCE> <TARGET>

Move or rename a file or directory.

Options:
  -h, --h, --help              Show this help message and exit successfully.

Positional arguments:
  WD                          Existing working directory.
  SOURCE                      Source file or directory.
  TARGET                      Destination name or existing destination directory.

Relative SOURCE and TARGET paths are interpreted from WD.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -*)
            echo "Unknown option $1" >&2
            usage error
			exit 1
            ;;
		-h|--h|--help)
	    	usage help
	    	exit 0
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
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done


# Check if the number of parameters is 3
if [ -z "$WD" ] || [ -z "SOURCE" ] || [ -z "$TARGET" ]; then
    echo "Error: Missing required arguments" >&2
    usage error
    exit 1
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
