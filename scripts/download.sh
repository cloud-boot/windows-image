#!/usr/bin/env bash
# download.sh — fetch a Microsoft dev VM VHDX into the operator's
# local workspace. Refuses to run unless the operator has set
# MS_DEV_VM_URL (which they got by accepting the Microsoft EULA on
# https://developer.microsoft.com/en-us/microsoft-edge/tools/vms/).
#
# This script writes ONLY to the local workdir. It does NOT push,
# upload, redistribute, or otherwise carry the Microsoft binary
# outside the operator's machine. See ../README.md for the broader
# legal model.

set -euo pipefail

cat "$(dirname "$0")/eula-banner.txt"

if [[ -z "${MS_DEV_VM_URL:-}" ]]; then
  cat >&2 <<'EOF'

ERROR: MS_DEV_VM_URL is not set.

  1. Visit https://developer.microsoft.com/en-us/microsoft-edge/tools/vms/
  2. Pick a VM image (MSEdge on Win11, MSEdge on Win10, …).
  3. Accept the EULA (each download shows the terms inline).
  4. The page yields a direct download URL — set:
        export MS_DEV_VM_URL='https://.../MSEdge-Win11.vhdx.zip'
  5. Re-run this script.

EOF
  exit 2
fi

WORKDIR="${WORKDIR:-./workdir}"
mkdir -p "$WORKDIR"
OUT="${OUT:-$WORKDIR/$(basename "${MS_DEV_VM_URL%%\?*}")}"

if [[ -f "$OUT" ]]; then
  echo "→ $OUT already exists, skipping download (delete to force re-fetch)"
  exit 0
fi

echo "→ downloading to $OUT (this is large — ~6-30 GB depending on VM)"
curl -fL --progress-bar -o "$OUT" "$MS_DEV_VM_URL"

# Most MS dev VMs ship as a .zip wrapping a .vhdx. Unzip on the fly.
case "$OUT" in
  *.zip)
    echo "→ unzipping $OUT"
    unzip -o "$OUT" -d "$WORKDIR"
    rm -f "$OUT"
    ;;
esac

ls -lh "$WORKDIR"
echo
echo "→ next: 'task convert' (VHDX → raw)"
