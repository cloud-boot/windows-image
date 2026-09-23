#!/usr/bin/env bash
# vhdx-to-oci.sh — convert the operator's downloaded VHDX to a raw
# disk image, then wrap it as an OCI artifact and push to the
# operator's GHCR namespace.
#
# This script never references cloud-boot's own GHCR — it pushes
# to whatever $WINDOWS_OCI_REGISTRY the operator points it at.
# That's the legal model: cloud-boot/windows-image ships the
# orchestration; the operator hosts the artifact under their
# own Microsoft license.

set -euo pipefail

WORKDIR="${WORKDIR:-./workdir}"
REGISTRY="${WINDOWS_OCI_REGISTRY:-}"
TAG="${TAG:-latest}"

if [[ -z "$REGISTRY" ]]; then
  cat >&2 <<'EOF'
ERROR: WINDOWS_OCI_REGISTRY is not set.

  Set it to YOUR own private GHCR namespace where Microsoft's
  redistribution restrictions still hold (single-tenant, your-
  org-only access). Example:

        export WINDOWS_OCI_REGISTRY='ghcr.io/your-org/cloud-boot-windows'

  cloud-boot does NOT host or proxy Microsoft binaries.

EOF
  exit 2
fi

VHDX="$(ls "$WORKDIR"/*.vhdx 2>/dev/null | head -1 || true)"
if [[ -z "$VHDX" ]]; then
  echo "ERROR: no .vhdx in $WORKDIR — run download.sh first" >&2
  exit 2
fi
echo "→ converting $VHDX → raw"
qemu-img convert -p -O raw "$VHDX" "$WORKDIR/win.raw"

# Compress for OCI push (raw is ~30 GB; lzma + zstd buy a ~3-5x
# saving for a freshly-installed Windows; over 50% blocks are zero).
echo "→ compressing with zstd (this is the slowest step, ~10-15 min)"
zstd -19 -q --force -o "$WORKDIR/win.raw.zst" "$WORKDIR/win.raw"
ls -lh "$WORKDIR/win.raw.zst"

# ORAS push: the artifact is a single layer, the compressed raw
# disk. Annotated with the operator's URL so consumers know which
# Microsoft VM source produced it.
if ! command -v oras >/dev/null; then
  echo "ERROR: oras not in PATH — install from https://oras.land" >&2
  exit 1
fi
echo "→ pushing to $REGISTRY:$TAG"
cd "$WORKDIR"
oras push "$REGISTRY:$TAG" \
  --artifact-type application/vnd.cloud-boot.windows-raw.v1 \
  --annotation "org.opencontainers.image.source=$(cd "$(dirname "$0")/.." && git config --get remote.origin.url 2>/dev/null || echo 'cloud-boot/windows-image')" \
  --annotation "org.opencontainers.image.description=Operator-staged Windows raw disk for cloud-boot routing tests" \
  --annotation "cloud-boot.windows.source-vhdx=$(basename "$VHDX")" \
  win.raw.zst:application/vnd.cloud-boot.windows-raw.zst

echo
echo "→ done. Pull with:"
echo "    oras pull $REGISTRY:$TAG"
