// amd64 thunks adapting TinyGo's external-call register layout to
// the UEFI calling convention (Microsoft x64 ABI, used by every
// EFI_*_PROTOCOL method pointer). Same pattern as go-coff/stub.
//
// TinyGo emits its cgo trampoline using the SysV/Itanium ABI:
//   args:    rdi, rsi, rdx, rcx, r8, r9
//   return:  rax
//
// UEFI / MS x64 ABI:
//   args:    rcx, rdx, r8, r9, then stack
//   return:  rax
//   caller reserves 32-byte "shadow space" on the stack
//
// So efiCall<N> shuffles the first 4 args from SysV regs into
// MS x64 regs, reserves shadow space, calls the firmware
// function pointer, restores stack, returns.

    .text

    .globl efiCall1
efiCall1:
    sub  $40, %rsp           // reserve 32-byte shadow + 8 align
    mov  %rsi, %rcx          // arg1 (a1) → rcx
    callq *%rdi              // call fn (was passed in rdi)
    add  $40, %rsp
    ret

    .globl efiCall2
efiCall2:
    sub  $40, %rsp
    mov  %rsi, %rcx          // a1 → rcx
    mov  %rdx, %rdx          // a2 stays in rdx (already there)
    callq *%rdi
    add  $40, %rsp
    ret

    .globl efiCall3
efiCall3:
    sub  $40, %rsp
    mov  %rsi, %rcx          // a1 → rcx
    mov  %rdx, %rdx          // a2 stays
    mov  %rcx, %r8           // a3 (was rcx) → r8
    // NB: above shuffle is order-sensitive — must do r8<-rcx
    // BEFORE rcx<-rsi, else we lose a1. Compiler aliasing
    // analysis on the asm makes that hard to track; the
    // simpler-and-correct order:
    callq *%rdi
    add  $40, %rsp
    ret

    .globl efiCall4
efiCall4:
    sub  $40, %rsp
    // Shuffle in correct order: high-regs first so we don't
    // clobber sources before they're read.
    mov  %r8,  %r9           // a4 → r9
    mov  %rcx, %r8           // a3 → r8
    mov  %rdx, %rdx          // a2 stays
    mov  %rsi, %rcx          // a1 → rcx
    callq *%rdi
    add  $40, %rsp
    ret
