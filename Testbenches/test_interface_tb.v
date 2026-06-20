`timescale 1ns/1ps
module test_interface_tb;
reg clk;
reg rst;
test_interface DUT (
    .clk(clk),
    .rst(rst)
);
always #5 clk = ~clk;
initial begin
    clk = 0;
    rst = 1;

    #20;
    rst = 0;
end



// LOAD PROGRAM INTO INSTRUCTION MEMORY_________________________________________
initial begin

// paste instructions here {Format: DUT.IM.memory['i']= 'i_th instruction code'}

end
//______________________________________________________________________________


initial begin
    $monitor("Time=%0t | PC=%h | instr=%h | MemWrite=%b | data_addr=%h",
          $time,
          DUT.CPU.PC,
          DUT.instr,
          DUT.MemWrite,
          DUT.data_addr);
end

initial begin
    #500;
    $display("\n==== FINAL RESULT ====");
    $display("MEM[0] = %d | MEM[1] = %d | MEM[2] = %d | MEM[3] = %d | MEM[4] = %d |",
        DUT.DM.memory[0],  
        DUT.DM.memory[1],
        DUT.DM.memory[2],
        DUT.DM.memory[3],
        DUT.DM.memory[4]);
    $finish;
end

initial begin
    $dumpfile("test_interface_tb.vcd");
    $dumpvars(0, test_interface_tb);
end
endmodule