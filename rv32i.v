`include "def.h"

module rv32i(
  input clk, rst_n,
  input [`DATA_W-1:0] id,
  input [`DATA_W-1:0] md,
  output [`DATA_W-1:0] iaddr, 
  output [`DATA_W-1:0] maddr,
  output [`DATA_W-1:0] wdata,
  output mwe,
  output ecall_op_out
);

  /* Fetch Stage */
  reg [`DATA_W-1:0] pc, idD, pcplus4D;
  wire [`DATA_W-1:0] pcplus4, br_pc;
  wire btaken;
  wire lwstall, brstall, stall;

  assign pcplus4 = pc + 4;
  assign iaddr = pc;

  always @(posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      pc <= 0;
      idD <= 0;
      pcplus4D <= 0;
    end
    else if (btaken & !stall) begin
      pc <= br_pc;
      idD <= `NOP;
      pcplus4D <= 0;
    end
    else if (!stall) begin
      pc <= pcplus4;
      idD <= id;
      pcplus4D <= pcplus4;
    end
  end

  /* Decode Stage */
  reg [`DATA_W-1:0] pcplus4E, reg1E, reg2E, srcbE;
  reg [`REG_W-1:0] rs1E, rs2E, rdE;
  reg [`REG_W-1:0] rs2M, rdM;
  reg [`REG_W-1:0] rdW;
  reg [20:0] imm_uE;
  reg ALUextE, RegWriteE, MemWriteE;
  reg RegWriteM, MemWriteM;
  reg RegWriteW;
  reg [1:0] ResultSrcE;
  reg [2:0] ALUControlE;
  reg ecall_opE;
  reg lw_opE, ALUSrcE;

  wire [2:0] funct3;
  wire [6:0] funct7;
  wire [`REG_W-1:0] rs1, rs2, rd ;
  wire [`DATA_W-1:0] reg1, reg2, srcb, immd, result, reg1f, reg2f;
  wire [`OPCODE_W-1:0] opcode;
  wire [`SHAMT_W-1:0] shamt;
  wire [`OPCODE_W-1:0] func;
  wire [`DATA_W-1:0] br_addr, jr_addr;
  wire [11:0] imm_i, imm_s;
  wire [12:0] imm_b;
  wire [20:0] imm_j, imm_u;

  wire alu_op, imm_op, bra_op;
  wire sw_op, beq_op, bne_op, blt_op, bge_op, bltu_op, bgeu_op, lw_op, jal_op, jalr_op;
  wire slt_op;
  wire lui_op;
  wire ecall_op;
  wire ALUext;
  wire signed [`DATA_W-1:0] sreg1, sreg2;
  wire [19:0] sext;
  wire [`DATA_W-1:0] alures;
  wire RegWrite, ALUSrc, MemWrite, Branch;
  wire [1:0] ImmSrc, ResultSrc, ALUOp;
  wire [2:0] ALUControl;

  reg [1:0] ResultSrcM;
  reg [`DATA_W-1:0] aluresM;


  // Instruction Decorder
  assign {funct7, rs2, rs1, funct3, rd, opcode} = idD;

  // Immidiate Value Generation
  assign imm_i = {funct7,rs2};
  assign imm_s = {funct7,rd};
  assign imm_b = {funct7[6],rd[0],funct7[5:0],rd[4:1],1'b0};
  assign imm_j = {idD[31], idD[19:12],idD[20],idD[30:21],1'b0};
  assign imm_u = idD[31:12];

  assign sreg1 = $signed(reg1f);
  assign sreg2 = $signed(reg2f);
  assign sext = {20{idD[31]}};

  assign alu_op  = (opcode == `OP_ALUR);
  assign imm_op  = (opcode == `OP_ALUI);
  assign sw_op   = (opcode == `OP_STORE) & (funct3 == 3'b010);
  assign lw_op   = (opcode == `OP_LOAD)  & (funct3 == 3'b010);
  assign bra_op  = (opcode == `OP_BRA);
  assign jal_op  = (opcode == `OP_JAL);
  assign lui_op  = (opcode == `OP_LUI);
  assign jalr_op = (opcode == `OP_JALR)& (funct3== 3'b000);
  assign beq_op  = bra_op & (funct3 == 3'b000);
  assign bne_op  = bra_op & (funct3 == 3'b001);
  assign blt_op  = bra_op & (funct3 == 3'b100);
  assign bge_op  = bra_op & (funct3 == 3'b101);
  assign bltu_op = bra_op & (funct3 == 3'b110);
  assign bgeu_op = bra_op & (funct3 == 3'b111);
  assign ecall_op = (opcode == `OP_SPE);


  // Main Decorder
  assign RegWrite  = lw_op | alu_op | imm_op | jal_op | jalr_op | lui_op;
  assign Branch = bra_op;
  assign ImmSrc = lw_op | imm_op | jalr_op ? 2'b00:
	          sw_op ?                    2'b01:
	          Branch ?                   2'b10:
		  jal_op ?                   2'b11:
		                             2'b00;

  assign ALUSrc = lw_op | sw_op | imm_op;
  assign MemWrite = sw_op;
  assign ResultSrc = jal_op | jalr_op ? 2'b00:
	             lui_op           ? 2'b01:
		     lw_op            ? 2'b10:
		                        2'b11;

  assign ALUOp = lw_op | sw_op   ? 2'b00:
	         alu_op | imm_op ? 2'b10:
		 Branch          ? 2'b01:
		                   2'b00;

  // ALU Decorder
  assign {ALUControl,ALUext} = (ALUOp == 2'b00) ? {`ALU_S_ADD, 1'b0}: 
	  		       (ALUOp == 2'b01) ? {`ALU_S_ADD, 1'b0}:
			       (ALUOp == 2'b10) & alu_op ? {funct3, funct7[5]}:
			       (ALUOp == 2'b10) & imm_op ? {funct3, 1'b0}:
			                                   {`ALU_S_ADD, 1'b0};


  // Data Selector
  assign immd = (ImmSrc == 2'b00) ? {sext, imm_i}: 
	        (ImmSrc == 2'b10) ? {sext[18:0],imm_b}: 
                (ImmSrc == 2'b01) ? {sext, imm_s}:
                                    {sext[10:0], imm_j};

  assign srcb = ALUSrc ? immd: reg2;


  // iaddr calculation
  assign reg1f = (rs1 != 0) & (RegWriteM & (rdM == rs1)) ? aluresM: reg1;
  assign reg2f = (rs2 != 0) & (RegWriteM & (rdM == rs2)) ? aluresM: reg2;
  assign br_addr = pc-4 + immd;
  assign jr_addr = reg1 + immd;
  assign btaken = ((beq_op & (reg1f == reg2f))    |
                   (bne_op  & (reg1f != reg2f))   |
                   (blt_op  & (sreg1 < sreg2))    |
                   (bge_op  & (sreg1 >= sreg2))   |
                   (bltu_op & (reg1f < reg2f))    |
                   (bgeu_op & (reg1f >= reg2f)))  |
		   (jal_op)                       |
		   (jalr_op)                      ? 1:
                                                    0;

  assign br_pc = (btaken & !jalr_op)  ? br_addr:
                 (jalr_op)            ? {jr_addr[31:1],1'b0}:
                                      0;

  assign lwstall = lw_opE & ((rdE == rs1) | ((rdE == rs2) & !imm_op & !sw_op)) & !jal_op & !jalr_op;
  assign brstall = bra_op & ((RegWriteE & ((rdE == rs1) | (rdE == rs2))) | 
	                     (RegWriteM & (ResultSrcM == 2'b10) & ((rdM == rs1) | (rdM == rs2))));
  assign stall = lwstall | brstall;

  always @(posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      pcplus4E <= 0;
      reg1E <= 0;
      reg2E <= 0;
      srcbE <= 0;
      rs1E <= 0;
      rs2E <= 0;
      rdE <= 0;
      imm_uE <= 0;
      ALUextE <= 0;
      RegWriteE <= 0;
      MemWriteE <= 0;
      ResultSrcE <= 0;
      ALUControlE <= 0;
      ecall_opE <= 0;
      lw_opE <= 0;
      ALUSrcE <= 0;
    end
    else if (stall) begin
      pcplus4E <= 0;
      reg1E <= 0;
      reg2E <= 0;
      srcbE <= 0;
      rs1E <= 0;
      rs2E <= 0;
      rdE <= 0;
      imm_uE <= 0;
      ALUextE <= 0;
      RegWriteE <= 0;
      MemWriteE <= 0;
      ResultSrcE <= 0;
      ALUControlE <= 0;
      ecall_opE <= 0;
      lw_opE <= 0;
      ALUSrcE <= 0;
    end
    else begin
      pcplus4E <= pcplus4D;
      reg1E <= reg1;
      reg2E <= reg2;
      srcbE <= srcb;
      rs1E <= rs1;
      rs2E <= rs2;
      rdE <= rd;
      imm_uE <= imm_u;
      ALUextE <= ALUext;
      RegWriteE <= RegWrite;
      MemWriteE <= MemWrite;
      ResultSrcE <= ResultSrc;
      ALUControlE <= ALUControl;
      ecall_opE <= ecall_op;
      lw_opE <= lw_op;
      ALUSrcE <= ALUSrc;
    end
  end

  /* Exec Stage */
  reg [`DATA_W-1:0] pcplus4M, reg2M;
  reg [20:0] imm_uM;
  reg ecall_opM;

  wire [`DATA_W-1:0] tmpres, alua, alub; 

  assign tmpres = (ResultSrcM == 2'b00) ? pcplus4M:
                  (ResultSrcM == 2'b01) ? {imm_uM,12'b0}:
                  (ResultSrcM == 2'b10) ? 0:
		                          aluresM;

  assign alua = (RegWriteM & (rdM == rs1E) & (rdM != 0)) ? tmpres:
                (RegWriteW & (rdW == rs1E) & (rdW != 0)) ? result:
		                                           reg1E;
  assign alub = (RegWriteM & !ALUSrcE & (rdM != 0) & (rdM == rs2E)) ? tmpres:
                (RegWriteW & !ALUSrcE & (rdW != 0) & (rdW == rs2E)) ? result:
		                                                      srcbE;

  alu alu_1(.A(alua), .B(alub), .S(ALUControlE), .ext(ALUextE), .Y(alures));

  always @(posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      pcplus4M <= 0;
      reg2M <= 0;
      rs2M <= 0;
      rdM <= 0;
      imm_uM <= 0;
      RegWriteM <= 0;
      MemWriteM <= 0;
      ResultSrcM <= 0;
      ecall_opM <= 0;
      aluresM <= 0;
    end
    else begin
      pcplus4M <= pcplus4E;
      reg2M <= reg2E;
      rs2M <= rs2E;
      rdM <= rdE;
      imm_uM <= imm_uE;
      RegWriteM <= RegWriteE;
      MemWriteM <= MemWriteE;
      ResultSrcM <= ResultSrcE;
      ecall_opM <= ecall_opE;
      aluresM <= alures;
    end
  end

  /* Mem Stage */
  reg [`DATA_W-1:0] pcplus4W;
  reg [20:0] imm_uW;
  reg [1:0] ResultSrcW;
  reg [`DATA_W-1:0] aluresW, mdW;
  reg ecall_opW;

  assign maddr = aluresM;
  assign wdata = (MemWriteM & (rdW == rs2M)) ? result:
	                                       reg2M;
  assign mwe = MemWriteM;

  always @(posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      pcplus4W <= 0;
      rdW <= 0;
      imm_uW <= 0;
      RegWriteW <= 0;
      ResultSrcW <= 0;
      ecall_opW <= 0;
      aluresW <= 0;
      mdW <= 0;
    end
    else begin
      pcplus4W <= pcplus4M;
      rdW <= rdM;
      imm_uW <= imm_uM;
      RegWriteW <= RegWriteM;
      ResultSrcW <= ResultSrcM;
      ecall_opW <= ecall_opM;
      aluresW <= aluresM;
      mdW <= md;
    end
  end

  /* Writeback Stage */
  assign result = (ResultSrcW == 2'b00) ? pcplus4W:
                  (ResultSrcW == 2'b01) ? {imm_uW,12'b0}:
                  (ResultSrcW == 2'b10) ? mdW:
		                          aluresW;
  assign ecall_op_out = ecall_opW;

  rfile rfile_1(.clk(clk), .D1(reg1), .A1(rs1), .D2(reg2), .A2(rs2), .WD3(result), .A3(rdW), .WE3(RegWriteW));

endmodule
