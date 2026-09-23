# windows-image/stub

Fully-redistributable PE32+ stub that mimics Windows Boot
Manager's first ~10 ms after `StartImage` — just enough to
end-to-end-test cloud-boot's `CloudBootTarget=windows` routing
without any Microsoft IP.

See [`../README.md`](../README.md) for the project-level rationale
(public stub vs. operator-staged real Windows).

## What the stub does

```text
1. UEFI fires `efi_main(ImageHandle, *SystemTable)`.
2. Open LoadedImage protocol on `ImageHandle` — assert that
   LoadedImage.FilePath is non-NULL (the loader did populate it;
   if not the cloud-boot LoadImage(DevicePath) handoff broke).
3. Print to ConOut:
     "Windows Boot Manager (cloud-boot stub)"
     "  FilePath = \EFI\Microsoft\Boot\bootmgfw.efi"
     "  routing OK — would now read BCD + winload.efi"
4. Sleep ~250 ms so the serial buffer drains.
5. ResetSystem(EfiResetShutdown).
```

The exact print strings let `loader/scripts/test-windows.sh`'s
grep find both `LoadImage(DevicePath) OK` (printed by the
loader before handoff) AND `Windows Boot Manager` (printed by
this stub after handoff), confirming the whole handoff worked.

## Build

```sh
task build-amd64     # → BOOTX64.EFI       (~3-4 KiB)
task build-arm64     # → BOOTAA64.EFI      (~3-4 KiB)
task package         # → windows-stub.tar  (both binaries staged for OCI push)
task push            # → ghcr.io/cloud-boot/windows-stub:latest  (requires ORAS + GHCR auth)
```

The build chain is identical in shape to `go-coff/stub`'s — TinyGo
emits `goos=linux goarch={amd64,arm64}` PE/COFF, our `pectl link`
stitches the final BOOTX64.EFI/BOOTAA64.EFI. lld-link works fine
on amd64/arm64; we use pectl for symmetry with the riscv64 /
loongarch64 builds in the parent ecosystem.

## Why not just an empty `int main(){ return 0; }` PE?

A null binary would compile, but it wouldn't validate that the
LoadImage(DevicePath) handoff actually populated
`LoadedImage.FilePath` — the whole point of `CloudBootTarget=windows`
sharing the BSD branch's DevicePath path. The stub does the
minimum work to:

1. Open `LoadedImageProtocol` on its own handle.
2. Walk the resulting `FilePath` DevicePath node chain.
3. Print the textual path so a test runner can see the loader's
   composite DevicePath survived the transition.

Without that assertion, a regression in
`buildFilePath()` (loader/cmd/efi-loader/main.go) would silently
pass tests because the stub would run regardless of whether
FilePath was NULL or not.

## License

BSD-3-Clause. The stub's source has no Microsoft IP.
