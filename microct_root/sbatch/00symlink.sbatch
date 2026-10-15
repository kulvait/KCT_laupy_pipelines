#!/bin/bash
#SBATCH --time=0-1:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/00symlink-%N-%j.out
#SBATCH --error=log/00symlink-%N-%j.err
#SBATCH --partition=allcpu

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Positional arguments
WD=""
SOURCE=""
TARGET=""

# Optional arguments
FORCE=false

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <SOURCE> <TARGET>

Options:
  --force                     Overwrite existing target if it exists.
  -h, --h, --help                 Show this help message and exit.

Positional Arguments:
  WD                          Working directory.
  SOURCE                      Source file or directory to link to.
  TARGET                      Symlink path to create.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case "$key" in
        --force)
            FORCE=true
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
            if [[ -z "${WD:-}" ]]; then
                WD="$1"
                echo "WD=$WD"
            elif [[ -z "${SOURCE:-}" ]]; then
                SOURCE="$1"
                echo "SOURCE=$SOURCE"
            elif [[ -z "${TARGET:-}" ]]; then
                TARGET="$1"
                echo "TARGET=$TARGET"
            else
                echo "Unexpected argument: $1" >&2
                usage error
                exit 1
            fi
            shift
            ;;
    esac
done

# Check required args
if [[ -z "${WD:-}" || -z "${SOURCE:-}" || -z "${TARGET:-}" ]]; then
    echo "Error: Missing required positional arguments." >&2
    usage error
    exit 1
fi

# Check working directory exists
if [[ ! -d "$WD" ]]; then
    echo "Error: Working directory does not exist: $WD" >&2
    exit 1
fi

cd "$WD" || { echo "Failed to cd into $WD"; exit 1; }

# Check source exists
if [[ ! -e "$SOURCE" ]]; then
    echo "Error: Source does not exist: $SOURCE" >&2
    exit 1
fi

# Ensure target directory exists
TARGET_DIR="$(dirname "$TARGET")"
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

SOURCE_ABSOLUTE=$(realpath -e -- "$SOURCE")

CMD=(ln -sT)
if [[ "$FORCE" == true ]]; then
    CMD+=(-f)
fi

printf 'Executing:'
printf ' %q' "${CMD[@]}" -- "$SOURCE_ABSOLUTE" "$TARGET"
printf '\n'
"${CMD[@]}" -- "$SOURCE_ABSOLUTE" "$TARGET"

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
