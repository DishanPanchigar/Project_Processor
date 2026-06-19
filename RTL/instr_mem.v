module instr_mem(
    input [63:0] addr,
    output [31:0] instr
); 
reg [31:0] memory [0:1024];
assign instr=memory[addr[9:2]];
endmodule