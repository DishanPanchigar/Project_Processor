`timescale 1ns/1ps

module alu_control_tb;
    reg  [6:0] opcode;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    wire [3:0] alu_ctrl;

    alu_control uut (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .alu_ctrl(alu_ctrl)
    );
    initial begin
        $dumpfile("alu_control_tb.vcd");
        $dumpvars(0, alu_control_tb);
        $monitor("t=%0t | opcode=%b funct3=%b funct7=%b | alu_ctrl=%b",
                 $time, opcode, funct3, funct7, alu_ctrl);
        opcode = 7'b0; funct3 = 3'b0; funct7 = 7'b0;
        // R-type ADD
        #10 opcode = 7'b0110011; funct3 = 3'b000; funct7 = 7'b0000000;
        // R-type SUB
        #10 opcode = 7'b0110011; funct3 = 3'b000; funct7 = 7'b0100000;
        // R-type AND
        #10 opcode = 7'b0110011; funct3 = 3'b111; funct7 = 7'b0000000;
        // R-type OR
        #10 opcode = 7'b0110011; funct3 = 3'b110; funct7 = 7'b0000000;
        // R-type XOR
        #10 opcode = 7'b0110011; funct3 = 3'b100; funct7 = 7'b0000000;
        // R-type SLL
        #10 opcode = 7'b0110011; funct3 = 3'b001; funct7 = 7'b0000000;
        // R-type SRL
        #10 opcode = 7'b0110011; funct3 = 3'b101; funct7 = 7'b0000000;
        // R-type SRA
        #10 opcode = 7'b0110011; funct3 = 3'b101; funct7 = 7'b0100000;
        // I-type ADDI
        #10 opcode = 7'b0010011; funct3 = 3'b000; funct7 = 7'b0000000;
        // I-type SRAI
        #10 opcode = 7'b0010011; funct3 = 3'b101; funct7 = 7'b0100000;
        // LOAD
        #10 opcode = 7'b0000011; funct3 = 3'b010; funct7 = 7'b0000000;
        // STORE
        #10 opcode = 7'b0100011; funct3 = 3'b010; funct7 = 7'b0000000;
        // BRANCH BEQ
        #10 opcode = 7'b1100011; funct3 = 3'b000; funct7 = 7'b0000000;
        // LUI
        #10 opcode = 7'b0110111; funct3 = 3'b000; funct7 = 7'b0000000;
        // AUIPC
        #10 opcode = 7'b0010111; funct3 = 3'b000; funct7 = 7'b0000000;
        // JAL
        #10 opcode = 7'b1101111; funct3 = 3'b000; funct7 = 7'b0000000;
        // JALR
        #10 opcode = 7'b1100111; funct3 = 3'b000; funct7 = 7'b0000000;
        #20 $finish;
    end
endmodule
