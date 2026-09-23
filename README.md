# cloud-boot/windows-image

Two-path Windows test infrastructure for cloud-boot's
`CloudBootTarget=windows` loader branch — one **fully
redistributable** (a tiny PE32+ stub that mimics Windows Boot
Manager's handoff signature), one **EULA-gated** (orchestration
to repackage a real Microsoft dev-VM VHDX into an OCI artifact in
your own private GHCR).

## Why this repo exists

Booting unmodified Windows is a goal of the loader's Windows
target ([`docs/reference/windows-target.md`](https://cloud-boot.github.io/docs/reference/windows-target/)).
But Microsoft does **not** publish a freely-redistributable
"Windows cloud image" the way Debian / Ubuntu / Fedora do — every
official source (Edge dev VMs, Server eval ISOs, Windows 10/11
ISOs) carries an EULA that **forbids public redistribution**.

So a public OCI artifact at `ghcr.io/cloud-boot/windows:latest`
that boots a real Windows desktop is legally a non-starter. We
solve the underlying need (reproducible Windows-handoff testing
across the cloud-boot ecosystem) two ways:

| Path | What it is | License | Where it lives |
| --- | --- | --- | --- |
| `stub/` | A ~3-KiB PE32+ binary that mimics Boot Manager's startup banner (prints `Windows Boot Manager (cloud-boot stub)` to the serial). Tests our LoadImage(DevicePath) handoff end-to-end without any Microsoft IP. | BSD-3-Clause, fully redistributable | **Published** at `ghcr.io/cloud-boot/windows-stub:latest` (public, free pull) |
| `scripts/` + `Taskfile.yaml` | A reproducible build pipeline: download MS dev VM (operator-side) → convert VHDX→raw → wrap as an OCI artifact → push to operator's **own** GHCR namespace. The repo carries the orchestration, no Microsoft bytes. | Operator-bound to MS dev-VM EULA | Each operator builds + hosts privately in their own GHCR |

## Quick start (routing-only test, public stub)

```sh
# Pull the public stub straight from ghcr.io
oras pull ghcr.io/cloud-boot/windows-stub:latest
# Now you have BOOTX64.EFI + BOOTAA64.EFI staged locally.

# Use it as a fake Windows Boot Manager in a smoke test of
# cloud-boot's CloudBootTarget=windows routing — no real Windows
# install required:
loader/scripts/test-windows.sh --stub  # --stub mode wires the stub PE into \EFI\Microsoft\Boot\bootmgfw.efi
```

This validates everything in the loader's handoff path:
DevicePath construction, LoadImage(SourceBuffer=NULL), child
image's LoadedImage.FilePath population, `StartImage` return.
What it does NOT validate is whatever real Windows does after the
handoff — that needs the real-Windows path below.

## Full-fidelity (operator-side, real Windows)

If you have a Microsoft EULA you're comfortable hosting against
(common case: a per-operator GitHub Actions workflow with
`secrets.WINDOWS_OCI_REGISTRY` pointing at YOUR private GHCR
namespace, your Microsoft access token in
`secrets.MS_DEV_VM_URL`):

```sh
# 1. Read & accept the dev-VM EULA at:
#    https://developer.microsoft.com/en-us/microsoft-edge/tools/vms/
# 2. Drop the resulting VHDX URL into the secret store:
export MS_DEV_VM_URL='https://download.microsoft.com/.../MSEdge-Win11.vhdx'
export WINDOWS_OCI_REGISTRY='ghcr.io/myorg/cloud-boot-windows'

task download       # → workdir/MSEdge-Win11.vhdx
task convert        # → workdir/win.raw (~30 GB)
task package        # → workdir/win.oci-artifact.tar
task push           # → $WINDOWS_OCI_REGISTRY:latest (operator's own GHCR)
```

`.github/workflows/build-real.yml` is the same flow as a GHA
workflow, gated by org-defined secrets. The repo can't run this
flow from `cloud-boot/`'s own GHCR — that would publish Microsoft
IP under the cloud-boot org account, which the EULA forbids.

## Layout

```
windows-image/
├── README.md                 (this file)
├── Taskfile.yaml             top-level orchestrator
├── stub/                     fully-redistributable PE stub
│   ├── main.go               TinyGo source — banner + ExitBootServices
│   ├── thunk-amd64.S         amd64 UEFI thunk
│   ├── thunk-arm64.S         arm64 UEFI thunk
│   ├── targets/              TinyGo target specs (uefi-amd64.json, uefi-arm64.json)
│   ├── Taskfile.yaml         build BOOTX64.EFI / BOOTAA64.EFI
│   └── README.md
├── scripts/                  real-Windows pipeline (operator-side)
│   ├── download.sh           wraps MS dev-VM download with EULA prompt
│   ├── vhdx-to-oci.sh        VHDX → raw → ORAS-packed OCI artifact
│   └── eula-banner.txt       the exact text the operator sees on download.sh first run
└── .github/workflows/
    ├── publish-stub.yml      builds + publishes the public stub on every push to main
    └── build-real.yml        TEMPLATE — operators copy into their own forks
```

## How the public stub passes Boot Manager's smell-test

`bootmgfw.efi` on a healthy install does roughly this within its
first ~10 ms after `StartImage`:

1. Reads its own `LoadedImage.FilePath` via the LoadedImage
   protocol on `gImageHandle`.
2. Parses the path to find the boot volume.
3. Opens `\Windows\System32\winload.efi` (or `winload.exe` legacy).
4. Reads BCD store from `\Boot\BCD`.
5. Prints "Windows Boot Manager" to whatever console handle the
   firmware gave it.

Our stub mimics steps 1 + 5: opens LoadedImage, walks FilePath
(asserting that the loader DID populate it — that's the whole
point of our test), prints `Windows Boot Manager (cloud-boot stub)
— routing OK from <devicepath>` to the serial console, then
calls `ExitBootServices` and idle-loops for 1 second before
calling `ResetSystem(EfiResetShutdown)`.

The serial output matches the regex `test-windows.sh` greps for
(`Windows Boot Manager|Loading kernel|winload|bootmgfw`), so the
existing test infrastructure works against the stub identically
to against the real binary.

## License

All files under `stub/` and `scripts/` are BSD-3-Clause. The
operator-staged Microsoft VHDX is bound by Microsoft's own terms
and is **never** committed or referenced in this repo's git
history.
