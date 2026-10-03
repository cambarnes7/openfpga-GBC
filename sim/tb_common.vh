// Shared bench: cart_top, a ROM model in which every 16 KiB bank starts with its own
// number (low byte, high byte), a download that feeds a header, and CPU bus tasks.
	reg clk = 0; always #5 clk = ~clk;
	reg reset = 1;
	reg [14:0] cart_addr = 0; reg cart_a15 = 0, cart_rd = 0, cart_wr = 0; reg [7:0] cart_di = 0;
	reg nCS = 1;
	wire [7:0] cart_do; wire cart_oe;
	wire [MAW-1:0] mbc_addr;
	reg cart_download = 0, ioctl_wr = 0; reg [24:0] ioctl_addr = 0; reg [15:0] ioctl_dout = 0;
	reg bk_wr = 0, bk_rtc_wr = 0; reg [16:0] bk_addr = 0; reg [15:0] bk_data = 0; wire [15:0] bk_q;
	reg ce_32k = 0; reg [32:0] RTC_time = 0;
	wire [31:0] RTC_timestampOut; wire [47:0] RTC_savedtimeOut; wire RTC_inuse;
	wire [7:0] ram_mask_file, ram_size; wire has_save, cram_rd, cram_wr, cart_ready, dn_write;
	wire isGBC_game, isSGB_game, rumbling; wire [63:0] ss_dout; wire [7:0] ss_cram;

	wire [10:0] rom_bank_sel = mbc_addr >> 14;
	wire [7:0] rom_di = (mbc_addr[13:0] == 0) ? rom_bank_sel[7:0] :
	                    (mbc_addr[13:0] == 1) ? {5'd0, rom_bank_sel[10:8]} :
	                    mbc_addr[7:0] ^ mbc_addr[15:8];

	cart_top dut (
		.reset(reset), .clk_sys(clk), .ce_cpu(1'b1), .ce_cpu2x(1'b1), .speed(1'b0),
		.megaduck(1'b0), .mapper_sel(3'd0),
		.cart_addr(cart_addr), .cart_a15(cart_a15), .cart_rd(cart_rd), .cart_wr(cart_wr),
		.cart_do(cart_do), .cart_di(cart_di), .cart_oe(cart_oe), .nCS(nCS),
		.mbc_addr(mbc_addr), .dn_write(dn_write), .cart_ready(cart_ready),
		.cram_rd(cram_rd), .cram_wr(cram_wr), .cart_download(cart_download),
		.ram_mask_file(ram_mask_file), .ram_size(ram_size), .has_save(has_save),
		.isGBC_game(isGBC_game), .isSGB_game(isSGB_game),
		.ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.bk_wr(bk_wr), .bk_rtc_wr(bk_rtc_wr), .bk_addr(bk_addr), .bk_data(bk_data), .bk_q(bk_q),
		.img_size(64'd0), .rom_di(rom_di), .joystick_analog_0(16'd0),
		.ce_32k(ce_32k), .RTC_time(RTC_time), .RTC_timestampOut(RTC_timestampOut),
		.RTC_savedtimeOut(RTC_savedtimeOut), .RTC_inuse(RTC_inuse),
		.SaveStateExt_Din(64'd0), .SaveStateExt_Adr(10'd0), .SaveStateExt_wren(1'b0),
		.SaveStateExt_rst(1'b0), .SaveStateExt_Dout(ss_dout), .savestate_load(1'b0),
		.sleep_savestate(1'b0), .Savestate_CRAMAddr(20'd0), .Savestate_CRAMRWrEn(1'b0),
		.Savestate_CRAMWriteData(8'd0), .Savestate_CRAMReadData(ss_cram), .rumbling(rumbling)
	);

	task dl_word(input [24:0] a, input [15:0] d); begin
		@(negedge clk); ioctl_addr = a; ioctl_dout = d; ioctl_wr = 1;
		@(negedge clk); ioctl_wr = 0; repeat (3) @(negedge clk);
	end endtask

	// Download a ROM of `bytes` bytes with the given header fields.
	task download(input [7:0] mbc_type, input [7:0] rom_code, input [7:0] ram_code,
	              input [7:0] dest, input [7:0] ext_ram, input [7:0] ext_feat, input [25:0] bytes);
		reg [25:0] a;
	begin
		reset = 1; @(negedge clk); cart_download = 1; repeat (4) @(negedge clk);
		dl_word(25'h100, 16'hC300);
		dl_word(25'h142, 16'h8000);              // CGB flag
		dl_word(25'h146, {mbc_type, 8'h00});
		dl_word(25'h148, {ram_code, rom_code});
		dl_word(25'h14a, {8'h33, dest});
		dl_word(25'h150, 16'h0001);              // TPP1 version 1.0
		dl_word(25'h152, {ext_feat, ext_ram});
		for (a = 26'h4000; a < bytes; a = a + 26'h4000) dl_word(a[24:0], 16'hFFFF);
		dl_word(bytes - 2, 16'hFFFF);
		cart_download = 0; repeat (8) @(negedge clk);
		reset = 0; repeat (4) @(negedge clk);
	end endtask

	reg [2:0] flags;          // cart_oe, cram_rd, cram_wr while the access is active
	reg [31:0] seen_addr;     // mbc_addr while the access is active

	task wr(input [15:0] a, input [7:0] d); begin
		@(negedge clk); cart_addr = a[14:0]; cart_a15 = a[15]; nCS = ~(a[15:13] == 3'b101);
		cart_di = d; cart_wr = 1; #1 flags = {cart_oe, cram_rd, cram_wr}; seen_addr = mbc_addr;
		@(negedge clk); cart_wr = 0; @(negedge clk);
	end endtask

	reg [7:0] rdata;
	task rd(input [15:0] a); begin
		@(negedge clk); cart_addr = a[14:0]; cart_a15 = a[15]; nCS = ~(a[15:13] == 3'b101);
		cart_rd = 1;
		repeat (3) @(negedge clk); rdata = cart_do; flags = {cart_oe, cram_rd, cram_wr}; seen_addr = mbc_addr;
		cart_rd = 0; @(negedge clk);
	end endtask
