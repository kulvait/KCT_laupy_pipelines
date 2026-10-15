#!/bin/bash
set -euo pipefail

scriptname=$(basename "$0")
ROOT="."
PATTERN="*.sbatch"
RUNTIME=false
TIMEOUT_SECONDS=10
PIPELINES=()
EXCLUDES=()

usage() {
    local mode="${1:-help}"
    local out=1
    if [[ "$mode" == "error" ]]; then
        out=2
    fi

    cat <<EOF >&${out}
Usage: ${scriptname} [OPTIONS]

Check Bash syntax in microct_root/sbatch and nanoct_root/sbatch.
By default, check both pipelines and all *.sbatch files.

Options:
  --micro                 Select microct only, unless --nano is also supplied.
  --nano                  Select nanoct only, unless --micro is also supplied.
  --root DIR              Repository root (default: current directory).
  --pattern GLOB          Match script basenames (default: *.sbatch).
  --exclude GLOB          Exclude a basename or repository-relative path.
                          Repeat this option to exclude multiple patterns.
  --runtime               Also execute help and missing-argument checks.
  --timeout SECONDS       Timeout per runtime invocation (default: 10).
                          Must be a positive integer.
  -h, --h, --help          Show this help and exit successfully.

Runtime checks:
  -h, --h, --help must exit 0 and produce nonempty output.
  Invocation without arguments must exit nonzero.
  Timeouts, signals, and command-launch failures are always failures.

WARNING:
  Runtime checks execute repository code. Temporary working directories and
  timeouts are NOT a sandbox. Use only with trusted scripts, preferably in a
  disposable environment without access to production data.

Quote glob patterns to prevent expansion by your calling shell.
EOF
}

die() {
    echo "Error: $*" >&2
    usage error
    exit 2
}

require_value() {
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
        die "$1 requires a value."
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --micro)
            PIPELINES+=("microct_root")
            shift
            ;;
        --nano)
            PIPELINES+=("nanoct_root")
            shift
            ;;
        --root)
            require_value "$@"
            ROOT="$2"
            shift 2
            ;;
        --pattern)
            require_value "$@"
            PATTERN="$2"
            shift 2
            ;;
        --exclude)
            require_value "$@"
            EXCLUDES+=("$2")
            shift 2
            ;;
        --runtime)
            RUNTIME=true
            shift
            ;;
        --timeout)
            require_value "$@"
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        -h|--h|--help)
            usage help
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
    die "--timeout must be a positive integer."

[[ -d "$ROOT" ]] || die "Repository root does not exist: $ROOT"
ROOT=$(cd -- "$ROOT" && pwd -P)

if [[ ${#PIPELINES[@]} -eq 0 ]]; then
    PIPELINES=("microct_root" "nanoct_root")
fi

if [[ "$RUNTIME" == true ]]; then
    command -v timeout >/dev/null 2>&1 ||
        die "--runtime requires GNU timeout."
    echo "WARNING: Runtime checks execute scripts; this is not a sandbox." >&2
fi

TMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TMP_ROOT"' EXIT

passed=0
failed=0
checked=0
skipped=0
configuration_errors=0
invocations=0

report_failure() {
    local label="$1"
    local logfile="$2"

    printf '  FAIL: %s\n' "$label" >&2
    if [[ -s "$logfile" ]]; then
        cat -- "$logfile" >&2
    fi
}

# Each runtime invocation gets a fresh working directory.
# Return status is recorded without triggering set -e.
run_script() {
    local script="$1"
    local logfile="$2"
    shift 2

    invocations=$((invocations + 1))
    local workdir="$TMP_ROOT/run-$invocations"
    mkdir -- "$workdir"

    RUN_STATUS=0
    (
        cd -- "$workdir"
        timeout --kill-after=2s "${TIMEOUT_SECONDS}s" \
            bash "$script" "$@" </dev/null
    ) >"$logfile" 2>&1 || RUN_STATUS=$?
}

shopt -s nullglob
SEEN_PIPELINES=()

for pipeline in "${PIPELINES[@]}"; do
    # Ignore repeated --micro / --nano options.
    already_seen=false
    for seen in "${SEEN_PIPELINES[@]}"; do
        if [[ "$seen" == "$pipeline" ]]; then
            already_seen=true
            break
        fi
    done
    [[ "$already_seen" == true ]] && continue
    SEEN_PIPELINES+=("$pipeline")

    directory="$ROOT/$pipeline/sbatch"
    if [[ ! -d "$directory" ]]; then
        echo "FAIL: Missing directory: $directory" >&2
        configuration_errors=$((configuration_errors + 1))
        continue
    fi

    for script in "$directory"/*.sbatch; do
        [[ -f "$script" ]] || continue

        basename="${script##*/}"
        relative="$pipeline/sbatch/$basename"
        [[ "$basename" == $PATTERN ]] || continue

        excluded=false
        for pattern in "${EXCLUDES[@]}"; do
            if [[ "$basename" == $pattern || "$relative" == $pattern ]]; then
                excluded=true
                break
            fi
        done

        if [[ "$excluded" == true ]]; then
            printf 'SKIP: %s\n' "$relative"
            skipped=$((skipped + 1))
            continue
        fi

        checked=$((checked + 1))
        script_failed=false
        logfile="$TMP_ROOT/check.log"

        if ! bash -n "$script" >"$logfile" 2>&1; then
            report_failure "$relative: syntax" "$logfile"
            script_failed=true
        elif [[ "$RUNTIME" == true ]]; then
            for flag in -h --h --help; do
                run_script "$script" "$logfile" "$flag"
                if [[ "$RUN_STATUS" -ne 0 || ! -s "$logfile" ]]; then
                    report_failure \
                        "$relative $flag: exit=$RUN_STATUS; expected 0 and output" \
                        "$logfile"
                    script_failed=true
                fi
            done

            run_script "$script" "$logfile"
            if [[ "$RUN_STATUS" -eq 0 || "$RUN_STATUS" -ge 124 ]]; then
                report_failure \
                    "$relative without arguments: exit=$RUN_STATUS; expected an argument error" \
                    "$logfile"
                script_failed=true
            fi
        fi

        if [[ "$script_failed" == true ]]; then
            failed=$((failed + 1))
        else
            printf 'PASS: %s\n' "$relative"
            passed=$((passed + 1))
        fi
    done
done

printf '\nChecked: %d | Passed: %d | Failed: %d | Excluded: %d | Configuration errors: %d\n' \
    "$checked" "$passed" "$failed" "$skipped" "$configuration_errors"

if [[ "$checked" -eq 0 ]]; then
    echo "Error: No scripts were checked." >&2
    exit 2
fi

if [[ "$configuration_errors" -gt 0 ]]; then
    exit 2
fi

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
