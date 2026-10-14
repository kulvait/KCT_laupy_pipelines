#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --job-name=detectCenter
#SBATCH --output=log/detectRotationCenter_sinogram-%N-%j.out
#SBATCH --error=log/detectRotationCenter_sinogram-%N-%j.err

# --- Default ext filename ---
EXT="ext_legacy.den"

# --- Parse optional arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ext)
      EXT="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 <working_directory> [--ext ext_filename]"
      exit 0
      ;;
    --*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      # First non-option argument is working directory but arguments can and typically will be passed after that
      WD="$1"
      shift
      ;;
  esac
done

if [ -z "$WD" ]; then
  echo "Error: Working directory not specified."
  echo "Usage: $0 <working_directory> [--ext ext_filename]"
  exit 1
elif [ ! -d "$WD" ]; then
  echo "Error: Directory $WD does not exist."
  exit 1
fi

# --- Change to working directory ---
cd "$WD" || { echo "Error: Could not change to directory $WD"; exit 1; }


# --- Load environment ---
source initGanrec
source sourcePath

# --- Prepare output directories and filenames ---
LOGDIR="log/detectRotationCenter"
mkdir -p "${LOGDIR}"

PYTHON_SCRIPT_BASENAME="detectRotationCenterNew"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
PDF_PATH="${LOGDIR}/${PYTHON_SCRIPT_BASENAME}_${TIMESTAMP}.pdf"

EXT_BASE=$(basename "$EXT" .den)
LOGFILE="${EXT_BASE}_rotationcenter.log"
SINOGRAMS="${EXT_BASE}_sinograms.den"

# --- Start timer ---
START_TIME=$(date +%s)

# --- Run detection ---
detectRotationCenterNew.py \
    --force \
    --input-h5 h5 \
    --store-sinograms "$SINOGRAMS" \
    --angle-count 1800 \
    --ord 0 \
    --sinogram-consistency "$EXT" \
    --log-file "$LOGFILE" \
    --savefig "${PDF_PATH}"

if [ $? -ne 0 ]; then
    echo "detectRotationCenterNew.py failed."
    exit 1
fi

# --- End timer and report ---
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))
ELAPSED_FMT=$(printf "%02d:%02d:%02d" $HOURS $MINUTES $SECONDS)

echo "07detectRotationCenter_sinogramConsistency.sbatch completed successfully, results in $LOGFILE and plots in $PDF_PATH, elapsed time: $ELAPSED_FMT."
