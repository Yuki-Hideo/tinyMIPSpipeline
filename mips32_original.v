//-------------------------------------------------------
// mips32.v - Fixed version
// パイプライン化されたMIPS32プロセッサの修正版
//-------------------------------------------------------

module mips32 #(parameter WIDTH = 32, REGBITS = 3) (
	input			clk, reset,
	input [WIDTH-1:0] 	memdata,
	output			memread, memwrite,
	output [WIDTH-1:0] 	adr, writedata
);
wire [31:0]	instr;
wire		zero, alusrca, memtoreg, iord, pcen, regwrite, regdst;
wire [1:0]	aluop, pcsource, alusrcb;
wire [3:0]	irwrite;
wire [2:0]	alucont;
wire		memwrite_internal;
controller cont(clk, reset, instr[31:26], zero, memread, memwrite_internal,
			   alusrca, memtoreg, iord, pcen, regwrite, regdst,
			   pcsource, alusrcb, aluop, irwrite);
alucontrol ac(aluop, instr[5:0], alucont);
datapath #(WIDTH, REGBITS) dp(clk, reset, memdata, alusrca, memtoreg,
			   iord, pcen, regwrite, regdst, pcsource, alusrcb,
			   irwrite, alucont, zero, instr, adr, writedata, memwrite_internal, memwrite);
endmodule

/* simplified controller for pipelined processor */
module controller (
	input			clk, reset,
	input [5:0]		op,
	input			zero,
	output reg		memread, memwrite, alusrca, memtoreg, iord,
	output			pcen,
	output reg		regwrite, regdst,
	output reg [1:0]	pcsource, alusrcb, aluop,
	output reg [3:0]	irwrite
);

// パイプライン用の簡略化されたコントローラー
// 常にPC更新を有効にし、命令フェッチを継続
assign pcen = 1'b1;

// 制御信号は命令の種類に応じて設定
always @(*) begin
	// デフォルト値
	memread = 1'b1;    // 常に命令フェッチ
	memwrite = 1'b0;
	alusrca = 1'b0;
	memtoreg = 1'b0;
	iord = 1'b0;       // 命令フェッチ用
	regwrite = 1'b0;
	regdst = 1'b0;
	pcsource = 2'b00;  // PC+4
	alusrcb = 2'b01;   // +4 for PC increment
	aluop = 2'b00;
	irwrite = 4'b1111; // 命令レジスタ更新
	
	// 命令に応じた制御信号（簡略化）
	case (op)
		6'b000000: begin // R-type
			regwrite = 1'b1;
			regdst = 1'b1;
			aluop = 2'b10;
		end
		6'b001000: begin // ADDI
			regwrite = 1'b1;
			alusrcb = 2'b10;
		end
		6'b100011: begin // LW
			regwrite = 1'b1;
			memtoreg = 1'b1;
			alusrcb = 2'b10;
		end
		6'b101011: begin // SW
			memwrite = 1'b1;
			alusrcb = 2'b10;
		end
		6'b000100: begin // BEQ
			aluop = 2'b01;
			pcsource = zero ? 2'b01 : 2'b00;
		end
		6'b000010: begin // J
			pcsource = 2'b10;
		end
	endcase
end
endmodule

/* alucontrol */
module alucontrol (
	input [1:0]		aluop,
	input [5:0]		funct,
	output reg [2:0]	alucont
);
always @(*)
	case (aluop)
		2'b00:	alucont <= 3'b010; // add for lb/sb/addi
		2'b01:	alucont <= 3'b110; // sub (for beq)
		default: case (funct) // R-Type instructions
			6'b100000: alucont <= 3'b010; // add
			6'b100010: alucont <= 3'b110; // subtract
			6'b100100: alucont <= 3'b000; // logical and
			6'b100101: alucont <= 3'b001; // logical or
			6'b101010: alucont <= 3'b111; // set on less
			default:   alucont <= 3'b010; // default to add
		endcase
	endcase
endmodule

/* simplified datapath */
module datapath #(parameter WIDTH = 32, REGBITS = 3) (
input			clk, reset,
input [WIDTH-1:0]	memdata,
input			alusrca, memtoreg, iord, pcen, regwrite, regdst,
input [1:0]		pcsource, alusrcb,
input [3:0]		irwrite,
input [2:0]		alucont,
output			zero,
output [31:0]		instr,
output [WIDTH-1:0]	adr, writedata,
input			memwrite_internal,
output			memwrite
);

parameter CONST_FOUR = 32'h4;

// PC register and next PC logic
wire [WIDTH-1:0] pc, nextpc, pcplus4, pcbranch, pcjump;
flopenr #(WIDTH) pcreg(clk, reset, pcen, nextpc, pc);

// PC+4 calculation
assign pcplus4 = pc + CONST_FOUR;

// Branch target calculation
wire [WIDTH-1:0] signext;
assign signext = {{16{instr[15]}}, instr[15:0]};
assign pcbranch = pcplus4 + (signext << 2);

// Jump target calculation
assign pcjump = {pcplus4[31:28], instr[25:0], 2'b00};

// Next PC mux
mux4 #(WIDTH) pcmux(pcplus4, pcbranch, pcjump, 32'b0, pcsource, nextpc);

// Address mux (PC for instruction fetch, ALU result for data)
mux2 #(WIDTH) adrmux(pc, aluout, iord, adr);

// Instruction register
reg [31:0] instreg;
always @(posedge clk) begin
	if (reset)
		instreg <= 32'b0;
	else if (irwrite[0])
		instreg <= memdata;
end
assign instr = instreg;

// Register file
wire [REGBITS-1:0] ra1, ra2, wa;
wire [WIDTH-1:0] wd, rd1, rd2;
assign ra1 = instr[25:21];
assign ra2 = instr[20:16];
mux2 #(REGBITS) wamux(instr[20:16], instr[15:11], regdst, wa);
mux2 #(WIDTH) wdmux(aluout, memdata, memtoreg, wd);
regfile #(WIDTH,REGBITS) rf(clk, regwrite, ra1, ra2, wa, wd, rd1, rd2);

// ALU
wire [WIDTH-1:0] srca, srcb, aluout;
mux2 #(WIDTH) srcamux(pc, rd1, alusrca, srca);
mux4 #(WIDTH) srcbmux(rd2, CONST_FOUR, signext, {signext[29:0], 2'b00}, alusrcb, srcb);
alu #(WIDTH) alunit(srca, srcb, alucont, aluout);
assign zero = (aluout == 32'b0);

// Output assignments
assign writedata = rd2;
assign memwrite = memwrite_internal;
endmodule

/* alu */
module alu #(parameter WIDTH = 32) (
	input [WIDTH-1:0]	a, b,
	input [2:0]		alucont,
	output reg [WIDTH-1:0]	result
);
wire [WIDTH-1:0]	b2, sum, slt;
assign b2 = alucont[2] ? ~b : b; 
assign sum = a + b2 + alucont[2];
assign slt = {31'b0, sum[WIDTH-1]};
always @(*)
	case (alucont[1:0])
		2'b00:	result <= a & b;
		2'b01:	result <= a | b;
		2'b10:	result <= sum;
		2'b11:	result <= slt;
	endcase
endmodule

/* regfile */
module regfile #(parameter WIDTH = 32, REGBITS = 3) (
	input			clk,
	input			regwrite,
	input [REGBITS-1:0]	ra1, ra2, wa,
	input [WIDTH-1:0]	wd,
	output [WIDTH-1:0]	rd1, rd2
);
reg [WIDTH-1:0] RAM [(1<<REGBITS)-1:0];

// Initialize register file
integer i;
initial begin
	for (i = 0; i < (1<<REGBITS); i = i + 1)
		RAM[i] = 32'b0;
end

always @(posedge clk)
	if (regwrite) RAM[wa] <= wd;
assign rd1 = (ra1 != 0) ? RAM[ra1] : 32'b0;
assign rd2 = (ra2 != 0) ? RAM[ra2] : 32'b0;
endmodule

/* flopen */
module flopen #(parameter WIDTH = 32) (
	input			clk, en,
	input [WIDTH-1:0]	d,
	output reg [WIDTH-1:0]	q
);
always @(posedge clk)
	if (en) q <= d;
endmodule

/* flopenr */
module flopenr #(parameter WIDTH = 32) (
	input			clk, reset, en,
	input [WIDTH-1:0]	d,
	output reg [WIDTH-1:0]	q
);
always @(posedge clk)
	if (reset) q <= 32'b0;
	else if (en) q <= d;
endmodule

/* mux2 */
module mux2 #(parameter WIDTH = 32) (
	input [WIDTH-1:0]	d0, d1,
	input			s,
	output [WIDTH-1:0]	y
);
assign y = s ? d1 : d0;
endmodule

/* mux4 */
module mux4 #(parameter WIDTH = 32) (
	input [WIDTH-1:0]	d0, d1, d2, d3,
	input [1:0]		s,
	output reg [WIDTH-1:0] 	y
);
always @(*)
	case (s)
		2'b00:	y <= d0;
		2'b01:	y <= d1;
		2'b10:	y <= d2;
		2'b11:	y <= d3;
	endcase
endmodule