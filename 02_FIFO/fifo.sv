/*

## FIFO

Inputs: clk, rst, en, push_in, pop_in, [7:0] din, [3:0] threshold
Outputs: [7:0] dout, empty, full, underrun, overrun, threshold_trigger

Width - 8 bit - Each item is 8 bit
Depth - 16 - 16 8-bit items can be stored

threshold is the limit for the depth of a FIFO, after which a trigger can be set to do some process

underrun is used to indicate pop request is received when empty is set
overrun is used to indicate push request is received when full is set

*/

module fifo(
    input rst, clk, en,
    input push_in, pop_in,
    input [7:0] din,
    input [3:0] threshold,
    output [7:0] dout,
    output reg empty, full, overrun, underrun, threshold_trigger
);

    reg [7:0] mem [16]; //Widh = 8, Depth = 16
    reg [3:0] waddr = 0;

    logic push, pop; //Controlled by the empty and full temp variables
    reg temp_full, temp_empty;

    //Empty Flag Logic
    always@(*) begin
        if(rst) temp_empty <= 1'b0;
        else begin
            case({push_in, pop_in}) //Packing push and pop in 2 bit data
                2'b01: temp_empty <= (~|(waddr) & en); 
                //Not of (Bitwise OR of waddr) will be 1 if any data is present so empty flag is reset and pop is possible
                //If FIFO is not enabled, then also empty can be set
                2'b10: temp_empty <= 1'b0; 
                //We are writing single byte of data so not empty
            endcase
        end
    end

    //Full Flag Logic
    always@(*) begin
        if(rst) temp_full <= 1'b0;
        else begin
            case({push_in, pop_in}) //Packing push and pop in 2 bit data
                2'b01: temp_full <= 1'b0;
                //We are removing single byte of data so not full
                2'b10: temp_full <= (&(waddr) & en); 
                //Bitwise AND of waddr will be 1 if FIFO is full so full flag is set and push is not possible
                //If FIFO is not enabled, then also full can be set
            endcase
        end
    end

    //Final Push and Pop logic
    assign push = push_in & ~temp_full  & ~pop_in & en; //User Input and Full Flag and Exclusive Input 
    assign pop  = pop_in  & ~temp_empty & ~push_in & en; //User Input and Empty Flag and Exclusive Input

    //Updating Write Pointer
    always@(posedge clk, posedge rst) begin
        if(rst) waddr <= 4'h0;
        else begin
            case({push, pop})
                2'b10: begin
                    if(waddr != 4'hf && temp_full == 1'b0) waddr <= waddr + 1;
                    else waddr <= waddr;
                end
                2'b01: begin
                    if(waddr != 4'h0 && temp_empty == 1'b0) waddr <= waddr - 1;
                    else waddr <= waddr;
                end
            endcase
        end
    end

    //Updating the FIFO
    assign dout = mem[0]; //First Out

    always@(posedge clk, posedge rst) begin
        if(rst) for(int i=0; i<16; ++i) mem[i] <= 0;
        else begin
            case({push, pop})
                2'b01: begin
                    for(int i=0; i<15; ++i) mem[i] <= mem[i+1];
                    mem[15] <= 0;
                end
                2'b10: mem[waddr] <= din;
            endcase
        end
    end

    //Underrun-Overrun Logic
    reg temp_underrun, temp_overrun;

    always@(*) begin
        if(rst) temp_underrun <= 1'b0;
        else if(pop_in == 1'b1 && temp_empty == 1'b1) temp_underrun <= 1'b1;
        else temp_underrun <= 1'b0;
    end

    always@(*) begin
        if(rst) temp_overrun <= 1'b0;
        else if(push_in == 1'b1 && temp_full == 1'b1) temp_overrun <= 1'b1;
        else temp_overrun <= 1'b0;
    end

    //Threshold Logic
    reg temp_threshold_trigger;

    always@(*) begin
        if(rst) temp_threshold_trigger <= 1'b0;
        else if(push ^ pop) temp_threshold_trigger <= (waddr >= threshold)? 1'b1 : 1'b0;
        //XOR because if push and pop are done simultaneously, then the number of elements remain the same
    end

    always@(posedge clk) begin
        empty <= temp_empty;
        full <= temp_full;
        underrun <= temp_underrun;
        overrun <= temp_overrun;
        threshold_trigger <= temp_threshold_trigger;
    end

endmodule

interface fifo_if;

    logic rst, clk, en;
    logic push_in, pop_in;
    logic [7:0] din;
    logic [3:0] threshold;
    logic [7:0] dout;
    logic empty, full, overrun, underrun, threshold_trigger;

endinterface

