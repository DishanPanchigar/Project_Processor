# Project KreaRV64I — A 5-Stage Pipelined RV64I CPU Core

A synthesizable Verilog implementation of a 64-bit RISC-V (RV64I base integer
subset) CPU, built as a classic 5-stage pipeline (Fetch → Decode → Execute →
Memory → Write-back) with hazard detection, data forwarding, and full
branch/jump support.

This README covers the architecture, the file layout, how to build and
simulate the project, how to load your own programs, and a troubleshooting
section built from real issues encountered while bringing this core up.

For the complete instruction encoding reference (opcodes, funct3/funct7
tables, immediate formats, and a step-by-step "how do I hand-assemble an
instruction" tutorial), see **`ISA_Documentation.md`** in **`Docs`** folder.
That document is the one you want open beside you while writing test
programs.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Pipeline Stages](#pipeline-stages)
3. [Hazard Handling](#hazard-handling)
4. [File Structure](#file-structure)
5. [Module Reference](#module-reference)
6. [Building and Simulating](#building-and-simulating)
7. [Loading a Program](#loading-a-program)
8. [Known Limitations](#known-limitations)
9. [Troubleshooting](#troubleshooting)
10. [Design Notes / Changelog](#design-notes--changelog)

---

## Architecture Overview

```
                ┌──────────┐
   instr_addr → │  IF      │ → instr_in
                │  (PC,    │
                │  instr   │
                │  fetch)  │
                └────┬─────┘
                     │ IF/ID latch
                ┌────▼─────┐
                │  ID      │  decode, register read,
                │          │  immediate generation,
                │          │  hazard detection
                └────┬─────┘
                     │ ID/EX latch
                ┌────▼─────┐
                │  EX      │  ALU, branch/jump resolution,
                │          │  forwarding muxes
                └────┬─────┘
                     │ EX/MEM latch
                ┌────▼─────┐
                │  MEM     │  data memory read/write
                └────┬─────┘
                     │ MEM/WB latch
                ┌────▼─────┐
                │  WB      │  register file write-back
                └──────────┘
```

- **Datapath width:** 64-bit (RV64I) throughout the register file, ALU, and
  memory data path. Instructions themselves are always 32 bits (no compressed
  `C` extension).
- **Register file:** 32 general-purpose 64-bit registers, `x0`–`x31`. `x0` is
  hardwired to zero (writes to it are silently dropped; reads always return
  0).
- **No privileged/system instructions:** no CSR access, no `ecall`/`ebreak`,
  no interrupts/exceptions, no `fence`. This is a clean RV64I integer
  pipeline for educational/simulation purposes, not a full application
  processor.
- **No M-extension:** no hardware `mul`/`div`. If you need multiplication,
  you must synthesize it from `add`/`sll`/loops in your own test programs.
- **Single memory access width:** loads and stores always move a full 64-bit
  word regardless of the `funct3` field. See
  [Known Limitations](#known-limitations) for what this means practically.

---

## Pipeline Stages

| Stage | What happens | Key signals |
|---|---|---|
| **IF** | `PC` indexes `instr_mem` combinationally; `PC` updates to `PC+4`, a branch target, or a jump target at the next clock edge. | `instr_addr`, `instr_in`, `PCWrite` |
| **ID** | Decode `opcode`/`rs1`/`rs2`/`rd` from `IF_ID_instr`; `control_unit` produces control signals; `reg_file` is read combinationally (with same-cycle write-through to handle WB-stage same-cycle hazards); `imm_gen` extracts and sign-extends the immediate; `hazard_detection_unit` checks for a load-use hazard. | `RegWrite_ID`, `MemRead_ID`, …, `rs1_data`, `rs2_data`, `imm_ID` |
| **EX** | Forwarding muxes select the freshest operand values; `ALU_control` picks the 4-bit ALU operation; `ALU64` computes the result; branch condition and jump targets are resolved **here** (not in MEM) — this is a classic "1-cycle-early" branch resolution design with a 2-instruction misprediction flush penalty. | `alu_result`, `zero`, `take_branch`, `is_jal`, `is_jalr` |
| **MEM** | `data_mem` is read or written using the EX-stage ALU result as the address. | `MemRead`, `MemWrite`, `data_addr`, `write_data`, `read_data` |
| **WB** | The register file is written with either the loaded memory value, the ALU result, or `PC+4` (for `jal`/`jalr`). | `write_back_data`, `MEM_WB_RegWrite` |

### Branch/Jump resolution timing

Branches and jumps are decided **in the EX stage**, not earlier. That means
by the time a branch instruction reaches EX, the two instructions
immediately following it in program order have already been fetched
speculatively (always "not-taken" / sequential prediction). If the branch
turns out to be taken (or it's a `jal`/`jalr`), both the `IF/ID` and `ID/EX`
pipeline latches are flushed (zeroed out) on that same clock edge that
updates `PC` to the new target. This gives a **2-cycle misprediction
penalty** for every taken branch or jump — there's no branch predictor here,
it's always "assume not taken, recover if wrong."

---

## Hazard Handling

### Data hazards — forwarding

The EX stage has its own forwarding muxes (`forwardA`/`forwardB` in
`cpu_core.v`) that compare the *destination register* of the instructions
currently sitting in `EX/MEM` and `MEM/WB` against the *source registers* of
the instruction currently in `ID/EX`:

- If `EX_MEM_rd` matches and `EX_MEM_RegWrite` is set → forward the EX/MEM
  ALU result (1-cycle-old value, the fastest path).
- Else if `MEM_WB_rd` matches and `MEM_WB_RegWrite` is set → forward the
  write-back value (2-cycle-old value).
- Else → use the register file value latched into `ID/EX` normally.

This covers ALU-to-ALU dependencies and ALU-result-used-as-store-data with
zero stalls.

### Data hazards — load-use stall

A load's result isn't available until the **MEM** stage. If the very next
instruction needs that loaded value in **EX** (one stage too early for
forwarding to help), `hazard_detection_unit` detects this
("load-use hazard") and:
1. Freezes the PC (`PCWrite = 0`)
2. Freezes the `IF/ID` latch (`IF_ID_Write = 0`)
3. Forces a bubble into `ID/EX` (`control_stall = 1`, which zeroes all
   control signals for that cycle, turning the in-flight instruction into a
   no-op for one cycle)

This costs exactly 1 stall cycle, after which the EX/MEM forward picks up
the loaded value normally.

### Control hazards — branch/jump flush

As described above: every taken branch, `jal`, or `jalr` flushes 2
instructions' worth of incorrectly-fetched work (`IF/ID` and `ID/EX` both
zeroed on the same edge `PC` jumps to its new target).

---

## File Structure

```
Project_Processor/
├── RTL/
│   ├── ALU64.v                  64-bit ALU (add/sub/logic/shift/compare/pass)
│   ├── ALU_control.v            ALUOp + funct3/funct7 → 4-bit ALU control code
│   ├── adder_4.v                4-bit carry-lookahead/ripple adder building block
│   ├── adder_64.v               64-bit adder built from adder_4 slices
│   ├── control_unit.v           opcode → {RegWrite, MemRead, MemWrite, ALUSrc,
│   │                             Branch, Jump, ALUOp}
│   ├── cpu_core.v                 the pipeline itself: all 5 stages, latches,
│   │                             forwarding, hazard wiring, branch/jump logic
│   ├── data_mem.v                256-entry x 64-bit data memory
│   ├── hazard_detection_unit.v   load-use hazard detector
│   ├── imm_gen.v                  instruction → sign-extended 64-bit immediate
│   ├── instr_mem.v               1025-entry x 32-bit instruction memory
│   ├── multiplexers.v             generic mux helper module(s)
│   ├── pc.v                       standalone PC register (reference component)
│   ├── reg_file.v                32 x 64-bit register file
│   ├── register.v                 generic register helper module
│   └── test_environment.v        top-level wrapper wiring cpu_core + instr_mem
│                                  + data_mem together
├── Testbenches/
│   └── test_environment_tb.v     your simulation entry point — clock/reset
│                                  generation, program loading, result checks
└── Simulation/
    └── (compiled .vvp output goes here)
```

---

## Module Reference

### `cpu_core` — top-level pipeline

```verilog
module cpu_core (
    input clk,
    input rst,

    output [63:0] instr_addr,
    input  [31:0] instr_in,

    output MemRead,
    output MemWrite,
    output [63:0] data_addr,
    output [63:0] write_data,
    input  [63:0] read_data
);
```
This is a Harvard-architecture core: separate instruction and data memory
ports, no shared bus. `instr_addr`/`instr_in` connect to `instr_mem`;
`MemRead`/`MemWrite`/`data_addr`/`write_data`/`read_data` connect to
`data_mem`. Both are wired up for you already in `test_environment.v`.

### `test_environment` — top-level test wrapper

Instantiates `cpu_core` (as `CPU`), `instr_mem` (as `IM`), and `data_mem` (as
`DM`), and wires them together. **This is the module your testbench
instantiates.** Hierarchical paths like `DUT.CPU.PC`, `DUT.IM.memory[i]`, and
`DUT.DM.memory[i]` all go through this wrapper (assuming you name your
instance `DUT` in the testbench, which the provided testbench does).

### `instr_mem` — instruction memory

```verilog
module instr_mem (
    input [63:0] addr,
    output [31:0] instr
);
reg [31:0] memory [0:1024];
assign instr = memory[addr[9:2]];
endmodule
```
- 1025 32-bit-wide entries, addressed by `addr[9:2]` (i.e. `byte_address / 4`
  — instructions are always 4-byte aligned).
- **No default program is loaded.** `memory[]` starts as all-`X`
  (uninitialized) until something writes into it. Your testbench is
  responsible for loading a program before the clock starts toggling — see
  [Loading a Program](#loading-a-program).
- Always end a program with an instruction that keeps the PC inside the
  region you actually loaded (a self-jump `jal x0, <its own address>` is the
  standard idiom) — otherwise the PC can wander into unloaded (`X`) memory
  and the core's behavior becomes undefined.

### `data_mem` — data memory

```verilog
module data_mem (
    input clk,
    input MemRead,
    input MemWrite,
    input [63:0] addr,
    input [63:0] write_data,
    output reg [63:0] read_data
);
reg [63:0] memory [0:255];
```
- 256 64-bit-wide entries, addressed by `addr[9:2]`. Because each entry is 8
  bytes wide but the index still increments by 1 for every 4 bytes of
  *address*, consecutive **8-byte-aligned** addresses (0, 8, 16, 24, …) map
  to indices 0, 2, 4, 6, … — i.e. every *other* memory index. **Always use
  multiples of 8 for your load/store addresses** to avoid two different
  64-bit stores partially overlapping.
- Initialized to all-zero at simulation start (unlike `instr_mem`). You can
  still pre-load specific values from your testbench (`DUT.DM.memory[i] =
  ...;`) before the clock starts if you want a non-zero starting data set
  (e.g. for sort/search test programs).
- Synchronous write, combinational read (classic single-port sync-write
  RAM behavior).

### `control_unit` — main decoder

Pure combinational opcode decoder. See `ISA_Documentation.md` for the full
opcode table; this module is what turns a 7-bit opcode into the
`RegWrite`/`MemRead`/`MemWrite`/`ALUSrc`/`Branch`/`Jump`/`ALUOp` signal
bundle that drives the rest of the pipeline.

### `ALU_control` — secondary decoder

Takes the 2-bit `ALUOp` from `control_unit` plus `funct3`/`funct7` from the
instruction and produces the 4-bit `alu_ctrl` code that selects the actual
operation inside `ALU64`. See `ISA_Documentation.md` for the full mapping
table — this is the module to consult if you're wondering "why did my `sra`
not work" or similar.

### `ALU64` — arithmetic/logic unit

64-bit ALU supporting: `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`,
`SLT` (signed less-than), `SLTU` (unsigned less-than), and `PASS` (used
internally for `lui`). Produces a `Zero` flag (`result == 0`) that both
branch resolution and a few other places key off of, plus `flag`
(carry/borrow), `overflow`, and `Negative` side outputs (not currently wired
to anything outside the ALU, but available if you want to extend the core).

### `reg_file` — register file

32 x 64-bit registers. Synchronous write, combinational read with built-in
same-cycle write-forwarding (if you read a register in the same cycle it's
being written, you get the new value, not the old one — this models a
register file with internal bypass, which simplifies the pipeline's own
forwarding logic since it only needs to handle EX/MEM and MEM/WB hazards,
not a same-cycle WB hazard). `x0` reads as hardwired zero and ignores all
writes.

### `hazard_detection_unit` — load-use stall detector

See [Hazard Handling](#hazard-handling) above.

### `imm_gen` — immediate generator

Decodes and sign-extends the correct immediate field for whichever
instruction format (`I`/`S`/`B`/`U`/`J`) the current opcode implies. See
`ISA_Documentation.md` for the exact bit-field formulas — getting these
right by hand is the single most error-prone part of writing your own
encoded instructions, especially for `B`-type (branches) and `J`-type
(`jal`), whose immediate bits are scrambled across the instruction word in a
specific, easy-to-get-wrong pattern.

---

## Building and Simulating

This project uses plain Verilog-2001/Icarus-Verilog-compatible syntax — no
vendor-specific IP, no SystemVerilog interfaces.

### Using Icarus Verilog (`iverilog`/`vvp`)

```sh
# Compile
iverilog -o Simulation/test_environment.vvp RTL/*.v Testbenches/test_environment_tb.v

# Run
vvp Simulation/test_environment.vvp
```

**You must re-run the `iverilog` compile step every single time you change
any `.v` file** — `vvp` only executes whatever was compiled into the `.vvp`
binary the last time you ran `iverilog`; it does not re-read your source
files. This trips people up constantly: you edit `instr_mem.v` or your
testbench, forget to recompile, run `vvp` again, and wonder why nothing
changed. If your results look "stuck" on an old program, recompile first.

### Using other simulators

The RTL avoids vendor-specific constructs, so it should compile cleanly
under Verilator, ModelSim/QuestaSim, Vivado xsim, or VCS with no changes —
adjust your compile/run commands to whatever your simulator's equivalent
invocation is.

---

## Loading a Program

Since `instr_mem.v` ships with **no preloaded program** by design (so you can
swap test programs freely without touching RTL), you load instructions from
your testbench, before reset is released:

```verilog
module test_environment_tb;
    reg clk, rst;
    test_environment DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        #20;
        rst = 0;
    end

    // Load your program HERE, in an initial block that runs at time 0,
    // BEFORE reset is released. Note the DUT.IM. prefix — without it,
    // Icarus will look for a variable called "memory" inside the
    // testbench itself and fail to elaborate.
    initial begin
        DUT.IM.memory[0] = 32'h00500093; // addi x1, x0, 5
        DUT.IM.memory[1] = 32'h00A00113; // addi x2, x0, 10
        DUT.IM.memory[2] = 32'h002081B3; // add  x3, x1, x2
        // ... etc.
        DUT.IM.memory[3] = 32'h0000006F; // jal x0, +0  (halt: infinite self-loop)
    end

    initial begin
        #500; // give it enough cycles to actually finish your program
        $display("x3 = %0d", DUT.CPU.RF.registers[3]);
        $finish;
    end
endmodule
```

Key rules:
1. **Always prefix with `DUT.IM.`** (or whatever you named your
   `test_environment` instance) — a bare `memory[i] = ...` inside the
   testbench refers to a nonexistent local variable and will fail to
   elaborate with a `Could not find variable` error.
2. **Load before reset releases.** The provided testbench releases `rst`
   at `#20`; as long as your loading `initial` block also runs at time 0 (any
   `initial` block does, by definition), ordering between multiple `initial`
   blocks at the same simulation time is determined by source/compile order,
   but in practice writing all your `memory[i] = ...;` assignments in one
   `initial` block guarantees they all land before the first clock edge.
3. **Always end with a self-jump halt** (`jal x0, <own address>`) so the core
   parks safely once your program finishes, instead of fetching uninitialized
   `X` instructions.
4. **Give the simulation enough `#delay` time** to actually finish your
   program before you sample results — a tight loop with several iterations
   plus pipeline fill/stall cycles can easily need several hundred
   nanoseconds at the default `#5` half-clock-period.
5. If you also want a non-zero starting data memory (e.g. an unsorted array
   to sort), preload `DUT.DM.memory[i] = ...;` in that same `initial` block.

See `ISA_Documentation.md` for exactly how to hand-encode each instruction
type into the 32-bit hex values you put on the right-hand side of those
`memory[i] = ...;` lines.

---

## Known Limitations

These are deliberate scope boundaries, not bugs — listed here so you know
what *not* to expect:

| Limitation | Detail |
|---|---|
| No byte/halfword load-store | `lb/lh/lbu/lhu/sb/sh` all decode (same opcode as `lw`/`ld`/`sw`/`sd`) but `data_mem` always moves a full 64-bit word regardless of `funct3`. Effectively only `ld`/`sd`-style full-width access is implemented. |
| No system/privileged instructions | `fence`, `ecall`, `ebreak`, all CSR instructions: not decoded, not implemented. |
| No M-extension | No hardware `mul`, `mulh`, `div`, `rem`, etc. |
| No exceptions/interrupts | No trap handling of any kind. Illegal opcodes silently decode to a "do-nothing" instruction (all control signals default to 0) rather than faulting. |
| No branch prediction | Every branch/jump is resolved in EX with a fixed 2-cycle flush penalty; there is no predictor of any kind (not even simple "predict taken"). |
| Single-issue, no caches | This is a simple in-order 5-stage scalar pipeline — no superscalar issue, no instruction or data caching, no MMU/virtual memory. |

---

## Troubleshooting

A running log of real issues encountered while exercising this core, kept
here so you don't have to rediscover them:

**"My loop never seems to repeat / branch behaves like it's always true or
always false."**
Double-check your hand-encoded immediate, especially for `B`-type
instructions — the offset bits are scrambled across the word in a specific
pattern (see `ISA_Documentation.md`), and it's extremely easy to get one bit
group wrong and silently encode the wrong target offset, even though the
*opcode/funct3/registers* part of the instruction is perfectly correct. A
classic symptom: the branch is taken, but jumps a few instructions short or
long of where you intended.

**"Could not find variable `memory[...]` in `test_environment_tb`" during
compile.**
You wrote `memory[i] = ...;` directly instead of `DUT.IM.memory[i] = ...;` (or
`DUT.DM.memory[i] = ...;` for data memory). Add the hierarchical prefix.

**"I changed my program but the simulation output didn't change at all."**
You ran `vvp` without re-running `iverilog` first. Recompile, then re-run.

**"My final `$display` is printing what look like raw instruction
words/garbage, not my computed results."**
Check that your `$display` is reading `DUT.DM.memory[...]` (data memory) and
not accidentally `DUT.IM.memory[...]` (instruction memory) — if the printed
numbers, converted to hex, look suspiciously like your program's actual
instruction encodings, this is almost certainly what happened.

**"My array-processing program's results land at unexpected memory
indices."**
Remember `data_mem` indexes by `addr[9:2]` (`byte_address / 4`), but if your
stores are 8 bytes apart (typical for 64-bit values), consecutive elements
land at memory indices `0, 2, 4, 6, …`, not `0, 1, 2, 3, …`. Index your
`$display`/checks accordingly.

**"The simulation just hangs / never finishes."**
You're missing a `$finish;` call in your testbench. The clock-generation
`always #5 clk = ~clk;` block runs forever; without an explicit `$finish`,
the simulator has no reason to ever stop.

---

## Design Notes / Changelog

- Branch condition logic in `cpu_core.v` was rewritten to correctly handle
  all six branch types (`beq`/`bne`/`blt`/`bge`/`bltu`/`bgeu`) based on
  `funct3`, rather than naively using the ALU's `Zero` flag directly for
  every branch type (which only happens to be correct for `beq`).
- `lui`/`auipc` handling was corrected so that `lui` passes its immediate
  straight through (rather than incorrectly adding it to whatever garbage
  value happened to be in the register addressed by the immediate's own
  bits), and `auipc` adds its immediate to the instruction's own PC (rather
  than to `rs1`, which isn't a real source register for that instruction).
- All fixes were made as internal logic changes only — no module port lists
  were altered anywhere in the design.
