module alu_control (
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,   
    output reg [3:0] alu_ctrl
);

always @(*) begin
    alu_ctrl = 4'b0000; 
    case (opcode)
        // R-TYPE (Register)
        7'b0110011: begin
            case (funct3)

                3'b000: begin
                    if (funct7 == 7'b0100000)
                        alu_ctrl = 4'b0001; // SUB
                    else
                        alu_ctrl = 4'b0000; // ADD
                end

                3'b111: alu_ctrl = 4'b0010; // AND
                3'b110: alu_ctrl = 4'b0011; // OR
                3'b100: alu_ctrl = 4'b0100; // XOR
                3'b001: alu_ctrl = 4'b0101; // SLL

                3'b101: begin
                    if (funct7 == 7'b0100000)
                        alu_ctrl = 4'b0111; // SRA
                    else 
                        alu_ctrl = 4'b0110; // SRL
                end

                3'b010: alu_ctrl = 4'b1000; // SLT
                3'b011: alu_ctrl = 4'b1001; // SLTU

            endcase
        end

        // I-TYPE (Immediate ALU)
        7'b0010011: begin
            case (funct3)

                3'b000: alu_ctrl = 4'b0000; // ADDI
                3'b111: alu_ctrl = 4'b0010; // ANDI
                3'b110: alu_ctrl = 4'b0011; // ORI
                3'b100: alu_ctrl = 4'b0100; // XORI
                3'b010: alu_ctrl = 4'b1000; // SLTI
                3'b011: alu_ctrl = 4'b1001; // SLTIU
                3'b001: alu_ctrl = 4'b0101; // SLLI

                // SRLI / SRAI (funct7 = instr[31:25])
                3'b101: begin
                    if (funct7 == 7'b0100000)
                        alu_ctrl = 4'b0111; // SRAI
                    else
                        alu_ctrl = 4'b0110; // SRLI
                end

            endcase
        end

        // LOAD / STORE (Address Calc)
        7'b0000011: alu_ctrl = 4'b0000; // LOAD -> ADD
        7'b0100011: alu_ctrl = 4'b0000; // STORE -> ADD

        // BRANCH (Comparison)
        7'b1100011: begin
            case (funct3)
                3'b000: alu_ctrl = 4'b0001; // BEQ -> SUB
                3'b001: alu_ctrl = 4'b0001; // BNE -> SUB
                3'b100: alu_ctrl = 4'b1000; // BLT
                3'b101: alu_ctrl = 4'b1000; // BGE
                3'b110: alu_ctrl = 4'b1001; // BLTU
                3'b111: alu_ctrl = 4'b1001; // BGEU
            endcase
        end

        // U-TYPE
        7'b0110111: alu_ctrl = 4'b1010; // LUI -> PASS B
        7'b0010111: alu_ctrl = 4'b0000; // AUIPC -> ADD (PC + imm)

        // JUMP
        7'b1101111: alu_ctrl = 4'b0000; // JAL -> ADD
        7'b1100111: alu_ctrl = 4'b0000; // JALR -> ADD

    endcase
end

endmodule