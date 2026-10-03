// Simulation stand-ins for the two VHDL modules cart.v instantiates.
module dpram #(parameter addr_width = 8, parameter data_width = 8) (
	input clock_a, input [addr_width-1:0] address_a, input wren_a,
	input [data_width-1:0] data_a, output reg [data_width-1:0] q_a,
	input clock_b, input [addr_width-1:0] address_b, input wren_b,
	input [data_width-1:0] data_b, output reg [data_width-1:0] q_b
);
	reg [data_width-1:0] mem [0:(1<<addr_width)-1];
	integer i;
	initial for (i = 0; i < (1<<addr_width); i = i + 1) mem[i] = 0;
	always @(posedge clock_a) begin
		if (wren_a) mem[address_a] <= data_a;
		q_a <= mem[address_a];
	end
	always @(posedge clock_b) begin
		if (wren_b) mem[address_b] <= data_b;
		q_b <= mem[address_b];
	end
endmodule

module eReg_SavestateV #(parameter index = 0, parameter Adr = 0, parameter size = 0,
                         parameter lsb = 0, parameter [63:0] def = 0) (
	input clk, input [63:0] BUS_Din, input [9:0] BUS_Adr, input BUS_wren, input BUS_rst,
	output [63:0] BUS_Dout, input [size-lsb:0] Din, output [size-lsb:0] Dout
);
	assign BUS_Dout = 64'd0;
	assign Dout = def[size-lsb:0];
endmodule
