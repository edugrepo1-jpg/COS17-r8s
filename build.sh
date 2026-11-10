#!/bin/bash
# ColorOS build entry point; the input firmware is FW/ColorOS.
set -euo pipefail

if (( $# < 2 )); then
    echo "Usage: $0 <x1s|y2s|z3s|r8s|SM-model> <erofs|ext4|f2fs> [--patch-only] [-z|--zip] [-p|--partition system|product|vendor|odm]" >&2
    exit 1
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export STOCK_DEVICE="$1" OUTPUT_FILESYSTEM="$2"
shift 2
PATCH_ONLY=false
BUILD_ZIP=false
PARTITION=all
while (($#)); do
    case "$1" in
        --patch-only) PATCH_ONLY=true; shift ;;
        -z|--zip) BUILD_ZIP=true; shift ;;
        -p|--partition)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
            PARTITION="$2"
            shift 2
            ;;
        --partition=*) PARTITION="${1#*=}"; shift ;;
        *) echo "Invalid argument: $1" >&2; exit 1 ;;
    esac
done
case "$PARTITION" in
    system|product|vendor|odm|all) ;;
    *) echo "Invalid partition: $PARTITION (use system, product, vendor, odm, or all)" >&2; exit 1 ;;
esac
if $BUILD_ZIP && [[ "$PARTITION" != all ]]; then
    echo "--zip requires a complete build; omit -p/--partition" >&2
    exit 1
fi
case "$STOCK_DEVICE" in
    x1s|SM-G980F|SM-G981B) DEVICE_TARGET=x1s ;;
    y2s|SM-G985F|SM-G986B) DEVICE_TARGET=y2s ;;
    z3s|SM-G988B) DEVICE_TARGET=z3s ;;
    r8s|SM-G780F) DEVICE_TARGET=r8s ;;
    *) echo "Unsupported device: $STOCK_DEVICE" >&2; exit 1 ;;
esac
case "$OUTPUT_FILESYSTEM" in erofs|ext4|f2fs) ;; *) echo 'Invalid filesystem' >&2; exit 1 ;; esac
export FIRM_DIR="$PWD/FW" OUT_DIR="$PWD/out/target/$DEVICE_TARGET"
export COLOROS_CACHE_DIR="$PWD/out/cache/$DEVICE_TARGET"
export COLOROS_LOG_DIR="$PWD/out/logs/$DEVICE_TARGET"
export PYTHONPYCACHEPREFIX="$PWD/out/cache/python"
mkdir -p "$OUT_DIR" "$COLOROS_CACHE_DIR" "$COLOROS_LOG_DIR"
BUILD_LOG="$COLOROS_LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
ln -sfn "$(basename "$BUILD_LOG")" "$COLOROS_LOG_DIR/build.log"
exec > >(tee "$BUILD_LOG") 2>&1
trap 'BUILD_STATUS=$?; echo "Build finished with exit code $BUILD_STATUS"' EXIT
echo "ColorOS target=$DEVICE_TARGET filesystem=$OUTPUT_FILESYSTEM partition=$PARTITION started=$(date -Is)"
export PATCHES_DIR="$PWD/QuantumROM/patches"
source scripts/QuantumRom.sh

FIRMWARE="$FIRM_DIR/ColorOS"
[[ -d "$FIRMWARE" ]] || { echo "Missing firmware: $FIRMWARE" >&2; exit 1; }
if [[ ! -f "$FIRMWARE/system/system/build.prop" ]]; then
    if [[ ! -f "$FIRMWARE/system.img" ]]; then
        EXTRACT_FIRMWARE "$FIRMWARE"
        EXTRACT_SUPER_IMG "$FIRMWARE"
    fi
    EXTRACT_FIRMWARE_IMG "$FIRMWARE" system.img
fi
# Each target uses its own vendor/odm images from Devices/*/extra.
PREPARE_COLOROS_TARGET "$FIRMWARE" "$DEVICE_TARGET"
FIRMWARE="$COLOROS_CACHE_DIR/firmware"

# Validate every planned operation before committing files. No One UI-specific patches.
BRINGUP_COLOROS "$FIRMWARE" "$DEVICE_TARGET"

if $PATCH_ONLY; then
    echo "Patches applied: $FIRMWARE. Images were not rebuilt (selected partition: $PARTITION)."
    exit 0
fi
rm -f "$OUT_DIR/SHA256SUMS" "$OUT_DIR/build-info.json"
if [[ "$PARTITION" == system || "$PARTITION" == product || "$PARTITION" == all ]]; then
    IMAGE_FIRMWARE="$COLOROS_CACHE_DIR/split-product"
    rm -rf -- "$IMAGE_FIRMWARE"
    echo "Processing product separation patch"
    python3 "$PATCHES_DIR/coloros/split-product.py" "$FIRMWARE" "$IMAGE_FIRMWARE"
fi
if [[ "$PARTITION" == all || "$PARTITION" == system || "$PARTITION" == product ]]; then
    BUILD_IMG "$IMAGE_FIRMWARE" "$PARTITION" "$OUTPUT_FILESYSTEM" "$OUT_DIR"
else
    BUILD_IMG "$FIRMWARE" "$PARTITION" "$OUTPUT_FILESYSTEM" "$OUT_DIR"
fi

if [[ "$PARTITION" == all ]]; then
    python3 "$PATCHES_DIR/coloros/verify-images.py" "$OUT_DIR" "$DEVICE_TARGET" "$OUTPUT_FILESYSTEM" --source-props "$FIRMWARE/system/system/build.prop"
else
    python3 "$PATCHES_DIR/coloros/verify-images.py" "$OUT_DIR" "$DEVICE_TARGET" "$OUTPUT_FILESYSTEM" --partitions "$PARTITION" --source-props "$FIRMWARE/system/system/build.prop"
fi

if $BUILD_ZIP; then
    python3 "$PATCHES_DIR/coloros/build-zip.py" "$DEVICE_TARGET" "$OUT_DIR"
fi
echo "Build and verification completed: $OUT_DIR"
