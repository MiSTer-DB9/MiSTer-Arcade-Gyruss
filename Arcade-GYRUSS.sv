//=========================================================
//  Arcade: Gyruss  for MiSTer
//
//                          Copyright (c) 2020 MiSTer-X
//=========================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output		  VGA_F1,
	
	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	output	USER_OSD,
	output	USER_MODE,
	input	[7:0] USER_IN,
	output	[7:0] USER_OUT
);

assign VGA_F1    = 0;
//assign USER_OUT  = '1;

wire   joy_split, joy_mdsel;
wire   [5:0] joy_in = {USER_IN[6],USER_IN[3],USER_IN[5],USER_IN[7],USER_IN[1],USER_IN[2]};
assign USER_OUT  = |status[31:30] ? {3'b111,joy_split,3'b111,joy_mdsel} : '1;
assign USER_MODE = |status[31:30] ;
assign USER_OSD  = joydb9md_1[7] & joydb9md_1[5]; // A�adir esto para OSD


assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

wire   screen_H = status[6]|direct_video;
assign HDMI_ARX = status[1] ? 8'd16 : screen_H ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : screen_H ? 8'd3 : 8'd4;

`include "build_id.v" 

localparam CONF_STR = {
	"A.GYRUSS;;",
	"-;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"H0O6,Orientation,Vert,Horz;",
	"-;",
	"OUV,Serial SNAC DB9MD,Off,1 Player,2 Players;",
	"-;",
	"DIP;",
	"-;",
	"OOS,Analog Video H-Pos,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31;",
	"OTV,Analog Video V-Pos,0,1,2,3,4,5,6,7;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Start 1P,Start 2P,Coin;",
	"jn,A,Start,Select,L;",
	"V,v",`BUILD_DATE
};

wire [4:0] HOFFS = status[28:24];
wire [2:0] VOFFS = status[31:29];


////////////////////   CLOCKS   ///////////////////

wire clk_48M,sndclk;
wire clk_hdmi = clk_48M;
wire clk_sys  = clk_48M;

pll pll
(
	.rst(0),
	.refclk(CLK_50M),
	.outclk_0(clk_48M),
	.outclk_1(sndclk)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire		direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire  [7:0]	ioctl_index;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;
wire [15:0] joystk1_USB, joystk2_USB;
wire [15:0] joystick_analog_0;
wire [15:0] joystick_analog_1;

wire [21:0]	gamma_bus;

wire [15:0] joystk1 = |status[31:30] ? {
	joydb9md_1[8] | (joydb9md_1[7] & joydb9md_1[4]),// Coin -> 10 *  Mode or Start + B
	joydb9md_1[11],// _start_2	-> 9 * Z (dummy)
	joydb9md_1[7], // _start_1	-> 8 * Start
	joydb9md_1[6], // btn_fireA	-> 4 * A
	joydb9md_1[3], // btn_up	-> 3 * U
	joydb9md_1[2], // btn_down	-> 2 * D
	joydb9md_1[1], // btn_left	-> 1 * L
	joydb9md_1[0], // btn_righ	-> 0 * R 
	} 
	: joystk1_USB;

wire [15:0] joystk2 =  status[31]    ? {
	joydb9md_2[8] | (joydb9md_2[7] & joydb9md_2[4]),// Coin -> 10 *  Mode or Start + B
	joydb9md_2[7], // _start_2	-> 9 * Start
	joydb9md_2[11],// _start_1	-> 8 (dummy)
	joydb9md_2[6], // btn_fireA	-> 4 * A
	joydb9md_2[3], // btn_up	-> 3 * U
	joydb9md_2[2], // btn_down	-> 2 * D
	joydb9md_2[1], // btn_left	-> 1 * L
	joydb9md_2[0], // btn_right	-> 0 * R 
	} 
	: status[30] ? joystk1_USB : joystk2_USB;


reg [15:0] joydb9md_1,joydb9md_2;
joy_db9md joy_db9md
(
  .clk       ( clk_sys    ), //35-50MHz
  .joy_split ( joy_split  ),
  .joy_mdsel ( joy_mdsel  ),
  .joy_in    ( joy_in     ),
  .joystick1 ( joydb9md_1 ),
  .joystick2 ( joydb9md_2 )	  
);


hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),


	.buttons(buttons),

	.status(status),
	.status_menumask({15'h0,direct_video}),
	
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joystk1_USB),
	.joystick_1(joystk2_USB),
	.joystick_analog_0(joystick_analog_0),
	.joystick_analog_1(joystick_analog_1),	
	.joy_raw({joydb9md_1[4],joydb9md_1[6],joydb9md_1[3:0]}),
	.ps2_key(ps2_key)
);

reg [7:0] DSW[8];
always @(posedge clk_sys) begin
	if (ioctl_wr) begin
		if ((ioctl_index==254) && !ioctl_addr[24:3]) DSW[ioctl_addr[2:0]] <= ioctl_dout;
	end
end

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_trig1       <= pressed; // space
			'h005: btn_one_player  <= pressed; // F1
			'h006: btn_two_players <= pressed; // F2

			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_trig1_2     <= pressed; // A
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_trig1 = 0;
reg btn_one_player  = 0;
reg btn_two_players = 0;

reg btn_start_1 = 0;
reg btn_start_2 = 0;
reg btn_coin_1  = 0;
reg btn_coin_2  = 0;
reg btn_up_2    = 0;
reg btn_down_2  = 0;
reg btn_left_2  = 0;
reg btn_right_2 = 0;
reg btn_trig1_2 = 0;


wire m_up2     = btn_up_2    | joystk2[3];
wire m_down2   = btn_down_2  | joystk2[2];
wire m_left2   = btn_left_2  | joystk2[1];
wire m_right2  = btn_right_2 | joystk2[0];
wire m_trig21  = btn_trig1_2 | joystk2[4];

wire m_start1  = btn_one_player  | joystk1[5] | joystk2[5] | btn_start_1;
wire m_start2  = btn_two_players | joystk1[6] | joystk2[6] | btn_start_2;

wire m_up1     = btn_up      | joystk1[3];
wire m_down1   = btn_down    | joystk1[2];
wire m_left1   = btn_left    | joystk1[1];
wire m_right1  = btn_right   | joystk1[0];
wire m_trig11  = btn_trig1   | joystk1[4];

wire m_coin1   = btn_one_player | btn_coin_1 | joystk1[7];
wire m_coin2   = btn_two_players| btn_coin_2 | joystk2[7];
wire m_coin    = (m_coin1|m_coin2);


///////////////////////////////////////////////////

wire hblank, vblank;
wire ce_vid;
wire hs, vs;
wire [2:0] r,g;
wire [1:0] b;

reg ce_pix;
always @(posedge clk_hdmi) begin
	reg old_clk;
	old_clk <= ce_vid;
	ce_pix  <= old_clk & ~ce_vid;
end

arcade_rotate_fx #(257,224,8) videoV
(
	.*,

	.clk_video(clk_hdmi),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(~hs),
	.VSync(~vs),

	.fx(status[5:3]),
	.no_rotate(screen_H),
);

wire			PCLK;
wire  [8:0] HPOS,VPOS;
wire  [7:0] POUT;
HVGEN hvgen
(
	.HPOS(HPOS),.VPOS(VPOS),.PCLK(PCLK),.iRGB(POUT),
	.oRGB({b,g,r}),.HBLK(hblank),.VBLK(vblank),.HSYN(hs),.VSYN(vs),
	.HOFFS(HOFFS),.VOFFS(VOFFS)
);
assign ce_vid = PCLK;

assign AUDIO_S = 0; // unsigned PCM

///////////////////////////////////////////////////

wire iRST = RESET | status[0] | buttons[1];

wire [7:0] INP0 = ~{3'b000,m_start2,m_start1,2'b00,m_coin};
wire [7:0] INP1 = ~{3'b000,m_trig11,m_down1,m_up1,m_right1,m_left1};
wire [7:0] INP2 = ~{3'b000,m_trig21,m_down2,m_up2,m_right2,m_left2};

wire [7:0] DSW0 = ~DSW[0];
wire [7:0] DSW1 = ~DSW[1];
wire [7:0] DSW2 = ~DSW[2];

FPGA_GYRUSS core
(
	.MCLK(clk_48M),.SCLK(sndclk),.RESET(iRST),
	.INP0(INP0),.INP1(INP1),.INP2(INP2),
	.DSW0(DSW0),.DSW1(DSW1),.DSW2(DSW2),
	.PH(HPOS),.PV(VPOS),.PCLK(PCLK),.POUT(POUT),
	.SND_L(AUDIO_L),.SND_R(AUDIO_R),
	
	.ROMCL(clk_sys),.ROMAD(ioctl_addr[16:0]),.ROMDT(ioctl_dout),.ROMEN(ioctl_wr && ioctl_index==0)
);

endmodule

