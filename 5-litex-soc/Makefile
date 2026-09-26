# SPDX-License-Identifier: MIT
# MyCPU is freely redistributable under the MIT License. See the file
# "LICENSE" for information on usage and redistribution of this file.

include ../common/build.mk

test:
	cd .. && sbt "project litexSoc" test

litex-rtl:
	cd .. && sbt "project litexSoc" "runMain board.litex.GenerateCa2025Mycpu"

contract: litex-rtl
	python3 scripts/test_litex_top_contract.py

examples:
	cd .. && sbt "project litexExamples" test
	python3 examples/scripts/uart_oracle.py examples/fixtures/gate_banner.txt

indent:
	find . -name '*.scala' | xargs scalafmt

clean:
	cd .. && sbt "project litexSoc" clean
	cd .. && sbt "project litexExamples" clean
	$(RM) -r test_run_dir
	$(RM) -r build/litex
	$(RM) -r examples/test_run_dir examples/target

.PHONY: test litex-rtl contract examples indent clean
