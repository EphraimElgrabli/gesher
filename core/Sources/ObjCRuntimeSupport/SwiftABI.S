#if defined(__arm64__)

.text
.p2align 2
.globl _ObjCCallSwiftAllocatingInitializer
_ObjCCallSwiftAllocatingInitializer:
    pacibsp
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16

    mov x16, x0
    mov x0, x1
    mov x1, x2
    mov x20, x3
    blr x16

    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    retab

 .p2align 2
.globl _ObjCCallSwiftMethodValue
_ObjCCallSwiftMethodValue:
    pacibsp
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x16, x0
    mov x20, x1
    mov x0, x2
    mov x1, x3
    mov x8, x4
    blr x16
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    retab

 .p2align 2
.globl _ObjCCallSwiftMethod4
_ObjCCallSwiftMethod4:
    pacibsp
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x16, x0
    mov x20, x1
    mov x0, x2
    mov x1, x3
    mov x2, x4
    mov x3, x5
    blr x16
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    retab

// Throwing static generic initializer of a protocol extension, e.g. Coherence's
// `CRDT.init(serializedData:)`: x0/x1 = the two-word argument (consumed), x2 = Self metadata,
// x3 = Self's witness table, x20 = Self metatype (swiftself), x8 = indirect result,
// x21 = error (swifterror). The thrown error, or 0, is stored to errorOut.
 .p2align 2
.globl _ObjCCallSwiftThrowingGenericInit
_ObjCCallSwiftThrowingGenericInit:
    pacibsp
    stp x22, x21, [sp, #-48]!
    stp x20, x19, [sp, #16]
    stp x29, x30, [sp, #32]
    add x29, sp, #32
    mov x16, x0
    mov x19, x6
    mov x8, x5
    mov x0, x1
    mov x1, x2
    mov x2, x3
    mov x20, x3
    mov x3, x4
    mov x21, #0
    blr x16
    str x21, [x19]
    ldp x29, x30, [sp, #32]
    ldp x20, x19, [sp, #16]
    ldp x22, x21, [sp], #48
    retab

#else

#error "Swift ABI bridge currently supports arm64 only."

#endif
