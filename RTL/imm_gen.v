module imm_gen(
    input [31:0] instr,
    output reg [63:0] imm
);
wire [6:0] opcode = instr [6:0];
always @(*) begin
    imm=64'b0;
  case (opcode)
    //I-type//
    7'b0010011,
    7'b0000011,
    7'b1100111: imm={{52{instr[31]}},instr[31:20]};

    //S-type//
    7'b0100011: imm={{52{instr[31]}}, instr[31:25], instr[11:7]};

    //B-type//
    7'b1100011: imm={{51{instr[31]}},instr[31],instr[7],instr[30:25],instr[11:8],1'b0};

    //U-type//
    7'b0110111,
    7'b0010111: imm={{32{instr[31]}},instr[31:12],12'b0};

    //J-type//
    7'b1101111: imm={{43{instr[31]}},instr[31],instr[19:12],instr[20],instr[30:21],1'b0};

    default: imm=64'b0;
  endcase
end
endmodule