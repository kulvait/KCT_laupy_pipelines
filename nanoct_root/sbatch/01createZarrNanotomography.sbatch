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
LOGFILE=""
RAW_DIR=""
WD=""
FOREIGN_LOG_FILE=""
FOREIGN_RAW_DIR=""
ZIP=false
COMPRESSION="zstd"
CLEVEL=5
BITSPERSAMPLE=""
OUTPUT_PREFIX="raw_zarr"
V2=false
THREADS=0
NO_CHECK_BLOCK_ORDER=false
ZERO_BASED_LOCAL_INDICES=false

usage() {
	local mode="${1:-help}"
	local out=1
	if [[ "$mode" == "error" ]]; then
		out=2
	fi
	cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <LOGFILE> <RAWDIR> <WD>
Options:
  --zip                       Create a zip file instead of a directory for the Zarr output.
  --compression <type>        Compression type for the Zarr output (default: zstd).
  --clevel <level>            Compression level (default: 5).
  --bitspersample <bits>      Optional image-codec bit depth.
  --v2                        Use Zarr v2 format instead of v3.
  --output-prefix <prefix>    Prefix for the output Zarr file or directory (default: raw_zarr).
  --foreign-log-file <file>   Separate measurement whose reference images supply dark fields.
  --foreign-raw-dir <dir>     Foreign TIFF directory; defaults to the foreign log directory.
  --no-check-block-order      Disable time-order versus counter-order validation.
  --zero-based-local-indices   Interpret the last index in multi-number TIFF names as zero-based.
  -j, --threads <num>         Number of threads to use (-1 automatic, 0 sequential).
  -h, --help                  Show this help message and exit.

Positional Arguments:
  LOGFILE                     Main acquisition's LogScan.log.
  RAWDIR                      Main TIFF directory.
  WD                          Working directory where the Zarr structure will be created.
EOF
}

require_value() {
	if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
		echo "Error: Option $1 requires a value." >&2
		usage error
		exit 1
	fi
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"
	case $key in
		--zip)
			ZIP=true
			shift
			;;
		--compression)
			require_value "$@"
			COMPRESSION="$2"
			shift 2
			;;
		--clevel)
			require_value "$@"
			CLEVEL="$2"
			shift 2
			;;
		--bitspersample)
			require_value "$@"
			BITSPERSAMPLE="$2"
			shift 2
			;;
		--v2)
			V2=true
			shift
			;;
		--output-prefix)
			require_value "$@"
			OUTPUT_PREFIX="$2"
			shift 2
			;;
		--foreign-log-file)
			require_value "$@"
			FOREIGN_LOG_FILE="$2"
			shift 2
			;;
		--foreign-raw-dir)
			require_value "$@"
			FOREIGN_RAW_DIR="$2"
			shift 2
			;;
		--no-check-block-order)
			NO_CHECK_BLOCK_ORDER=true
			shift
			;;
		--zero-based-local-indices)
			ZERO_BASED_LOCAL_INDICES=true
			shift
			;;
		-j|--threads)
			require_value "$@"
			THREADS="$2"
			shift 2
			;;
		-h|--help)
			usage help
			exit 0
			;;
		-*)
			echo "Unknown option $1" >&2
			usage error
			exit 1
			;;
		*)
			POSITIONAL+=("$1")
			shift
			;;
	esac
done

if [[ ${#POSITIONAL[@]} -ne 3 ]]; then
	echo "Error: Expected 3 positional arguments <LOGFILE> <RAWDIR> <WD>, got ${#POSITIONAL[@]}." >&2
	usage error
	exit 1
fi

LOGFILE="${POSITIONAL[0]}"
RAW_DIR="${POSITIONAL[1]}"
WD="${POSITIONAL[2]}"

echo "LOGFILE=$LOGFILE"
echo "RAW_DIR=$RAW_DIR"
echo "WD=$WD"

if [[ ! -f "$LOGFILE" ]]; then
	echo "Error: Log file does not exist: $LOGFILE" >&2
	exit 1
fi
if [[ ! -d "$RAW_DIR" ]]; then
	echo "Error: Raw directory does not exist: $RAW_DIR" >&2
	exit 1
fi
if [[ ! -d "$WD" ]]; then
	echo "Error: Working directory does not exist: $WD" >&2
	exit 1
fi
if [[ -n "$FOREIGN_LOG_FILE" && ! -f "$FOREIGN_LOG_FILE" ]]; then
	echo "Error: Foreign log file does not exist: $FOREIGN_LOG_FILE" >&2
	exit 1
fi
if [[ -n "$FOREIGN_RAW_DIR" && ! -d "$FOREIGN_RAW_DIR" ]]; then
	echo "Error: Foreign raw directory does not exist: $FOREIGN_RAW_DIR" >&2
	exit 1
fi
if [[ -n "$FOREIGN_RAW_DIR" && -z "$FOREIGN_LOG_FILE" ]]; then
	echo "Error: --foreign-raw-dir requires --foreign-log-file." >&2
	exit 1
fi

LOGFILE="$(realpath "$LOGFILE")"
RAW_DIR="$(realpath "$RAW_DIR")"
if [[ -n "$FOREIGN_LOG_FILE" ]]; then
	FOREIGN_LOG_FILE="$(realpath "$FOREIGN_LOG_FILE")"
fi
if [[ -n "$FOREIGN_RAW_DIR" ]]; then
	FOREIGN_RAW_DIR="$(realpath "$FOREIGN_RAW_DIR")"
fi

cd "$WD" || { echo "Failed to cd into $WD" >&2; exit 1; }

source initZarr

ARG=()
ARG+=("--force")
ARG+=("-j" "$THREADS")
ARG+=("--raw-dir" "$RAW_DIR")

if [[ "$ZIP" == true ]]; then
	ARG+=("--zip")
	OUTPUT="${OUTPUT_PREFIX}.zar"
else
	OUTPUT="${OUTPUT_PREFIX}"
fi

case "$COMPRESSION" in
	zstd|jpeg2k|avif|htj2k|jpegxr|jpegxl|sz3|zfp|none|lz4|gzip|blosc|blosc-blosclz|blosc-lz4|blosc-lz4hc|blosc-snappy|blosc-zlib|blosc-zstd)
		ARG+=("--compression" "$COMPRESSION")
		;;
	*)
		echo "Error: Invalid compression type: $COMPRESSION" >&2
		exit 1
		;;
esac

ARG+=("--clevel" "$CLEVEL")

if [[ -n "$BITSPERSAMPLE" ]]; then
	ARG+=("--bitspersample" "$BITSPERSAMPLE")
fi

if [[ "$V2" == true ]]; then
	ARG+=("--v2")
fi
if [[ "$NO_CHECK_BLOCK_ORDER" == true ]]; then
	ARG+=("--no-check-block-order")
fi
if [[ "$ZERO_BASED_LOCAL_INDICES" == true ]]; then
	ARG+=("--zero-based-local-indices")
fi
if [[ -n "$FOREIGN_LOG_FILE" ]]; then
	ARG+=("--foreign-log-file" "$FOREIGN_LOG_FILE")
fi
if [[ -n "$FOREIGN_RAW_DIR" ]]; then
	ARG+=("--foreign-raw-dir" "$FOREIGN_RAW_DIR")
fi

tiffScanDataToZarrForNanotomography "${ARG[@]}" "$LOGFILE" "$OUTPUT"

# Create param.json from zarr.json
if [[ "$ZIP" == true ]]; then
	tmp_dir=$(mktemp -d "./tmp_01createZarrStructure_XXXXXX")
	unzip -j "$OUTPUT" "zarr.json" -d "$tmp_dir" && mv "$tmp_dir/zarr.json" ./param.json
	rmdir "$tmp_dir"
else
	if [[ "$V2" == true ]]; then
		cp "$OUTPUT/.zattrs" param.json
	else
		cp "$OUTPUT/zarr.json" param.json
	fi
fi

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
