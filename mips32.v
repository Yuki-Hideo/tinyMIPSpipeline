// top, imem, dmem modules removed to avoid conflict with sum32.v testbench


module mips32(
	input clk, reset,
	output [31:0] pcF,
	input [31:0] instrF,
	output memwriteM,
	output [31:0] aluoutM, writedataM,
	input [31:0] readdataM
);
	// F=Fetch, D=Decode, E=Execute, M=Memory, W=Writeback
	wire [5:0] opD, functD;
	wire regdstE, alusrcE, pcsrcD, memtoregE, memtoregM, memtoregW, regwriteE, regwriteM, regwriteW;
	wire [2:0] alucontrolE;
	wire flushE, equalD;

	controller c(
		clk, reset, opD, functD, flushE, equalD,
		memtoregE, memtoregM, memtoregW, memwriteM, pcsrcD, branchD,
		alusrcE, regdstE, regwriteE, regwriteM, regwriteW, jumpE,
		alucontrolE
	);
	
	datapath dp(
		clk, reset, memtoregE, memtoregM, memtoregW, pcsrcD, branchD,
		alusrcE, regdstE, regwriteE, regwriteM, regwriteW, jumpD,
		alucontrolE,
		equalD, pcF, instrF,
		aluoutM, writedataM, readdataM,
		opD, functD, flushE
	);
endmodule


module controller(
	input clk, reset,
	input [5:0] opD, functD,
	input flushE, equalD,
	output	memtoregE, memtoregM, memtoregW, memwriteM,
	output       pcsrcD, branchD, alusrcE,
	output       regdstE, regwriteE, regwriteM, regwriteW,
	output       jumpD,
	output [2:0] alucontrolEoutput	
);
	wire [1:0] aluopD;

	wire	memtoregD, memwriteD, alusrcD,
			regdstD, regwriteD;
	wire [2:0] alucontrolD;
	wire	memwriteE;
	
	maindec md(
		opD, memtoregD, memwriteD, branchD,
		alusrcD, regdstD, regwriteD, jumpD,
		aluopD
	);
	
	aludec	ad(functD, aluopD, alucontrolD);

	assign pcsrcD = branchD & equalD;

	// パイプラインレジスタ
	floprc #(8) regE(
		clk, reset, flushE,
		{memtoregD, memwriteD, alusrcD, regdstD, regwriteD, alucontrolD}, 
		{memtoregE, memwriteE, alusrcE, regdstE, regwriteE,  alucontrolE}
	);
	flopr #(3) regM(
		clk, reset, 
		{memtoregE, memwriteE, regwriteE},
		{memtoregM, memwriteM, regwriteM}
	);
	flopr #(2) regW(
		clk, reset,
		{memtoregM, regwriteM}, 
		{memtoregW, regwriteW}
	);
endmodule

module maindec(
	input	[5:0] op,
	output	memtoreg, memwrite,
	output	branch, alusrc,
	output	regdst, regwrite,
	output	jump,
	output	[1:0] aluop
);
	reg [9:0] controls;
	
	// 制御信号をセット
	assign {
		regwrite, regdst, alusrc,
		branch, memwrite,
		memtoreg, jump, aluop
	} = controls;

	// 分岐命令やロード命令などをデコード
	always @(*) begin
		case(op)
			6'b000000: controls <= 9'b110000010; //Rtyp
			6'b100011: controls <= 9'b101001000; //LW
			6'b101011: controls <= 9'b001010000; //SW
			6'b000100: controls <= 9'b000100001; //BEQ
			6'b001000: controls <= 9'b101000000; //ADDI
			6'b000010: controls <= 9'b000000100; //J
			default:   controls <= 9'bxxxxxxxxx; //???
		endcase
	end
endmodule
		
module aludec(
	input	[5:0] funct,
	input	[1:0] aluop,
	output reg	[2:0] alucontrol
);
	// ALUで行う演算命令をデコード
	always @(*) begin
		case(aluop)
		2'b00: alucontrol <= 3'b010;  // add
		2'b01: alucontrol <= 3'b110;  // sub
		default: case(funct)          // RTYPE
			6'b100000: alucontrol <= 3'b010; // ADD
			6'b100010: alucontrol <= 3'b110; // SUB
			6'b100100: alucontrol <= 3'b000; // AND
			6'b100101: alucontrol <= 3'b001; // OR
			6'b101010: alucontrol <= 3'b111; // SLT
			default:   alucontrol <= 3'bxxx; // ???
			endcase
		endcase
	end
endmodule
	

module datapath(
	input         clk, reset,
	input         memtoregE, memtoregM, memtoregW, 
	input         pcsrcD, branchD,
	input         alusrcE, regdstE,
	input         regwriteE, regwriteM, regwriteW, 
	input         jumpD,
	input  [2:0]  alucontrolE,
	output        equalD,
	output [31:0] pcF,
	input  [31:0] instrF,
	output [31:0] aluoutM, writedataM,
	input  [31:0] readdataM,
	output [5:0]  opD, functD,
	output        flushE
);
	// フォワーディング信号とレジスタ番号、ストール制御信号
	wire        forwardaD, forwardbD;
	wire [1:0]  forwardaE, forwardbE;
	wire        stallF;
	wire [4:0]  rsD, rtD, rdD, rsE, rtE, rdE;
	wire [4:0]  writeregE, writeregM, writeregW;
	wire        flushD;
	// パイプラインの 各ステージの データ信号
	wire [31:0] pcnextFD, pcnextbrFD, pcplus4F, pcbranchD;
	wire [31:0] signimmD, signimmE, signimmshD;
	wire [31:0] srcaD, srca2D, srcaE, srca2E;
	wire [31:0] srcbD, srcb2D, srcbE, srcb2E, srcb3E;
	wire [31:0] pcplus4D, instrD;
	wire [31:0] aluoutE, aluoutW;
	wire [31:0] readdataW, resultW;

	// ハザード検知
	hazard h(
		rsD, rtD, rsE, rtE, writeregE, writeregM, writeregW, 
		regwriteE, regwriteM, regwriteW, 
		memtoregE, memtoregM, branchD,
		forwardaD, forwardbD, forwardaE, forwardbE,
		stallF, stallD, flushE
	);

	// PC更新の選択（PC+4 / 分岐先 / ジャンプ先  のいずれかから選択)
	mux2 #(32) pcbrmux(pcplus4F, pcbranchD, pcsrcD, pcnextbrFD);
	// ジャンプ先アドレス（PC上位４ビット＋命令の下位２６ビット＋00）
	mux2 #(32) pcmux(
		pcnextbrFD,{pcplus4D[31:28], instrD[25:0], 2'b00}, 
        jumpD, pcnextFD
	);

	// レジスタファイル（readポート２つ、writeポート１つ）
	regfile rf(
		clk, regwriteW, rsD, rtD, writeregW,
		resultW, srcaD, srcbD
	);

	// Fetchステージ
	flopenr #(32) pcreg(clk, reset, ~stallF, pcnextFD, pcF);
  	adder       pcadd1(pcF, 32'b100, pcplus4F);

	// Decodeステージ
	flopenr #(32) r1D(clk, reset, ~stallD, pcplus4F, pcplus4D);
	flopenrc #(32) r2D(clk, reset, ~stallD, flushD, instrF, instrD);
	signext     se(instrD[15:0], signimmD);
	sl2         immsh(signimmD, signimmshD);
	adder       pcadd2(pcplus4D, signimmshD, pcbranchD);
	mux2 #(32)  forwardadmux(srcaD, aluoutM, forwardaD, srca2D);
	mux2 #(32)  forwardbdmux(srcbD, aluoutM, forwardbD, srcb2D);
	eqcmp       comp(srca2D, srcb2D, equalD);

		// 命令のデコード
	assign opD = instrD[31:26];
	assign functD = instrD[5:0];
	assign rsD = instrD[25:21];
	assign rtD = instrD[20:16];
	assign rdD = instrD[15:11];

	assign flushD = pcsrcD | jumpD;

	// Execute-ステージ
	floprc #(32) r1E(clk, reset, flushE, srcaD, srcaE);
	floprc #(32) r2E(clk, reset, flushE, srcbD, srcbE);
	floprc #(32) r3E(clk, reset, flushE, signimmD, signimmE);
	floprc #(5)  r4E(clk, reset, flushE, rsD, rsE);
	floprc #(5)  r5E(clk, reset, flushE, rtD, rtE);
	floprc #(5)  r6E(clk, reset, flushE, rdD, rdE);
	mux3 #(32)  forwardaemux(srcaE, resultW, aluoutM, forwardaE, srca2E);
	mux3 #(32)  forwardbemux(srcbE, resultW, aluoutM, forwardbE, srcb2E);
		// ALUの第２oオペラんdの選択
	mux2 #(32)  srcbmux(srcb2E, signimmE, alusrcE, srcb3E);
		// 演算の 実行
	alu         alu(srca2E, srcb3E, alucontrolE, aluoutE);
		// 書き込みレジスタの選択
	mux2 #(5)   wrmux(rtE, rdE, regdstE, writeregE);

	// Memoryステージ
	flopr #(32) r1M(clk, reset, srcb2E, writedataM);
	flopr #(32) r2M(clk, reset, aluoutE, aluoutM);
	flopr #(32) r3M(clk, reset, writeregE, writeregM);

	// Writebackステージ
	flopr #(32) r1W(clk, reset, aluoutM, aluoutW);
	flopr #(32) r2W(clk, reset, readdataM, readdataW);
	flopr #(5)  r3W(clk, reset, writeregM, writeregW);
		// レジスタに書き込む データの選択
	mux2 #(32)  resmux(aluoutW, readdataW, memtoregW, resultW);
endmodule

module hazard(
	input  [4:0] rsD, rtD, rsE, rtE, 
	input  [4:0] writeregE, writeregM, writeregW,
	input        regwriteE, regwriteM, regwriteW,
	input        memtoregE, memtoregM, branchD,
	output           forwardaD, forwardbD,
	output reg [1:0] forwardaE, forwardbE,
	output       stallF, stallD, flushE
);
	wire lwstallD, branchstallD;
	
	// Decodeステージのフォワーディング検出
	assign forwardaD = (rsD != 0 & rsD == writeregM & regwriteM);
	assign forwardbD = (rtD != 0 & rtD == writeregM & regwriteM);

	// Executeステージのフォw−ディング制御
	always @(*) begin
		forwardaE = 2'b00; forwardbE = 2'b00;
		if (rsE != 0)
			if (rsE == writeregM & regwriteM) forwardaE = 2'b10;
			else if (rsE == writeregW & regwriteW) forwardaE = 2'b01;
		if (rtE != 0)
			if (rtE == writeregM & regwriteM) forwardbE = 2'b10;
			else if (rtE == writeregW & regwriteW) forwardbE = 2'b01;
	end

	// ストール
	assign #1 lwstallD = memtoregE & (rtE == rsD | rtE == rtD);
	assign #1 branchstallD = branchD & (
		regwriteE & (writeregE == rsD | writeregE == rtD) | 
		memtoregM & (writeregM == rsD | writeregM == rtD)
	);

	assign #1 stallD = lwstallD | branchstallD;
	assign #1 stallF = stallD; // Dでのストールはそれ以前のステージにもストールを起こす
	assign #1 flushE = stallD; // Dでのストールが起きたら次のステージをフラッシュする


endmodule


module alu(
	input	[31:0] a, b,
	input	[2:0] alucont,
	output reg [31:0] result
);
	wire [31:0] b2, sum, slt;

	// 減算のaときは補数をとる
	assign #1 b2 = alucont[2] ? ~b : b;
	assign #1 sum = a + b2 + alucont[2];
	// slt命令用の符号ビットを抽出
	assign #1 slt = sum[31];

	// 制御信号に応じて演算
	always@(*) begin
		case(alucont[1:0])
			2'b00: result <= #1 a & b;
			2'b01: result <= #1 a | b;
			2'b10: result <= #1 sum;
			2'b11: result <= #1 slt;
		endcase
	end
endmodule
	

module regfile(
	input	clk, 
	input	we3,
	// 3ポート(readポート２つ、writeポート１つ)
	input	[4:0]	ra1, ra2, wa3,
	input	[31:0]	wd3,
	output	[31:0]	rd1, rd2
);
	// 32個の３２ビットレジスタ配列
	reg [31:0] rf[31:0];

	//  クロックのi立ちさがrで書き込み
	always @(negedge clk) begin
		if (we3) rf[wa3] <= wd3;
	end

	// レジスタ０は つねに０
	assign #1 rd1 = (ra1 != 0) ? rf[ra1] : 0;
	assign #1 rd2 = (ra2 != 0) ? rf[ra2] : 0;
endmodule

	

module adder(
	input	[31:0] a, b,
	output	[31:0] y
);
	assign #1 y = a + b;
endmodule

module eqcmp(
	input	[31:0] a, b,
	output	eq
);
	assign #1 eq = (a == b);
endmodule

module sl2(
	input	[31:0] a,
	output	[31:0] y
);
	// ２ビット左シフト
	assign #1 y = {a[29:0], 2'b00};
endmodule

module signext(
	input	[15:0] a,
	output	[31:0] y
);
	// 符号拡張
	assign #1 y = {{16{a[15]}}, a};
endmodule


// フリップフロップ

// 基本的なフリップフロップ
module flopr #(parameter WIDTH = 8) (
	input	clk, reset,
	input	[WIDTH-1:0] d,
	output reg	[WIDTH-1:0] q
);
	always @(posedge clk, posedge reset) begin
		if (reset) q <= #1 0; // reset信号で０にクリア
		else	q <= #1 d;
	end
endmodule	

module floprc #(parameter WIDTH = 8)
              (input                  clk, reset, clear,
               input      [WIDTH-1:0] d, 
               output reg [WIDTH-1:0] q);

  always @(posedge clk, posedge reset)
    if (reset)      q <= #1 0;
    else if (clear) q <= #1 0;
    else            q <= #1 d;
endmodule

//　イネーブル付きフリップフロップ
module flopenr #(parameter WIDTH = 8)(
	input                  clk, reset,
	input                  en,
	input      [WIDTH-1:0] d, 
	output reg [WIDTH-1:0] q
);
	always @(posedge clk, posedge reset) begin
		if (reset) q <= #1 0;
		else if (en) q <= #1 d;
	end
endmodule

//　クリア 機能付きフリップフロップ
module flopenrc #(parameter WIDTH = 8)(
	input                  clk, reset,
	input                  en, clear,
	input      [WIDTH-1:0] d, 
	output reg [WIDTH-1:0] q
);
	always @(posedge clk, posedge reset) begin
		if (reset) q <= #1 0;
		else if (clear) q <= #1 0;
		else if (en) q <= #1 d;
	end
endmodule


// マルチプレクサ

// ２入力
module mux2 #(parameter WIDTH = 8) (
	input	[WIDTH-1:0] d0, d1,
	input	s,
	output	[WIDTH-1:0] y
);
	assign #1 y = s ? d1 : d0;
endmodule
	
// 3入力
module mux3 #(parameter WIDTH = 8) (
	input	[WIDTH-1:0] d0, d1, d2,
	input	[1:0] s,
	output	[WIDTH-1:0] y
);
	assign #1 y = s[1] ? d2 : (s[0] ? d1 : d0);
endmodule