#!/bin/bash
#SBATCH --time=0-12:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=06computeExtinction
#SBATCH --output=log/06computeExtinction-%N-%j.out
#SBATCH --error=log/06computeExtinction-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# === Defaults ===
WD=""
REF="ref.den"
IMG="img.den"
OUT="ext.den"
KEEP_INPUT_FILES=true
FORCE=false
PHASECONTRAST=true

# === Usage function ===
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD>

Arguments:
  WD                          Working directory

Options:
  --ref <file>                Reference file (default: ${REF})
  --img <file>                Image file (default: ${IMG})
  --out <file>                Output file (default: ${OUT})
  --force                     Overwrite output file if it already exists
  --remove-input-files        Delete input files after successful processing
  --no-phase-contrast         Enable claming IMG to REF to avoid negative extinction values (default: NOT clamping IMG to REF to allow negative extinction values possible in phase contrast)
  --h, --help                 Show this help message and exit

EOF
}

# === Parse command line arguments ===
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --ref)
            if [[ -z $2 || $2 =~ ^- ]]; then
                echo "Error: --ref requires a file argument"
                usage error
				exit 1
            fi
            REF="$2"
            shift 2
            ;;

        --img)
            if [[ -z $2 || $2 =~ ^- ]]; then
                echo "Error: --img requires a file argument"
                usage error
				exit 1
            fi
            IMG="$2"
            shift 2
            ;;

        --out)
            if [[ -z $2 || $2 =~ ^- ]]; then
                echo "Error: --out requires a file argument"
                usage error
				exit 1
            fi
            OUT="$2"
            shift 2
            ;;
        --remove-input-files)
            KEEP_INPUT_FILES=false
            shift
            ;;
		--no-phase-contrast)
		    PHASECONTRAST=false
	    	shift
	    	;;
		--force)
			FORCE=true
			shift
			;;
		--h|--help)
	    	usage help
	    	exit 0
	    	;;
        -*)
            echo "Unknown option: $1"
            usage error
			exit 1
            ;;

        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL_ARGS[@]} -ne 1 ]]; then
    echo "Error: Expected exactly one positional argument for working directory (WD) but got ${#POSITIONAL_ARGS[@]}"
    usage error
    exit 1
fi

WD="${POSITIONAL_ARGS[0]}"

#Start script
source initGanrec

cd "$WD" || { echo "Error: Cannot change to working directory $WD" >&2 ; exit 1; }

if [ ! -f "${REF}" ]; then
    echo "Error: Reference file ${REF} does not exist." >&2
    exit 1
fi

if [ ! -f "${IMG}" ]; then
    echo "Error: Image file ${IMG} does not exist." >&2
    exit 1
fi

if [ -f "${OUT}.den" ] && [ "$FORCE" = false ]; then
    echo "Error: Output file ${OUT}.den already exists. Use --force to overwrite." >&2
    exit 1
fi


ARG=()
if [ "$FORCE" = true ]; then
    ARG+=("--force")
fi

function computeExtinction()
{
	local FLAT_IN="$1"
	local IMG_IN="$2"
	local EXT_OUT="$3"

	 # Base names only for temp file naming (no path, no extension)
	local FLAT_BASE=$(basename "${FLAT_IN}" .den)
	local IMG_BASE=$(basename "${IMG_IN}" .den)
	# Create a unique temporary directory in the current working directory
	local TMPDIR=$(mktemp -d -p . "tmp_06computeExtinction_XXXXXX")
	# Check if the directory was created successfully
	if [ ! -d "$TMPDIR" ]; then
    	echo "Failed to create temporary directory."
    	exit 1
	fi
	dentk-framecalc1 --avg "${FLAT_IN}" "${TMPDIR}/${FLAT_BASE}_avg"
	#Calculate double softplus of average flatfield to make it positive
	dentk-calc1 --double-softplus "${TMPDIR}/${FLAT_BASE}_avg" "${TMPDIR}/${FLAT_BASE}_cor"
	#Calculate double softplus of average img data to make it positive
	dentk-calc1 --double-softplus "${IMG_IN}" "${TMPDIR}/${IMG_BASE}_softplus"
	if [ "$PHASECONTRAST" = true ]; then
		mv "${TMPDIR}/${IMG_BASE}_softplus" "${TMPDIR}/${IMG_BASE}_cor"
	else
	    #START does not apply for phase contrast
	    dentk-framecalc --min "${TMPDIR}/${IMG_BASE}_softplus" "${TMPDIR}/${FLAT_BASE}_cor" "${TMPDIR}/${IMG_BASE}_cor"
	    #END does not apply for phase contrast
	fi
	dentk-framecalc --flipped-divide "${TMPDIR}/${IMG_BASE}_cor" "${TMPDIR}/${FLAT_BASE}_cor" "${TMPDIR}/tra_inv"
	dentk-calc1 "${ARG[@]}" --log "${TMPDIR}/tra_inv" "${EXT_OUT}"
	rm -rf "$TMPDIR"
	# Optionally remove input files to save space
    if [ "$KEEP_INPUT_FILES" = false ] && [ -f "${EXT_OUT}" ]; then
		rm -f "${FLAT_IN}"
	    rm -f "${IMG_IN}"
	fi
}

#computeExtinction ref_clean_darksub_curcor.den img_clean_darksub_curcor.den ext_curcor.den
computeExtinction "$REF" "$IMG" "$OUT"

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
