//Assume 16x oversampling

module uart_tx_top(
    input clk, rst, baud_pulse, parity_enable, tx_hold_reg_empty, stop_bit, sticky_parity, even_parity_select, set_break,
    input [7:0] din, //Input from TX FIFO
    input [1:0] wls,
    output reg pop, sreg_empty, tx
);

    typedef enum logic [1:0] { 
        idle,
        start,
        send,
        parity
    } state_type;

    state_type state = idle;

    reg [7:0] shift_register; //TX Hold Register
    reg tx_data; //Temp TX Line Data
    reg d_parity; //Temp Parity before SP, EPS logic
    reg [2:0] bit_count = 0; //Max bit count is 8
    reg [4:0] count = 5'd15; //Oversampling => 1 bit per 16 clock cycles but if 2 stop bits are used then 36 clock cycles used
    reg parity_out; //Final Parity

    always@(posedge clk, posedge rst) begin
        if(rst) begin
            state <= idle;
            count <= 5'd15;
            bit_count <= 0;
            shift_register <= 8'bxxxxxxxx;
            pop <= 1'b0;
            sreg_empty <= 1'b0;
            tx_data <= 1'b1;
        end
        else if(baud_pulse) begin
            case(state)
                idle: begin
                    if(tx_hold_reg_empty == 1'b0) begin //If Register is not empty, start transmission
                        if(count != 0) begin //Not completed 16 cycles from the previous transmission, TX still has data
                            count <= count - 1;
                            state <= idle;
                        end
                        else begin
                            
                            //Next state will be start

                            count <= 5'd15;
                            state <= start;
                            bit_count <= {1'b1, wls}; // {MSB, LSB}

                            /*
                            If wls == 0, bit_count = 5(4) (100)
                            If wls == 1, bit_count = 6(5) (101)
                            If wls == 2, bit_count = 7(6) (110)
                            If wls == 3, bit_count = 8(7) (111)
                            */

                            pop <= 1'b1; //Read from FIFO
                            shift_register <= din;
                            sreg_empty <= 1'b0;

                            tx_data <= 1'b0; //Start bit

                        end
                    end
                end

                start: begin
                    
                    case(wls) //XOR of all valid data bits to get if ODD
                        2'b00: d_parity <= ^din[4:0];
                        2'b01: d_parity <= ^din[5:0];
                        2'b10: d_parity <= ^din[6:0];
                        2'b11: d_parity <= ^din[7:0];
                    endcase

                    if(count !=0) begin //Already made count 15 in previous state
                        count <= count -1;
                        state <= start;
                    end
                    else begin
                        count <= 5'd15;
                        state <= send;

                        tx_data <= shift_register[0]; //LSB first
                        shift_register <= shift_register >> 1; //Shift Right to make MSB 0 and LSB the next data
                    end
                end
                
                send: begin

                    case({sticky_parity, even_parity_select})
                        2'b00: parity_out <= ~d_parity; //ODD parity, already ODD, so parity should be 0
                        2'b01: parity_out <= d_parity; //EVEN parity, already ODD, so parity should be 1
                        2'b10: parity_out <= 1'b1;     //Sticky parity, so parity should be 1
                        2'b11: parity_out <= 1'b0;     //Sticky parity, so parity should be 0
                    endcase

                    if(bit_count != 0) begin
                        if(count != 0) begin
                            count <= count - 1;
                            state <= send;
                        end
                        else begin
                            count <= 5'd15;
                            bit_count <= bit_count - 1;
                            state <= send;

                            tx_data <= shift_register[0]; //LSB first
                            shift_register <= shift_register >> 1; //Shift Right to make MSB 0 and LSB the next data
                        end
                    end
                    else begin
                        if(count != 0) begin//Waiting for 16 cycles for the last data bit
                            count <= count -1;
                            state <= send;
                        end
                        else begin
                            count <= 5'd15;
                            sreg_empty <= 1'b1;

                            if(parity_enable == 1'b1) begin
                                state <= parity;
                                count <= 5'd15;
                                tx_data <= parity_out;
                            end
                            else begin
                                state <= idle;
                                tx_data <= 1'b1;
                                count <= (stop_bit == 1'b0) ? 5'd15 : (wls == 2'b00) ? 5'd23 : 5'd31;
                                //If STB is 0, then 1 bit (16), else [If wls is 0, then 1.5 (24) bit else 2 (32) bits]
                            end
                        end
                    end
                end
                parity: begin
                    if(count != 0) begin //Finish sending parity bit set in previous state
                        count <= count -1;
                        state <= parity;
                    end
                    else begin
                        state <= idle;
                        tx_data <= 1'b1;
                        count <= (stop_bit == 1'b0) ? 5'd15 : (wls == 2'b00) ? 5'd23 : 5'd31;
                        //If STB is 0, then 1 bit (16), else [If wls is 0, then 1.5 (24) bit else 2 (32) bits]
                    end
                end
                default: ;
            endcase
        end
    end


    //Break Logic

    always@(posedge clk, posedge rst) begin 
        if(rst) tx <= 1'b1;
        else tx <= tx_data & ~set_break;
    end

endmodule













