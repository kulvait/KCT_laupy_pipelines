#!/bin/bash
#SBATCH --time=0-09:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/01createZarrStructure-%N-%j.out
#SBATCH --error=log/01createZarrStructure-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Arguments
WD=""
ZIP=false
COMPRESSION="zstd"
NOCOMP=false
JPEG2K=false
HTJ2K=false
AVIF=false
JPEGXR=false
CLEVEL=5
OUTPUT_PREFIX="raw_zarr"
V2=false
THREADS=0

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD>
Options:
  --zip                       Create a zip file instead of a directory for the Zarr output.
  --compression <type>        Compression type for the Zarr output (default: zstd, other choices: jpeg2k, avif, htj2k, jpegxr, jpegxl, sz3, zfp, none).
  --v2                        Use Zarr v2 format instead of v3.
  --clevel <level>            Compression level (default: 5, for j2k 60-70 is recommended as this is PSNR based).
  --output-prefix <prefix>    Prefix for the output Zarr file or directory (default: raw_zarr).
  -j, --threads <num>         Number of threads to use (default: 0, which means auto-detect).
  --h, --help                 Show this help message and exit.

Positional Arguments:
  WD                          Working directory where the Zarr structure will be created.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
		--zip)
			ZIP=true
			shift
			;;
		--compression)
			COMPRESSION="$2"
			shift 2
			;;
		--v2)
			V2=true
			shift
			;;
		--clevel)
			CLEVEL="$2"
			shift 2
			;;
		--output-prefix)
			OUTPUT_PREFIX="$2"
			shift 2
			;;
		-j|--threads)
			THREADS="$2"
			shift 2
			;;
		--h|--help)
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

# Check required args
if [[ -z "${WD:-}" ]]; then
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

source initZarr
H5FILE=h5
RAWDIR=raw
ARG=()
ARG+=("--force")
ARG+=("-j" "$THREADS")
if [[ "$ZIP" == true ]]; then
	ARG+=("--zip")
	OUTPUT="${OUTPUT_PREFIX}.zar"
else
	OUTPUT="${OUTPUT_PREFIX}"
fi

#Check if compression is one of the allowed values
case "$COMPRESSION" in
    zstd|jpeg2k|avif|htj2k|jpegxr|jpegxl|sz3|zfp|none)
	ARG+=("--compression" "$COMPRESSION")
	;;
    *)
	echo "Error: Invalid compression type: $COMPRESSION" >&2
	exit 1
	;;
esac

ARG+=("--clevel" "$CLEVEL")
ARG+=("--raw-dir" "$RAWDIR")

if [[ "$V2" == true ]]; then
	ARG+=("--v2")
fi

rawTiffStructureToZarr.py "${ARG[@]}" "$H5FILE" "$OUTPUT"

# Create param.json from zarr.json
if [[ "$ZIP" == true ]]; then
    tmp_dir=$(mktemp -d "./tmp_01createZarrStructure_XXXXXX")
    unzip -j "$OUTPUT" "zarr.json" -d "$tmp_dir" &&
        mv "$tmp_dir/zarr.json" ./param.json
    rmdir "$tmp_dir"
else
    if [[ "$V2" == true ]]; then
        cp "$OUTPUT/.zattrs" param.json
    else
        cp "$OUTPUT/zarr.json" param.json
    fi  
fi

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
