module uart_reg_tb;
 
  reg clk=0, rst=0;
  reg wr,rd;
  reg rx_fifo_empty;
  reg [7:0] rx_fifo_in;
  reg [2:0] addr;
  reg [7:0] din;
  reg rx_output_error, rx_parity_error, rx_frame_error, rx_break_error;
  wire tx_push; 
  wire rx_pop;
  
  wire baud_out; 

  wire tx_rst, rx_rst;
  wire [3:0] rx_fifo_threshold;
  
  wire [7:0] dout;
  
  csr_t csr_out;
  
  uart_registers dut(
      clk, rst,
      wr, rd,
      rx_fifo_empty,
      rx_output_error, rx_parity_error, rx_frame_error, rx_break_error,
      addr,   
      din,
      rx_fifo_in,
      tx_push, rx_pop, tx_rst, rx_rst,
      rx_fifo_threshold,
      dout,
      csr_out,
      baud_out
  );
  
  always #5 clk = ~clk;
  
  initial begin

    //Reset
    rst = 1;
    repeat(5) @(posedge clk);
    rst = 0; 

    //Update Divisor

    //Update DLAB = 1 in LCR
    @(negedge clk);
    wr = 1;
    addr = 3'h3;
    din <= 8'b10000000;
  
    //Update LSB Divisor
    @(negedge clk);
    addr = 3'h0;
    din <= 8'b0000_1000; // 08
  
    //Update MSB Divisor
    @(negedge clk);
    addr = 3'h1;
    din <= 8'b0000_0001;
    
    //Update DLAB = 0 in LCR 
    @(negedge clk);
    addr = 3'h3;
    din <= 8'b0000_0000;

    $stop;

  end

endmodule
