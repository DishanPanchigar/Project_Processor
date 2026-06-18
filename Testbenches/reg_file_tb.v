`timescale 1ns/1ps

module reg_file_tb;
    reg clk;
    reg [4:0] rs1_addr;
    reg [4:0] rs2_addr;
    reg [4:0] rd_addr;
    reg [63:0] write_data;
    reg reg_write;
    wire [63:0] rs1_data;
    wire [63:0] rs2_data;
    reg_file uut (
        .clk(clk),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .write_data(write_data),
        .reg_write(reg_write),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end
    initial begin
        $dumpfile("reg_file_tb.vcd");
        $dumpvars(0, reg_file_tb);
        $monitor("t=%0t | clk=%b | rs1_addr=%d | rs2_addr=%d | rd_addr=%d | write_data=%h | reg_write=%b | rs1_data=%h | rs2_data=%h",
                 $time, clk, rs1_addr, rs2_addr, rd_addr, write_data, reg_write, rs1_data, rs2_data);
        // Initialize
        rs1_addr = 0; rs2_addr = 0; rd_addr = 0;
        write_data = 64'h0; reg_write = 0;
        // Wait a bit
        #10;
        // Write to register 1
        rd_addr = 5'd1; write_data = 64'hDEADBEEFCAFEBABE; reg_write = 1;
        #10; reg_write = 0;
        // Read back from register 1
        rs1_addr = 5'd1; rs2_addr = 5'd0;
        #10;
        // Write to register 2
        rd_addr = 5'd2; write_data = 64'h123456789ABCDEF0; reg_write = 1;
        #10; reg_write = 0;
        // Read both registers
        rs1_addr = 5'd1; rs2_addr = 5'd2;
        #10;
        // Test bypass (write and read same cycle)
        rd_addr = 5'd3; write_data = 64'hFACEFACEFACEFACE; reg_write = 1;
        rs1_addr = 5'd3; rs2_addr = 5'd3;
        #10; reg_write = 0;
        // Read register 0 (should always be zero)
        rs1_addr = 5'd0; rs2_addr = 5'd0;
        #10;
        #20;
        $finish;
    end
endmodule
