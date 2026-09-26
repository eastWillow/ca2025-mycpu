# 4-soc 與 5-litex-soc：差異、WNS、上真實 FPGA

這份講義給已經做完 `4-soc`、正要做 `5-litex-soc` 的人。讀完應能回答三件事：

1. 為什麼 LiteX 不能直接拿 `4-soc` 的教育 SoC 去開 BIOS。
2. 100 MHz 的 WNS 是從哪一條組合路徑冒出來的，以及什麼叫「修架構、不改五級」。
3. 上 Arty A7-35T 時，bitstream 綠了還不算數，還要看哪些契約。

配套小型範例（可改、可測）在 [`../examples/`](../examples/README.md)。主實驗的 `[CA25: Exercise 22]`–`30` 在 [`../README.md`](../README.md)。

## 1. 兩個 lab 在學什麼

`4-soc` 教的是：**自己當 SoC 設計師**。CPU 旁邊有你寫的 AXI 解碼、2MB 記憶體、VGA、UART、從 `0x1000` 載入的課堂程式。驗證手段是 ChiselTest、Verilator、自己的 `shell` / `nyancat`。

`5-litex-soc` 教的是：**把同一顆五級 CPU 交給別人的 SoC**。LiteX 已經有 DDR3、UART、BIOS、CSR 匯流排。你只能交出一個穩定邊界：clock、reset、32-bit interrupt、指令 AXI-Lite、資料 AXI-Lite。驗證手段變成「LiteX BIOS 是否出現 `litex>` → `help` → `LiteX BIOS, available commands:` → `litex>`」。

一句話：`4-soc` 證明 CPU 在自己的玩具世界裡會跑；`5-litex-soc` 證明同一顆 CPU 在 LiteX 的真實週邊與 100 MHz DDR 時序下仍是那顆五級 CPU。

## 2. 對照表

| | `4-soc` | `5-litex-soc` |
|---|---|---|
| 角色 | 教育 SoC | LiteX CPU 核心 |
| 公開頂層 | `board.verilator.Top` / FPGA `Top`（debug、VGA、loader） | `board.litex.Ca2025Mycpu` |
| 重設位址 | 課堂映像常在 `0x1000` | LiteX 整合 ROM 固定 `0x00000000` |
| 記憶體 | 自己的 2MB + ROM loader | LiteX 的 ROM / SRAM / DDR3 |
| UART | 自己的 MMIO 控制器 | LiteX UART（polling 或 IRQ） |
| 顯示 | VGA 640×480 | 沒有。BIOS 只走序列埠 |
| 中斷 | 課堂 CLINT 編碼（舊測試曾用 `Timer0=0x1` 這種 code） | 扁平 32-bit 向量，bit 對 bit 進 `mip`/`mie` |
| `mepc` | 必須是被打斷的那一筆 ID 指令 | 相同契約；LiteX BIOS 會依賴它 |
| 時脈目標 | Verilator 不閉合 FPGA 時序 | Arty DDR3 **100 MHz**（週期 10 ns） |
| 通過標準 | `make test`、`make check-uart` | `make test`、`make contract`；上板還要 WNS ≥ 0 與 UART 四件套 |
| 出題方式 | `4-soc` 是完整實作（參考解答） | `[CA25: Exercise]` 挖空，與 `1-single-cycle` 相同 |

不要做的對應：

- 把 `4-soc` 的 VGA/UART 搬進 LiteX top。LiteX 不認這些埠。
- 為了過時序把 branch resolution 整段搬出 ID。那是 **redesign**，超出本課。
- 用 `4-soc` 的 `make sim` 字幕當成 LiteX BIOS 證明。

## 3. 為什麼會出現 WNS

### 3.1 WNS 是什麼

FPGA 時序以**暫存器到暫存器**為單位。時脈 100 MHz 時，兩個 flop 之間最多 10 ns（再扣 clock uncertainty）。

```
WNS = 時脈週期 −（邏輯延遲 + 繞線延遲 + 不確定性）
```

- WNS ≥ 0：這條路徑趕得上，**才允許** `--load` / `--flash`。
- WNS < 0：矽上這條路徑會在下一拍前算不完。產生 bitstream 只代表「檔案寫出來了」，**不是** BIOS boot。負 WNS 影像是失敗證據。

本專案實測過的數字（Arty A7-35T，`main_crg_clkout0` = 100 MHz）：

| 階段 | WNS | 最差路徑（簡化） |
|---|---|---|
| 第一次 Gate 1 | −2.604 ns | IF/ID instruction → 重新導向 → **CSR `mhpmcounter` enable** |
| 拿掉 RF write-through 後 | 約 −0.97 ns | instruction → RF → branch compare → IF/ID **SR（flush）** |
| Explore 後仍差 30 ps | −0.030 ns | MEM `PC+4` 組合轉送進 ID redirect |
| Gate 1 關閉 | **+0.019 ns** | ExtraTimingOpt + polling BIOS |
| Gate 4 一度 | −0.009 ns | instruction → RF → BEQ/BLT CARRY4 → **`pc.D`**（IRQ 變體） |
| Gate 4 關閉 | **+0.153 ns** | 註冊 PC redirect + 兩拍 valid flush |

### 3.2 三條真實的壞路徑

這些不是假想題，是 STA 報表上的 source / destination。

**路徑 A — 計數器 enable（最先爆）**

IF/ID 的 instruction 位元經過 decode、redirect，最後打進效能計數器的 clock enable。計數器是 64-bit，enable 網路又寬又晚。修復：事件先 `RegNext` 再進 counter（Exercise 30a）。總數少一拍可見、不少一次。

**路徑 B — 寬同步 flush（fanout）**

IF/ID 若在 flush 時把 instruction 整顆同步重設成 NOP（`0x00000013`），compare 結果會打到**每一顆** instruction flop 的 S/R 腳。實測 instruction 淨 fanout 到過 5654，路徑裡繞線可佔七成以上。修復：只清 1-bit `valid`；payload 不跟 flush 走（Exercise 27）。ID 看到 `valid=0` 就當 NOP。

**路徑 C — 同週期 compare → PC**

```
if2id.instruction → decode → RF 讀 → 32-bit 比較（CARRY4）→ jump_flag → pc.D
```

這是 ID 階段提前解析 branch 的代價：省一拍 bubble，但 10 ns 裝不下。IRQ 變體若再把 CLINT handler mux 疊上 `if_jump_*`，同一條路徑更長（Gate 4 曾剩 9 ps）。修復：

- trap 只走 InstructionFetch 既有 mux，不要在 ID 再 OR 一次（Exercise 29）
- PC 吃**已經存在的** `prev_jump_flag` / `prev_jump_addr`，不要吃組合比較（Exercise 28）
- IF/ID valid 多 flush 一拍，丟掉多抓的那一個順序 fetch（Exercise 30b）

這仍然是五級、仍然在 ID 解析 branch，只是 PC 更新晚一拍。

### 3.3 邏輯深度 vs 繞線

報表上若 Data Delay 的 70% 以上是 net / route，問題常常是 **fanout 與擺位被拉開**，不是 ALU 少了一級。這時再疊 LUT 優化通常救不了 9 ps；要切路徑（加 flop）或減 fanout（不要用 32-bit 同步 reset 當 bubble）。

P&R 有隨機性：同一份 RTL，Explore 可能 −0.009、ExtraTimingOpt 可能 −0.2。負 WNS 不論大小都不得當 boot 證明。

### 3.4 什麼算修、什麼算改寫

| 可做（architectural fix） | 不可做（redesign） |
|---|---|
| 計數器事件取樣 | 把所有 branch 解析搬到 EX |
| valid-bit flush | 改成 3-stage 或 6-stage |
| 用既有 `RegNext(jump)` 延後 PC | 拿掉 ID forwarding / 提前 branch |
| trap mux 只留在 IF | 為時序關掉預測器當「最終核心」 |

功能回歸必須留下：load-to-branch 迴圈離開、`jal ra` 的 link 是 PC+4 不是跳轉目標、CLINT `mepc`。

## 4. 放到真實 FPGA 要考慮什麼

### 4.1 板級契約（這次鎖定的）

- 板：Digilent Arty A7-35T（`xc7a35ticsg324-1L`）
- 記憶體：DDR3，不是 `4-soc` 的 on-chip 2MB
- 系統時脈：100 MHz
- UART：115200，裝置通常是 `/dev/ttyUSB1`（FT2232 的 UART 通道）
- 工具：Vivado；`--load` 進 SRAM，**只有最終 IRQ+CRC 影像**才 `--flash`

少任何一項，就不是這份「hardware proof」。降頻、改用 BRAM、關掉 IRQ，都只算 diagnostic boot。

### 4.2 證明梯子（為什麼不能一次燒最終版）

```
Gate 1  Arty,  no CRC, noirq,  --load     先證明 CPU+DDR+polling UART
Gate 2  sim,   CRC,    noirq              再打開 BIOS CRC
Gate 3  sim,   CRC,    standard/IRQ       再打開中斷
Gate 4  Arty,  CRC,    standard, --flash  最後才寫 SPI
```

前一關紅，後關的成功物證無效。Sim 不能代替 Gate 1/4。舊 bitstream、負 WNS 影像都不能當證明。

### 4.3 BIOS 與 CPU 腳位必須一致

LiteX 的規則：`cpu.interrupt` 這個屬性**存在**，BIOS 就會定義 `CONFIG_CPU_HAS_INTERRUPT`，UART 改走 ISR。

實測：`noirq` 若仍露出 `interrupt` 並在 RTL 把腳綁 0，BIOS 會把硬體 FIFO 寫滿然後等永遠不會來的 ISR。UART 只吐約 19 個 banner 位元組就停。修復：`noirq` **不要宣告** `self.interrupt`，讓 BIOS 編譯成 `UART_POLLING`。

`standard` 必須真的接 32-bit 向量，Gate 3/4 才有意義。

### 4.4 UART 觀測會騙人

- BIOS prompt 是 `ESC[92;1mlitexESC[0m>`，比對前要剝 CSI，否則字面搜 `litex>` 會假失敗。
- `litex_term` 需要真實 TTY；腳本請用 pyserial，**先開 UART 再** `--load`/`--flash`。
- 開 serial 可能脈衝 DTR，FPGA 會重開機。Gate 4 還要確認 banner 日期／`BIOS CRC passed`，避免把仍留在 SRAM 的 Gate 1 影像當成 flash 證明。
- LiteX sim 的 serial2tcp：client 必須在 BIOS 開始 TX **之前**掛上，否則會丟開頭。

通過定義永遠是這四件：`litex>`、你打下的 `help`、`LiteX BIOS, available commands:`、再一個 `litex>`。只有 banner、只有 bitstream、只有 WNS，都不算。

### 4.5 DDR、CRC、燒錄

- DDR 初始化失敗會停在 leveling / memtest，看起來像 CPU 掛了。先看 BIOS 是否印 `Memtest OK`。
- Gate 1 用 `--bios-no-crc` 是為了少一個變數；Gate 2 起必須 CRC 通過（`BIOS CRC passed`）。
- `--flash` 寫的是 SPI。寫完 FPGA 可能還在跑舊的 SRAM 影像，需要 `boot_hw_device` 或按 PROG 從 flash 重載。
- 燒錄過程會載入 flash proxy bitstream，UART 會出現垃圾，這正常。

### 4.6 上板前檢查清單

- [ ] `main_crg_clkout0` 的 setup WNS ≥ 0，TNS = 0
- [ ] 影像就是這一版 `Ca2025Mycpu.v` 的 hash，不是資料夾裡隨便一個 `.bit`
- [ ] `noirq` 影像的 BIOS **沒有** `CONFIG_CPU_HAS_INTERRUPT`；`standard` 有
- [ ] UART 開著、115200、剝 CSI
- [ ] 看到的 BIOS 日期／CRC 對得上這次 build，不是上一張 SRAM 影像
- [ ] `help` 之後有 `LiteX BIOS, available commands:` 與第二個 prompt

## 5. 建議學習順序

1. 讀本文件第 2、3 節，對照 `4-soc/README.md` 與 `5-litex-soc/README.md`。
2. 跑小型範例（不需板、不需填完整 CPU）：[`../examples/README.md`](../examples/README.md)。
3. 填 `5-litex-soc` 的 Exercise 22–30，`make test` / `make contract`。
4. 用第 4 節清單讀一份真實 `digilent_arty_timing.rpt`（課堂提供或自己的 Gate 影像）。
5. 有板再走 Gate 1；沒有板就停在契約測試與範例，不要用 sim 冒充上板。

## 6. 自我檢查

- [ ] 能說出 `4-soc` 多了哪些 LiteX 不准看到的埠。
- [ ] 能指出 WNS 的單位、100 MHz 的預算（10 ns）、負 WNS 為什麼不能燒。
- [ ] 能畫路徑 C：instruction → RF → compare → `pc.D`，並說註冊 jump 與 valid flush 各切哪一段。
- [ ] 能解釋 `noirq` 若留下 `interrupt` 屬性，為什麼 UART 會在 banner 後假死。
- [ ] 改過 `examples/` 裡至少一個 Mini，讓原本失敗的測試變綠。
