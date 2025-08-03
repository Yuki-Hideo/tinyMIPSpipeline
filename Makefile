# テストベンチ（iverilog/vvp）
test: mips32.v mips32_tb.v
	iverilog -o mips32_tb mips32_tb.v mips32.v
	vvp mips32_tb
#MODEL = /home/cad/lib/NANGATE45/cells.v
#SCRIPT = nangate45
MODEL = /home/cad/lib/TSMC16/cells.v
SCRIPT = tsmc16

ex1:
	ncverilog +access+r test32.v mips32.v
ex2:
	ncverilog +access+r sum32.v mips32.v
ex3:
	ncverilog +access+r fib32.v mips32.v
syn:
	dc_shell -f ${SCRIPT}/syn.tcl | tee syn.log
par:
	innovus -init ${SCRIPT}/par.tcl | tee par.log
sta:
	dc_shell -f ${SCRIPT}/sta.tcl | tee sta.log
dsim:
	ncverilog +define+__POST_PR__ +access+r -v ${MODEL} sum32.v mips32.final.vnet | tee dsim.log
saif:
	vcd2saif -input dump.vcd -output mips32.saif
power:
	vcd2saif -input dump.vcd -output mips32.saif
	dc_shell -f ${SCRIPT}/power.tcl | tee power.log
clean:
	rm -rf xcelium.d xmverilog.*
	rm -rf WORK command.log default.svf
	rm -rf innovus.* *.enc.dat *.enc timingReports Default.view
	rm -rf .cadence *.rpt *.rpt.old rc_model.bin
	rm -f dump.trn dump.dsn sdf.log
allclean:
	make clean
	rm -f sim.log syn.log par.log sta.log power.log dsim.log
	rm -f mips32.vnet mips32.sdc mips32.final.vnet mips32.sdf mips32.spef
	rm -rf .simvision dump.vcd mips32.saif mips32.sdf.X
