module dff(
    input wire clk, rst,
    input [7:0] din,
    output reg dout
);

    always@(posedge clk or negedge rst) begin
        if(!rst) dout <= 0;
        else dout <= din;
    end

endmodule

interface dff_if;

    logic clk, rst;
    logic [7:0] din, dout;

endinterface
