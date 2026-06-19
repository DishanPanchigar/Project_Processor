module data_mem (
    input clk,
    input MemRead,
    input MemWrite,
    input [63:0] addr,
    input [63:0] write_data,
    output reg [63:0] read_data
);

reg [63:0] memory [0:255];
integer i;

initial begin
    for (i = 0; i < 256; i = i + 1)
        memory[i] = 0;
end

// WRITE
always @(posedge clk) begin
    if (MemWrite)
        memory[addr[9:2]] <= write_data;
end

// READ
always @(*) begin
    if (MemRead)
        read_data = memory[addr[9:2]];
    else
        read_data = 64'b0;
end

endmodule