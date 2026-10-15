#!/bin/bash
#SBATCH --time=0-23:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/00reconstructCGLS-%N-%j.out
#SBATCH --error=log/00reconstructCGLS-%N-%j.err
#SBATCH --partition=allgpu

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Initialize positional arguments
WD=""
EXT=""
# Initialize optional arguments
MAGNIFICATION=""
COR_ADDITIONALOFFSET_PIX=0.0
PWLS_VECTOR=""
#-v will change KEEPOUTPUTFILES to true
KEEPINPUTFILES=false
#-u will change TIFFOUTPUT to false
TIFFOUTPUT=true
ROTATIONAXISFILE="rotationaxis_EXT_360.log"
STRAIGHT_ROTATION_AXIS=false
BACKPROJECT_ONLY=false
BOXX=""
BOXY=""
GEOMETRY_INFO_FILE="h5"
BINNING=2
OUTPUT_PREFIX=""
OUTPUT_SUFFIX=""

# Function to print usage and exit
usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <EXT>

Reconstruct an extinction DEN file using CGLS, or perform backprojection only.

Options:
  --backproject               Perform backprojection only.
  --binning UINT              Binning factor (default: 2).
  --geometry-info FILE        Geometry information path (default: h5).
  -m MAGNIFICATION            Override magnification (default: not specified).
  -o OFFSET                   Additional COR offset in pixels (default: 0.0).
  --pwls-vector FILE          PWLS vector file (default: not specified).
  --rotation-axis-file FILE   Rotation-axis file (default: rotationaxis_EXT_360.log).
  --straight-rotation-axis    Assume a straight rotation axis without skew fitting.
  --volume-sizex SIZE         Override volume X size.
  --volume-sizey SIZE         Override volume Y size.
  --output-prefix PREFIX      Output prefix (default: recb<BINNING>).
  --output-suffix SUFFIX      Append a suffix to the generated output name.
  -u, --keep-input-files      Keep intermediate input files.
  -v, --den-output            Produce DEN output instead of TIFF output.
  -h, --h, --help              Show this help message and exit successfully.

Positional arguments:
  WD                          Existing working directory containing params.
  EXT                         Input extinction DEN file.

Relative file paths are interpreted from WD.
The default rotation-axis filename is literal: rotationaxis_EXT_360.log.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
		--backproject)
		    BACKPROJECT_ONLY=true
	    	shift
	    	;;
		--binning)
		    BINNING="$2"
	    	shift
	    	shift
	    	;;
        -m)
            MAGNIFICATION="$2"
            shift
            shift
            ;;
        -o)
            COR_ADDITIONALOFFSET_PIX="$2"
            shift
            shift
            ;;
        --rotation-axis-file)
            ROTATIONAXISFILE="$2"
            shift
            shift
            ;;
        --pwls-vector)
			if [ -n "$2" ] && [[ "$2" != -* ]]; then
				PWLS_VECTOR="$2"
				shift 2
			else
				echo "Error: --pwls-vector option requires an argument." >&2
				usage error
				exit 1
			fi
	    	;;
		--geometry-info)
			if [ -n "$2" ] && [[ "$2" != -* ]]; then
				GEOMETRY_INFO_FILE="$2"
				shift 2
			else
				echo "Error: --geometry-info option requires an argument." >&2
				usage error
				exit 1
			fi
	    	;;
        --output-prefix)
	    	OUTPUT_PREFIX="$2"
	    	shift 2
	    	;;
		--output-suffix)
	    	OUTPUT_SUFFIX="$2"
			shift 2
	    	;;
        -u|--keep-input-files)
            KEEPINPUTFILES=true
            shift
            ;;
        -v|--den-output)
            TIFFOUTPUT=false
            shift
            ;;
        --volume-sizex)
            BOXX="$2"
            shift
            shift
            ;;
        --volume-sizey)
            BOXY="$2"
            shift
            shift
            ;;
		--straight-rotation-axis)
		    STRAIGHT_ROTATION_AXIS=true
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
            elif [ -z "$EXT" ]; then
                EXT="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage error
	    		exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$OUTPUT_PREFIX" ]]; then
    OUTPUT_PREFIX="recb${BINNING}"
fi

# Check if the number of parameters is 2
if [ -z "$WD" ] || [ -z "$EXT" ]; then
	echo "Error: Missing required positional arguments." >&2
    usage error
	exit 1
fi

# Assign parameters to variables
PATH=$PATH:$PWD/bin

# Check if WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

cd $WD

# Check if EXT exists
if [ ! -f "$EXT" ]; then
    echo "Error: $EXT is not a file" >&2
    exit 1
fi

echo "WD=$WD"
echo "EXT=$EXT"
echo "ROTATIONAXISFILE=$ROTATIONAXISFILE"
if [[ "$COR_ADDITIONALOFFSET_PIX" != "0.0" ]]; then
	echo "COR_ADDITIONALOFFSET_PIX=$COR_ADDITIONALOFFSET_PIX"
fi
echo "BOXX=$BOXX"
echo "BOXY=$BOXY"

unset LD_PRELOAD
source initGanrec

#Start of the body of the script

function LoadModule()
{
    if module list 2>&1| grep -qw $1; then
        echo "Module $1 already loaded."
    else
        echo "Loading module $1."
        module load $1
    fi  
}

THREADS=`nproc --all`
ARX="--force -j ${THREADS}"

LoadModule maxwell
LoadModule cuda/11.8

source params
pixel_size_x=${pixel_size_x:-1}

PIXELSIZE=$(calc "${pixel_size_x}*${BINNING}")
ADDITIONALOFFSET=$(calc "${COR_ADDITIONALOFFSET_PIX}*${PIXELSIZE}")

EXTBASE=$(basename $EXT)
EXTBASE=${EXTBASE%.*}

if [[ "$BACKPROJECT_ONLY" != true ]]; then
    OUT="${OUTPUT_PREFIX}_cgls_${EXTBASE}"
else
    OUT="${OUTPUT_PREFIX}_backproject_${EXTBASE}"
fi

if [[ ${COR_ADDITIONALOFFSET_PIX} != 0.0 ]]; then
	OUT=${OUT}_offset${COR_ADDITIONALOFFSET_PIX}pix
fi

if [[ -n ${OUTPUT_SUFFIX} ]]; then
	OUT=${OUT}_${OUTPUT_SUFFIX}
fi

if [ ! -f $EXT ]; then
	echo "FIle $EXT does not exist!"
	exit 1
fi

SLICECOUNT=16

DIMX=$(dentk-info --dim $EXT  | cut -f1)
DIMY=$(dentk-info --dim $EXT  | cut -f2)
DIMZ=$(dentk-info --dim $EXT  | cut -f3)
FROM=0
TO=$( calc "${DIMY}-1" )
#FROM=$suggested_minindex
#TO=$suggested_maxindex

#Folowing can by sourced from params but I wish also to avoid unbound variable error if they are not set
if [[ -n ${zpos_min_pix:-} ]]; then
	FROM=$zpos_min_pix
fi
if [[ -n ${suggested_minindex_beam:-} ]]; then
	FROM=$suggested_minindex_beam
fi
if [[ -n ${zpos_max_pix:-} ]]; then
	TO=$zpos_max_pix
fi
if [[ -n ${suggested_maxindex_beam:-} ]]; then
	TO=$suggested_maxindex_beam
fi
if [[ -n ${zpos_zero_pix:-} ]]; then
	ZEROOFFSET=$zpos_zero_pix
else
	ZEROOFFSET=0.0
fi
#FROM=100
#TO=163

MODULUS=$(calc "(${TO} + 1 - ${FROM}) % ${SLICECOUNT}")
LAST=$(calc "${TO} - ${MODULUS}")
LASTSTART=$(calc "${TO} - ${MODULUS} + 1")

redis-server.init
#GPUCOUNT=$( redis-cli llen IDLEGPU )
#GPUCOUNT=$( redis-cli llen IDLEGPU )
GPUCOUNT=$( GPU.py --gpu-count )
if [[ $GPUCOUNT == 0 ]]; then
	echo "No GPU to run reconstruction!"
	exit 1
fi
PROCCOUNT=$( calc "2*$GPUCOUNT" )

#DEBUG
PID=0

# Get platform ID
PLATFORMID=$(platformID)

# Start building argument string
ARG=(
  --rotation-axis-file "$ROTATIONAXISFILE"
  -p "$PLATFORMID"
)
if [[ "$BACKPROJECT_ONLY" == true ]]; then
   ARG+=(-f)
fi

# Append optional arguments based on flags
if [[ -n "$MAGNIFICATION" ]]; then
    ARG+=(-q "$MAGNIFICATION")
fi

if [[ "$KEEPINPUTFILES" == true ]]; then
	ARG+=(-u)
fi

if [[ "$TIFFOUTPUT" == false ]]; then
	ARG+=(-v)
fi

if [[ -n "$PWLS_VECTOR" ]]; then
	ARG+=(--pwls-vector "$PWLS_VECTOR")
fi

# Add shared reconstruction parameters
ARG+=(
  -g "$ZEROOFFSET"
  -e "$COR_ADDITIONALOFFSET_PIX"
  -i "$EXT"
  -o "$OUT"
  -b "$BINNING"
  -w
)
ARG+=("--geometry-info" "$GEOMETRY_INFO_FILE")

# Add BOXX and BOXY if they are specified
if [ -n "$BOXX" ]; then
    ARG+=(--box-x "$BOXX")
fi

if [ -n "$BOXY" ]; then
	ARG+=(--box-y "$BOXY")
fi

if [[ "$STRAIGHT_ROTATION_AXIS" == true ]]; then
	ARG+=(--straight-rotation-axis)
fi

# Execute reconstruction jobs
tmpdir=$(mktemp -d -p . tmp_00reconstructCGLS_logs.XXXXXX)
job_ids=()
job_pids=()

run_job() {
    local start_index="$1"
    local slice_count="$2"
    local job_id="reconstructSlice2D_start${start_index}_count${slice_count}"

    echo "Starting reconstructSlice2D for start index $start_index and slice count $slice_count"

    job_ids+=("$job_id")

    (
        exit_code=0

        reconstructSlice2D ${ARG[@]} \
            --start-index "$start_index" \
            --slice-count "$slice_count" \
        || exit_code=$?

        echo "$exit_code" > "$tmpdir/exit_${job_id}"
    ) >"$tmpdir/out_${job_id}" 2>"$tmpdir/err_${job_id}" &

    job_pids+=($!)
}

if [[ "$MODULUS" -ne 0 ]]; then
    run_job "$LASTSTART" "$MODULUS"
fi

# Parallel job execution -n 1 is redundant because of use -I {} to silence warning -n 1 was not specified but it executes individual commands
if [[ "$LAST" -ge "$FROM" ]]; then
    for (( START_INDEX = FROM; START_INDEX <= LAST; START_INDEX += SLICECOUNT )); do
        run_job "$START_INDEX" "$SLICECOUNT"

        # limit parallelism
        while [ "$(jobs -rp | wc -l)" -ge "$PROCCOUNT" ]; do
            wait -n || true
        done
    done
fi

# Wait for all background jobs to finish
wait

# Collect exit codes and logs
FAILED_JOBS=0
for job_id in "${job_ids[@]}"; do
    exit_file="$tmpdir/exit_${job_id}"
    out_file="$tmpdir/out_${job_id}"
    err_file="$tmpdir/err_${job_id}"

    exit_code=999
    if [ -f "$exit_file" ]; then
		exit_code=$(cat "$exit_file")
    fi

    if [ "$exit_code" -ne 0 ]; then
	    FAILED_JOBS=$((FAILED_JOBS + 1))
    fi
    
    if [ -s "$out_file" ]; then
        echo "" 
    	if [ "$exit_code" -ne 0 ]; then
	    	echo "$job_id failed with code $exit_code. Stdout:" 
    	else
	    	echo "$job_id completed successfully. Stdout:"
    	fi
	    cat "$out_file"
    fi

    if [ -s "$err_file" ]; then
		echo "" >&2
        if [ "$exit_code" -ne 0 ]; then
	    	echo "$job_id failed with code $exit_code. Stderr:" >&2
		else
	    	echo "$job_id completed successfully. Stderr:" >&2
		fi
	    cat "$err_file" >&2
    fi

done

rm -rf "$tmpdir"

# Check if any jobs failed and exit with an error code if so
if [ "$FAILED_JOBS" -ne 0 ]; then
    echo "$FAILED_JOBS jobs failed. Check logs for details." >&2
fi

#DEBUG
#redis-server.shutdown

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"

# Check if any jobs failed and exit with an error code if so
if [ "$FAILED_JOBS" -ne 0 ]; then
    exit 1
fi
