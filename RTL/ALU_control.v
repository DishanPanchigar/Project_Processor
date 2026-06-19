module ALU_control (
    input  [1:0] ALUOp,
    input  [2:0] funct3,
    input  [6:0] funct7,   
    output reg [3:0] alu_ctrl
);

always @(*) begin
    alu_ctrl = 4'b0000;

    case (ALUOp)

        // 00 → LOAD / STORE / AUIPC / JUMP → ADD
        2'b00: alu_ctrl = 4'b0000;

        // 01 → BRANCH
        2'b01: begin
            case (funct3)
                3'b000: alu_ctrl = 4'b0001; // BEQ → SUB
                3'b001: alu_ctrl = 4'b0001; // BNE → SUB
                3'b100: alu_ctrl = 4'b1000; // BLT
                3'b101: alu_ctrl = 4'b1000; // BGE
                3'b110: alu_ctrl = 4'b1001; // BLTU
                3'b111: alu_ctrl = 4'b1001; // BGEU
                default: alu_ctrl = 4'b0000;
            endcase
        end

        // 10 → R-type / I-type
        2'b10: begin
            case (funct3)

                3'b000: begin
                    if (funct7 == 7'b0100000)
                        alu_ctrl = 4'b0001; // SUB
                    else
                        alu_ctrl = 4'b0000; // ADD / ADDI
                end

                3'b111: alu_ctrl = 4'b0010; // AND / ANDI
                3'b110: alu_ctrl = 4'b0011; // OR / ORI
                3'b100: alu_ctrl = 4'b0100; // XOR / XORI
                3'b001: alu_ctrl = 4'b0101; // SLL / SLLI

                3'b101: begin
                    if (funct7 == 7'b0100000)
                        alu_ctrl = 4'b0111; // SRA / SRAI
                    else
                        alu_ctrl = 4'b0110; // SRL / SRLI
                end

                3'b010: alu_ctrl = 4'b1000; // SLT / SLTI
                3'b011: alu_ctrl = 4'b1001; // SLTU / SLTIU

                default: alu_ctrl = 4'b0000;
            endcase
        end

        default: alu_ctrl = 4'b0000;
    endcase
end

endmodule