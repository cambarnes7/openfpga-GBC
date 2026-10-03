// Random bus traffic against one mapper; prints every observable cartridge output.
// Run on two source trees and diff the output: any change in an existing mapper's
// behaviour shows up as a differing line (see run.sh and compare_upstream.sh).
`timescale 1ns/1ps
module tb_trace;
	localparam MAW = `MAW;
`include "tb_common.vh"
	reg [1:0] c32 = 0;
	always @(posedge clk) begin c32 <= c32 + 1'd1; ce_32k <= (c32 == 0); end

	integer seed = 32'h1234 + `CASE, n, r;
	reg [15:0] a;
	task show(input [7:0] tag); begin
		$display("%c %h %h | %h %h %b %b | %h %h %b %b %b", tag, a, cart_di, seen_addr, rdata,
		         flags, rumbling, ram_mask_file, ram_size, has_save, RTC_inuse, cart_ready);
	end endtask
	initial begin
		RTC_time = {1'b1, 32'd500000};
		case (`CASE)
			 0: download(8'h00, 8'h00, 8'h00, 8'h00, 8'hFF, 8'hFF, 26'h0008000); // no mapper
			 1: download(8'h00, 8'h01, 8'h00, 8'h00, 8'hFF, 8'hFF, 26'h0010000); // no mapper, 64 KiB
			 2: download(8'h03, 8'h06, 8'h03, 8'h01, 8'hFF, 8'hFF, 26'h0200000); // MBC1+RAM+BATTERY
			 3: download(8'h06, 8'h03, 8'h00, 8'h01, 8'hFF, 8'hFF, 26'h0040000); // MBC2
			 4: download(8'h10, 8'h06, 8'h03, 8'h01, 8'hFF, 8'hFF, 26'h0200000); // MBC3+TIMER+RAM
			 5: download(8'h10, 8'h07, 8'h05, 8'h01, 8'hFF, 8'hFF, 26'h0400000); // MBC30
			 6: download(8'h1B, 8'h08, 8'h04, 8'h01, 8'hFF, 8'hFF, 26'h0800000); // MBC5, 8 MiB, 128 KiB
			 7: download(8'h19, 8'h05, 8'h00, 8'h01, 8'hFF, 8'hFF, 26'h0100000); // MBC5, 1 MiB
			 8: download(8'h1E, 8'h07, 8'h03, 8'h01, 8'hFF, 8'hFF, 26'h0400000); // MBC5+RUMBLE
			 9: download(8'h1B, 8'h08, 8'h02, 8'h01, 8'hFF, 8'hFF, 26'h1000000); // MBC5 header, 16 MiB file
			10: download(8'h20, 8'h05, 8'h03, 8'h01, 8'hFF, 8'hFF, 26'h0100000); // MBC6
			11: download(8'h22, 8'h06, 8'h00, 8'h01, 8'hFF, 8'hFF, 26'h0200000); // MBC7
			12: download(8'hFF, 8'h05, 8'h03, 8'h01, 8'hFF, 8'hFF, 26'h0100000); // HuC1
			13: download(8'hFE, 8'h06, 8'h03, 8'h01, 8'hFF, 8'hFF, 26'h0200000); // HuC3
			14: download(8'hFC, 8'h05, 8'h04, 8'h01, 8'hFF, 8'hFF, 26'h0100000); // Game Boy Camera
			15: download(8'hFD, 8'h04, 8'h03, 8'h01, 8'hFF, 8'hFF, 26'h0080000); // TAMA5
			16: download(8'h97, 8'h04, 8'h00, 8'h01, 8'hFF, 8'hFF, 26'h0080000); // Rocket
			17: download(8'h13, 8'h05, 8'h03, 8'h65, 8'h05, 8'h0C, 26'h0100000); // MBC3 with TPP1-like bytes
			18: download(8'hBC, 8'h05, 8'h03, 8'h65, 8'h05, 8'h0C, 26'h0100000); // $BC but not TPP1
		endcase
		a = 0; rd(16'h0000); show("I");
		for (n = 0; n < 20000; n = n + 1) begin
			r = $random(seed);
			case (r[18:16])
				0, 1:    a = {2'b00, r[13:0]};           // 0000-3FFF
				2, 3:    a = {2'b01, r[13:0]};           // 4000-7FFF
				4:       a = {3'b101, r[12:0]};          // A000-BFFF
				5:       a = {3'b101, 9'd0, r[3:0]};     // A000-A00F
				6:       a = {2'b00, r[13:12], 12'd0};   // register addresses
				7:       a = {2'b01, r[13:12], 12'd0};
			endcase
			if (r[20]) begin
				// bias the data towards the values the mappers decode
				wr(a, r[21] ? r[31:24] : (r[22] ? 8'h0A : {4'h0, r[27:24]}));
				show("W");
			end else begin
				rd(a); show("R");
			end
		end
		$finish;
	end
endmodule
