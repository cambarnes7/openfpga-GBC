// TPP1 mapper (https://github.com/aaaaaa123456789/tpp1/blob/master/specification.md)
//
// MR0/MR1: 16-bit ROM bank for 4000-7FFF (no "0 becomes 1" fixup), MR2: SRAM bank,
// MR3: control (write-only), MR4: status (read-only). The registers are written
// through 0000-3FFF, selected by address bits 1-0 only.
//
// Limits of this implementation:
//  - ROM: the low 11 bits of the bank reach the SDRAM (2048 banks = 32 MiB).
//  - SRAM: the low 4 bits of MR2 are used (16 banks = 128 KiB, the core's cart RAM).
//  - Rumble: 20-23 are accepted and MR4 always reports speed 0, which the
//    specification allows for a cartridge without a motor.
//
// RTC persistence uses the MBC3 mechanism (same save file tail, see RTC_savedtimeOut).

module tpp1 (
	input             enable,
	input             reset,

	input             clk_sys,
	input             ce_cpu,

	input             savestate_load,
	input      [63:0] savestate_data2,
	inout      [63:0] savestate_back2_b,

	input             ce_32k,
	input      [32:0] RTC_time,
	inout      [31:0] RTC_timestampOut_b,
	inout      [47:0] RTC_savedtimeOut_b,
	inout             RTC_inuse_b,

	input             bk_rtc_wr,
	input      [16:0] bk_addr,
	input      [15:0] bk_data,

	input             has_ram,
	input       [3:0] ram_mask,
	input      [10:0] rom_mask,
	input       [7:0] features,   // header byte $0153: bit 2 = RTC, bit 3 = battery

	input      [14:0] cart_addr,
	input             cart_a15,

	input             cart_rd,
	input             cart_wr,
	input       [7:0] cart_di,
	inout             cart_oe_b,

	input             nCS,

	input       [7:0] cram_di,
	inout       [7:0] cram_do_b,
	inout      [16:0] cram_addr_b,

	inout      [24:0] mbc_addr_b,
	inout             ram_enabled_b,
	inout             has_battery_b
);

localparam MAP_REGS   = 3'd0;  // MR3 = 00: MR0/MR1/MR2/MR4, read-only
localparam MAP_RAM_RO = 3'd2;  // MR3 = 02: SRAM, read-only
localparam MAP_RAM_RW = 3'd3;  // MR3 = 03: SRAM, read/write
localparam MAP_RTC    = 3'd5;  // MR3 = 05: RTC latch registers, read/write

wire [24:0] mbc_addr;
wire  [7:0] cram_do;
wire [16:0] cram_addr;
wire        cart_oe;
wire        ram_enabled;
wire        has_battery;
wire [63:0] savestate_back2;
wire        is_cram_addr = ~nCS & ~cart_addr[14];

reg  [31:0] RTC_timestampOut = 0;
reg  [47:0] RTC_savedtimeOut;
wire        has_rtc   = features[2];
wire        RTC_inuse = has_rtc;

assign mbc_addr_b         = enable ? mbc_addr         : 25'hZ;
assign cram_do_b          = enable ? cram_do          :  8'hZ;
assign cram_addr_b        = enable ? cram_addr        : 17'hZ;
assign cart_oe_b          = enable ? cart_oe          :  1'hZ;
assign ram_enabled_b      = enable ? ram_enabled      :  1'hZ;
assign has_battery_b      = enable ? has_battery      :  1'hZ;
assign savestate_back2_b  = enable ? savestate_back2  : 64'hZ;
assign RTC_timestampOut_b = enable ? RTC_timestampOut : 32'hZ;
assign RTC_savedtimeOut_b = enable ? RTC_savedtimeOut : 48'hZ;
assign RTC_inuse_b        = enable ? RTC_inuse        :  1'hZ;

// --------------------- CPU register interface ------------------

reg  [7:0] mr0, mr1, mr2;
reg  [2:0] map_mode;

// RTC registers (the clock itself is further down)
reg [14:0] rtc_subseconds;   // restarts when the clock is set
reg [14:0] stamp_subseconds = 0; // free running, for the host timestamp
reg  [5:0] rtc_seconds;
reg  [5:0] rtc_minutes;
reg  [4:0] rtc_hours;
reg  [2:0] rtc_weekday;
reg  [7:0] rtc_weeks;
reg        rtc_running = 0;
reg        rtc_overflow = 0;

// RTC latch registers, in A000-A003 order: RTCW, RTCDH, RTCM, RTCS
reg  [7:0] latch_w, latch_dh, latch_m, latch_s;

wire mr_wr    = cart_wr & ~cart_a15 & ~cart_addr[14];
wire mr3_wr   = ce_cpu & mr_wr & (cart_addr[1:0] == 2'd3);
wire latch_wr = ce_cpu & cart_wr & is_cram_addr & (map_mode == MAP_RTC) & has_rtc;

wire cmd_latch     = mr3_wr & has_rtc & (cart_di == 8'h10);
wire cmd_set       = mr3_wr & has_rtc & (cart_di == 8'h11);
wire cmd_clear_ovf = mr3_wr & has_rtc & (cart_di == 8'h14);
wire cmd_stop      = mr3_wr & has_rtc & (cart_di == 8'h18);
wire cmd_start     = mr3_wr & has_rtc & (cart_di == 8'h19);

assign savestate_back2[ 7: 0] = mr0;
assign savestate_back2[15: 8] = mr1;
assign savestate_back2[23:16] = mr2;
assign savestate_back2[26:24] = map_mode;
assign savestate_back2[31:27] = 0;
assign savestate_back2[63:32] = { latch_w, latch_dh, latch_m, latch_s };

// The registers return to their power-on values when reset rises (and while no
// TPP1 cartridge is loaded). A savestate loaded afterwards restores them.
reg reset_1;

always @(posedge clk_sys) begin
	reset_1 <= reset;

	if(savestate_load & enable) begin
		mr0      <= savestate_data2[ 7: 0];
		mr1      <= savestate_data2[15: 8];
		mr2      <= savestate_data2[23:16];
		map_mode <= savestate_data2[26:24];
	end else if(~enable | (reset & ~reset_1)) begin
		mr0      <= 8'd1;
		mr1      <= 8'd0;
		mr2      <= 8'd0;
		map_mode <= MAP_REGS;
	end else if(ce_cpu) begin
		if (mr_wr) begin
			case(cart_addr[1:0])
				2'd0: mr0 <= cart_di;
				2'd1: mr1 <= cart_di;
				2'd2: mr2 <= cart_di;
				2'd3: begin
					case(cart_di)
						8'h00: map_mode <= MAP_REGS;
						8'h02: map_mode <= MAP_RAM_RO;
						8'h03: map_mode <= MAP_RAM_RW;
						8'h05: map_mode <= MAP_RTC;
						default: ; // RTC and rumble commands, and undefined values, keep the mapping
					endcase
				end
			endcase
		end
	end
end

// 0x0000-0x3FFF = Bank 0
wire [10:0] rom_bank   = (~cart_addr[14]) ? 11'd0 : { mr1[2:0], mr0 };

// mask address lines to enable proper mirroring
wire [10:0] rom_bank_m = rom_bank & rom_mask;

assign mbc_addr = { rom_bank_m, cart_addr[13:0] };

wire [3:0] ram_bank = mr2[3:0] & ram_mask;

assign cram_addr   = { ram_bank, cart_addr[12:0] };
assign ram_enabled = (map_mode == MAP_RAM_RW) & has_ram;
assign has_battery = features[3];

// The RAM area is always driven: registers, SRAM, RTC latch, or $FF.
assign cart_oe = cart_rd & (~cart_a15 | is_cram_addr);

wire [7:0] mr4 = { 4'hF, rtc_overflow, rtc_running, 2'b00 };

reg [7:0] cram_do_r;
always @* begin
	cram_do_r = 8'hFF;
	case (map_mode)
		MAP_REGS:
			case (cart_addr[1:0])
				2'd0: cram_do_r = mr0;
				2'd1: cram_do_r = mr1;
				2'd2: cram_do_r = mr2;
				2'd3: cram_do_r = mr4;
			endcase
		MAP_RAM_RO, MAP_RAM_RW:
			if (has_ram) cram_do_r = cram_di;
		MAP_RTC:
			if (has_rtc)
				case (cart_addr[1:0])
					2'd0: cram_do_r = latch_w;
					2'd1: cram_do_r = latch_dh;
					2'd2: cram_do_r = latch_m;
					2'd3: cram_do_r = latch_s;
				endcase
		default: ;
	endcase
end

assign cram_do = cram_do_r;

/////////////////////////////  RTC  ///////////////////////////////


wire        RTC_timestampNew = RTC_time[32];
wire [31:0] RTC_timestampIn  = RTC_time[31:0];

reg [31:0] RTC_timestampSaved;
reg [31:0] RTC_savedtimeIn;
reg        RTC_saveLoaded;
reg        RTC_timestampNew_1;

// Seconds the clock still has to catch up after a save was loaded.
reg [31:0] diffSeconds = 0;

localparam [31:0] SECONDS_PER_DAY  = 32'd86400;
localparam [31:0] SECONDS_PER_WEEK = 32'd604800;

wire catchup_week = (diffSeconds >= SECONDS_PER_WEEK);
wire catchup_day  = ~catchup_week & (diffSeconds >= SECONDS_PER_DAY);
wire catchup_sec  = ~catchup_week & ~catchup_day & (diffSeconds != 0);

// The prescaler pauses during the catch-up (a few milliseconds at most), so a
// real second never coincides with a catch-up step.
wire catching_up  = (diffSeconds != 0);
wire second_tick  = ce_32k & (&rtc_subseconds) & rtc_running & ~catching_up;

always @(posedge clk_sys) begin
	RTC_savedtimeOut <= { 18'd0, rtc_running, rtc_overflow, rtc_weeks, rtc_weekday,
	                      rtc_hours, rtc_minutes, rtc_seconds };

	// host timestamp: taken from the Pocket when it arrives, then counted here
	if (ce_32k) begin
		stamp_subseconds <= stamp_subseconds + 1'd1;
		if (&stamp_subseconds) RTC_timestampOut <= RTC_timestampOut + 1'd1;
	end
	RTC_timestampNew_1 <= RTC_timestampNew;
	if (RTC_timestampNew != RTC_timestampNew_1) begin
		RTC_timestampOut <= RTC_timestampIn;
	end

	// load the save file tail into an intermediate register
	RTC_saveLoaded <= 1'b0;
	if (bk_rtc_wr & enable) begin
		case (bk_addr[7:0])
			0: RTC_timestampSaved[15:0]  <= bk_data;
			1: RTC_timestampSaved[31:16] <= bk_data;
			2: RTC_savedtimeIn[15:0]     <= bk_data;
			3: RTC_savedtimeIn[31:16]    <= bk_data;
			4: RTC_saveLoaded            <= 1'b1;
		endcase
	end

	if (ce_32k & rtc_running & ~catching_up) rtc_subseconds <= rtc_subseconds + 1'd1;

	if (~enable) begin
		// no cartridge, or a new one is loading: an unused RTC is stopped
		rtc_seconds    <= 6'd0;
		rtc_minutes    <= 6'd0;
		rtc_hours      <= 5'd0;
		rtc_weekday    <= 3'd0;
		rtc_weeks      <= 8'd0;
		rtc_running    <= 1'b0;
		rtc_overflow   <= 1'b0;
		rtc_subseconds <= 15'd0;
		diffSeconds    <= 32'd0;
	end else if (RTC_saveLoaded) begin
		rtc_seconds    <= RTC_savedtimeIn[5:0];
		rtc_minutes    <= RTC_savedtimeIn[11:6];
		rtc_hours      <= RTC_savedtimeIn[16:12];
		rtc_weekday    <= RTC_savedtimeIn[19:17];
		rtc_weeks      <= RTC_savedtimeIn[27:20];
		rtc_overflow   <= RTC_savedtimeIn[28];
		rtc_running    <= RTC_savedtimeIn[29];
		rtc_subseconds <= 15'd0;
		if (RTC_savedtimeIn[29] && RTC_timestampOut > RTC_timestampSaved)
			diffSeconds <= RTC_timestampOut - RTC_timestampSaved;
		else
			diffSeconds <= 32'd0;
	end else if (cmd_set) begin
		rtc_weeks      <= latch_w;
		rtc_weekday    <= latch_dh[7:5];
		rtc_hours      <= latch_dh[4:0];
		rtc_minutes    <= latch_m[5:0];
		rtc_seconds    <= latch_s[5:0];
		rtc_subseconds <= 15'd0;
		diffSeconds    <= 32'd0;
	end else begin
		if (cmd_stop)      rtc_running  <= 1'b0;
		if (cmd_start)     rtc_running  <= 1'b1;
		if (cmd_clear_ovf) rtc_overflow <= 1'b0;

		if (catchup_week) begin
			diffSeconds <= diffSeconds - SECONDS_PER_WEEK;
			rtc_weeks   <= rtc_weeks + 1'd1;
			if (&rtc_weeks) rtc_overflow <= 1'b1;
		end else begin
			if (catchup_day) diffSeconds <= diffSeconds - SECONDS_PER_DAY;
			if (catchup_sec) diffSeconds <= diffSeconds - 1'd1;

			if (second_tick | catchup_sec) begin
				rtc_seconds <= rtc_seconds + 1'd1;
				if (rtc_seconds == 6'd59) begin
					rtc_seconds <= 6'd0;
					rtc_minutes <= rtc_minutes + 1'd1;
					if (rtc_minutes == 6'd59) begin
						rtc_minutes <= 6'd0;
						rtc_hours   <= rtc_hours + 1'd1;
					end
				end
			end

			if (catchup_day | ((second_tick | catchup_sec) && rtc_seconds == 6'd59
			                   && rtc_minutes == 6'd59 && rtc_hours == 5'd23)) begin
				if (~catchup_day) rtc_hours <= 5'd0;
				rtc_weekday <= rtc_weekday + 1'd1;
				if (rtc_weekday == 3'd6) begin
					rtc_weekday <= 3'd0;
					rtc_weeks   <= rtc_weeks + 1'd1;
					if (&rtc_weeks) rtc_overflow <= 1'b1;
				end
			end
		end
	end

	// latch registers: copied from the clock by MR3 = 10, written through A000-BFFF
	if (cmd_latch) begin
		latch_w  <= rtc_weeks;
		latch_dh <= { rtc_weekday, rtc_hours };
		latch_m  <= { 2'b00, rtc_minutes };
		latch_s  <= { 2'b00, rtc_seconds };
	end else if (latch_wr) begin
		case (cart_addr[1:0])
			2'd0: latch_w  <= cart_di;
			2'd1: latch_dh <= cart_di;
			2'd2: latch_m  <= cart_di;
			2'd3: latch_s  <= cart_di;
		endcase
	end

	if (savestate_load & enable) begin
		{ latch_w, latch_dh, latch_m, latch_s } <= savestate_data2[63:32];
	end
end

endmodule
