# ID-stage forwarding to cut the branch penalty from 2 to 1 cycles

`FiveStageFinal` (the default in `3-pipeline` and the CPU in `4-soc`) resolves branches in the ID stage, and the forwarding unit (`fivestage_final/Forwarding.scala`) provides a second set of bypass paths — EX/MEM and MEM/WB → ID — so the branch operands are ready for comparison in ID, one cycle earlier than in the classic EX-resolving designs.

**Considered options**: EX-stage branch resolution (as in `FiveStageStall`/`FiveStageForward`) is simpler — one forwarding network, branches compare in EX — but costs a 2-cycle penalty on taken branches and flushes two pipeline registers. ID resolution needs operands at ID time, which only extra ID forwarding supplies (the register file read at ID is otherwise stale for 1–2-cycle-old dependencies).

**Consequences**: taken branches flush only IF/ID (1 bubble); the forwarding unit is wider (4 output selects instead of 2) and `Control` must stall on load→ID and jump→ID dependencies that EX resolution would hide. CPI drops from ~1.8 (stall) toward ~1.2 at the price of this wider hazard logic.
