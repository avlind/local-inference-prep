#!/bin/bash
# =============================================================================
# 1-format-ssd.sh — Format a USB-C SSD as exFAT (GPT) on macOS
# so it is writable on this Mac AND readable on the Dell GB10s (DGX OS/Linux).
#
# Usage:  bash 1-format-ssd.sh
# =============================================================================
set -euo pipefail

VOLUME_NAME="GB10MODELS"

echo "============================================================"
echo " GB10 SSD Formatter — exFAT / GPT"
echo "============================================================"
echo
echo "This will format a drive as exFAT with a GPT partition table:"
echo "  - macOS: native read/write (for downloading models)"
echo "  - DGX OS / Ubuntu on the GB10: native read/write"
echo
echo "External physical disks currently attached:"
echo "------------------------------------------------------------"
diskutil list external physical
echo "------------------------------------------------------------"
echo

# --- Identify the target disk -----------------------------------------------
read -r -p "Enter the disk identifier to format (e.g. disk4, NOT disk4s1): " DISK_ID

# Basic sanity checks
if [[ ! "$DISK_ID" =~ ^disk[0-9]+$ ]]; then
  echo "ERROR: '$DISK_ID' is not a whole-disk identifier (expected e.g. 'disk4')."
  exit 1
fi

if [[ "$DISK_ID" == "disk0" || "$DISK_ID" == "disk1" ]]; then
  echo "ERROR: $DISK_ID is almost certainly an internal drive. Refusing."
  exit 1
fi

# Confirm it is external
if ! diskutil info "/dev/$DISK_ID" | grep -q "Device Location: *External"; then
  if ! diskutil info "/dev/$DISK_ID" | grep -qi "External: *Yes"; then
    echo "WARNING: macOS does not report /dev/$DISK_ID as external."
    read -r -p "Are you ABSOLUTELY sure this is the USB SSD? (yes/no): " SURE
    [[ "$SURE" == "yes" ]] || { echo "Aborted."; exit 1; }
  fi
fi

echo
echo "Details for /dev/$DISK_ID:"
echo "------------------------------------------------------------"
diskutil info "/dev/$DISK_ID" | grep -E "Device / Media Name|Disk Size|Protocol|Device Location" || true
echo "------------------------------------------------------------"
echo
echo ">>> ALL DATA ON /dev/$DISK_ID WILL BE DESTROYED. <<<"
read -r -p "Type the disk identifier again to confirm: " CONFIRM
[[ "$CONFIRM" == "$DISK_ID" ]] || { echo "Identifiers did not match. Aborted."; exit 1; }

# --- Format ------------------------------------------------------------------
echo
echo "Formatting /dev/$DISK_ID as exFAT (GPT), volume name: $VOLUME_NAME ..."
diskutil eraseDisk ExFAT "$VOLUME_NAME" GPT "/dev/$DISK_ID"

# --- Verify ------------------------------------------------------------------
echo
if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
  echo "SUCCESS. Drive mounted at /Volumes/$VOLUME_NAME"
  df -h "/Volumes/$VOLUME_NAME"
  mkdir -p "/Volumes/$VOLUME_NAME/models"
  echo
  echo "Created /Volumes/$VOLUME_NAME/models — the download script targets this."
  echo "Next: run  bash 2-download-models.sh"
else
  echo "Format completed but volume not found at /Volumes/$VOLUME_NAME."
  echo "Unplug/replug the drive, then check:  ls /Volumes/"
fi
