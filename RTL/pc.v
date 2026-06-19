module pc (
    input clk,
    input rst,
    input [63:0] PC_next,
    output reg [63:0] PC
);

always @(posedge clk or posedge rst) begin
    if (rst)
        PC <= 0;
    else
        PC <= PC_next;
end

endmodule