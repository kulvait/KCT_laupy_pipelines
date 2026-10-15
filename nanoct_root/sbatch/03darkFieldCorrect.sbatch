#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/03darkFieldCorrect-%N-%j.out
#SBATCH --error=log/03darkFieldCorrect-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# === Default values ===
KEEP_INPUT_FILES=true
IMG="img_clean.den"
REF="ref_clean.den"
DARK="dar_clean.den"
WD=""

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD>

Options:
  --img <file>                Input image file (default: img_clean.den)
  --ref <file>                Input reference file (default: ref_clean.den)
  --dar <file>                Input dark field file (default: dar_clean.den)
  --remove-input-files        Delete input files after successful processing
  -h, --h, --help             Show this help message and exit.

Arguments:
  WD                          Working directory
EOF
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --remove-input-files)
            KEEP_INPUT_FILES=false
            shift
            ;;
        --img)
            IMG="$2"
            shift 2
            ;;
        --ref)
            REF="$2"
            shift 2
            ;;
        --dar)
            DARK="$2"
            shift 2
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
            else
                echo "Unexpected argument: $1" >&2
                usage error
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "${WD:-}" ]]; then
    echo "Error: Missing required positional arguments." >&2
    usage error
    exit 1
fi

if [[ ! -d "$WD" ]]; then
    echo "Error: Working directory does not exist: $WD" >&2
    exit 1
fi

cd "$WD" || { echo "Failed to cd into $WD"; exit 1; }

ARG="--force -j -1"

testExistence() {
    if [[ ! -f "$1" ]]; then
        echo "File $1 does not exist."
        exit 1
    fi
}

darkFieldCorrect() {
    local darkfield="$1"
    shift
    local inputs=("${!1}")
    shift
    local outputs=("${!1}")

    testExistence "$darkfield"

    if [[ ${#inputs[@]} -ne ${#outputs[@]} ]]; then
        echo "Number of inputs and outputs must match."
        exit 1
    fi

    tmpdir=$(mktemp -d -p . darkfield_temp_XXXX)
    echo "Using temporary directory: $tmpdir"
    dark_med="$tmpdir/dark_med.den"
    dentk-framecalc1 $ARG --median "$darkfield" "$dark_med"

    for ((i=0; i<${#inputs[@]}; i++)); do
        input="${inputs[$i]}"
        output="${outputs[$i]}"
        filename_in="$(basename "$input")"
        base_in="${filename_in%.den}"

        testExistence "$input"
        echo "Processing $input to produce $output"

        input_sub="$tmpdir/${base_in}_sub.den"
        dentk-framecalc $ARG --subtract "$input" "$dark_med" "$input_sub"
        dentk-calc1 $ARG --double-softplus "$input_sub" "$output"
    done

    echo "Cleaning up temporary directory: $tmpdir"
    rm -rf "$tmpdir"
}

mkdir -p log

inputs=("$IMG" "$REF")
suffix="_darksub"
darkfield="$DARK"
outputs=()

for input in "${inputs[@]}"; do
    base="${input%.*}"
    ext="${input##*.}"
    output="${base}${suffix}.${ext}"
    outputs+=("$output")
done

darkFieldCorrect "$darkfield" inputs[@] outputs[@]

if [[ $KEEP_INPUT_FILES == false ]]; then
    for input in "${inputs[@]}"; do
        if [[ -f "$input" ]]; then
            rm "$input"
            echo "Deleted input file: $input"
        fi
    done
    rm "$darkfield"
fi

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
