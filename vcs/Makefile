.PHONY: vcs run merge cov verdi clean

#compile command
VCS	=	vcs +v2k  -timescale=1ns/1ps	\
			-full64	\
			-debug_access+all	\
			-f filelist.f	\
			+mindelays	\
			-negdelay	\
			+neg_tchk	\
			-l vcs.log \
			+incdir+../rtl/header

VERDI=Verdi-Ultra -f filelist.f   \
		-ssf tinyriscv_soc.fsdb    \
		-nologo                \
		-l verdi.log

# ------------------------------------------------------------------
# Coverage: VCS must see -cm at BOTH compile time and run time.
# Compile on O-2018.09-SP2 requires '+' separated types
# (line,cond,tgl,branch,fsm,assert: 'line,cond,...' comma form FAILS).
# Use default cm_dir (= current dir -> vdb name 'simv.vdb');
# 'urg -dir +./cov' style paths are NOT accepted by this URG version.
# ------------------------------------------------------------------
COV_TYPES = line+cond+tgl+branch+fsm+assert

# Default test program: prebuilt riscv-tests binary in ../tests/isa/generated
# The TB waits x26==1 (tohost) then x27==1 -> TEST_PASS.
TESTS_DIR ?= ../tests/isa/generated
TEST       ?= rv32ui-p-simple
MEM_SRC     = $(TESTS_DIR)/$(TEST).bin

# start compile and simulate
vcs:
	$(VCS)

run: inst.data
	./simv -cm $(COV_TYPES)

# generate ROM init file from test binary (original flow script)
inst.data: $(MEM_SRC)
	python3 generate_inst_data.py $(MEM_SRC)

# merge all coverage in simv.vdb into HTML report + terminal summary
merge:
	rm -rf cov_report
	urg -dir simv.vdb -report cov_report
	@echo "=== terminal summary (see cov_report/html/index.html for details) ==="
	@cat cov_report/mergereport.txt cov_report/grp/summary.txt 2>/dev/null || true

# one-shot: compile + run + report
cov: vcs run merge

#run verdi
verdi:
	$(VERDI)

#clean
clean:
	rm -rf  ./Verdi-SXLog ./Verdi-UltraLog ./dff ./csrc *.daidir *log *.vpd *.vdb simv* *.key *race.out* *.rc *.fsdb *.vpd *.log *.conf *.dat *.conf *.so uart cov cov_report inst.data
