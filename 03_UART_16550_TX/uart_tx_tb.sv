module uar_txt_tb;

    //Inputs
    reg clk, rst, baud_pulse, parity_enable, tx_hold_reg_empty, stop_bit, sticky_parity, even_parity_select, set_break;
    reg [7:0] din; //Input from TX FIFO
    reg [1:0] wls;

    //Outputs
    wire pop, sreg_empty, tx;

    uart_tx_top dut(
    clk, rst, baud_pulse, parity_enable, tx_hold_reg_empty, stop_bit, sticky_parity, even_parity_select, set_break, din, wls,
    pop, sreg_empty, tx
    );

    initial begin
        clk <= 1'b0;
        rst <= 1'b0;
        baud_pulse <= 1'b0;
        parity_enable <= 1'b1; //Sending Parity
        tx_hold_reg_empty <= 1'b0;
        stop_bit <= 1'b1; //2bit duration for 8 bits
        sticky_parity <= 1'b0;
        even_parity_select <= 1'b1; //Even Parity
        set_break <= 1'b0;
        din = 8'ha4;
        wls = 2'b11; //8 bits
    end

    always #5 clk <= ~clk; //100MHz

    initial begin
        rst = 1'b1;
        repeat(5) @(posedge clk);
        rst = 1'b0;
    end

    integer count = 10416; 
    //Baud Rate = 9600 => 100Mz/9600 = 10416

    //Baud Pulse Generator
    always@(posedge clk) begin
        if(rst == 0) begin
            if(count != 0) begin
                count <= count - 1;
                baud_pulse <= 1'b0;
            end
            else begin
                count <= 5;
                baud_pulse <= 1'b1;
            end
        end
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

    initial $monitor("[MON] :: din : %0b :: tx : %0b :: pop : %0b :: sreg_empty : %0b", din, tx, pop, sreg_empty);

    initial #10000 $finish();

endmodule