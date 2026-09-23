// arm64 thunks. Both Go and UEFI on arm64 use the same AAPCS64
// calling convention (args in x0..x7, return in x0, link in x30),
// so the only thing the thunk does is slide the function pointer
// out of x0 into x16 (a scratch register), shift remaining args
// left, then `br x16`. The link register is saved/restored across
// the call.

    .text

    .globl efiCall1
efiCall1:
    sub  sp, sp, #16
    str  x30, [sp]
    mov  x16, x0             // save fn
    mov  x0,  x1             // a1 → x0
    blr  x16
    ldr  x30, [sp]
    add  sp, sp, #16
    ret

    .globl efiCall2
efiCall2:
    sub  sp, sp, #16
    str  x30, [sp]
    mov  x16, x0
    mov  x0,  x1
    mov  x1,  x2
    blr  x16
    ldr  x30, [sp]
    add  sp, sp, #16
    ret

    .globl efiCall3
efiCall3:
    sub  sp, sp, #16
    str  x30, [sp]
    mov  x16, x0
    mov  x0,  x1
    mov  x1,  x2
    mov  x2,  x3
    blr  x16
    ldr  x30, [sp]
    add  sp, sp, #16
    ret

    .globl efiCall4
efiCall4:
    sub  sp, sp, #16
    str  x30, [sp]
    mov  x16, x0
    mov  x0,  x1
    mov  x1,  x2
    mov  x2,  x3
    mov  x3,  x4
    blr  x16
    ldr  x30, [sp]
    add  sp, sp, #16
    ret
