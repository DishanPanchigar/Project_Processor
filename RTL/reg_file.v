module reg_file(
    input clk,
    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    input [4:0] rd_addr,
    input [63:0] write_data,
    input reg_write,

    output [63:0] rs1_data,
    output [63:0] rs2_data
);
reg [63:0] registers [31:0];
// WRITE LOGIC (SYNCHRONOUS)
always @(posedge clk) begin
    if (reg_write && (rd_addr != 5'b00000)) begin
        registers[rd_addr] <= write_data;
    end
end
// READ LOGIC (COMBINATIONAL)
assign rs1_data = (rs1_addr == 5'b00000) ? 64'b0 :
                  (reg_write && (rd_addr == rs1_addr) && (rd_addr != 5'b00000)) ? write_data :
                  registers[rs1_addr];

assign rs2_data = (rs2_addr == 5'b00000) ? 64'b0 :
                  (reg_write && (rd_addr == rs2_addr) && (rd_addr != 5'b00000)) ? write_data :
                  registers[rs2_addr];
endmodule