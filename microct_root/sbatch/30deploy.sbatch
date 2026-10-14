#!/bin/bash
#SBATCH --time=0-03:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --partition=allcpu,allgpu
#SBATCH --output=log/30deploy-%N-%j.out
#SBATCH --error=log/30deploy-%N-%j.err

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Arguments
WD=""
DEPLOY_SOURCE=""
DEPLOY_MODE="copy"
FORCE=false
ZAR_TO_TIFF=false
TARGET_NAME=""

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi

    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS] <WD> <DEPLOY_SOURCE>

Deploy reconstruction results into the processed directory.

Deployment modes:
  copy       Recursively copy DEPLOY_SOURCE directory into DEPLOY_TARGET.
             Result: DEPLOY_TARGET/<DEPLOY_SOURCE> contains a full copy.

  symlink    Copy DEPLOY_SOURCE to DEPLOY_TARGET, then replace the copied
             directory with a symbolic link pointing to the original source.

  process    Copy the *contents* of DEPLOY_SOURCE into DEPLOY_TARGET.
             Optionally performs transformations (e.g. .zarr → .tiff).

Options:
  --mode <copy|symlink|process>
        Select deployment mode (default: copy).

  --target-name <name>
        For mode copy or symlink, specify the name of the directory created in DEPLOY_TARGET
        

  --zarr-to-tiff
        When used with --mode process, convert .zarr datasets into
        directories of .tiff files during deployment.

  --force
        Overwrite existing files or directories in DEPLOY_TARGET.

  -h, --help
        Show this help message and exit.

Positional Arguments:
  WD               Working directory where deployment will be performed.
  DEPLOY_SOURCE    File or directory to deploy

Examples:
  ${scriptname} /data/run1
  ${scriptname} --mode process --zarr-to-tiff /data/run1
  ${scriptname} --mode symlink /data/run1 custom_source_dir

EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
		--mode)
			DEPLOY_MODE="$2"
			shift 2
			;;
		--zarr-to-tiff)
			ZAR_TO_TIFF=true
			shift
			;;
		--target-name)
			TARGET_NAME="$2"
			shift 2
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
            echo "Unknown option $1" >&2
            usage error
	    	exit 1
            ;;
        *)
            if [[ -z "${WD:-}" ]]; then
                WD="$1"
            elif [[ -z "${DEPLOY_SOURCE:-}" ]]; then
				DEPLOY_SOURCE="$1"
	    	else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done

case "$DEPLOY_MODE" in
    copy|symlink|process)
        ;;
    *)
        echo "Error: Invalid --mode '$DEPLOY_MODE'. Must be one of: copy, symlink, process." >&2
        exit 1
        ;;
esac

#For process there does not need to be a target name, for copy and symlink there needs to be a target name
if [[ "$DEPLOY_MODE" == "process" ]]; then
    if [[ -n "${TARGET_NAME:-}" ]]; then
		echo "Error: --target-name is invalid when --mode is 'process'. It is only applicable for 'copy' and 'symlink' modes." >&2
		exit 1
    fi
fi

# Check required args
if [[ -z "${WD:-}" || -z "${DEPLOY_SOURCE:-}" ]]; then
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

# --- Validate DEPLOY_SOURCE existence ---
if [ ! -e "$DEPLOY_SOURCE" ]; then
    echo "Error: DEPLOY_SOURCE '$DEPLOY_SOURCE' does not exist." >&2
    exit 1
fi

# --- Mode-specific validation ---
if [ "$DEPLOY_MODE" = "process" ]; then
    if [ ! -d "$DEPLOY_SOURCE" ]; then
        echo "Error: In 'process' mode, DEPLOY_SOURCE must be a directory." >&2
        exit 1
    fi
fi

if [[ "$ZAR_TO_TIFF" == true ]]; then
   	source initZarr
fi


#If processed folder exist or is symlink copy it to target variable
#I have to figure out part of real abspath of current folder which ends with "scratch_cc"
#E.g. from /asap3/petra3/gpfs/p05/2025/data/11023208/scratch_cc/kct_P05SANDSILT/wd/samplefolder 
CURRENTPATH=$(pwd -P)
DIRNAME=$(basename "$CURRENTPATH")
SCRATCHPATH=$(echo "$CURRENTPATH" | sed 's/\(.*scratch_cc\).*/\1/')
#Test if SCRATCHPATH exists and end with scratch_cc
if [ ! -d "$SCRATCHPATH" ] || [[ "$SCRATCHPATH" != *scratch_cc ]]; then
	echo "Error: Current path does not contain 'scratch_cc' or 'scratch_cc' folder does not exist."
	exit 1
fi
#Get parent path
BEAMTIMEPATH=$(dirname "$SCRATCHPATH")
PROCESSEDPATH="$BEAMTIMEPATH/processed"
RAWPATH="$BEAMTIMEPATH/raw"
SCRATCHPATH="$BEAMTIMEPATH/scratch_cc"
#Test if all three folders exist
if [ -d "$PROCESSEDPATH" ] && [ -d "$RAWPATH" ] && [ -d "$SCRATCHPATH" ]; then
	DEPLOYTARGET="$PROCESSEDPATH/$DIRNAME"
else
	echo "Error: 'processed', 'raw' or 'scratch_cc' folder does not exist."
	exit 1
fi

# --- Step 1: Ensure DEPLOYTARGET is a directory ---
if [ -e "$DEPLOYTARGET" ]; then
    if [ ! -d "$DEPLOYTARGET" ]; then
        echo "Error: '$DEPLOYTARGET' exists but is not a directory."
        exit 1
    fi
else
    mkdir -p "$DEPLOYTARGET" || {
        echo "Error: Failed to create '$DEPLOYTARGET'"
        exit 1
    }
fi
echo "Deploy target: $DEPLOYTARGET"

# --- Step 2: Ensure 'processed' symlink points to DEPLOYTARGET ---
LINK_NAME="processed"

if [ -L "$LINK_NAME" ]; then
    CURRENT_TARGET=$(readlink -f "$LINK_NAME")

    if [ "$CURRENT_TARGET" != "$DEPLOYTARGET" ]; then
        rm "$LINK_NAME"
        ln -s "$DEPLOYTARGET" "$LINK_NAME"
    fi
elif [ -e "$LINK_NAME" ]; then
    # Exists but is NOT a symlink → error (as you requested)
    echo "Error: '$LINK_NAME' exists and is not a symlink."
    exit 1
else
    # Does not exist → create symlink
    ln -s "$DEPLOYTARGET" "$LINK_NAME"
fi


function copy_if_exists {
    local src="$1"
    local dest="$2"
    local target_name="${3:-}"

    if [ ! -e "$src" ]; then
        echo "Warning: '$src' does not exist and will be skipped."
        return 1
    fi

    local base target

    if [[ -n "$target_name" ]]; then
        base="$target_name"
    else
        base=$(basename "$src")
    fi

    target="$dest/$base"

    if [ -e "$target" ]; then
        if [ "$FORCE" = true ]; then
            echo "Overwriting existing '$target'"
            rm -rf "$target"
        else
            echo "Error: '$target' already exists (use --force to overwrite)"
            return 1
        fi
    fi

    cp -r "$src" "$target"
}

function deploy_to_target {
    local src="${1%/}"
    local dest="$2"
    local target_name="${3:-}"

    if [ ! -e "$src" ]; then
        echo "Warning: '$src' does not exist and will be skipped."
        return 1
    fi

    local src_base dest_dir final_dest link_name

    src_base=$(basename "$src")
    link_name="$src"   # symlink keeps original name

    if [ -d "$dest" ] || [[ "$dest" == */ ]]; then
        dest_dir="$dest"

        if [[ -n "$target_name" ]]; then
            final_dest="$dest_dir/$target_name"
        else
            final_dest="$dest_dir/$src_base"
        fi
    else
        dest_dir=$(dirname "$dest")
        final_dest="$dest"
    fi

    mkdir -p "$dest_dir"
    dest_dir=$(readlink -f "$dest_dir")
    final_dest="$dest_dir/$(basename "$final_dest")"

    if [ -e "$final_dest" ]; then
        if [ "$FORCE" = true ]; then
            echo "Overwriting existing '$final_dest'"
            rm -rf "$final_dest"
        else
            echo "Error: '$final_dest' already exists (use --force to overwrite)"
            return 1
        fi
    fi

    mv "$src" "$final_dest"

    # recreate symlink with ORIGINAL name
    ln -sfn "$final_dest" "$link_name"
}

if [ "$DEPLOY_MODE" == "copy" ]; then
    echo "Deploying in 'copy' mode..."
    copy_if_exists "$DEPLOY_SOURCE" "$DEPLOYTARGET" "$TARGET_NAME"
elif [ "$DEPLOY_MODE" == "symlink" ]; then
    echo "Deploying in 'symlink' mode..."
    deploy_to_target "$DEPLOY_SOURCE" "$DEPLOYTARGET" "$TARGET_NAME"
elif [ "$DEPLOY_MODE" == "process" ]; then
    echo "Deploying in 'process' mode..."
	shopt -s nullglob
		for ITM in "$DEPLOY_SOURCE"/*; do
	        if [[ "$ZAR_TO_TIFF" == true ]] && [[ "$ITM" == *.zar ]]; then
				tmpdir=$(mktemp -d -p . tmp_30deploy.XXXXXX)
		    	# Implement zarr to tiff conversion logic here
		    	ITEMNAME=$(basename "${ITM%.zar}")
		        zarrToDen.py "${ITM}:/" "${tmpdir}/${ITEMNAME}.den"
                denFilesToTifFiles.py --prefix "vk_cgls_${DIRNAME}_" "${tmpdir}/${ITEMNAME}.den" "${tmpdir}/${ITEMNAME}"
                copy_if_exists "${tmpdir}/${ITEMNAME}" "$DEPLOYTARGET"
				rm -rf "$tmpdir"
			else
		    	copy_if_exists "$ITM" "$DEPLOYTARGET"
			fi
		done
	shopt -u nullglob
else
    echo "Error: Unknown deployment mode '$DEPLOY_MODE'."
    exit 1
fi

#Copy JSON from raw_zarr to DEPLOYTARGET as info.json
#copy_if_exists "raw_zarr/zarr.json" "$DEPLOYTARGET/info.json"
#Copy reconstruction folders recb2_cgls_bro_v20_0.0005 and recb2_cgls_bro_v20_0.0005_tv to DEPLOYTARGET 
#deploy_to_target "recb2_cgls_bro_v20_0.0005" "$DEPLOYTARGET"
#deploy_to_target "recb2_cgls_bro_v20_0.0005_tv" "$DEPLOYTARGET"

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
