module test_interface(input clk, rst);

// ================= WIRES =================
wire [63:0] instr_addr;
wire [31:0] instr;

wire MemRead, MemWrite;
wire [63:0] data_addr;
wire [63:0] write_data;
wire [63:0] read_data;

// ================= CPU =================
cpu_core CPU (
    .clk(clk),
    .rst(rst),

    .instr_addr(instr_addr),
    .instr_in(instr),   // ✅ FIXED (was instr before)

    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .data_addr(data_addr),
    .write_data(write_data),
    .read_data(read_data)
);

// ================= INSTRUCTION MEMORY =================
instr_mem IM (
    .addr(instr_addr),
    .instr(instr)
);

// ================= DATA MEMORY =================
data_mem DM (
    .clk(clk),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .addr(data_addr),
    .write_data(write_data),
    .read_data(read_data)
);

endmodule