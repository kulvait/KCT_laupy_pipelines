#!/bin/bash
#SBATCH --time=0-23:00:00
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --output=log/28cropAndMask-%N-%j.out
#SBATCH --error=log/28cropAndMask-%N-%j.err
#SBATCH --partition=allgpu

set -euo pipefail
scriptname="${PIPELINE_SCRIPTNAME:-$(basename "$0")}"
jobname="${PIPELINE_JOBNAME:-$(basename "$0")}"
trap 'echo "[$(date)] ERROR in ${jobname}:${LINENO}: ${BASH_COMMAND}" >&2' ERR
echo "START ${jobname} $*"
start_time=$(date +%s)

# Default values
#I/0 parameters
WD=""
INPUT=""
OUTPUT=""
OUTPUT_IS_DEN=false
INPUT_IS_DEN=false
DELETE_INPUT=false
FORCE=false
#Program parameters
ODX=""
ODY=""
ODZ=""
RADIUS=""
RADIAL_CENTER_X=""
RADIAL_CENTER_Y=""
RADIAL_CENTER_OFFSET_X=""
RADIAL_CENTER_OFFSET_Y=""

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi  
    cat <<EOF >&${out}
Usage: $0 [OPTIONS] <WD> <INPUT> <OUTPUT>

Positional arguments:
  WD                          Working directory (required)
  INPUT                       DEN file or directory with TIFF images to process (required)
  OUTPUT                      DEN file or directory for output (required)

Options:
  --out-dimx ODX              Set output dimension in X direction
  --out-dimy ODY              Set output dimension in Y direction
  --out-dimz ODZ              Set output dimension in Z direction
  --radial-center-x CX        Absolute X coordinate of radial mask center
  --radial-center-y CY        Absolute Y coordinate of radial mask center
  --radial-center-offset-x OX Offset from image center in X direction
  --radial-center-offset-y OY Offset from image center in Y direction
  --radial-mask-radius RADIUS Set radius for radial mask (in pixels)
  --den-output                Output is DEN (default: OUTPUT ends with .den)
  --delete-input              Remove input after processing (default if INPUT equals OUTPUT)
  --force                     Overwrite existing OUTPUT if it exists and is specified
  -h, --help                  Show this help message and exit

Note:
  --den-output defaults to false, so unless OUTPUT ends in .den, the output will not be in DEN format.
  --delete-input defaults to false, but if INPUT equals OUTPUT, the input will be deleted after processing.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --out-dimx)
            ODX="$2"
            shift 2
            ;;
        --out-dimy)
            ODY="$2"
            shift 2
            ;;
        --out-dimz)
            ODZ="$2"
            shift 2
            ;;
        --radial-mask-radius)
            RADIUS="$2"
            shift 2
            ;;
        --radial-center-x)
    	    RADIAL_CENTER_X="$2"
    	    shift 2
    	    ;;
    	--radial-center-y)
    	    RADIAL_CENTER_Y="$2"
    	    shift 2
    	    ;;
    	--radial-center-offset-x)
    	    RADIAL_CENTER_OFFSET_X="$2"
    	    shift 2
    	    ;;
    	--radial-center-offset-y)
    	    RADIAL_CENTER_OFFSET_Y="$2"
    	    shift 2
    	    ;;
        --den-output)
	        OUTPUT_IS_DEN=true
            shift
            ;;
        --delete-input)
	    	DELETE_INPUT=true
	    	shift
	    	;;
        --force)
            FORCE=true
            shift
            ;;
		-h|--help)
	        usage help
	        exit 0
	        ;;
        -*)
            echo "Unknown option: $1" >&2
            usage error
	    	exit 1
            ;;
        *)
            # Positional arguments: WD and INPUT
            if [ -z "$WD" ]; then
                WD="$1"
                echo "WD=$WD"
            elif [ -z "$INPUT" ]; then
                INPUT="$1"
                echo "INPUT=$INPUT"
            elif [ -z "$OUTPUT" ]; then
                OUTPUT="$1"
                echo "OUTPUT=$OUTPUT"
			else
                echo "Unexpected argument: $1" >&2
                usage error
				exit 1
            fi
            shift
            ;;
    esac
done


# Check if the number of positional arguments is correct (both WD and INPUT must be set)
if [ -z "$WD" ] || [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
    echo "Error: Missing required positional arguments" >&2
    usage error
    exit 1
fi

# Ensure --radial-center-x and --radial-center-offset-x are not both set, same for Y
if [ -n "$RADIAL_CENTER_X" ] && [ -n "$RADIAL_CENTER_OFFSET_X" ]; then
    echo "Error: --radial-center-x and --radial-center-offset-x are mutually exclusive. Please specify only one of them." >&2
    usage
fi

if [ -n "$RADIAL_CENTER_Y" ] && [ -n "$RADIAL_CENTER_OFFSET_Y" ]; then
    echo "Error: --radial-center-y and --radial-center-offset-y are mutually exclusive. Please specify only one of them." >&2
    usage
fi

# Assign parameters to variables
PATH=$PATH:$PWD/bin

# Check if WD is a directory
if [ ! -d "$WD" ]; then
    echo "Error: $WD is not a directory" >&2
    exit 1
fi

cd $WD

unset LD_PRELOAD
source initGanrec

TMPDIR=$(mktemp -d -p . "tmp_28cropAndMask_XXXXX")
INPUTBASE=$(basename "$INPUT")

#Prepare names for intermediate files
ORIGDEN="${TMPDIR}/${INPUTBASE}.den"
FILTEREDDEN="${TMPDIR}/${INPUTBASE}_flt.den"
FILTEREDOUTPUT="${TMPDIR}/${INPUTBASE}_flt"

# If OUTPUT exists require --force to overwrite
if [ -e "$OUTPUT" ] && [ "$FORCE" = false ]; then
    echo "Error: Output '$OUTPUT' already exists. Use --force to overwrite." >&2
    exit 1
fi

TIFPREFIX=""
# Check if INPUT is a directory or file
if [ ! -d "$INPUT" ]; then
    # If it is a file, assume it is in a DEN format
    if [ -f "$INPUT" ]; then
        ORIGDEN="$INPUT"
        INPUT_IS_DEN=true
        TIFPREFIX=$(basename "$INPUT" .den)
    else
        echo "Error: $INPUT is neither a valid directory nor a valid file" >&2
        exit 1
    fi
else
    # Convert INPUT (a directory) to DEN format
    echo "Converting TIFF images in directory '$INPUT' to DEN format..."
	# Collect and sort .tif files from INPUT
	mapfile -t TIF_FILES < <(find "$INPUT" -maxdepth 1 -type f -name '*.tif' -printf '%f\n' | sort)
	
	# Ensure we found files
	if [ ${#TIF_FILES[@]} -eq 0 ]; then
	    echo "No .tif files found in $INPUT"
	    exit 1
	fi
	
	# Compute common prefix
	TIFPREFIX="${TIF_FILES[0]}"
	for f in "${TIF_FILES[@]}"; do
	    while [[ "${f#"$TIFPREFIX"}" == "$f" ]]; do
	        TIFPREFIX="${TIFPREFIX%?}"
	    done
	done
	
	# Optional: strip .tif if prefix ends with it
	TIFPREFIX="${TIFPREFIX%.tif}"
	
	echo "Common prefix: $TIFPREFIX"
	
	# Build full paths for command
	FULL_PATHS=()
	for f in "${TIF_FILES[@]}"; do
	    FULL_PATHS+=("$INPUT/$f")
	done
	
	# Run your original command with sorted files
	tiffImagesToDenStack.py "${FULL_PATHS[@]}" "$ORIGDEN"
fi

# If INPUT equals OUTPUT, set DELETE_INPUT to true
if [ "$INPUT" = "$OUTPUT" ]; then
    DELETE_INPUT=true
    if [ "$INPUT_IS_DEN" = true ]; then
        OUTPUT_IS_DEN=true
	# IF OUTPUT ends with .den, set OUTPUT_IS_DEN to true
    elif [[ "$OUTPUT" == *.den ]]; then
		OUTPUT_IS_DEN=true
    fi
fi

# Get the dimensions of the DEN file
echo "Getting dimensions of the DEN file '$ORIGDEN'..."
dims=$(dentk-info --dim "$ORIGDEN")

# Check if dentk-info command succeeded
if [ $? -ne 0 ]; then
    echo "Error: 'dentk-info' failed. '$ORIGDEN' is not a valid DEN file." >&2
    exit 1
fi

# Parse the output into dimx, dimy, and dimz
IFS=$'\t' read -r dimx dimy dimz <<< "$dims"

# Check if exactly three dimensions are returned
if [ -z "$dimx" ] || [ -z "$dimy" ] || [ -z "$dimz" ]; then
    echo "Error: 'dentk-info' did not return three dimensions for '$ORIGDEN'." >&2
    exit 1
fi

# Check if dimensions are positive integers
if ! [[ "$dimx" =~ ^[0-9]+$ ]] || ! [[ "$dimy" =~ ^[0-9]+$ ]] || ! [[ "$dimz" =~ ^[0-9]+$ ]]; then
    echo "Error: One or more dimensions from '$ORIGDEN' are not valid positive integers." >&2
    exit 1
fi

# Check if dimensions are greater than 0
if [ "$dimx" -le 0 ] || [ "$dimy" -le 0 ] || [ "$dimz" -le 0 ]; then
    echo "Error: One or more dimensions from '$ORIGDEN' are non-positive. Cannot process the file." >&2
    exit 1
fi

# If ODX, ODY, or ODZ are not provided, set them to original dimensions
# If ODX, ODY, or ODZ are provided but larger than original dimensions, exit with error
if [ -z "$ODX" ]; then
    ODX="$dimx"
elif [ "$ODX" -gt "$dimx" ]; then
    echo "Error: Specified out-dimx ($ODX) is larger than original dimension ($dimx)." >&2
    exit 1
fi

if [ -z "$ODY" ]; then
    ODY="$dimy"
elif [ "$ODY" -gt "$dimy" ]; then
    echo "Error: Specified out-dimy ($ODY) is larger than original dimension ($dimy)." >&2
    exit 1
fi

if [ -z "$ODZ" ]; then
    ODZ="$dimz"
elif [ "$ODZ" -gt "$dimz" ]; then
    echo "Error: Specified out-dimz ($ODZ) is larger than original dimension ($dimz)." >&2
    exit 1
fi

# If RADIUS is not provided, set it to half of the smallest from ODX and ODY
if [ -z "$RADIUS" ]; then
    if [ "$ODX" -lt "$ODY" ]; then
	RADIUS=$((ODX / 2))
    else
	RADIUS=$((ODY / 2))
    fi
fi

echo "Working Directory (WD): $WD"
echo "Input Directory/File (INPUT): $INPUT"
echo "Output Directory (OUTPUT): $OUTPUT"
echo "Input is DEN file: $INPUT_IS_DEN"
echo "Output is DEN file: $OUTPUT_IS_DEN"
echo "Delete Input After Processing: $DELETE_INPUT"
echo "Overwrite Existing Output if Exists: $FORCE"
echo "Original dimensions ($dimx, $dimy, $dimz)"
echo "Output Dimensions: ($ODX, $ODY, $ODZ)"
echo "Radial Mask Radius: $RADIUS"

filter_radial_mask() {
    local input_den_file="$1"
    local output_den_file="$2"

    if [ -z "$input_den_file" ] || [ -z "$output_den_file" ]; then
        echo "Error: Both input and output den files must be specified." >&2
        return 1
    fi

    #Error if input den file does not exist or output den file exists
    if [ ! -f "$input_den_file" ]; then
		echo "Error: Input den file '$input_den_file' does not exist." >&2
		return 1
    fi

    if [ -f "$output_den_file" ]; then
		echo "Error: Output den file '$output_den_file' already exists." >&2
		return 1
    fi

    # Construct arguments for radial center if provided
    radial_center_args=""
    
    if [ -n "${RADIAL_CENTER_X:-}" ]; then
        radial_center_args="${radial_center_args} --radial-center-x ${RADIAL_CENTER_X}"
    fi
    
    if [ -n "${RADIAL_CENTER_Y:-}" ]; then
        radial_center_args="${radial_center_args} --radial-center-y ${RADIAL_CENTER_Y}"
    fi
    
    if [ -n "${RADIAL_CENTER_OFFSET_X:-}" ]; then
        radial_center_args="${radial_center_args} --radial-center-offset-x ${RADIAL_CENTER_OFFSET_X}"
    fi
    
    if [ -n "${RADIAL_CENTER_OFFSET_Y:-}" ]; then
        radial_center_args="${radial_center_args} --radial-center-offset-y ${RADIAL_CENTER_OFFSET_Y}"
    fi


    # Call the filterRadialMask.py script with the provided parameters
    filterRadialMask.py ${radial_center_args} --out-dimx "$ODX" --out-dimy "$ODY" --out-dimz "$ODZ" --radial-mask-radius "$RADIUS" "$input_den_file" "$output_den_file"
    
    # Check the exit status of the filterRadialMask.py command
    if [ $? -ne 0 ]; then
        echo "Error: filterRadialMask.py failed to process files." >&2
        return 1
    fi

    echo "filterRadialMask.py completed successfully: $input_den_file -> $output_den_file"
    return 0
}

filter_radial_mask "$ORIGDEN" "$FILTEREDDEN"

#If OUDIR is set, test that is does not exist yet
if [ -e "$OUTPUT" ]; then
	if [ "$FORCE" = true ]; then
		echo "Warning: Removing existing output '$OUTPUT' due to --force option."
		rm -rf "$OUTPUT"
	else
    	echo "Error: Specified output directory '$OUTPUT' already exists. Please choose a different directory or use --force to overwrite." >&2
    	exit 1
	fi
fi

if [ "$DELETE_INPUT" = true ] && [ -e "$INPUT" ]; then
	if [ "$INPUT_IS_DEN" = true ]; then
		echo "Deleting input file '$INPUT' due to --delete-input option."
		rm -f "$INPUT"
	else
		echo "Deleting input directory '$INPUT' and its contents due to --delete-input option."
        #If it is simlink just delete the simlink, not the original directory
		if [ -L "$INPUT" ]; then
		    echo "Input '$INPUT' is a symbolic link. Removing the symbolic link without affecting the original directory."
		    rm "$INPUT"
		else
		    # Check if INPUT contains exactly one subdirectory called 'log' or no subdirectories
		    subdirs=$(find "$INPUT" -mindepth 1 -maxdepth 1 -type d)
		    log_subdir=$(find "$INPUT" -mindepth 1 -maxdepth 1 -type d -name "log")
		
		    if [ $(echo "$subdirs" | wc -l) -gt 1 ] && [ -z "$log_subdir" ]; then
		        # If there are multiple subdirectories and 'log' is not one of them, print an error
		        echo "Error: $INPUT contains multiple subdirectories or invalid structure. Aborting deletion." >&2
		        exit 1
		    fi
		    # Remove the log contents if the structure is valid
		    if [ -n "$log_subdir" ]; then
		        echo "Removing contents of '$INPUT/log'..."
		        rm "$INPUT/log"/*
		
		        # Remove the 'log' directory itself if it's now empty
		        rmdir "$INPUT/log"
		    fi
		    # Remove any other files left in the directory
		    echo "Removing remaining contents of '$INPUT'..."
		    rm "$INPUT"/*
		
		    # Remove the original directory itself
		    echo "Removing original directory '$INPUT'..."
		    rmdir "$INPUT"
	    	if [ -z "$OUTPUT" ]; then
				OUTPUT="$INPUT"
	            OUTDEN="${OUTPUT}.den"
	    	fi
		fi
	fi
fi

# Handle output based on user options
if [ "$OUTPUT_IS_DEN" = false ]; then
    # If only den file is requested, move the filtered den to INPUT
    denFilesToTifFiles.py --prefix "$TIFPREFIX" "$FILTEREDDEN" "$FILTEREDOUTPUT"
    mv "$FILTEREDOUTPUT" "$OUTPUT"
else
    # If output is den, move the filtered den to OUTPUT
    mv "$FILTEREDDEN" "$OUTPUT"
fi

rm -rf $TMPDIR

# End body of the script
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
hours=$((elapsed_time / 3600))
minutes=$(((elapsed_time % 3600) / 60))
seconds=$((elapsed_time % 60))
formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
echo "END $jobname $formatted_time"
