`timescale 1ns/1ps

module test_interface_tb;

reg clk;
reg rst;

// Instantiate DUT
test_interface DUT (
    .clk(clk),
    .rst(rst)
);

//////////////////////////////////////////////////////////////
// CLOCK
//////////////////////////////////////////////////////////////
always #5 clk = ~clk;

//////////////////////////////////////////////////////////////
// INITIALIZATION
//////////////////////////////////////////////////////////////
initial begin
    clk = 0;
    rst = 1;

    #20;
    rst = 0;
end

//////////////////////////////////////////////////////////////
// LOAD PROGRAM INTO INSTRUCTION MEMORY
//////////////////////////////////////////////////////////////
initial begin
// Fibonacci sequence
DUT.IM.memory[0]  = 32'h00500113; // addi x2, x0, 5      outer_count = 5
DUT.IM.memory[1]  = 32'h00000193; // addi x3, x0, 0      ptr = 0
DUT.IM.memory[2]  = 32'h00A00513; // addi x10, x0, 10     value = 10
DUT.IM.memory[3]  = 32'h00300213; // addi x4, x0, 3      inner_count = 3 (nested dummy loop)
DUT.IM.memory[4]  = 32'hFFF20213; // addi x4, x4, -1     inner_count--
DUT.IM.memory[5]  = 32'hFE021EE3; // bne  x4, x0, INNER
DUT.IM.memory[6]  = 32'h00A1B023; // sd   x10, 0(x3)     mem[ptr] = value
DUT.IM.memory[7]  = 32'h00818193; // addi x3, x3, 8      ptr += 8
DUT.IM.memory[8]  = 32'h00A50513; // addi x10, x10, 10   value += 10
DUT.IM.memory[9]  = 32'hFFF10113; // addi x2, x2, -1     outer_count--
DUT.IM.memory[10] = 32'hFE0112E3; // bne  x2, x0, OUTER
DUT.IM.memory[11] = 32'h00000193; // addi x3, x0, 0      ptr = 0 (reset)
DUT.IM.memory[12] = 32'h00000A13; // addi x20, x0, 0     sum = 0
DUT.IM.memory[13] = 32'h00500A93; // addi x21, x0, 5     count = 5
DUT.IM.memory[14] = 32'h0001BB03; // ld   x22, 0(x3)
DUT.IM.memory[15] = 32'h016A0A33; // add  x20, x20, x22
DUT.IM.memory[16] = 32'h00818193; // addi x3, x3, 8
DUT.IM.memory[17] = 32'hFFFA8A93; // addi x21, x21, -1
DUT.IM.memory[18] = 32'hFE0A98E3; // bne  x21, x0, SUM
DUT.IM.memory[19] = 32'h0000006F; // jal x0, HALT (park forever)
end

//////////////////////////////////////////////////////////////
// MONITORING
//////////////////////////////////////////////////////////////
initial begin
    $monitor("Time=%0t | PC=%h | instr=%h | MemWrite=%b | data_addr=%h",
          $time,
          DUT.CPU.PC,
          DUT.instr,
          DUT.MemWrite,
          DUT.data_addr);
end

//////////////////////////////////////////////////////////////
// END SIMULATION
//////////////////////////////////////////////////////////////
initial begin
    #500;
    $display("\n==== FINAL RESULT ====");
    $display("MEM[0] = %d | MEM[1] = %d | MEM[2] = %d | MEM[3] = %d | MEM[4] = %d |",
        DUT.DM.memory[0],   // <-- must be DM (data memory), not IM (instruction memory)
        DUT.DM.memory[1],
        DUT.DM.memory[2],
        DUT.DM.memory[3],
        DUT.DM.memory[4]);
    $finish;
end

endmodule