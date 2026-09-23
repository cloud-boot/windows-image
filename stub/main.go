// windows-stub — a fully-redistributable PE32+ UEFI binary that
// mimics Windows Boot Manager's first ~10 ms after StartImage,
// just enough to end-to-end-test cloud-boot's
// CloudBootTarget=windows routing path. See ../README.md.
//
// The stub is intentionally minimal and free of Microsoft IP:
//
//   1. Opens LoadedImageProtocol on its own ImageHandle.
//   2. Asserts FilePath is non-NULL — the cloud-boot loader's
//      LoadImage(DevicePath, SourceBuffer=NULL) branch MUST
//      have populated this; if it didn't, the handoff is broken.
//   3. Prints the standard "Windows Boot Manager" banner that
//      loader/scripts/test-windows.sh's grep regex looks for.
//   4. Calls ResetSystem(EfiResetShutdown) so the QEMU runner
//      exits cleanly with `-no-reboot`.
//
// Build tags are the same as go-coff/stub for symmetry —
// `uefi` plus the TinyGo-specific `tinygo.uefi`.

//go:build uefi

package main

import "unsafe"

// efiHandle is the EFI_HANDLE opaque pointer.
type efiHandle = uintptr

// efiStatus is the UEFI EFI_STATUS code. EFI_SUCCESS = 0.
type efiStatus = uintptr

// efiGUID is the 16-byte EFI_GUID structure.
type efiGUID struct {
	Data1 uint32
	Data2 uint16
	Data3 uint16
	Data4 [8]uint8
}

// efiSimpleTextOutput is just enough of EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL
// for OutputString.
type efiSimpleTextOutput struct {
	reset        uintptr
	outputString uintptr // (this, *uint16) → status
	// … other fields omitted; we only call outputString
}

// efiRuntimeServices is just enough of EFI_RUNTIME_SERVICES for
// ResetSystem.
type efiRuntimeServices struct {
	hdr                  [24]byte // EFI_TABLE_HEADER
	getTime              uintptr
	setTime              uintptr
	getWakeupTime        uintptr
	setWakeupTime        uintptr
	setVirtualAddressMap uintptr
	convertPointer       uintptr
	getVariable          uintptr
	getNextVariableName  uintptr
	setVariable          uintptr
	getNextHighMonotonic uintptr
	resetSystem          uintptr // (ResetType, ResetStatus, DataSize, ResetData)
}

// efiBootServices is just enough for OpenProtocol + Stall.
type efiBootServices struct {
	hdr                        [24]byte
	raiseTPL                   uintptr
	restoreTPL                 uintptr
	allocatePages              uintptr
	freePages                  uintptr
	getMemoryMap               uintptr
	allocatePool               uintptr
	freePool                   uintptr
	createEvent                uintptr
	setTimer                   uintptr
	waitForEvent               uintptr
	signalEvent                uintptr
	closeEvent                 uintptr
	checkEvent                 uintptr
	installProtocolInterface   uintptr
	reinstallProtocolInterface uintptr
	uninstallProtocolInterface uintptr
	handleProtocol             uintptr // (Handle, *GUID, **VOID) → status
	reserved                   uintptr
	registerProtocolNotify     uintptr
	locateHandle               uintptr
	locateDevicePath           uintptr
	installConfigurationTable  uintptr
	loadImage                  uintptr
	startImage                 uintptr
	exit                       uintptr
	unloadImage                uintptr
	exitBootServices           uintptr
	getNextMonotonicCount      uintptr
	stall                      uintptr // (Microseconds) → status
	// … rest omitted
}

// efiSystemTable is enough of EFI_SYSTEM_TABLE for our purposes.
type efiSystemTable struct {
	hdr              [24]byte
	firmwareVendor   uintptr
	firmwareRevision uint32
	_pad1            [4]byte
	consoleInHandle  efiHandle
	conIn            uintptr
	consoleOutHandle efiHandle
	conOut           *efiSimpleTextOutput
	stdErrHandle     efiHandle
	stdErr           uintptr
	runtimeServices  *efiRuntimeServices
	bootServices     *efiBootServices
	// numTableEntries + configurationTable omitted
}

// efiLoadedImageProtocol — the structure we need to inspect.
// EFI_LOADED_IMAGE_PROTOCOL_GUID = 5B1B31A1-9562-11d2-8E3F-00A0C969723B
type efiLoadedImageProtocol struct {
	revision     uint32
	_pad         [4]byte
	parentImage  efiHandle
	systemTable  *efiSystemTable
	deviceHandle efiHandle
	filePath     uintptr // *EFI_DEVICE_PATH_PROTOCOL — what we assert non-NULL
	reserved     uintptr
	// … remaining fields omitted; we only need filePath
}

// LoadedImageProtocol GUID.
var loadedImageGUID = efiGUID{
	Data1: 0x5B1B31A1,
	Data2: 0x9562,
	Data3: 0x11d2,
	Data4: [8]uint8{0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B},
}

// Reset types (EFI_RESET_TYPE).
const (
	efiResetCold     uintptr = 0
	efiResetWarm     uintptr = 1
	efiResetShutdown uintptr = 2
)

//go:export efi_main
func efi_main(imageHandle efiHandle, st *efiSystemTable) efiStatus {
	co := st.conOut
	bs := st.bootServices

	writeUTF16(co, "Windows Boot Manager (cloud-boot stub)\r\n")
	writeUTF16(co, "  asserting LoadedImage.FilePath was populated by cloud-boot...\r\n")

	// Open LoadedImageProtocol on our own handle.
	var liPtr uintptr
	st1 := efiCall3(bs.handleProtocol,
		imageHandle,
		uintptr(unsafe.Pointer(&loadedImageGUID)),
		uintptr(unsafe.Pointer(&liPtr)))
	if st1 != 0 {
		writeUTF16(co, "  FAIL: HandleProtocol(LoadedImage) returned non-success\r\n")
		shutdown(st)
		return st1
	}
	li := (*efiLoadedImageProtocol)(unsafe.Pointer(liPtr))
	if li.filePath == 0 {
		writeUTF16(co, "  FAIL: LoadedImage.FilePath is NULL — cloud-boot did NOT populate it\r\n")
		writeUTF16(co, "  (the loader fell back to LoadImage(SourceBuffer) instead of DevicePath)\r\n")
		shutdown(st)
		return 1
	}
	writeUTF16(co, "  routing OK — FilePath non-NULL, cloud-boot's DevicePath handoff worked\r\n")
	writeUTF16(co, "  would now read BCD + winload.efi (this stub stops here)\r\n")

	// Drain the serial buffer.
	efiCall1(bs.stall, 250000) // 250 ms

	shutdown(st)
	// Unreachable, but the Go compiler insists on a return.
	return 0
}

func shutdown(st *efiSystemTable) {
	rt := st.runtimeServices
	if rt == nil {
		return
	}
	efiCall4(rt.resetSystem, efiResetShutdown, 0, 0, 0)
}

// writeUTF16 turns an ASCII string into a UTF-16LE NUL-terminated
// EFI string and hands it to ConOut.OutputString. Keeps a static
// scratch buffer so we don't need AllocatePool — no-heap pattern.
var utf16Buf [256]uint16

func writeUTF16(co *efiSimpleTextOutput, s string) {
	for i := 0; i < len(s) && i < len(utf16Buf)-1; i++ {
		utf16Buf[i] = uint16(s[i])
	}
	utf16Buf[len(s)] = 0
	efiCall2(co.outputString,
		uintptr(unsafe.Pointer(co)),
		uintptr(unsafe.Pointer(&utf16Buf[0])))
}

// External thunks (see thunk-{amd64,arm64}.S) that adapt TinyGo's
// Go-side calling convention to the UEFI calling convention. Same
// pattern as go-coff/stub.

//go:linkname efiCall1 efiCall1
func efiCall1(fn uintptr, a1 uintptr) efiStatus

//go:linkname efiCall2 efiCall2
func efiCall2(fn uintptr, a1, a2 uintptr) efiStatus

//go:linkname efiCall3 efiCall3
func efiCall3(fn uintptr, a1, a2, a3 uintptr) efiStatus

//go:linkname efiCall4 efiCall4
func efiCall4(fn uintptr, a1, a2, a3, a4 uintptr) efiStatus
