//-------------------------------------------------------
// test.v
// Max Yi (byyi@hmc.edu) and David_Harris@hmc.edu 12/9/03
// Model of subset of MIPS processor described in Ch 1
//
// Matsutani: SDF annotation is added
// Matsutani: datapath width is changed to 32-bit
//-------------------------------------------------------
`timescale 1ns/10ps

/* top level design for testing */
// Modified by Matsutani
//module top #(parameter WIDTH = 8, REGBITS = 3) ();
module top #(parameter WIDTH = 32, REGBITS = 3) ();
reg			clk;
reg			reset;
wire			memread, memwrite;
wire [WIDTH-1:0]	adr, writedata, memdata;
wire [31:0] pc, instr;
// 10nsec --> 100MHz
parameter STEP = 10.0;
integer cycles;
// instantiate devices to be tested - パイプライン版mips32に対応
mips32 dut(clk, reset, pc, instr, memwrite, adr, writedata, memdata);
// 命令メモリとデータメモリを分離
imem imem(pc[7:2], instr);
dmem dmem(clk, memwrite, adr, writedata, memdata);
// initialize test
initial begin
`ifdef __POST_PR__
	$sdf_annotate("mips32.sdf", top.dut, , "sdf.log", "MAXIMUM");
`endif
	// dump waveform
	$dumpfile("dump.vcd");
	$dumpvars(0, top.dut);
	// reset
	clk <= 0; reset <= 1; cycles = 0; # 22; reset <= 0;
	// stop at 1,000 cycles
	#(STEP*1000);
	$display("Simulation failed (timeout)");
	$display("Executed cycles: %d", cycles);
	$display("Simulation time: %t", $time);
	$finish;
end
// generate clock to sequence tests
always #(STEP / 2)
	clk <= ~clk;
always @(negedge clk) begin
	cycles = cycles + 1;
	if (memwrite) begin
		$display("Data [%d] is stored in Address [%d]", writedata, adr);
		// Modified by Matsutani
		//if (adr == 5 & writedata == 7)
		if (adr == 252 & writedata == 210)
		//
			$display("Simulation completely successful");
		else
			$display("Simulation failed");
		$display("Executed cycles: %d", cycles);
		$display("Simulation time: %t", $time);
		$finish;
	end
end
endmodule

/* external memory accessed by MIPS */
module imem(
	input [5:0] a,
	output [31:0] rd
);
	reg [31:0] RAM[63:0];

	initial
		begin
			$readmemh("sum32.dat", RAM);
		end

	assign rd = RAM[a]; // 先頭６ビットを読む(オペコード)
endmodule

module dmem(
	input clk, we,
	input [31:0] a, wd,
	output [31:0] rd
);
	reg [31:0] RAM[63:0];
	
	assign rd = RAM[a[31:2]]; // ワードを読み込む(アドレスの上位３０ビットを使用（ワードアラインメント)

	always @(posedge clk) begin
		if (we) begin
			RAM[a[31:2]] <= wd; // クロック立ち上がりでwrite enableのときにワードを書き込む
		end
	end
endmodule
