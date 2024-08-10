// Code your design here
/*

## UART Registers

10 Registers and Address Bus is 3 bit (8 possible values)
Addressing is done with {LCR.DLAB, addr}

 => 0000 - IN/OUT - Transmitter Holding Register (THR)/ Receiver Buffer Register (RBR) - Both FIFO
 -- 0001 - OUT    - Interrupt Enable Register (IER) (Omitted)
 => 1000 - OUT    - DLL (Divisor LSB)
 => 1001 - OUT    - DHL (Divisor MSB)
 -- x010 - OUT    - Interrupt Identification Register(IIR) (Omitted)
 => x010 - IN     - FIFO Control Register
 => x011 - OUT    - Data Format (Line Control) Register (LCR)
 -- x100 - OUT    - Modem Contrl Register (MCR) (Omitted)
 => x101 - IN     - Serialisation Status (Line Status) Register (LSR)
 -- x110 - IN     - Modem Status Register (MSR) (Omitted)
 => x111 - IN/OUT - Scratch Pad Register (SPR)

 // IN (Write is enabled , Write Only) / OUT (Read is enabled, Read Only)

*/

//LCR

typedef struct packed {
    logic       dlab; //Divisor Latch Access Bit   
    logic       bc;   //Break Control  
    logic       sp;   //Stick Parity  
    logic       eps;  //Even Parity Select
    logic       pen;  //Parity Enable
    logic       stb;  //Stop Bit
    logic [1:0] wls;  //Word Length Select
} lcr_t;

 //FCR

typedef struct packed {

    logic [1:0] rx_trigger;        //Receive trigger threshold - Possible values - 1,4,8,14 byes //No interrupts used
    logic [1:0] reserved;          //reserved
    logic       dma_mode;          //DMA mode select //Set to zero to disable
    logic       tx_rst;            //Transmit FIFO Reset
    logic       rx_rst;            //Receive FIFO Reset
    logic       fifo_ena;
    //Transmitter and receiver FIFOs mode enable. 
    //FIFOEN must be set before other FCR bits are written to or the FCR bits are not programmed. Clearing this bit clears the FIFO counters
} fcr_t;

//LSR

typedef struct packed {
    logic       rx_fifo_error;     //Parity, Frame or Break Error at receiver
    logic       temt;              //Transmitter Empty
    logic       thre;              //Transmitter Holding Register Empty
    logic       bi;                //Break Interrupt
    logic       fe;                //Framing Error
    logic       pe;                //Parity Error
    logic       oe;                //Overrun Error
    logic       dr;                //Data Ready
} lsr_t; //Line Status Register

//All Registers
typedef struct {
    fcr_t       fcr; 
    lcr_t       lcr; 
    lsr_t       lsr; 
    logic [7:0] scr; //Scratchpad
 } csr_t;

 //Divisor

typedef struct packed {
    logic [7:0] dmsb;    //Divisor Latch MSB
    logic [7:0] dlsb;    //Divisor Latch LSB
} div_t;
 
 
 

 module uart_registers(
    input clk, rst,
    input wr, rd,
    input rx_fifo_empty,
    input rx_output_error, rx_parity_error, rx_frame_error, rx_break_error,
    input [2:0] addr,   
    input [7:0] din,
    input [7:0] rx_fifo_in,

    output tx_push, rx_pop, tx_rst, rx_rst,
    output [3:0] rx_fifo_threshold,
    output reg [7:0] dout,
    output csr_t csr_out,
    output baud_out
 );

    csr_t csr; //Temporary CSR
     
    bit [3:0] dlab_addr;
    assign dlab_addr = {csr.lcr.dlab, addr};

    /////////////////////////////// THR and RBR

    //THR is the temporary buffer for storing 8 bit data before serial transmission
    //It is an 1 byte register for 8250 and 16 byte FIFO for 16550
    // => 0000 - IN/OUT - Transmitter Holding Register (THR)/ Receiver Buffer Register (RBR)

    // Inputs to Registers - wr,dlab and addr
    // Output from Registers to THR - push signal to read data to be send from TSR
    // Input to THR from TX logic is pop signal to get the data to be send and output to TX logic is data to be sent

    wire tx_fifo_wr;
    assign tx_fifo_wr = wr & (dlab_addr == 4'b0000); //Input to Shift register
    assign tx_push = tx_fifo_wr; //Send Push signal to TX FIFO // Shift Register to FIFO

    //RHR is the temporary buffer for storing 8 bit data after serial transmission
    //Read the data bit-wise and store in RHR
    // => 0000 - IN/OUT - Transmitter Holding Register (THR)/ Receiver Buffer Register (RBR)

    // Inputs to Register - wr,dlab and addr
    // Output from Registers to RBR - pop signal to read data that was recieved in RBR
    // Input to RBR from RX logic is push signal to get the data that was received 

    wire rx_fifo_rd;
    assign rx_fifo_rd = rd & (dlab_addr == 4'b0000);
    assign rx_pop = rx_fifo_rd;

    reg [7:0] rx_data; //Data received
    always@(posedge clk) if(rx_pop) rx_data <= rx_fifo_in; //Data received retrieved by sending pop signal to RBR

    /////////////////////////////// DLL and DHL and Baud Generation

    div_t divisor; //16 bit packed data

    reg update_baud;
    reg baud_pulse  = 0;
    reg [15:0] baud_count = 0;

    //  => 1000 - OUT    - DLL (Divisor LSB)
    //  => 1001 - OUT    - DHL (Divisor MSB)

    always@(posedge clk) begin
        if(wr & (dlab_addr == 4'b1000)) begin
            divisor.dlsb <= din; //Update DLL
            update_baud <= 1'b1; //Update Baud count
        end
        if(wr & (dlab_addr == 4'b1001)) begin
            divisor.dmsb <= din; //Update DGL
            update_baud <= 1'b1; //Update Baud count
        end
    end

    always @(posedge clk, posedge rst) begin
        if (rst) baud_count  <= 16'h0;
        else if (update_baud || baud_count == 16'h0000) baud_count <= divisor; // Baud Count has reached one full cycle
        else baud_count <= baud_count -1;
    end
 
    //generate baud pulse when baud count reaches zero
    always @(posedge  clk) baud_pulse <= |divisor & ~|baud_count; //TRUE only if divisor is not ZERO and baud_count is ZERO
 
    assign baud_out = baud_pulse; /// baud pulse for both tx and rx 


    //////////////////////////////// FCR Write Operation

    // => x010 - IN - FIFO Control Register

    always @(posedge clk, posedge rst) begin
        if(rst) csr.fcr <= 8'h00;
        else if (wr == 1'b1 && addr == 3'b010) begin
            csr.fcr.rx_trigger <= din[7:6];
            csr.fcr.dma_mode   <= din[3];
            csr.fcr.tx_rst     <= din[2];
            csr.fcr.rx_rst     <= din[1];
            csr.fcr.fifo_ena   <= din[0];
        end
        else begin
            csr.fcr.tx_rst     <= 1'b0;
            csr.fcr.rx_rst     <= 1'b0;
        end
    end

    assign tx_rst = csr.fcr.tx_rst;  ////reset tx and rx fifo --> go to tx and rx fifo
    assign rx_rst = csr.fcr.rx_rst;

    //Update FIFO Threshold Count - Based on rx_trigger - 1, 4, 8, 14

    reg [3:0] rx_fifo_th_count = 0;

    always@(*) begin
        if(csr.fcr.fifo_ena == 1'b0) rx_fifo_th_count = 0;
        else begin
            case(csr.fcr.rx_trigger)
                2'b00: rx_fifo_th_count = 4'd1;
                2'b01: rx_fifo_th_count = 4'd4;
                2'b10: rx_fifo_th_count = 4'd8;
                2'b11: rx_fifo_th_count = 4'd14;
            endcase
        end
    end

    assign rx_fifo_threshold = rx_fifo_th_count;   /// -- > go to rx fifo


    //////////////////////////////// LCR Write Operation

    //  => x011 - OUT - Data Format (Line Control) Register (LCR)

    reg [7:0] lcr_temp;

    always @(posedge clk, posedge rst) begin
        if(rst) csr.lcr <= 8'h00;
        else if (wr == 1'b1 && addr == 3'b011) csr.lcr <= din;
    end

    wire read_lcr;
    assign read_lcr = (rd == 1) & (addr == 3'b011);

    always@(posedge clk) if(read_lcr) lcr_temp <= csr.lcr;

    //////////////////////////////// LSR Write Operation
 

    always@(posedge clk, posedge rst) begin
        if(rst) csr.lsr <= 8'b01100000; //Transmitter Empty and THR is empty
        else begin
            csr.lsr.dr <=  ~rx_fifo_empty;
            csr.lsr.oe <=   rx_output_error;
            csr.lsr.pe <=   rx_parity_error;
            csr.lsr.fe <=   rx_frame_error;
            csr.lsr.bi <=   rx_break_error;
        end
    end
 
    reg [7:0] lsr_temp; 
    wire read_lsr;
    assign read_lsr = (rd == 1) & (addr == 3'b101);

    always@(posedge clk) if(read_lsr) lsr_temp <= csr.lsr;
 
    //////////////////////////////// Scratch Pad Register

    always@(posedge clk, posedge rst) begin
        if(rst) csr.scr <= 8'h00;
        else if(wr == 1'b1 && addr == 3'b111) csr.scr <= din;
    end 
 
    reg [7:0] scr_temp; 
    wire read_scr;
    assign read_scr = (rd == 1) & (addr == 3'b111);

    always@(posedge clk) if(read_scr) scr_temp <= csr.scr;
 
    ////////////////////////////////////////////
    
    always@(posedge clk) begin
        case(addr)
            0: dout <= csr.lcr.dlab ? divisor.dlsb : rx_data;
            1: dout <= csr.lcr.dlab ? divisor.dmsb : 8'h00; //IER is disabled
            2: dout <= 8'h00; //IIR is disabled
            3: dout <= lcr_temp;
            4: dout <= 8'h00; //MCR is disabled
            5: dout <= lsr_temp;
            6: dout <= 8'h00; //MSR is disabled
            7: dout <= scr_temp;
            default: ;
        endcase
    end
    
    
    assign csr_out = csr;
    
    endmodule
    




    
