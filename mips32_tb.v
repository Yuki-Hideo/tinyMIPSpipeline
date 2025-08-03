//-------------------------------------------------------
// mips32_tb.v - tinyMIPSパイプライン版テストベンチ
// パイプライン化されたMIPS32プロセッサのテスト環境
//-------------------------------------------------------

module mips32_tb();
  reg         clk;
  reg         reset;
  wire [31:0] writedata, dataadr;
  wire        memwrite;
  
  // DUTインスタンス化
  top dut(clk, reset, writedata, dataadr, memwrite);
  
  // クロック生成 (10ns周期)
  initial clk = 0;
  always #5 clk = ~clk;
  
  // リセットシーケンス
  initial begin
    $display("=== MIPS32 Pipeline Processor Test ===");
    reset = 1;
    #25;
    reset = 0;
    $display("Reset released at time %t", $time);
  end
  
  // 実行監視
  always @(negedge clk) begin
    if (memwrite) begin
      $display("Memory Write: addr=%h, data=%h at time %t", dataadr, writedata, $time);
      
      // テスト成功条件 (フィボナッチなどの結果確認)
      if (dataadr === 32'h54 && writedata === 32'h7) begin
        $display("*** Test PASSED: Expected result found ***");
        #20;
        $finish;
      end
      // テスト失敗条件
      else if (dataadr > 32'h100) begin
        $display("*** Test FAILED: Unexpected memory access ***");
        #20;
        $finish;
      end
    end
  end
  
  // タイムアウト
  initial begin
    #10000;
    $display("*** Test TIMEOUT ***");
    $finish;
  end
  
  // 波形ダンプ (オプション)
  initial begin
    $dumpfile("mips32_wave.vcd");
    $dumpvars(0, mips32_tb);
  end
endmodule

module top(input         clk, reset, 
           output [31:0] writedata, dataadr, 
           output        memwrite);

  wire [31:0] pc, instr, readdata;
  
  // プロセッサとメモリのインスタンス化
  mips mips_cpu(clk, reset, pc, instr, memwrite, dataadr, writedata, readdata);
  imem instruction_memory(pc[7:2], instr);
  dmem data_memory(clk, memwrite, dataadr, writedata, readdata);

endmodule

// データメモリ (64ワード)
module dmem(input         clk, we,
            input  [31:0] a, wd,
            output [31:0] rd);

  reg  [31:0] RAM[63:0];
  
  // 初期化 (テストデータ設定)
  initial begin
    $readmemh("dmem.dat", RAM);
  end

  assign rd = RAM[a[31:2]]; // ワード境界アクセス

  always @(posedge clk)
    if (we) begin
      RAM[a[31:2]] <= wd;
      $display("DMEM Write: addr=%h, data=%h", a, wd);
    end
endmodule

// 命令メモリ (64ワード)
module imem(input  [5:0]  a,
            output [31:0] rd);

  reg  [31:0] RAM[63:0];

  initial begin
    // テストプログラム読み込み
    $readmemh("test32.dat", RAM);
    $display("Instruction memory loaded from test32.dat");
  end

  assign rd = RAM[a]; // ワード境界アクセス
endmodule