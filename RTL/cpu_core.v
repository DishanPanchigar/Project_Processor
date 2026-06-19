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

// =====================
// PC
// =====================
reg [63:0] PC;
wire [63:0] PC_plus4 = PC + 4;
assign instr_addr = PC;

// =====================
// IF/ID
// =====================
reg [63:0] IF_ID_PC;
reg [31:0] IF_ID_instr;

// =====================
// ID stage
// =====================
wire [6:0] opcode = IF_ID_instr[6:0];
wire [4:0] rs1 = IF_ID_instr[19:15];
wire [4:0] rs2 = IF_ID_instr[24:20];
wire [4:0] rd  = IF_ID_instr[11:7];

wire RegWrite_ID, MemRead_ID, MemWrite_ID, ALUSrc_ID, Branch_ID, Jump_ID;
wire [1:0] ALUOp_ID;

control_unit CU (
    .opcode(opcode),
    .RegWrite(RegWrite_ID),
    .MemRead(MemRead_ID),
    .MemWrite(MemWrite_ID),
    .ALUSrc(ALUSrc_ID),
    .Branch(Branch_ID),
    .Jump(Jump_ID),
    .ALUOp(ALUOp_ID)
);

wire [63:0] rs1_data, rs2_data;
wire [63:0] imm_ID;

reg_file RF (
    .clk(clk),
    .rs1_addr(rs1),
    .rs2_addr(rs2),
    .rd_addr(MEM_WB_rd),
    .write_data(write_back_data),
    .reg_write(MEM_WB_RegWrite),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

imm_gen IG (.instr(IF_ID_instr), .imm(imm_ID));

// =====================
// Hazard Detection
// =====================
wire PCWrite, IF_ID_Write, control_stall;

hazard_detection_unit HDU (
    .ID_EX_MemRead(ID_EX_MemRead),
    .ID_EX_rd(ID_EX_rd),
    .IF_ID_rs1(rs1),
    .IF_ID_rs2(rs2),
    .PCWrite(PCWrite),
    .IF_ID_Write(IF_ID_Write),
    .control_stall(control_stall)
);

// =====================
// ID/EX
// =====================
reg [63:0] ID_EX_PC, ID_EX_rs1, ID_EX_rs2, ID_EX_imm;
reg [4:0] ID_EX_rs1_addr, ID_EX_rs2_addr, ID_EX_rd;
reg [1:0] ID_EX_ALUOp;
reg ID_EX_ALUSrc, ID_EX_Branch, ID_EX_MemRead, ID_EX_MemWrite, ID_EX_RegWrite, ID_EX_Jump;
reg [2:0] ID_EX_funct3;
reg [6:0] ID_EX_funct7;
reg [6:0] ID_EX_opcode;

// =====================
// Forwarding
// =====================
reg [1:0] forwardA, forwardB;

always @(*) begin
    forwardA = 2'b00;
    forwardB = 2'b00;

    if (EX_MEM_RegWrite && (EX_MEM_rd != 0) && (EX_MEM_rd == ID_EX_rs1_addr))
        forwardA = 2'b10;
    else if (MEM_WB_RegWrite && (MEM_WB_rd != 0) && (MEM_WB_rd == ID_EX_rs1_addr))
        forwardA = 2'b01;

    if (EX_MEM_RegWrite && (EX_MEM_rd != 0) && (EX_MEM_rd == ID_EX_rs2_addr))
        forwardB = 2'b10;
    else if (MEM_WB_RegWrite && (MEM_WB_rd != 0) && (MEM_WB_rd == ID_EX_rs2_addr))
        forwardB = 2'b01;
end

wire [63:0] forwardA_data = (forwardA==2'b10)?EX_MEM_alu :
                           (forwardA==2'b01)?write_back_data : ID_EX_rs1;

wire [63:0] forwardB_data = (forwardB==2'b10)?EX_MEM_alu :
                           (forwardB==2'b01)?write_back_data : ID_EX_rs2;

// =====================
// ALU
// =====================
wire [63:0] ALU_B = ID_EX_ALUSrc ? ID_EX_imm : forwardB_data;

wire [3:0] alu_ctrl;
ALU_control ALUCTRL (
    .ALUOp(ID_EX_ALUOp),
    .funct3(ID_EX_funct3),
    .funct7(ID_EX_funct7),
    .alu_ctrl(alu_ctrl)
);

wire [63:0] alu_result;
wire zero;

// LUI must pass the immediate straight through (rd = imm), it must NOT add
// whatever garbage value happens to sit in the register addressed by
// instr[19:15] (those bits are part of the LUI immediate, not a real rs1).
// AUIPC must add the immediate to the instruction's own PC, not to rs1_data.
wire is_lui   = (ID_EX_opcode == 7'b0110111);
wire is_auipc = (ID_EX_opcode == 7'b0010111);

wire [63:0] ALU_A        = is_auipc ? ID_EX_PC : forwardA_data;
wire [3:0]  final_alu_ctrl = is_lui ? 4'b1010 : alu_ctrl;   // 4'b1010 = PASS (result = B)

ALU64 ALU (
    .A(ALU_A),
    .B(ALU_B),
    .control(final_alu_ctrl),
    .result(alu_result),
    .Zero(zero),
    .flag(),
    .overflow(),
    .Negative()
);

// =====================
// Branch & Jump
// =====================
// BUG FIX: the original code used `take_branch = ID_EX_Branch & zero` for
// EVERY branch type. That only happens to be correct for BEQ. For BNE the
// branch must fire when the ALU (SUB) result is NON-zero; for BLT/BLTU the
// ALU (SLT/SLTU) result is 1 exactly when the branch must be taken (so the
// condition is ~zero, not zero); for BGE/BGEU it's the opposite of
// BLT/BLTU. This is exactly the bug that breaks BNE-based loops (e.g. the
// classic Fibonacci `bne x4, x0, LOOP` loop never iterating).
wire branch_condition =
    (ID_EX_funct3 == 3'b000) ?  zero :   // BEQ : rs1 == rs2  -> SUB result == 0
    (ID_EX_funct3 == 3'b001) ? ~zero :   // BNE : rs1 != rs2  -> SUB result != 0
    (ID_EX_funct3 == 3'b100) ? ~zero :   // BLT : SLT result == 1 -> taken
    (ID_EX_funct3 == 3'b101) ?  zero :   // BGE : SLT result == 0 -> taken
    (ID_EX_funct3 == 3'b110) ? ~zero :   // BLTU: SLTU result == 1 -> taken
    (ID_EX_funct3 == 3'b111) ?  zero :   // BGEU: SLTU result == 0 -> taken
                                1'b0;

wire take_branch = ID_EX_Branch & branch_condition;
wire [63:0] branch_target = ID_EX_PC + ID_EX_imm;

wire is_jal  = ID_EX_Jump && (ID_EX_opcode == 7'b1101111);
wire is_jalr = ID_EX_Jump && (ID_EX_opcode == 7'b1100111);

wire [63:0] jal_target  = ID_EX_PC + ID_EX_imm;
wire [63:0] jalr_target = (forwardA_data + ID_EX_imm) & ~64'd1;

// =====================
// EX/MEM
// =====================
reg [63:0] EX_MEM_alu, EX_MEM_rs2, EX_MEM_PC;
reg [4:0] EX_MEM_rd;
reg EX_MEM_MemRead, EX_MEM_MemWrite, EX_MEM_RegWrite, EX_MEM_Jump;

always @(posedge clk) begin
    EX_MEM_alu <= alu_result;
    EX_MEM_rs2 <= forwardB_data;
    EX_MEM_PC  <= ID_EX_PC;
    EX_MEM_rd  <= ID_EX_rd;
    EX_MEM_MemRead <= ID_EX_MemRead;
    EX_MEM_MemWrite<= ID_EX_MemWrite;
    EX_MEM_RegWrite<= ID_EX_RegWrite;
    EX_MEM_Jump    <= ID_EX_Jump;
end

assign MemRead  = EX_MEM_MemRead;
assign MemWrite = EX_MEM_MemWrite;
assign data_addr = EX_MEM_alu;
assign write_data = EX_MEM_rs2;

// =====================
// MEM/WB
// =====================
reg [63:0] MEM_WB_mem, MEM_WB_alu, MEM_WB_PC;
reg [4:0] MEM_WB_rd;
reg MEM_WB_RegWrite, MEM_WB_MemRead, MEM_WB_Jump;

always @(posedge clk) begin
    MEM_WB_mem <= read_data;
    MEM_WB_alu <= EX_MEM_alu;
    MEM_WB_PC  <= EX_MEM_PC;
    MEM_WB_rd  <= EX_MEM_rd;
    MEM_WB_RegWrite <= EX_MEM_RegWrite;
    MEM_WB_MemRead  <= EX_MEM_MemRead;
    MEM_WB_Jump     <= EX_MEM_Jump;
end

wire [63:0] write_back_data =
    MEM_WB_Jump ? (MEM_WB_PC + 4) :
    (MEM_WB_MemRead ? MEM_WB_mem : MEM_WB_alu);

// =====================
// PC UPDATE
// =====================
always @(posedge clk or posedge rst) begin
    if (rst)
        PC <= 0;
    else if (PCWrite) begin
        if (take_branch)
            PC <= branch_target;
        else if (is_jal)
            PC <= jal_target;
        else if (is_jalr)
            PC <= jalr_target;
        else
            PC <= PC_plus4;
    end
end

// =====================
// IF/ID PIPE
// =====================
wire flush = take_branch || is_jal || is_jalr;

always @(posedge clk) begin
    if (rst) begin
        IF_ID_instr <= 0;
        IF_ID_PC    <= 0;
    end
    else if (IF_ID_Write) begin
        if (flush) begin
            IF_ID_instr <= 32'b0;
            IF_ID_PC    <= 0;
        end else begin
            IF_ID_instr <= instr_in;
            IF_ID_PC    <= PC;
        end
    end
end

// =====================
// ID/EX PIPE (🔥 FIXED FLUSH)
// =====================
always @(posedge clk) begin
    if (flush) begin
        ID_EX_PC <= 0;
        ID_EX_rs1 <= 0;
        ID_EX_rs2 <= 0;
        ID_EX_imm <= 0;
        ID_EX_rs1_addr <= 0;
        ID_EX_rs2_addr <= 0;
        ID_EX_rd <= 0;
        ID_EX_opcode <= 0;

        ID_EX_ALUOp   <= 0;
        ID_EX_ALUSrc  <= 0;
        ID_EX_Branch  <= 0;
        ID_EX_MemRead <= 0;
        ID_EX_MemWrite<= 0;
        ID_EX_RegWrite<= 0;
        ID_EX_Jump    <= 0;

        ID_EX_funct3 <= 0;
        ID_EX_funct7 <= 0;
    end
    else begin
        ID_EX_PC <= IF_ID_PC;
        ID_EX_rs1 <= rs1_data;
        ID_EX_rs2 <= rs2_data;
        ID_EX_imm <= imm_ID;
        ID_EX_rs1_addr <= rs1;
        ID_EX_rs2_addr <= rs2;
        ID_EX_rd <= rd;
        ID_EX_opcode <= opcode;

        ID_EX_ALUOp   <= control_stall ? 2'b00 : ALUOp_ID;
        ID_EX_ALUSrc  <= control_stall ? 0 : ALUSrc_ID;
        ID_EX_Branch  <= control_stall ? 0 : Branch_ID;
        ID_EX_MemRead <= control_stall ? 0 : MemRead_ID;
        ID_EX_MemWrite<= control_stall ? 0 : MemWrite_ID;
        ID_EX_RegWrite<= control_stall ? 0 : RegWrite_ID;
        ID_EX_Jump    <= control_stall ? 0 : Jump_ID;

        ID_EX_funct3 <= IF_ID_instr[14:12];
        ID_EX_funct7 <= IF_ID_instr[31:25];
    end
end

endmodule