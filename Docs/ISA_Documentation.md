# RV64I ISA Documentation — Project Processor

This document is the complete reference for every instruction this
processor implements: its encoding format, its exact opcode/funct3/funct7
bit pattern, what the hardware actually does with it, and a hands-on
tutorial for hand-assembling your own instructions into the 32-bit hex
values you load into `instr_mem`.

This is written to the **actual RTL**, not the general RV64I spec — meaning
every table below reflects exactly what `control_unit.v`, `ALU_control.v`,
`ALU64.v`, and `imm_gen.v` do in this specific design. Where this core
differs from "real" RV64I hardware (and it does, in a few places — see
[Deviations From Standard RV64I](#deviations-from-standard-rv64i)), that's
called out explicitly.

---

## Table of Contents

1. [Quick Reference Card](#quick-reference-card)
2. [Instruction Formats](#instruction-formats)
3. [Immediate Encoding Rules](#immediate-encoding-rules)
4. [Opcode Map](#opcode-map)
5. [Full Instruction-by-Instruction Reference](#full-instruction-by-instruction-reference)
   - [R-type ALU instructions](#r-type-alu-instructions)
   - [I-type ALU immediate instructions](#i-type-alu-immediate-instructions)
   - [Load instructions](#load-instructions)
   - [Store instructions](#store-instructions)
   - [Branch instructions](#branch-instructions)
   - [Jump instructions](#jump-instructions)
   - [Upper-immediate instructions](#upper-immediate-instructions)
6. [ALU Control Code Reference](#alu-control-code-reference)
7. [Step-by-Step Encoding Tutorial](#step-by-step-encoding-tutorial)
8. [Worked Examples](#worked-examples)
9. [Common Encoding Mistakes](#common-encoding-mistakes)
10. [Deviations From Standard RV64I](#deviations-from-standard-rv64i)
11. [Register Reference](#register-reference)
12. [Mini-Assembler Reference (Python)](#mini-assembler-reference-python)

---

## Quick Reference Card

| Mnemonic | Format | Opcode | funct3 | funct7 | Operation |
|---|---|---|---|---|---|
| `add`  | R | `0110011` | `000` | `0000000` | `rd = rs1 + rs2` |
| `sub`  | R | `0110011` | `000` | `0100000` | `rd = rs1 - rs2` |
| `and`  | R | `0110011` | `111` | `0000000` | `rd = rs1 & rs2` |
| `or`   | R | `0110011` | `110` | `0000000` | `rd = rs1 \| rs2` |
| `xor`  | R | `0110011` | `100` | `0000000` | `rd = rs1 ^ rs2` |
| `sll`  | R | `0110011` | `001` | `0000000` | `rd = rs1 << rs2[5:0]` |
| `srl`  | R | `0110011` | `101` | `0000000` | `rd = rs1 >> rs2[5:0]` (logical) |
| `sra`  | R | `0110011` | `101` | `0100000` | `rd = rs1 >>> rs2[5:0]` (arithmetic) |
| `slt`  | R | `0110011` | `010` | `0000000` | `rd = (rs1 < rs2) ? 1 : 0` (signed) |
| `sltu` | R | `0110011` | `011` | `0000000` | `rd = (rs1 < rs2) ? 1 : 0` (unsigned) |
| `addi` | I | `0010011` | `000` | — | `rd = rs1 + imm` |
| `andi` | I | `0010011` | `111` | — | `rd = rs1 & imm` |
| `ori`  | I | `0010011` | `110` | — | `rd = rs1 \| imm` |
| `xori` | I | `0010011` | `100` | — | `rd = rs1 ^ imm` |
| `slli` | I | `0010011` | `001` | `0000000`* | `rd = rs1 << shamt` |
| `srli` | I | `0010011` | `101` | `0000000`* | `rd = rs1 >> shamt` (logical) |
| `srai` | I | `0010011` | `101` | `0100000`* | `rd = rs1 >>> shamt` (arithmetic) |
| `slti` | I | `0010011` | `010` | — | `rd = (rs1 < imm) ? 1 : 0` (signed) |
| `sltiu`| I | `0010011` | `011` | — | `rd = (rs1 < imm) ? 1 : 0` (unsigned) |
| `lw`/`ld`/`lb`/`lh`†| I | `0000011` | any | — | `rd = mem[rs1 + imm]` (always full 64-bit) |
| `sw`/`sd`/`sb`/`sh`†| S | `0100011` | any | — | `mem[rs1 + imm] = rs2` (always full 64-bit) |
| `beq`  | B | `1100011` | `000` | — | `if (rs1 == rs2) PC += imm` |
| `bne`  | B | `1100011` | `001` | — | `if (rs1 != rs2) PC += imm` |
| `blt`  | B | `1100011` | `100` | — | `if (rs1 < rs2) PC += imm` (signed) |
| `bge`  | B | `1100011` | `101` | — | `if (rs1 >= rs2) PC += imm` (signed) |
| `bltu` | B | `1100011` | `110` | — | `if (rs1 < rs2) PC += imm` (unsigned) |
| `bgeu` | B | `1100011` | `111` | — | `if (rs1 >= rs2) PC += imm` (unsigned) |
| `jal`  | J | `1101111` | — | — | `rd = PC+4; PC += imm` |
| `jalr` | I | `1100111` | `000` | — | `rd = PC+4; PC = (rs1+imm) & ~1` |
| `lui`  | U | `0110111` | — | — | `rd = imm` (immediate passed straight through) |
| `auipc`| U | `0010111` | — | — | `rd = PC + imm` |

\* `slli`/`srli`/`srai` use `instr[31:25]` exactly like an R-type `funct7`
field, even though they're encoded as I-type instructions — the top 7 bits
distinguish `srli` from `srai`, and the bottom 6 bits of `instr[25:20]` are
the actual shift amount (`shamt`).

† This hardware does **not** distinguish `lw`/`ld`/`lb`/`lh` (or
`sw`/`sd`/`sb`/`sh`) by `funct3` — every load/store always moves a full
64-bit value. See [Deviations](#deviations-from-standard-rv64i). It is
strongly recommended you always write `ld`/`sd` encodings (`funct3 = 011`)
for clarity, since that's what the hardware actually does regardless of what
you write.

---

## Instruction Formats

RISC-V has six base instruction encoding formats. This core implements
five of them (no `R4`-type, which is only used by some floating-point
extensions this core doesn't have).

```
 31        25 24      20 19      15 14    12 11       7 6        0
┌────────────┬─────────┬─────────┬────────┬──────────┬──────────┐
│  funct7    │   rs2   │   rs1   │ funct3 │    rd    │  opcode  │   R-type
├────────────┴─────────┼─────────┼────────┼──────────┼──────────┤
│      imm[11:0]       │   rs1   │ funct3 │    rd    │  opcode  │   I-type
├────────────┬─────────┼─────────┼────────┼──────────┼──────────┤
│ imm[11:5]  │   rs2   │   rs1   │ funct3 │ imm[4:0] │  opcode  │   S-type
├──┬─────────┼─────────┼─────────┼────────┼──┬───────┴┬─────────┤
│12│imm[10:5]│   rs2   │   rs1   │ funct3 │11│imm[4:1]│  opcode │   B-type
├──┴─────────┴─────────┴─────────┴────────┴┬─┴────────┴┬────────┤
│              imm[31:12]                  │    rd     │ opcode │   U-type
├──┬──────────────┬──┬─────────────────────┴──┬────────┼────────┤
│20│  imm[10:1]   │11│       imm[19:12]       │   rd   │ opcode │   J-type
└──┴──────────────┴──┴────────────────────────┴────────┴────────┘
```

Every format keeps `opcode` in bits `[6:0]` and (where present) `rd` in bits
`[11:7]` in the exact same place — this is what lets the same register file
read/write logic work for every instruction type without knowing the format
in advance.

---

## Immediate Encoding Rules

This is the single most error-prone part of hand-assembling RISC-V
instructions, because three of the five formats **scramble the immediate
bits** across the instruction word instead of storing them contiguously.
Here's exactly how `imm_gen.v` reconstructs each one — match these formulas
exactly when hand-encoding.

### I-type immediate (12 bits, sign-extended to 64)
```
imm[63:12] = instr[31]  (sign extension)
imm[11:0]  = instr[31:20]
```
Straightforward — it's just the top 12 bits of the instruction, copied down
and sign-extended. Used by `addi`/`andi`/`ori`/`xori`/`slti`/`sltiu`,
loads, and `jalr`.

### S-type immediate (12 bits, sign-extended to 64)
```
imm[63:12] = instr[31]  (sign extension)
imm[11:5]  = instr[31:25]
imm[4:0]   = instr[11:7]
```
Split into two pieces because `instr[11:7]` is normally the `rd` field — but
stores don't write a register, so that field is repurposed to hold the
bottom 5 immediate bits instead. Used by stores.

### B-type immediate (13 bits effective, but bit 0 is implicit zero —
branches always have an even byte offset; sign-extended to 64)
```
imm[63:13] = instr[31]  (sign extension)
imm[12]    = instr[31]
imm[11]    = instr[7]
imm[10:5]  = instr[30:25]
imm[4:1]   = instr[11:8]
imm[0]     = 0           (always — not stored, implied)
```
This is the scrambled one. Notice `instr[31]` is used *twice* (once as the
top bit of the immediate, once again as the sign-extension fill) — that's
normal and intentional, it's just how the sign bit propagates. The order in
the instruction word (`instr[7]` then `instr[30:25]` then `instr[11:8]`) is
specifically chosen so that bit 31 (the branch's sign bit) lines up with bit
31 of a B-type *and* a J-type instruction in the same position, simplifying
hardware sign-extension logic — but it makes the bits look completely
out-of-order if you're reading the raw hex by eye.

### U-type immediate (20 bits, placed in the upper bits, sign-extended to
64)
```
imm[63:32] = instr[31]   (sign extension)
imm[31:12] = instr[31:12]
imm[11:0]  = 0            (always — not stored, implied)
```
The simplest format — the 20 immediate bits are already contiguous in the
instruction word and just get shifted left by 12 (i.e. they directly become
bits 31 down to 12 of the result, with the bottom 12 bits zeroed). Used by
`lui`/`auipc`.

### J-type immediate (21 bits effective, bit 0 implicit zero;
sign-extended to 64)
```
imm[63:20] = instr[31]   (sign extension)
imm[20]    = instr[31]
imm[19:12] = instr[19:12]
imm[11]    = instr[20]
imm[10:1]  = instr[30:21]
imm[0]     = 0            (always — not stored, implied)
```
Even more scrambled than B-type. Used only by `jal`.

**Practical takeaway:** don't try to encode B-type or J-type immediates by
manually shuffling bits in your head every time. Use the worked formulas in
the [Step-by-Step Encoding Tutorial](#step-by-step-encoding-tutorial) below,
or better, use the [mini-assembler](#mini-assembler-reference-python)
provided at the end of this document, which encodes all of this correctly
for you from plain mnemonics.

---

## Opcode Map

The full opcode space this core's `control_unit` actually decodes
(everything else falls through to the `default` case, which sets all
control signals to 0 — effectively a silent no-op):

| `opcode[6:0]` | Hex | Format | Instructions | `RegWrite` | `MemRead` | `MemWrite` | `ALUSrc` | `Branch` | `Jump` | `ALUOp` |
|---|---|---|---|---|---|---|---|---|---|---|
| `0110011` | `0x33` | R | add, sub, and, or, xor, sll, srl, sra, slt, sltu | 1 | 0 | 0 | 0 | 0 | 0 | `10` |
| `0010011` | `0x13` | I | addi, andi, ori, xori, slli, srli, srai, slti, sltiu | 1 | 0 | 0 | 1 | 0 | 0 | `10` |
| `0000011` | `0x03` | I | lw/ld/lb/lh (all behave as a 64-bit load) | 1 | 1 | 0 | 1 | 0 | 0 | `00` |
| `0100011` | `0x23` | S | sw/sd/sb/sh (all behave as a 64-bit store) | 0 | 0 | 1 | 1 | 0 | 0 | `00` |
| `1100011` | `0x63` | B | beq, bne, blt, bge, bltu, bgeu | 0 | 0 | 0 | 0 | 1 | 0 | `01` |
| `1101111` | `0x6F` | J | jal | 1 | 0 | 0 | 0 | 0 | 1 | `00`(unused) |
| `1100111` | `0x67` | I | jalr | 1 | 0 | 0 | 1 | 0 | 1 | `00`(unused) |
| `0110111` | `0x37` | U | lui | 1 | 0 | 0 | 1 | 0 | 0 | `00`(overridden internally to PASS) |
| `0010111` | `0x17` | U | auipc | 1 | 0 | 0 | 1 | 0 | 0 | `00`(ADD, but with PC as operand A) |

`ALUOp` is the 2-bit signal that `control_unit` hands to `ALU_control`,
which then combines it with `funct3`/`funct7` to pick the actual 4-bit ALU
operation — see the [ALU Control Code Reference](#alu-control-code-reference)
below for that second-level decode.

---

## Full Instruction-by-Instruction Reference

### R-type ALU instructions

All R-type instructions share `opcode = 0110011`. They differ only by
`funct3` (and `funct7` for the two cases that need to distinguish a
variant: `add`/`sub` and `srl`/`sra`).

| Instr | funct3 | funct7 | Semantics |
|---|---|---|---|
| `add  rd, rs1, rs2` | `000` | `0000000` | `rd = rs1 + rs2` |
| `sub  rd, rs1, rs2` | `000` | `0100000` | `rd = rs1 - rs2` |
| `sll  rd, rs1, rs2` | `001` | `0000000` | `rd = rs1 << rs2[5:0]` |
| `slt  rd, rs1, rs2` | `010` | `0000000` | `rd = (signed(rs1) < signed(rs2)) ? 1 : 0` |
| `sltu rd, rs1, rs2` | `011` | `0000000` | `rd = (unsigned(rs1) < unsigned(rs2)) ? 1 : 0` |
| `xor  rd, rs1, rs2` | `100` | `0000000` | `rd = rs1 ^ rs2` |
| `srl  rd, rs1, rs2` | `101` | `0000000` | `rd = rs1 >> rs2[5:0]` (zero-fill) |
| `sra  rd, rs1, rs2` | `101` | `0100000` | `rd = rs1 >>> rs2[5:0]` (sign-fill) |
| `or   rd, rs1, rs2` | `110` | `0000000` | `rd = rs1 \| rs2` |
| `and  rd, rs1, rs2` | `111` | `0000000` | `rd = rs1 & rs2` |

Encoding template:
```
funct7[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | 0110011
```

Note: shift amounts for `sll`/`srl`/`sra` use the **full 6 bits**
(`rs2[5:0]`) of the register operand, since this is a 64-bit core (shift
amounts 0–63 are all valid; RV32I would only use `rs2[4:0]`).

### I-type ALU immediate instructions

Same ALU operations as the R-type set above, but with an immediate operand
instead of `rs2`. `opcode = 0010011`.

| Instr | funct3 | Semantics |
|---|---|---|
| `addi  rd, rs1, imm` | `000` | `rd = rs1 + imm` |
| `slli  rd, rs1, shamt` | `001` | `rd = rs1 << shamt` |
| `slti  rd, rs1, imm` | `010` | `rd = (signed(rs1) < signed(imm)) ? 1 : 0` |
| `sltiu rd, rs1, imm` | `011` | `rd = (unsigned(rs1) < unsigned(imm)) ? 1 : 0` |
| `xori  rd, rs1, imm` | `100` | `rd = rs1 ^ imm` |
| `srli  rd, rs1, shamt` | `101` | `rd = rs1 >> shamt` (zero-fill) |
| `srai  rd, rs1, shamt` | `101` | `rd = rs1 >>> shamt` (sign-fill) |
| `ori   rd, rs1, imm` | `110` | `rd = rs1 \| imm` |
| `andi  rd, rs1, imm` | `111` | `rd = rs1 & imm` |

Encoding template (general case, `addi`/`andi`/`ori`/`xori`/`slti`/`sltiu`):
```
imm[11:0][31:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | 0010011
```

Encoding template (shift variants `slli`/`srli`/`srai` — note these reuse
the top 7 bits as a funct7-style discriminator, and only the bottom 6 bits
of what would be the immediate field are the actual shift amount):
```
funct7[31:25] | shamt[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | 0010011
```
where `funct7 = 0000000` for `slli`/`srli` and `0100000` for `srai`.

### Load instructions

`opcode = 0000011`. Real RV64I distinguishes `lb`/`lh`/`lw`/`ld` (and their
unsigned `lbu`/`lhu`/`lwu` variants) by `funct3`. **This hardware ignores
`funct3` entirely for loads** — every load is a full 64-bit access, address
= `rs1 + imm`. Recommended encoding is `funct3 = 011` (the real `ld`
encoding) for clarity, since that's what actually happens regardless:

```
ld  rd, imm(rs1)      → rd = mem64[rs1 + imm]
```
Encoding template:
```
imm[11:0][31:20] | rs1[19:15] | 011 | rd[11:7] | 0000011
```

### Store instructions

`opcode = 0100011`. Same caveat as loads — `funct3` is ignored, every store
moves a full 64-bit value. Recommended encoding is `funct3 = 011` (real
`sd`):

```
sd  rs2, imm(rs1)     → mem64[rs1 + imm] = rs2
```
Encoding template:
```
imm[11:5][31:25] | rs2[24:20] | rs1[19:15] | 011 | imm[4:0][11:7] | 0100011
```
Note the operand order in assembly syntax: `sd rs2, imm(rs1)` — `rs2` is the
*value being stored*, `rs1` is the *base address register*. This trips
people up because it's the opposite emphasis from a load.

### Branch instructions

`opcode = 1100011`. All six compare `rs1` against `rs2` and, if the
condition holds, add the (sign-extended, sign bit replicated) `imm` to the
**branch instruction's own PC** (not PC+4) to compute the new PC.

| Instr | funct3 | Taken when... |
|---|---|---|
| `beq  rs1, rs2, label` | `000` | `rs1 == rs2` |
| `bne  rs1, rs2, label` | `001` | `rs1 != rs2` |
| `blt  rs1, rs2, label` | `100` | `signed(rs1) < signed(rs2)` |
| `bge  rs1, rs2, label` | `101` | `signed(rs1) >= signed(rs2)` |
| `bltu rs1, rs2, label` | `110` | `unsigned(rs1) < unsigned(rs2)` |
| `bgeu rs1, rs2, label` | `111` | `unsigned(rs1) >= unsigned(rs2)` |

Encoding template (see [B-type immediate](#b-type-immediate-13-bits-effective-but-bit-0-is-implicit-zero--branches-always-have-an-even-byte-offset-sign-extended-to-64)
above for exactly how `imm` maps into bits):
```
imm[12] | imm[10:5] | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[4:1] | imm[11] | 1100011
```

`imm` here is the **byte offset from the branch instruction's own address to
the target**, and must always be even (bit 0 is never stored — it's
implicitly 0). To branch backward to an earlier instruction, use a negative
offset (two's-complement, sign-extended).

### Jump instructions

#### `jal` — jump and link

`opcode = 1101111`, no `funct3`. `rd = PC+4` (the return address — the
address of the instruction *after* the `jal`), then `PC = PC + imm` (PC of
the `jal` itself, plus the immediate).

```
jal  rd, label
```
Encoding template (see [J-type immediate](#j-type-immediate-21-bits-effective-bit-0-implicit-zero-sign-extended-to-64)
above):
```
imm[20] | imm[10:1] | imm[11] | imm[19:12] | rd[11:7] | 1101111
```
Use `rd = x0` for an unconditional jump where you don't care about the
return address (the "I just want to goto somewhere" idiom — this is exactly
how this core's example test programs implement an infinite-loop halt:
`jal x0, <own address>`, i.e. an offset of 0).

#### `jalr` — jump and link register

`opcode = 1100111`, `funct3 = 000`. `rd = PC+4`, then
`PC = (rs1 + imm) & ~1` (the `& ~1` forces the LSB to 0, guaranteeing an
even/aligned target even if `rs1+imm` happened to be odd).

```
jalr  rd, imm(rs1)
```
Encoding template (ordinary I-type):
```
imm[11:0][31:20] | rs1[19:15] | 000 | rd[11:7] | 1100111
```

This is the only way to jump to a computed/dynamic address (register +
offset) rather than a fixed compile-time offset — useful for indirect calls,
return-from-subroutine (`jalr x0, 0(ra)`), or computed jump tables. Since
this core has no direct way to load a 64-bit absolute address in one
instruction, the standard pattern for "jump to an address I computed
earlier" is `auipc`/`addi` to build up the target into a register, then
`jalr` off of that register — see the worked example below.

### Upper-immediate instructions

`opcode = 0110111` (`lui`) or `0010111` (`auipc`), no `funct3`/`funct7` (the
full instruction word minus `rd`/`opcode` is the immediate).

```
lui    rd, imm20      → rd = imm20 << 12     (sign-extended to 64 bits)
auipc  rd, imm20      → rd = PC + (imm20 << 12)
```
Encoding template (both):
```
imm[19:0][31:12] | rd[11:7] | opcode
```

**Important hardware-specific note:** in this implementation, `lui` does
**not** add anything to a register — it is a pure pass-through of the
immediate. This matters because `instr[19:15]` (normally the `rs1` field)
is actually *part of the immediate* for a U-type instruction, not a real
register — so it would be incorrect (and was, in fact, a real bug fixed in
this codebase) to treat `lui` as `rd = rs1 + imm`. Likewise, `auipc` adds
the immediate specifically to **the auipc instruction's own PC**, not to any
register value.

`auipc` is typically paired with `addi` or `jalr` to build a PC-relative
absolute address spanning more than the 12-bit immediate range a single
I-type instruction allows:
```
auipc x5, 0          # x5 = PC of this instruction
addi  x5, x5, 16     # x5 = PC of this instruction + 16  (an absolute address)
jalr  x6, 0(x5)      # jump there, save return address in x6
```

---

## ALU Control Code Reference

This is the *second*-level decode this core uses internally. `control_unit`
produces a coarse 2-bit `ALUOp`, and `ALU_control` combines that with
`funct3`/`funct7` to produce the actual 4-bit code that `ALU64` switches on.
You generally don't need to think about this when writing assembly — it's
purely an implementation detail of how the hardware is structured — but
it's documented here in full because it's invaluable when debugging "why
did my instruction compute the wrong thing."

**`ALUOp` (from `control_unit`):**

| `ALUOp` | Meaning | Used by |
|---|---|---|
| `00` | Address computation — plain ADD | loads, stores, `jalr`, `auipc` |
| `01` | Branch comparison | all branches |
| `10` | Full R/I-type ALU decode (uses funct3/funct7) | R-type and I-type ALU ops |

**4-bit `alu_ctrl` (from `ALU_control`, fed into `ALU64`):**

| `alu_ctrl` | Operation | `ALUOp` it comes from | funct3 | funct7 |
|---|---|---|---|---|
| `0000` | ADD | `00` (always), or `10` with funct3=`000`,funct7≠`0100000` | — | — |
| `0001` | SUB | `10` with funct3=`000`,funct7=`0100000`; or `01` with funct3=`000`/`001` (beq/bne) | | |
| `0010` | AND | `10`, funct3=`111` | | |
| `0011` | OR | `10`, funct3=`110` | | |
| `0100` | XOR | `10`, funct3=`100` | | |
| `0101` | SLL | `10`, funct3=`001` | | |
| `0110` | SRL | `10`, funct3=`101`, funct7≠`0100000` | | |
| `0111` | SRA | `10`, funct3=`101`, funct7=`0100000` | | |
| `1000` | SLT (signed) | `10`, funct3=`010`; or `01` funct3=`100`/`101` (blt/bge) | | |
| `1001` | SLTU (unsigned) | `10`, funct3=`011`; or `01` funct3=`110`/`111` (bltu/bgeu) | | |
| `1010` | PASS (`result = B`) | special-cased directly in `cpu_core.v` for `lui`, bypassing `ALU_control` entirely | | |

Notice branches reuse the **same** ALU hardware as `sub`/`slt`/`sltu` — a
`beq`/`bne` literally computes `rs1 - rs2` and checks the `Zero` flag;
`blt`/`bge` compute `slt(rs1,rs2)` (1 or 0) and check whether that result is
1 or 0; `bltu`/`bgeu` do the same with `sltu`. This is why getting the
branch *condition* logic right requires correctly inverting the ALU's
`Zero` flag for some branch types and not others — `beq` wants `Zero==1`,
but `blt` wants `Zero==0` (because a `Zero` result there means "not less
than", i.e. don't branch) — see `cpu_core.v`'s `branch_condition` wire for
the exact per-`funct3` logic.

---

## Step-by-Step Encoding Tutorial

Let's hand-encode an instruction from scratch, end to end, picking one
example from each format.

### Example 1: `add x3, x1, x2` (R-type)

1. Opcode for R-type ALU ops: `0110011`
2. `funct3` for `add`: `000`
3. `funct7` for `add` (not `sub`): `0000000`
4. `rs2 = x2 = 5'b00010 = 2`
5. `rs1 = x1 = 5'b00001 = 1`
6. `rd  = x3 = 5'b00011 = 3`

Assemble the bits, MSB to LSB:
```
funct7    rs2    rs1    funct3  rd      opcode
0000000   00010  00001  000     00011   0110011
```
Concatenated: `0000000 00010 00001 000 00011 0110011`
= `0000 0000 0010 0000 1000 0001 1011 0011`
= `0x002081B3`

### Example 2: `addi x1, x0, 5` (I-type)

1. Opcode: `0010011`
2. `funct3` for `addi`: `000`
3. `imm = 5` → as 12-bit two's complement: `000000000101`
4. `rs1 = x0 = 00000`
5. `rd = x1 = 00001`

```
imm[11:0]      rs1     funct3  rd      opcode
000000000101   00000   000     00001   0010011
```
= `0000 0000 0101 0000 0000 0000 1001 0011`
= `0x00500093`

### Example 3: `sd x3, 0(x0)` (S-type)

1. Opcode: `0100011`
2. `funct3`: `011` (recommended, though ignored by hardware)
3. `imm = 0` → 12-bit: `000000000000`, split into `imm[11:5]=0000000` and
   `imm[4:0]=00000`
4. `rs2 = x3 = 00011` (value being stored)
5. `rs1 = x0 = 00000` (base address)
6. `rd` field is repurposed to hold `imm[4:0]` for S-type, so there's no
   real `rd` here.

```
imm[11:5]  rs2     rs1     funct3  imm[4:0]  opcode
0000000    00011   00000   011     00000     0100011
```
= `0000 0000 0011 0000 0000 0011 0010 0011`
= `0x00303023`

### Example 4: `bne x1, x2, LOOP` where LOOP is 24 bytes before this
instruction (B-type)

1. Opcode: `1100011`
2. `funct3` for `bne`: `001`
3. `imm = -24` (branch backward 24 bytes). As a 13-bit two's complement
   value (remember bit 0 is always 0 and not stored):
   `-24` in 13-bit two's complement = `1111111101000`.
   Split per the B-type immediate rule:
   - `imm[12]` = `1`
   - `imm[11]` = `1`
   - `imm[10:5]` = `111111`
   - `imm[4:1]` = `0100`
   - `imm[0]` = `0` (implicit, not stored)
4. `rs2 = x2 = 00010`
5. `rs1 = x1 = 00001`

```
imm[12] imm[10:5] rs2    rs1    funct3 imm[4:1] imm[11] opcode
1       111111    00010  00001  001    0100     1       1100011
```
Concatenated bit-for-bit (32 bits total):
`1 111111 00010 00001 001 0100 1 1100011`
= `1111 1110 0010 0000 1001 0100 1110 0011`
= `0xFE2094E3`

(This was double-checked by re-deriving it field-by-field from the known-
correct value rather than trusting a single manual pass — exactly the kind
of cross-check you should do for any B-type or J-type immediate you hand
encode. When in doubt, verify against the
[mini-assembler](#mini-assembler-reference-python) below.)

### Example 5: `jal x0, +0` (J-type, self-jump halt idiom)

1. Opcode: `1101111`
2. `imm = 0` → trivially all-zero immediate bits
3. `rd = x0 = 00000`

```
imm[20] imm[10:1]  imm[11] imm[19:12] rd     opcode
0       0000000000 0       00000000  00000  1101111
```
= `0x0000006F`

This is the standard "park here forever" halt instruction used at the end
of every example program in this project.

### Example 6: `lui x15, 0x12345` (U-type)

1. Opcode: `0110111`
2. `imm20 = 0x12345` (the 20-bit immediate, representing bits 31:12 of the
   final value)
3. `rd = x15 = 01111`

```
imm[19:0]              rd      opcode
00010010001101000101   01111   0110111
```
= `0x123457B7`

Result: `x15 = 0x12345000` (the 20-bit immediate shifted left by 12, with
the bottom 12 bits zero).

---

## Worked Examples

### A 3-instruction "hello, ALU" smoke test

```verilog
DUT.IM.memory[0] = 32'h00500093; // addi x1, x0, 5      x1 = 5
DUT.IM.memory[1] = 32'h00A00113; // addi x2, x0, 10     x2 = 10
DUT.IM.memory[2] = 32'h002081B3; // add  x3, x1, x2     x3 = 15
DUT.IM.memory[3] = 32'h0000006F; // jal  x0, +0         halt (park here)
```
Expected after running: `x1=5, x2=10, x3=15`.

### A countdown loop using `bne`

```verilog
DUT.IM.memory[0] = 32'h00500213; // addi x4, x0, 5       counter = 5
                                   // LOOP:
DUT.IM.memory[1] = 32'hFFF20213; // addi x4, x4, -1      counter--
DUT.IM.memory[2] = 32'hFE021EE3; // bne  x4, x0, LOOP     loop while counter != 0
DUT.IM.memory[3] = 32'h0000006F; // jal  x0, +0          halt
```
Expected: `x4 = 0` after 5 iterations.

(`0xFE021EE3` encodes `bne x4,x0,-8` — back to the `addi x4,x4,-1`
instruction, two instructions / 8 bytes behind the branch.)

### Indirect jump via `auipc` + `jalr`

```verilog
DUT.IM.memory[0]  = 32'h00000E17; // auipc x28, 0         x28 = PC of this instr
DUT.IM.memory[1]  = 32'h010E0E13; // addi  x28, x28, 16   x28 += 16 → addr of memory[4]
DUT.IM.memory[2]  = 32'h000E0EE7; // jalr  x29, 0(x28)    jump to x28, x29 = return addr
DUT.IM.memory[3]  = 32'h3E700F13; // addi  x30, x0, 999   (skipped over — never executes)
DUT.IM.memory[4]  = 32'h00900F13; // addi  x30, x0, 9     <- jump lands here, x30 = 9
DUT.IM.memory[5]  = 32'h0000006F; // jal   x0, +0         halt
```
Expected: `x30 = 9` (not `999` — proving the jump actually skipped
`memory[3]`), `x29` holds the return address (`memory[2]`'s address + 4).

---

## Common Encoding Mistakes

1. **Forgetting B-type and J-type immediates encode a *byte offset relative
   to the branch/jump's own address*, not an absolute address.** If you
   want to jump to absolute instruction index `N` from current instruction
   index `M`, the immediate is `(N - M) * 4`.

2. **Off-by-one on which instruction is "target."** When counting bytes for
   a backward branch, count from the branch instruction's own address to
   the target instruction's address — not from the *next* instruction after
   the branch.

3. **Forgetting the immediate must be even for B/J types.** Bit 0 is never
   stored; if your computed byte offset happens to be odd, you have a bug
   somewhere upstream (instruction addresses are always multiples of 4 in
   this core, so any valid offset between two instruction addresses is
   automatically a multiple of 4, hence always even).

4. **Mixing up `sw`/`sd` operand order.** It's `sd rs2, imm(rs1)` — the
   *first* operand is the value, the *second* is the base register. This is
   backwards from how most people instinctively read "store A into B."

5. **Treating `lui`/`auipc`'s `instr[19:15]` field as a real register.**
   It's part of the immediate. Don't read register data from it when
   manually tracing through what an instruction "should" do — and if you're
   extending this core's hardware yourself, don't wire that field into the
   register file's `rs1` read port for these two opcodes (this exact mistake
   was a real bug found and fixed in this codebase early on).

6. **Forgetting `slli`/`srli`/`srai` use the top 7 bits as a funct7-style
   discriminator, not extra immediate bits.** The actual shift amount is
   only `instr[25:20]` (6 bits, since this is a 64-bit core with shift
   amounts 0–63) — don't accidentally compute a 12-bit immediate and dump it
   into the same field positions you'd use for `addi`.

7. **Forgetting every load/store on this specific hardware moves a full
   64-bit value, regardless of what `funct3` you write.** If you're porting
   a real RV64I program that uses `lw` and `sw` (32-bit-width ops) expecting
   32-bit semantics, the results will not match — this core always reads/
   writes the full 8 bytes at the computed address.

8. **Forgetting to end your program with a halt.** If the PC walks off the
   end of your loaded instructions into uninitialized (`X`) memory, behavior
   is undefined from that point on. Always end with `jal x0, <own address>`.

---

## Deviations From Standard RV64I

A consolidated list (cross-referenced with the README's
"Known Limitations" section) of everywhere this specific implementation
differs from the official RISC-V RV64I specification:

| Area | Standard RV64I | This core |
|---|---|---|
| Load/store width | `funct3` selects byte/half/word/double, signed or unsigned | Always full 64-bit, `funct3` ignored entirely |
| System instructions | `ecall`/`ebreak`/`fence`/CSR access defined | Not implemented; not decoded at all |
| M-extension | Separate extension, not part of base RV64I anyway | Not implemented (correctly out of scope) |
| Exceptions/traps | Illegal instructions trap | Illegal opcodes silently no-op (all control signals 0) |
| Branch prediction | Implementation-defined; real cores usually predict | None — always "predict not-taken," resolved in EX, fixed 2-cycle flush penalty on any taken branch/jump |
| Compressed (`C`) extension | Optional 16-bit instruction extension | Not implemented (all instructions are 32-bit) |

---

## Register Reference

| Register | RISC-V ABI name (if you choose to follow convention) | Notes |
|---|---|---|
| `x0` | `zero` | Hardwired to 0. Writes are silently discarded. |
| `x1`–`x31` | — | No ABI register-usage convention is enforced by this hardware — it's a bare pipeline, not a full calling-convention-aware processor. Use any register for any purpose; the only special one is `x0`. |

This core does not enforce or assume any calling convention (no automatic
stack pointer, no enforced `ra`/`sp`/argument registers) — if you want one
for a larger test program, you establish and maintain it entirely in your
own assembly, e.g. by convention treating `x2` as a stack pointer and
manually doing `addi sp, sp, -N` / loads/stores around it, the same way real
software toolchains do, just without any hardware or assembler enforcing it
for you.

---

## Mini-Assembler Reference (Python)

If you'd rather not hand-encode every instruction, here's a minimal Python
assembler that matches this core's exact encoding rules (including correct
B-type/J-type immediate scrambling and forward/backward label resolution).
Save this as `asm.py` and use it as shown below.

```python
class Asm:
    def __init__(self):
        self.lines = []
        self.labels = {}

    def L(self, name):
        self.labels[name] = len(self.lines)

    def add(self, op, *args):
        self.lines.append({'op': op, 'args': args})

    def assemble(self):
        return [self.encode(i, ln) for i, ln in enumerate(self.lines)]

    def resolve(self, idx, label):
        return (self.labels[label] - idx) * 4

    def encode(self, idx, ln):
        op, a = ln['op'], ln['args']

        def r(x):
            return x if isinstance(x, int) else int(x.lower().lstrip('x'))

        def imm_bits(v, bits):
            return v & ((1 << bits) - 1)

        def R(o, rd, rs1, rs2, f3, f7):
            return (f7 << 25) | (r(rs2) << 20) | (r(rs1) << 15) | (f3 << 12) | (r(rd) << 7) | o

        def I(o, rd, rs1, f3, imm):
            imm = imm_bits(imm, 12)
            return (imm << 20) | (r(rs1) << 15) | (f3 << 12) | (r(rd) << 7) | o

        def S(o, rs1, rs2, f3, imm):
            imm = imm_bits(imm, 12)
            return (((imm >> 5) & 0x7F) << 25) | (r(rs2) << 20) | (r(rs1) << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | o

        def B(o, rs1, rs2, f3, imm):
            imm = imm_bits(imm, 13)
            b12, b11 = (imm >> 12) & 1, (imm >> 11) & 1
            b10_5, b4_1 = (imm >> 5) & 0x3F, (imm >> 1) & 0xF
            return (b12 << 31) | (b10_5 << 25) | (r(rs2) << 20) | (r(rs1) << 15) | (f3 << 12) | (b4_1 << 8) | (b11 << 7) | o

        def U(o, rd, imm):
            return (imm_bits(imm, 20) << 12) | (r(rd) << 7) | o

        def J(o, rd, imm):
            imm = imm_bits(imm, 21)
            b20, b19_12 = (imm >> 20) & 1, (imm >> 12) & 0xFF
            b11, b10_1 = (imm >> 11) & 1, (imm >> 1) & 0x3FF
            return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (r(rd) << 7) | o

        R_OPS = {'add': (0, 0), 'sub': (0, 0x20), 'and': (7, 0), 'or': (6, 0),
                 'xor': (4, 0), 'sll': (1, 0), 'srl': (5, 0), 'sra': (5, 0x20),
                 'slt': (2, 0), 'sltu': (3, 0)}
        I_OPS = {'addi': 0, 'andi': 7, 'ori': 6, 'xori': 4, 'slti': 2, 'sltiu': 3}

        if op in R_OPS:
            f3, f7 = R_OPS[op]
            return R(0x33, a[0], a[1], a[2], f3, f7)
        if op in I_OPS:
            return I(0x13, a[0], a[1], I_OPS[op], a[2])
        if op == 'slli': return I(0x13, a[0], a[1], 1, a[2] & 0x3F)
        if op == 'srli': return I(0x13, a[0], a[1], 5, a[2] & 0x3F)
        if op == 'srai': return I(0x13, a[0], a[1], 5, (a[2] & 0x3F) | (0x20 << 5))
        if op in ('lw', 'ld'):
            rd, imm, rs1 = a
            return I(0x03, rd, rs1, 3, imm)
        if op in ('sw', 'sd'):
            rs2, imm, rs1 = a
            return S(0x23, rs1, rs2, 3, imm)
        if op in ('beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu'):
            f3 = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}[op]
            return B(0x63, a[0], a[1], f3, self.resolve(idx, a[2]))
        if op == 'jal':
            return J(0x6F, a[0], self.resolve(idx, a[1]))
        if op == 'jalr':
            return I(0x67, a[0], a[1], 0, a[2])
        if op == 'lui':
            return U(0x37, a[0], a[1])
        if op == 'auipc':
            return U(0x17, a[0], a[1])
        raise ValueError(f"unknown op {op}")
```

**Usage:**
```python
from asm import Asm
A = Asm()
a, L = A.add, A.L

a('addi', 'x4', 'x0', 5)      # 0
L('LOOP')
a('addi', 'x4', 'x4', -1)     # 1
a('bne', 'x4', 'x0', 'LOOP')  # 2
a('jal', 'x0', 'HALT')        # 3
L('HALT')
a('jal', 'x0', 'HALT')        # 4

for i, w in enumerate(A.assemble()):
    print(f"DUT.IM.memory[{i}] = 32'h{w & 0xFFFFFFFF:08X};")
```
This prints ready-to-paste `DUT.IM.memory[i] = 32'h....;` lines for your
testbench, with every label reference (forward or backward) correctly
resolved to the right byte offset — including all the B-type/J-type bit
scrambling described earlier in this document, handled for you.
