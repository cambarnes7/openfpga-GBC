// Directed TPP1 test: the checks of utils/tpp1_selftest (CSE repo) driven on the
// cartridge bus, plus rollover, overflow and save-tail persistence.
`timescale 1ns/1ps
module tb_tpp1;
	localparam MAW = 25;
`include "tb_common.vh"
	integer fails = 0, checks = 0;
	task check(input [255:0] name, input [63:0] got, input [63:0] want); begin
		checks = checks + 1;
		if (got !== want) begin fails = fails + 1; $display("FAIL %0s: got %h want %h", name, got, want); end
	end endtask

	// ce_32k: one pulse per `div` clocks; div=1 makes a second 32768 clocks long
	integer div = 1, divc = 0;
	always @(posedge clk) begin divc <= (divc + 1 >= div) ? 0 : divc + 1; ce_32k <= (divc == 0); end
	task seconds(input integer n); begin repeat (n * 32768 * div) @(posedge clk); end endtask

	task set_bank(input [15:0] b); begin wr(16'h0000, b[7:0]); wr(16'h0001, b[15:8]); end endtask
	task check_bank(input [15:0] b, input [10:0] want); begin
		set_bank(b);
		rd(16'h4000); check("bank lo", rdata, want[7:0]);
		check("mbc_addr", mbc_addr, {want, 14'd0});
		rd(16'h4001); check("bank hi", rdata, {5'd0, want[10:8]});
		rd(16'h0000); check("home bank", rdata, 8'h00);
	end endtask
	task set_clock(input [7:0] w, input [7:0] dh, input [7:0] m, input [7:0] s); begin
		wr(16'h0003, 8'h05);
		wr(16'hA000, w); wr(16'hA001, dh); wr(16'hA002, m); wr(16'hA003, s);
		wr(16'h0003, 8'h11);
	end endtask
	reg [31:0] clock_now;
	task read_clock; begin
		wr(16'h0003, 8'h10); wr(16'h0003, 8'h05);
		rd(16'hA000); clock_now[31:24] = rdata; rd(16'hA001); clock_now[23:16] = rdata;
		rd(16'hA002); clock_now[15:8] = rdata;  rd(16'hA003); clock_now[7:0] = rdata;
	end endtask
	task load_tail(input [31:0] stamp, input [47:0] saved);
		integer i; reg [15:0] words [0:9];
	begin
		words[0] = stamp[15:0]; words[1] = stamp[31:16];
		words[2] = saved[15:0]; words[3] = saved[31:16]; words[4] = saved[47:32];
		for (i = 5; i < 10; i = i + 1) words[i] = 16'hFFFF;
		for (i = 0; i < 10; i = i + 1) begin
			@(negedge clk); bk_addr = i; bk_data = words[i]; bk_rtc_wr = 1;
			@(negedge clk); bk_rtc_wr = 0; @(negedge clk);
		end
	end endtask

	integer i;
	reg [15:0] banks [0:15];
	reg [47:0] tail; reg [31:0] stamp;
	initial begin
		banks[0]=1; banks[1]=2; banks[2]=3; banks[3]=127; banks[4]=128; banks[5]=255; banks[6]=256;
		banks[7]=257; banks[8]=511; banks[9]=512; banks[10]=513; banks[11]=1023; banks[12]=1024;
		banks[13]=2047; banks[14]=2048; banks[15]=4095;

		RTC_time = {1'b1, 32'd1000000};
		// ---------- 32 MiB, 64 KiB SRAM (shift 4), RTC + battery ----------
		download(8'hBC, 8'h0A, 8'hC1, 8'h65, 8'h04, 8'h0F, 26'h2000000);
		check("has_save", has_save, 1); check("ram_size code (64k)", ram_size, 8'd5);
		check("ram_mask_file", ram_mask_file, 8'h7F); check("RTC_inuse", RTC_inuse, 1);
		check("rumbling", rumbling, 0);
		// 1. power-on registers, mirrored every four bytes
		rd(16'hA000); check("MR0 init", rdata, 8'h01); rd(16'hA001); check("MR1 init", rdata, 8'h00);
		rd(16'hA002); check("MR2 init", rdata, 8'h00); rd(16'hBFFF); check("MR4 init", rdata, 8'hF0);
		check("cart_oe A000 held", cart_oe, 0);
		rd(16'h4000); check("bank 1 at power-on", rdata, 8'h01);
		// 2. banks: all 11 bits reach the address, the rest of the 16 are ignored
		for (i = 0; i < 14; i = i + 1) check_bank(banks[i], banks[i][10:0]);
		check_bank(16'd2048, 11'd0); check_bank(16'd4095, 11'd2047); check_bank(16'd0, 11'd0);
		// registers hold all eight bits; only address bits 1-0 select them
		wr(16'h2000, 8'h02); wr(16'h3FFD, 8'h81); wr(16'h1236, 8'hC7);
		wr(16'h0003, 8'h00);
		rd(16'hA000); check("MR0 readback", rdata, 8'h02); rd(16'hA005); check("MR1 readback", rdata, 8'h81);
		rd(16'hA002); check("MR2 readback", rdata, 8'hC7);
		wr(16'hA000, 8'h55); rd(16'hA000); check("register window is read-only", rdata, 8'h02);
		wr(16'h4000, 8'h33); rd(16'hA000); check("4000-7FFF writes ignored", rdata, 8'h02);
		set_bank(16'd1);
		// 3. SRAM
		wr(16'h0003, 8'h03);
		wr(16'h0002, 8'h00); wr(16'hA000, 8'h11); wr(16'hBFFF, 8'h22);
		wr(16'h0002, 8'h07); wr(16'hA000, 8'h77); wr(16'hBFFF, 8'h88);
		wr(16'h0002, 8'h00); rd(16'hA000); check("sram b0 A000", rdata, 8'h11); rd(16'hBFFF); check("sram b0 BFFF", rdata, 8'h22);
		wr(16'h0002, 8'h07); rd(16'hA000); check("sram b7 A000", rdata, 8'h77); rd(16'hBFFF); check("sram b7 BFFF", rdata, 8'h88);
		wr(16'h0002, 8'h0F); rd(16'hA000); check("sram bank 15 mirrors 7 (8 banks)", rdata, 8'h77);
		wr(16'h0002, 8'h07);
		wr(16'h0003, 8'h02); wr(16'hA000, 8'hEE); rd(16'hA000); check("sram read-only", rdata, 8'h77);
		wr(16'h0003, 8'h00); wr(16'hA000, 8'hEE); wr(16'h0003, 8'h03); rd(16'hA000); check("sram safe in register mode", rdata, 8'h77);
		wr(16'h0003, 8'h05); wr(16'hA000, 8'hEE); wr(16'h0003, 8'h03); rd(16'hA000); check("sram safe in RTC mode", rdata, 8'h77);
		// 4. RTC: set, start, run, latch, stop
		set_clock(0, 0, 0, 0);
		wr(16'h0003, 8'h19); wr(16'h0003, 8'h00);
		rd(16'hA003); check("MR4 running", rdata, 8'hF4);
		seconds(9);
		read_clock; check("clock after 9 s", clock_now, 32'h00000009);
		seconds(2);
		rd(16'hA003); check("latch holds", rdata, 8'h09);
		wr(16'h0003, 8'h18); wr(16'h0003, 8'h00); rd(16'hA003); check("MR4 stopped", rdata, 8'hF0);
		read_clock; check("clock at stop", clock_now, 32'h0000000B);
		seconds(2);
		read_clock; check("stopped clock stays", clock_now, 32'h0000000B);
		// latch registers are full bytes, readable as written
		wr(16'hA000, 8'hAB); wr(16'hA001, 8'hCD); wr(16'hA006, 8'hEF); wr(16'hA007, 8'h12);
		rd(16'hA000); check("latch W", rdata, 8'hAB); rd(16'hA001); check("latch DH", rdata, 8'hCD);
		rd(16'hA002); check("latch M", rdata, 8'hEF); rd(16'hA003); check("latch S", rdata, 8'h12);
		// rollover: week 255, day 6, 23:59:58 -> week 0, day 0, 00:00:01 + overflow
		set_clock(8'hFF, {3'd6, 5'd23}, 8'd59, 8'd58);
		wr(16'h0003, 8'h19); seconds(3);
		read_clock; check("rollover", clock_now, 32'h00000001);
		wr(16'h0003, 8'h00); rd(16'hA003); check("MR4 overflow", rdata, 8'hFC);
		wr(16'h0003, 8'h14); rd(16'hA003); check("MR4 overflow cleared", rdata, 8'hF4);
		// minute and hour carries
		set_clock(8'd3, {3'd2, 5'd9}, 8'd59, 8'd59); seconds(1);
		read_clock; check("hour carry", clock_now, {8'd3, 3'd2, 5'd10, 8'd0, 8'd0});
		set_clock(8'd3, {3'd2, 5'd23}, 8'd59, 8'd59); seconds(1);
		read_clock; check("day carry", clock_now, {8'd3, 3'd3, 5'd0, 8'd0, 8'd0});
		// rumble: accepted, speed always 0, mapping unchanged
		wr(16'h0003, 8'h00); wr(16'h0003, 8'h23); rd(16'hA003); check("rumble speed 0", rdata, 8'hF4);
		check("rumbling", rumbling, 0); wr(16'h0003, 8'h20);
		// 5. save tail: what the core writes, then a reload 2 weeks 3 days 4:05:06 later
		div = 64; // slow the prescaler so no real second passes during a catch-up
		set_clock(8'd10, {3'd5, 5'd22}, 8'd58, 8'd57);
		repeat (4) @(negedge clk);
		tail = RTC_savedtimeOut; stamp = RTC_timestampOut;
		check("tail layout", tail, {18'd0, 1'b1, 1'b0, 8'd10, 3'd5, 5'd22, 6'd58, 6'd57});
		RTC_time = {1'b0, stamp + 32'd1483506};
		download(8'hBC, 8'h09, 8'hC1, 8'h65, 8'h05, 8'h0C, 26'h1000000);
		check("ram_size code (128k)", ram_size, 8'd4); check("ram_mask_file 128k", ram_mask_file, 8'hFF);
		wr(16'h0003, 8'h00); rd(16'hA003); check("fresh cart: RTC stopped", rdata, 8'hF0);
		load_tail(stamp, tail);
		repeat (90000) @(negedge clk);  // the catch-up takes up to 86399 clocks
		rd(16'hA003); check("reloaded: RTC running", rdata, 8'hF4);
		// 10w 5d 22:58:57 + 2w 3d 04:05:06 = 13w 2d 03:04:03
		read_clock; check("catch-up", clock_now, {8'd13, 3'd2, 5'd3, 8'd4, 8'd3});
		// 16 MiB: bank 1023 is the last one, 1024 mirrors bank 0
		check_bank(16'd1023, 11'd1023); check_bank(16'd512, 11'd512); check_bank(16'd1024, 11'd0);
		// a stopped clock does not catch up; overflow survives the reload
		tail = {18'd0, 1'b0, 1'b1, 8'd200, 3'd1, 5'd2, 6'd3, 6'd4};
		RTC_time = {1'b1, stamp + 32'd9999999};
		download(8'hBC, 8'h07, 8'hC1, 8'h65, 8'h00, 8'h04, 26'h400000);
		check("no SRAM: no save", has_save, 0);
		load_tail(stamp, tail); repeat (90000) @(negedge clk);  // the catch-up takes up to 86399 clocks
		read_clock; check("stopped reload", clock_now, {8'd200, 3'd1, 5'd2, 8'd3, 8'd4});
		wr(16'h0003, 8'h00); rd(16'hA003); check("stopped + overflow", rdata, 8'hF8);
		wr(16'h0003, 8'h03); rd(16'hA000); check("no SRAM reads FF", rdata, 8'hFF);
		check_bank(16'd255, 11'd255); check_bank(16'd256, 11'd0);
		// catch-up across the week counter's wrap sets overflow
		tail = {18'd0, 1'b1, 1'b0, 8'd255, 3'd6, 5'd23, 6'd59, 6'd59};
		RTC_time = {1'b0, stamp + 32'd10000000};
		download(8'hBC, 8'h07, 8'hC1, 8'h65, 8'h05, 8'h0C, 26'h400000);
		load_tail(stamp + 32'd9999999, tail); repeat (90000) @(negedge clk);  // the catch-up takes up to 86399 clocks
		read_clock; check("catch-up wrap", clock_now, 32'h00000000);
		wr(16'h0003, 8'h00); rd(16'hA003); check("catch-up overflow", rdata, 8'hFC);
		// reset keeps the clock, restores the registers
		wr(16'h0000, 8'h42); wr(16'h0002, 8'h03); wr(16'h0003, 8'h03);
		@(negedge clk); reset = 1; repeat (4) @(negedge clk); reset = 0; repeat (4) @(negedge clk);
		rd(16'hA000); check("MR0 after reset", rdata, 8'h01); rd(16'hA002); check("MR2 after reset", rdata, 8'h00);
		rd(16'hA003); check("RTC survives reset", rdata, 8'hFC);

		$display("%0d checks, %0d failed", checks, fails);
		if (fails == 0) $display("PASS"); else $display("FAILED");
		$finish;
	end
endmodule
