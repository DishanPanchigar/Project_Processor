module hazard_detection_unit (
    input ID_EX_MemRead,
    input [4:0] ID_EX_rd,
    input [4:0] IF_ID_rs1,
    input [4:0] IF_ID_rs2,

    output reg PCWrite,
    output reg IF_ID_Write,
    output reg control_stall   // turns control signals into NOP
);

always @(*) begin
    // default → no stall
    PCWrite      = 1;
    IF_ID_Write  = 1;
    control_stall = 0;

    // LOAD-USE hazard
    if (ID_EX_MemRead &&
       ((ID_EX_rd == IF_ID_rs1) || (ID_EX_rd == IF_ID_rs2))) begin

        PCWrite      = 0;  // freeze PC
        IF_ID_Write  = 0;  // freeze IF/ID
        control_stall = 1; // inject bubble
    end
end

endmodule