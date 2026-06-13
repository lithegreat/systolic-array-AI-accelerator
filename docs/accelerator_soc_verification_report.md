# 加速器 SoC 级功能验证报告

> 适用范围：Edu4Chip Didactic SoC 中 TUM 学生子系统（SS1）所集成的脉动阵列
> AI 加速器（systolic-array accelerator）的 **SoC 级**功能验证。
> 本报告记录已完成的工作、遇到的问题与解决方法（含 QuestaSim 取指 X 的解决），以及
> 对应的官方文档来源。

---

## 1. 概述

加速器本体（`rtl/` 下的 control / MAC / array / matrix 模块）此前已通过独立的
APB 测试平台（`sim/testbenches/tb_accel.sv`）完成单元级验证。本阶段目标是在
**完整 SoC**（Ibex 内核 + OBI/APB 总线 + 加速器）下，由 RISC-V 内核运行真实
固件（`accel.c`）通过总线驱动加速器，端到端验证集成正确性。

核心判定标准：内核把 C = A·B 的结果逐元素与黄金参考比对后，将
`accel_result` 写为 **`0xACCE5500`（PASS）** 或 `0xBADD0000 | 错误数`（FAIL）。

本阶段在两个独立环境完成验证：

| 环境 | 工具 | 状态 |
|------|------|------|
| 本地开发机 / CI runner | Verilator（2-state） | 通过（功能签核） |
| TUM eikon 实验服务器 | QuestaSim 2023.4（4-state，全 SoC + JTAG） | 通过（`+initreg+0` 消除取指 X，见 §5） |

---

## 2. 验证环境与基础设施

- **加速器参数**：M=N=K=16，`DATA_W=16`（有符号），`ACC_W=32`。MAC 为有符号
  乘 + 32 位累加，溢出按**二进制补码回绕、不饱和**（见 `rtl/MAC/mac_pe.sv`）。
- **数据布局（行主序，与硬件缓冲一致）**：`A[i][k] -> i*K+k`，`B[k][j] -> k*N+j`，
  `C[i][j] -> i*N+j`；APB 每个 32 位字按 **LSB-lane first** 打包两个 16 位元素。
- **加速器 APB 基址**：`0x0105_1000`（ICN_SS 槽位 1 = `tum_ss`）。
- **本地工具链**：Verilator 5.046；xPack `riscv-none-elf-gcc` 15.2.0（裸机 newlib）。
- **CI runner**：892 MiB RAM / 2 vCPU / 默认 0 swap；Docker 镜像内 Verilator 5.048。
- **eikon**：12 核 / 30 GiB RAM；`riscv64-unknown-elf-gcc` 15.2.0；QuestaSim 2023.4
  必须在 `alma.sif`（apptainer）容器内运行。

---

## 3. 已完成的工作

### 3.1 测试固件升级为「随机数据 + 黄金参考」

将 `Didactic-SoC/sw/accel/accel.c` 从「全 1 冒烟测试」升级为数据驱动的功能测试，
方法对齐 `sim/common/c_code/main_gemm.c` 的随机输入 + 预计算黄金参考范式：

- 新增生成器 `sim/common/c_code/gen_accel_data.py`（numpy，固定种子 `0xACCE`），
  生成 16x16 的有符号 16 位 A/B，并按 **与 RTL MAC 完全一致的 32 位二进制补码
  回绕**计算黄金矩阵 `C = A·B`，输出 `Didactic-SoC/sw/accel/accel_gemm_data.h`。
- `accel.c` 流式写入随机 A/B（每字两元素，LSB-lane first），触发计算，轮询
  `STATUS.done`，读回 256 个 C 元素逐一与黄金比对。

设计要点（均经 RTL 核对）：

- `const` 数组进入 `.rodata`，位于 IMEM 就地读取；唯一可写全局 `accel_result`
  位于 DMEM 字 0（`0x0101_0000`）。
- 链接脚本 `link.ld` 中 IMEM 仅 `0x1000`（4 KB = 1024 字）；新镜像
  `.text`+`.rodata` = 2936 B，留有余量。

### 3.2 Verilator 全 SoC 功能验证（功能签核）

- 自驱动 testbench `Didactic-SoC/verification/verilator/src/soc_accel/tb_soc_accel.sv`
  实例化完整 `Didactic` 顶层，免 JTAG 引导：强制
  `ctrl_reg_array.boot_reg_0 = 0xF01BF06F`（= `jal` 跳到 imem 复位向量 `0x80`）。
- 关键陷阱：`sysctrl_obi_xbar` 把**整字节地址**转发给 `i_imem`，而 `sp_sram` 用
  `addr_i` **直接作为字索引**；因此 `$readmemh` 须把程序字 `i` 散列到 `ram[i*4]`。
- 结果：`accel_result = 0xACCE5500`，**RESULT: PASS**，`[soc_accel] OK`。
- 已纳入 CI（`accel_soc_sim` 作业），并针对 runner 内存受限做了优化（见 §4.1、§4.2）。

### 3.3 工具链交叉验证（eikon）

将固件源同步至 eikon，用其 `riscv64-unknown-elf-gcc 15.2.0` 重新构建 `accel.hex`：
结果与本地 xPack 工具链**逐字节一致**（734 字版 md5 `2fe6e9c52938b6b4de66a584608c24dd`，
`.text`=2936 B）。证明固件可在两套工具链下可复现。
（其后 §4.4 把 `main` 改为 `return`，镜像增至 736 字。）

### 3.4 QuestaSim 全 SoC 流程打通（eikon）

封装脚本 `scripts/lab_server_sim.sh`，在 `alma.sif` 容器内完成
`compile -> elaborate -> run_sim`。已成功跑通：编译 0 错误、elaboration 0 错误、
**许可证签出成功**、JTAG 引导 + `load_L2` 加载 736 字、`resume`、内核开始执行
（UART 输出 `accel: start`）。取指 X 的解决见 §5。

---

## 4. 遇到的问题与解决方法

### 4.1 Verilator 版本差异导致 UNOPTFLAT 致命错误

- **现象**：runner 镜像 Verilator 5.048 把 OBI 交叉开关 grant 的组合环
  `UNOPTFLAT` 警告升级为致命错误（dev box 的 5.046 不报），导致 CI 构建失败。
- **根因**：`UNOPTFLAT` 是 Verilator 对「按位看不循环、但按信号看循环」逻辑的
  保守告警，通常良性（见官方文档 §6）。
- **解决**：在 `verilate_soc_accel.py` 的构建参数加 `-Wno-UNOPTFLAT`，使其在不同
  Verilator 版本间可移植。

### 4.2 CI runner 内存受限（892 MB / 0 swap）

- **现象**：全 SoC 构建峰值聚合 RSS 约 893 MB，接近物理内存，无 swap 易 OOM。
- **解决**：
  - 构建参数加 `VERILATOR_JOBS=1`（串行）+ `--output-split` 限制单个 g++ 峰值；
  - runner 上添加 2 GB 持久 swapfile 作兜底；
  - 用预烤依赖镜像（`.bender` + `vendor_ips`）避免每次联网；
  - 验证：runner 上构建 + 仿真峰值 mem+swap 约 1475 MB，PASS。

### 4.3 QuestaSim 许可证与容器环境

- **现象一**：宿主机直接 `vsim` 报 `FT_Done_MM_Var`（libfreetype 符号缺失）。
  - **解决**：QuestaSim 必须在 `alma.sif`（apptainer）容器内运行，容器自带正确库。
- **现象二**：容器内 `vmap: command not found`；License 签出失败
  `Failed to initialize licensing environment`。
  - **根因**：`launch_alma_apptainer` 启动的是干净环境（PATH 丢失）；且
    `LM_LICENSE_FILE` 在登录壳层未设置。
  - **解决**：在 `scripts/lab_server_sim.sh` 中通过 `apptainer exec --env` 同时转发
    `PATH` 与 `LM_LICENSE_FILE`/`MGLS_LICENSE_FILE`，默认指向 TUM EI 许可证服务器
    `1717@license.lis.ei.tum.de`（从 `lx01` 实测仅 1717 端口可达，且 1717 为 Mentor
    FlexLM 端口）。验证：容器内 `vsim` 可成功签出许可证（Errors: 0）。

### 4.4 testbench 完成握手不成立（程序死循环）

- **现象**：`tb_didactic` 一直停在 "Waiting for end of computation"。
- **根因**：官方 `tb_didactic` 通过轮询 `readMem(0x0102_0380)` 的 bit31 判定程序结束；
  而 `crt0.S` 的 `postMain` 只有在 **`main` 返回**时才把 `(a0 | 0x8000_0000)` 写入
  `0x0102_0380`。原 `accel.c` 以 `while(1)` 结尾，从不返回，握手寄存器永不被写。
- **解决**：`accel.c` 的 `main` 改为 **返回**（PASS 返 0，FAIL/超时返非 0），同时仍
  把 `accel_result` 写入 DMEM 供 Verilator tb 观察。Verilator 仍 PASS（无回归）。

### 4.5 `run_sim` 无头模式不推进仿真

- **现象**：`make run_sim` 仅推进 0 ns 即 `<EOF>`。
- **根因**：`sim/Makefile` 硬编码 `-do "run 0ms;"`（为 GUI 设计）。
- **解决**：新增可覆盖变量 `RUN_CMD ?= run 0ms;`，无头运行时由脚本传
  `RUN_CMD="run -all; quit -f"`（默认值保留原 GUI 行为，不影响他人）。

### 4.6 common_cells 仲裁器断言风暴（2.1 GB 日志）

- **现象**：`common_cells/src/rr_arb_tree.sv:173` 的 `lock_req`（LockIn `ASSUME`）
  在内核正常 OBI 访存时**每周期触发**，累计 **138 万次**，日志膨胀至 2.1 GB，
  仿真几近停滞。
- **根因**：Ibex 会在 grant 之前合法地撤销 OBI 请求，触发该 `ASSUME`；这是
  **SoC 自带 IP 的协议假设噪声**，与加速器无关（Verilator 流程也用同名宏关闭它）。
- **解决**：在 `sim/Makefile` 的 `DUT_DEFINES` 加 `+define+COMMON_CELLS_ASSERTS_OFF`
  （与 Verilator 一致）。效果：断言 138 万 -> 42 次，日志 2.1 GB -> 192 KB。

---

## 5. QuestaSim 全 SoC 取指 X —— 已解决（不改 RTL）

### 5.1 现象与根因

**现象**：内核 `resume` 后开始执行，但在 `PC 0x0100_023c` 取到指令
**`0xX0XXX7XX`**（部分位为 4-state 未知值 X），随即触发非法指令异常并自旋，导致
`tb_didactic` 永远等不到完成信号。

**已排除的可能**：

- `load_L2` 实测把**正确**值 `0x2407_0713` 写入了 `0x23c`（且 736 字**全部**写对），
  说明 **imem 内容正确**——X 不来自内存内容。
- 同一份 `accel.hex` 在 **Verilator（2-state）** 下运行到 **PASS**，说明**不是加速器
  或固件的功能 bug**。

**根因（已在 RTL 中定位）**：本 SoC 用 **`ResetAll=0`** 例化 Ibex，于是
`vendor_ips/ibex/rtl/ibex_fetch_fifo.sv` 的 `g_rdata_nr` 分支（约 236–255 行）里
取指 FIFO 的数据触发器 `rdata_q` / `err_q` **没有复位**，在 4-state QuestaSim 中上电
为 X。非对齐 / 压缩指令的拼接 `{rdata_q[1][15:0], rdata[31:16]}` 把这个 X 混进取到的
指令字，于是出现「半字为 X」的 `0xX0XXX7XX`。真实硅片 / FPGA 上这些触发器上电为确定值，
2-state 的 Verilator 默认按 0 处理，因此都正确；唯独 4-state 的 QuestaSim 触发该 X 悲观性。

### 5.2 解决方法：`vopt +initreg+0`（不改 RTL）

在 elaboration（`vopt`）阶段加 **`+initreg+0`**，把所有未复位触发器初始化为 0
（与硅片 / Verilator 的 2-state 行为一致），即可消除取指 X。已在
`Didactic-SoC/sim/Makefile` 中设为默认：

```makefile
INIT_OPTS ?= +initreg+0          # 进入 VOPT_OPTS
```

**关键教训**：先前一次尝试同时加了 `+initreg+0 +initmem+0`，其中的 **`+initmem` 使
`vsim` 内核崩溃**（`Trouble with Simulation Kernel`，Error 218），掩盖了「`+initreg`
单独即可修复」这一事实。取指 X 是**触发器**问题，**只需 `+initreg+0`，绝不要加
`+initmem`**。

### 5.3 验证结果

在 eikon 上以默认 `INIT_OPTS=+initreg+0` 重跑全 SoC 流程（两次：断言关闭 / 断言开启），
均得到：

```
# RX string: accel: PASS
# [TB] Time 29831700 ns - JTAG RETURN OK: Received status core: 0x00000000
```

即内核执行 `accel.c`、经真实 OBI/APB 总线驱动加速器、回读 C 与黄金比对全部正确，
通过 `0x0102_0380` 完成握手返回状态 0（成功）；**断言开启时无任何 `ASSERT FAILED`、
无非法指令**。至此 **QuestaSim 全 SoC 功能仿真端到端通过**，且未改动任何 RTL。

---

## 6. 官方文档索引

### Verilator（X 处理、收敛、UNOPTFLAT）

- 参数 `--x-assign` / `--x-initial` / `--x-initial-edge`（控制显式 X 与未初始化变量的
  2-state 取值，含 `0`/`1`/`unique`/`fast` 模式）：
  <https://verilator.org/guide/latest/exe_verilator.html>
  （摘录：`--x-initial 0` 把未初始化变量初始化为 0；`--x-assign` 控制显式 X 的取值；
  时钟初值默认 0，除非 `--x-initial-edge`。）
- `UNOPTFLAT`（组合环告警）与 `DIDNOTCONVERGE`（收敛失败）：
  <https://verilator.org/guide/latest/warnings.html>
- 未知态（Unknown States）总体说明：
  <https://verilator.org/guide/latest/languages.html#unknown-states>
- 运行时随机复位 `+verilator+rand+reset+2` / `+verilator+seed`：
  <https://verilator.org/guide/latest/exe_sim.html>

### Ibex（取指 / 寄存器堆 / 引导 / 断言）

- **Instruction Fetch**（prefetch buffer = FIFO；非对齐 / 压缩指令需两次字对齐访问
  拼接）—— 取指 X 的直接根因依据：
  <https://ibex-core.readthedocs.io/en/latest/03_reference/instruction_fetch.html>
- **Core Integration**（`RegFileFF` 默认基于触发器的寄存器堆；复位 PC =
  `boot_addr_i + 0x80`；Debug Module 地址参数；`SecureIbex`）：
  <https://ibex-core.readthedocs.io/en/latest/02_user/integration.html>
- **Register File**（三种实现及其上电/复位行为）：
  <https://ibex-core.readthedocs.io/en/latest/03_reference/register_file.html>
- **Verification**（UVM/cosim 方法学，X 检查断言所在环境）：
  <https://ibex-core.readthedocs.io/en/latest/03_reference/verification.html>
- `ASSERT_KNOWN` 等断言宏定义（lowRISC `prim_assert`，由 `+define+INC_ASSERT` 启用）：
  <https://github.com/lowRISC/ibex/blob/master/vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv>

### PULP common_cells（仲裁器断言）

- `rr_arb_tree.sv`（含 `LockIn` 的 `lock_req` `ASSUME`；由
  `ifndef COMMON_CELLS_ASSERTS_OFF` 包裹）：
  <https://github.com/pulp-platform/common_cells/blob/master/src/rr_arb_tree.sv>

### 总线 / 调试协议

- **OBI**（Open Bus Interface，Ibex 取指/LSU 所用协议子集）规范：
  <https://github.com/openhwgroup/obi/blob/072d9173b3bf7d5cdc2c2cf68fb74c6453a7f0c4/OBI-v1.0.pdf>
- **RISC-V Debug**（JTAG 调试模块，`tb_didactic` 引导/轮询所依据）：
  <https://github.com/riscv/riscv-debug-spec>

### QuestaSim / Questa（寄存器与内存初始化）

- 确定性初始化选项语法（从 Questa 2023.4 `vopt`/`vish`/`vsimk` 二进制内置 help
  字符串提取，权威依据）：

  ```
  +initmem[=<spec>][+0|1|X|Z][{+<selection>[.]}]
  +initreg[=<spec>][+0|1|X|Z][{+<selection>[.]}]
  +noinitmem[{+<selection>}]   +noinitreg[{+<selection>}]
  +initmem+<seed>  +initreg+<seed>   (随机化种子)
  +initregNBA | +noinitregNBA       (是否以非阻塞方式应用，默认启用)
  ```

  二进制提示：「applying +initreg/+initmem options to vlog/vopt」。
- 对应 Siemens EDA 官方手册（通常需 Siemens Support 账号访问
  <https://support.sw.siemens.com>）：
  - *Questa SIM Command Reference Manual* — `vopt` / `vsim` 命令，`+initmem` /
    `+initreg` 选项。
  - *Questa SIM User's Manual* — 寄存器/内存初始化（X 消除）相关章节。

---

## 7. 本次涉及的文件（截至本报告，尚未提交）

| 文件 | 变更 |
|------|------|
| `sim/common/c_code/gen_accel_data.py` | 新增：随机 A/B + 黄金参考生成器 |
| `Didactic-SoC/sw/accel/accel_gemm_data.h` | 新增（生成）：测试向量与黄金矩阵 |
| `Didactic-SoC/sw/accel/accel.c` | 改：随机数据 + 黄金比对；`main` 改为 `return` |
| `Didactic-SoC/sim/Makefile` | 改：`RUN_CMD`、`COMMON_CELLS_ASSERTS_OFF`、`INIT_OPTS ?= +initreg+0` |
| `scripts/lab_server_sim.sh` | 改：转发 `PATH` 与许可证、无头 `RUN_CMD` |

> 注：`Didactic-SoC` 是子模块，其改动需在子模块分支提交后由主仓库更新 gitlink。

---

## 8. 结论与建议

- **加速器在 SoC 级的功能正确性已经签核**：Verilator 全 SoC 下内核经真实 OBI/APB
  总线驱动加速器，`accel_result = 0xACCE5500`，PASS；并由 eikon 独立工具链构建出
  逐字节一致的固件佐证。
- **QuestaSim 全 SoC 流程也已端到端通过**：通过 `vopt +initreg+0`（不改任何 RTL）
  消除 Ibex 取指 FIFO 未复位触发器导致的 4-state 取指 X，内核成功执行并经
  `0x0102_0380` 握手返回成功（`JTAG RETURN OK: status 0x00000000`），断言开启亦无失败。
- **建议**：日常功能签核用 Verilator（快、license-free、已纳入 CI）；QuestaSim 经
  `scripts/lab_server_sim.sh` 在 eikon 上做 4-state 全 SoC 集成回归（已默认带
  `+initreg+0`，开箱即用）。
