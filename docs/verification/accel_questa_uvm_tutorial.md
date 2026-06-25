# QuestaSim UVM 测试平台教程

> **适合人群**：完全没有接触过 UVM 的初学者。  
> **目标**：通过本项目 `sim/testbenches/accel_questa_uvm/` 中的真实代码，从零理解
> UVM 的每一个概念，最终能独立添加新测试。  
> **仿真器**：QuestaSim 2023.4，在 eikon 服务器上运行。

---

## 目录

1. [为什么要用 UVM？](#1-为什么要用-uvm)
2. [UVM 的核心思想：层次化组件](#2-uvm-的核心思想层次化组件)
3. [项目文件总览](#3-项目文件总览)
4. [第一步：信号接口 `apb_if.sv`](#4-第一步信号接口-apb_ifsv)
5. [第二步：事务 `apb_seq_item`](#5-第二步事务-apb_seq_item)
6. [第三步：Sequencer 序列器](#6-第三步sequencer-序列器)
7. [第四步：Driver 驱动器](#7-第四步driver-驱动器)
8. [第五步：Monitor 监视器](#8-第五步monitor-监视器)
9. [第六步：Agent 代理](#9-第六步agent-代理)
10. [第七步：Sequence 序列（激励场景）](#10-第七步sequence-序列激励场景)
11. [第八步：RAL 寄存器抽象层](#11-第八步ral-寄存器抽象层)
12. [第九步：Scoreboard 记分板](#12-第九步scoreboard-记分板)
13. [第十步：Coverage 覆盖率收集器](#13-第十步coverage-覆盖率收集器)
14. [第十一步：Environment 环境](#14-第十一步environment-环境)
15. [第十二步：Test 测试类](#15-第十二步test-测试类)
16. [第十三步：tb_top 顶层模块](#16-第十三步tb_top-顶层模块)
17. [三大机制详解](#17-三大机制详解)
18. [如何运行测试](#18-如何运行测试)
19. [如何添加新测试](#19-如何添加新测试)
20. [常见报错速查](#20-常见报错速查)

---

## 1. 为什么要用 UVM？

### 传统测试平台的问题

在没有 UVM 之前，验证工程师通常直接写 SystemVerilog `initial` 块：

```systemverilog
// 传统方式（不用 UVM）
initial begin
    PSEL = 1; PWRITE = 1; PADDR = 10'h100; PWDATA = 32'h1;
    @(posedge clk); PENABLE = 1;
    @(posedge clk); PENABLE = 0; PSEL = 0;
    // ... 几百行重复代码 ...
end
```

这种方式的问题：
- **不可复用**：换一个 DUT，所有代码都要重写。
- **无法随机化**：激励是固定的，无法自动发现边界情况。
- **没有自动比对**：需要手工检查波形，容易漏 bug。

### UVM 的解决思路

UVM（Universal Verification Methodology，通用验证方法学）提供了一套**标准化的组件框架**：

```
"我不关心你发什么信号，我只告诉你发一个 APB 写事务到地址 0x100"
```

UVM 把验证分为**三个独立层次**：

| 层次 | 做什么 | 对应本项目 |
|---|---|---|
| **激励层** | 描述"要做什么"（写寄存器、读数据…） | Sequence |
| **总线层** | 把"做什么"翻译成"怎么驱动信号" | Driver / Monitor |
| **功能层** | 判断"结果对不对"，统计"覆盖了什么" | Scoreboard / Coverage |

---

## 2. UVM 的核心思想：层次化组件

### 组件树（本项目）

```
tb_top (SystemVerilog module)
│
└── uvm_test_top  ←── 由 run_test("+UVM_TESTNAME=xxx") 动态创建
    │
    ├── accel_base_test / accel_zero_test / ...   (Test)
    │   │
    │   └── accel_env                              (Environment)
    │       │
    │       ├── apb_agent                          (Agent = UVC)
    │       │   ├── apb_sequencer                  (Sequencer)
    │       │   ├── apb_driver                     (Driver)
    │       │   └── apb_monitor                    (Monitor) ──┐
    │       │                                                   │ analysis port
    │       ├── accel_scoreboard  ←─────────────────────────────┤
    │       ├── accel_coverage    ←─────────────────────────────┘
    │       ├── accel_reg_block   (RAL 寄存器模型)
    │       ├── accel_reg_adapter (RAL ↔ APB 桥)
    │       └── uvm_reg_predictor (RAL 镜像同步)
```

**数据流**：

```
Test / Sequence
    │  create + start sequence items
    ▼
Sequencer ──── 分发 item ────► Driver ──► 驱动 APB 信号 ──► DUT
                                                              │
Monitor ◄─────────────────────────── 采样 APB 总线 ──────────┘
    │
    │  analysis port (广播)
    ├──► Scoreboard  (比对结果)
    └──► Coverage    (统计覆盖率)
```

### UVM 的两类基类

UVM 中所有类分为两大类：

| 类型 | 基类 | 特点 | 典型用途 |
|---|---|---|---|
| **Component** | `uvm_component` | 有父组件，组成固定层次 | Agent, Driver, Monitor, Env, Test |
| **Object** | `uvm_object` | 无父组件，动态创建 | Sequence Item, Sequence, Config |

> **记住这个区别**：Component 在 `build_phase` 里创建，整个仿真期间存活；
> Object 随时创建、随时销毁。

---

## 3. 项目文件总览

```
sim/testbenches/accel_questa_uvm/
├── apb_if.sv           # SystemVerilog 接口（不是 UVM 类，是硬件连接点）
├── apb_pkg.sv          # APB UVC：seq_item + config + sequencer + driver + monitor + agent
├── accel_env_pkg.sv    # 加速器专用：RAL + Sequence + Scoreboard + Coverage + Env
├── accel_tests_pkg.sv  # 5 个测试类
├── tb_top.sv           # 顶层模块：时钟/复位/DUT/run_test()
└── Makefile            # compile → elaborate → run → regress
```

---

## 4. 第一步：信号接口 `apb_if.sv`

> **文件**：[sim/testbenches/accel_questa_uvm/apb_if.sv](../../sim/testbenches/accel_questa_uvm/apb_if.sv)

### 接口的作用

`interface` 是 SystemVerilog 的特性，**不是 UVM 类**。它把一组信号打包成一个"插座"，
让 DUT 和测试平台都插到同一个插座上，避免在两边各声明一遍信号。

```systemverilog
interface apb_if (input logic clk);

    logic        reset_int;
    logic [9:0]  PADDR;
    logic        PSEL;
    // ... 所有 APB 信号 ...

    // 驱动时钟块：Driver 用这个在时钟沿后一个延迟驱动信号
    clocking driver_cb @(posedge clk);
        default input #1step output #1;   // 输出比时钟沿晚 1ns 变化
        output PADDR, PSEL, PENABLE, PWRITE, PWDATA;
        input  PRDATA, PREADY, PSLVERR;
    endclocking

    // 监视时钟块：Monitor 用这个在时钟沿前采样信号（稳定值）
    clocking monitor_cb @(posedge clk);
        default input #1step;             // 采样时钟沿前 1step（极短延迟）
        input reset_int, PADDR, PSEL, PENABLE, PWRITE, PWDATA, PRDATA, PREADY, PSLVERR;
    endclocking

endinterface : apb_if
```

### Clocking Block 解决时序竞争

如果 Driver 直接赋值 `PSEL = 1`，而 Monitor 在同一时刻采样，可能读到旧值（竞争）。
Clocking Block 通过 `#1step`（时钟沿前无穷小时刻）和 `#1`（时钟沿后 1ns）解决这个问题：

```
时间轴:  ─────────────────────────────────►
         ↑posedge
         │         ← #1step 之前采样（Monitor）
         │    ← #1 之后驱动（Driver）
```

### Virtual Interface

在 UVM 类（纯 SystemVerilog 类）中**不能直接引用** `interface`，
因为接口是硬件实例，而 UVM 类是软件对象。解决方法是用 `virtual interface`：

```systemverilog
// 在 Driver 类中声明：
virtual apb_if vif;   // "虚拟接口"句柄，相当于指向真实接口的指针

// 使用时：
vif.driver_cb.PSEL <= 1;   // 通过句柄访问信号
```

---

## 5. 第二步：事务 `apb_seq_item`

> **位置**：`apb_pkg.sv` 中的 `apb_seq_item` 类

### 什么是事务（Transaction）？

事务是 UVM 的基本激励单元，它描述**"发生了什么"**，而不是**"怎么发信号"**。

对 APB 总线来说，一次事务就是"在地址 X 写入值 Y"或"从地址 X 读取"。

```systemverilog
class apb_seq_item extends uvm_sequence_item;

    // ① 字段声明必须在 uvm_object_utils 宏之前（QuestaSim 要求）
    rand logic [9:0]  addr;    // rand 表示可以被约束随机化
    rand logic [31:0] data;
    rand bit          write;   // 1=写，0=读
    bit               slverr;  // 不可随机：由 Driver 从 PSLVERR 捕获

    // ② 向 UVM 工厂注册，并声明字段（用于 print/copy/compare）
    `uvm_object_utils_begin(apb_seq_item)
        `uvm_field_int(addr,   UVM_ALL_ON)
        `uvm_field_int(data,   UVM_ALL_ON)
        `uvm_field_int(write,  UVM_ALL_ON)
        `uvm_field_int(slverr, UVM_ALL_ON)
    `uvm_object_utils_end

    // ③ 约束：地址必须 4 字节对齐
    constraint c_word_align { addr[1:0] == 2'b00; }

    // ④ 构造函数（Object 只有 name 参数，没有 parent）
    function new(string name = "apb_seq_item");
        super.new(name);
    endfunction

endclass
```

### `uvm_object_utils` 宏做了什么？

这个宏展开后会生成几十行代码，包括：
- 向 **UVM 工厂**注册类（使 `type_id::create()` 能工作）
- 实现 `clone()`、`copy()`、`compare()`、`print()` 方法

> **新手常见错误**：把 `uvm_object_utils` 用在 Component 类上，或把
> `uvm_component_utils` 用在 Object 类上。记住规则：
> - 有 `(string name, uvm_component parent)` 构造函数 → `uvm_component_utils`  
> - 只有 `(string name = "xxx")` 构造函数 → `uvm_object_utils`

---

## 6. 第三步：Sequencer 序列器

> **位置**：`apb_pkg.sv` 中的 `apb_sequencer` 类

Sequencer 是一个**"调度员"**，它本身不产生激励，只负责把 Sequence 产生的
`seq_item` 排队，然后一个个交给 Driver。

```systemverilog
class apb_sequencer extends uvm_sequencer #(apb_seq_item);
    `uvm_component_utils(apb_sequencer)

    // 构造函数：Component 需要 name + parent
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass
```

本项目的 Sequencer 几乎是空的，因为 `uvm_sequencer` 基类已经实现了所有调度逻辑。
参数 `#(apb_seq_item)` 告诉它只接受 `apb_seq_item` 类型的事务。

---

## 7. 第四步：Driver 驱动器

> **位置**：`apb_pkg.sv` 中的 `apb_driver` 类

Driver 把抽象事务翻译成**真实的 APB 信号时序**。它只做一件事：
从 Sequencer 取事务，驱动信号，等待 DUT 响应，把结果写回事务。

### APB 协议时序（SETUP → ACCESS）

```
        clk:  ─┐ ┌─┐ ┌─┐ ┌─┐
               └─┘ └─┘ └─┘ └─┘
       PSEL:  ──────────────
     PENABLE:      ─────────    ← PENABLE 在第二个周期才拉高
      PREADY:           ──      ← DUT 准备好时拉高（可插入等待态）
                  SETUP  ACCESS
```

```systemverilog
class apb_driver extends uvm_driver #(apb_seq_item);
    `uvm_component_utils(apb_driver)

    virtual apb_if vif;   // 虚拟接口句柄

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 从 config_db 取出 tb_top 注册的接口
        if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Driver: no virtual interface in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        apb_seq_item item;
        // 等待复位结束
        @(negedge vif.reset_int);

        forever begin
            // 1. 向 Sequencer 请求下一个事务（阻塞直到有事务）
            seq_item_port.get_next_item(item);

            // 2. 驱动 SETUP 周期
            @(vif.driver_cb);
            vif.driver_cb.PADDR   <= item.addr;
            vif.driver_cb.PWRITE  <= item.write;
            vif.driver_cb.PWDATA  <= item.data;
            vif.driver_cb.PSEL    <= 1'b1;
            vif.driver_cb.PENABLE <= 1'b0;

            // 3. 驱动 ACCESS 周期
            @(vif.driver_cb);
            vif.driver_cb.PENABLE <= 1'b1;

            // 4. 等待 PREADY（DUT 可能插入等待态）
            do @(vif.driver_cb); while (!vif.driver_cb.PREADY);

            // 5. 把读回的数据/错误写进事务（Sequence 可以检查）
            if (!item.write) item.data   = vif.driver_cb.PRDATA;
            item.slverr = vif.driver_cb.PSLVERR;

            // 6. 释放总线
            vif.driver_cb.PSEL    <= 1'b0;
            vif.driver_cb.PENABLE <= 1'b0;

            // 7. 告知 Sequencer 事务完成
            seq_item_port.item_done();
        end
    endtask

endclass
```

### 关键点

- `seq_item_port.get_next_item(item)` 和 `item_done()` 是 Driver 与 Sequencer 通信的固定模式，必须成对出现。
- `vif.driver_cb.PSEL <= 1` 使用非阻塞赋值 `<=`，通过 clocking block 自动延迟到时钟沿后 1ns 生效。

---

## 8. 第五步：Monitor 监视器

> **位置**：`apb_pkg.sv` 中的 `apb_monitor` 类

Monitor 是**只读的被动观察者**——它永远不驱动信号，只是采样总线，
把完成的事务发送给 Scoreboard 和 Coverage Collector。

```systemverilog
class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    // Analysis port：可以连接到多个订阅者（Scoreboard、Coverage 等）
    uvm_analysis_port #(apb_seq_item) ap;

    virtual apb_if vif;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);   // 创建 analysis port
        void'(uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif));
    endfunction

    task run_phase(uvm_phase phase);
        apb_seq_item item;
        forever begin
            // 等到 ACCESS 阶段且 PREADY 拉高（一次完整事务）
            @(vif.monitor_cb);
            if (vif.monitor_cb.PSEL && vif.monitor_cb.PENABLE
                                    && vif.monitor_cb.PREADY) begin
                item = apb_seq_item::type_id::create("mon_item");
                item.addr   = vif.monitor_cb.PADDR;
                item.write  = vif.monitor_cb.PWRITE;
                item.data   = vif.monitor_cb.PWRITE ? vif.monitor_cb.PWDATA
                                                    : vif.monitor_cb.PRDATA;
                item.slverr = vif.monitor_cb.PSLVERR;
                // 广播给所有连接到 ap 的订阅者
                ap.write(item);
            end
        end
    endtask

endclass
```

### Monitor 与 Driver 的区别

| | Driver | Monitor |
|---|---|---|
| 方向 | 驱动信号（输出） | 采样信号（输入） |
| 与 Sequencer | 有连接 (`seq_item_port`) | 无连接 |
| 广播 | 不使用 analysis port | 使用 `ap.write(item)` 广播 |

---

## 9. 第六步：Agent 代理

> **位置**：`apb_pkg.sv` 中的 `apb_agent` 类

Agent 是一个**打包容器**，把 Sequencer + Driver + Monitor 组装成一个可复用的 UVC
（Universal Verification Component，通用验证组件）。

```systemverilog
class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)

    apb_sequencer  seqr;
    apb_driver     drv;
    apb_monitor    mon;

    // 转发 Monitor 的 analysis port，外部可直接连接 agent.ap
    uvm_analysis_port #(apb_seq_item) ap;

    apb_config cfg;   // 配置对象（是否主动、接口句柄等）

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);

        // 取配置对象（如果没有则使用默认值）
        if (!uvm_config_db #(apb_config)::get(this, "", "cfg", cfg))
            cfg = apb_config::type_id::create("cfg");

        // 只有 ACTIVE 模式才创建 Driver 和 Sequencer
        if (cfg.is_active == UVM_ACTIVE) begin
            seqr = apb_sequencer::type_id::create("seqr", this);
            drv  = apb_driver::type_id::create("drv",  this);
        end
        mon = apb_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        // 连接 Driver 的 seq_item_port ↔ Sequencer 的 seq_item_export
        if (cfg.is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);

        // 把 Monitor 的 ap 转发给 Agent 的 ap（外部观察者连 agent.ap 即可）
        mon.ap.connect(ap);
    endfunction

endclass
```

### 主动（ACTIVE）vs 被动（PASSIVE）

- **ACTIVE**：有 Driver + Sequencer，会主动驱动总线。用于 DUT 的激励端。
- **PASSIVE**：只有 Monitor，只观察不驱动。用于旁路观测点（如系统总线监听）。

本项目只使用一个 ACTIVE 的 APB Agent。

---

## 10. 第七步：Sequence 序列（激励场景）

> **位置**：`accel_env_pkg.sv` 中的 `accel_base_seq` 及其子类

### Sequence 是什么？

Sequence 是"脚本"，描述一段有意义的操作（例如"加载矩阵 A 和 B"）。
它通过调用 `start_item` / `finish_item` 把事务发给 Sequencer，
再由 Sequencer 交给 Driver 执行。

```
Sequence
  │
  │  start_item(item)    ← 等待 Sequencer "空闲"
  │  item.randomize()    ← 填充事务内容
  │  finish_item(item)   ← 把事务交给 Driver，等 Driver 完成
  │
  ▼
Sequencer ──► Driver ──► 信号
```

### `accel_base_seq`：封装 APB 读写原语

```systemverilog
class accel_base_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(accel_base_seq)

    // 阻塞 APB 写：等到 Driver 完成才返回
    task do_write(input logic [9:0] addr, input logic [31:0] data);
        apb_seq_item item = apb_seq_item::type_id::create("wr_item");
        start_item(item);   // 等待 Sequencer 分配
        // randomize with 约束：写操作，固定地址和数据
        if (!item.randomize() with { write == 1; addr == local::addr;
                                     data == local::data; })
            `uvm_fatal("RAND", "randomize failed")
        finish_item(item);  // 发给 Driver，阻塞到完成
    endtask

    task do_read(input logic [9:0] addr, output logic [31:0] data);
        apb_seq_item item = apb_seq_item::type_id::create("rd_item");
        start_item(item);
        if (!item.randomize() with { write == 0; addr == local::addr; })
            `uvm_fatal("RAND", "randomize failed")
        finish_item(item);
        data = item.data;   // Driver 把 PRDATA 写回了 item.data
    endtask

endclass
```

### `accel_load_ab_seq`：加载矩阵 A 和 B

```systemverilog
class accel_load_ab_seq extends accel_base_seq;
    `uvm_object_utils(accel_load_ab_seq)

    logic signed [15:0] a_flat[];   // 调用者在 start() 之前填入
    logic signed [15:0] b_flat[];
    int unsigned        data_w = 16;

    virtual task body();
        logic [31:0] word;

        // 1. 复位 A/B 写指针
        do_write(ADDR_AB_CTRL, 32'h1);

        // 2. 按行优先顺序写入 A（16 位模式：两个元素打包进一个 32 位字）
        for (int i = 0; i < a_flat.size()/2; i++) begin
            word[15:0]  = a_flat[i*2];
            word[31:16] = a_flat[i*2+1];
            do_write(ADDR_A_DATA, word);
        end

        // 3. 同理写入 B
        for (int i = 0; i < b_flat.size()/2; i++) begin
            word[15:0]  = b_flat[i*2];
            word[31:16] = b_flat[i*2+1];
            do_write(ADDR_B_DATA, word);
        end
    endtask

endclass
```

> **注意** `body()` 任务：Sequence 的主体逻辑一定写在 `virtual task body()` 里，
> 不在构造函数里。

---

## 11. 第八步：RAL 寄存器抽象层

> **位置**：`accel_env_pkg.sv` 中的 `accel_*_reg` 和 `accel_reg_block`

### 为什么要有 RAL？

直接用 `do_write(10'h108, 32'd4)` 设置矩阵行数是可以的，
但含义不清晰，换一个地址偏移就要修改所有测试。

RAL（Register Abstraction Layer，寄存器抽象层）提供了面向对象的寄存器模型：

```systemverilog
// 不用 RAL：
do_write(10'h108, 32'd4);   // 什么意思？

// 用 RAL：
reg_model.m_dim.value.write(status, 4, UVM_FRONTDOOR);   // 清晰！
```

### 寄存器定义示例

```systemverilog
// M_DIM 寄存器（地址 0x108，8 位宽，可读写）
class accel_dim_reg extends uvm_reg;
    `uvm_object_utils(accel_dim_reg)

    uvm_reg_field value;   // 字段：代表寄存器中某几位

    function new(string name = "accel_dim_reg");
        super.new(name, 32, UVM_NO_COVERAGE);  // 32 位宽，不开内置覆盖
    endfunction

    virtual function void build();
        value = uvm_reg_field::type_id::create("value");
        // configure(parent, 位宽, 起始位, 访问类型, 是否volatile, 复位值, ...)
        value.configure(this, 8, 0, "RW", 0, 8'h0, 1, 1, 0);
    endfunction

endclass
```

### 寄存器块：把所有寄存器组织在一起

```systemverilog
class accel_reg_block extends uvm_reg_block;
    `uvm_object_utils(accel_reg_block)

    accel_ctrl_reg    ctrl;
    accel_status_reg  status_r;
    accel_dim_reg     m_dim, n_dim, k_dim;
    // ...

    virtual function void build();
        // 创建 APB 地址映射，基地址 0x100
        uvm_reg_map default_map = create_map("default_map", 'h100, 4, UVM_LITTLE_ENDIAN);

        ctrl     = accel_ctrl_reg::type_id::create("ctrl");
        ctrl.build();
        default_map.add_reg(ctrl, 'h00, "RW");  // 偏移 0x00 → 绝对地址 0x100

        m_dim    = accel_dim_reg::type_id::create("m_dim");
        m_dim.build();
        default_map.add_reg(m_dim, 'h08, "RW");  // 偏移 0x08 → 地址 0x108

        lock_model();  // 冻结模型，不再允许修改
    endfunction

endclass
```

### RAL 适配器：连接 RAL 与 APB

RAL 内部使用通用 `uvm_reg_bus_op` 表示读写操作，
`accel_reg_adapter` 负责把它翻译成 `apb_seq_item`：

```systemverilog
class accel_reg_adapter extends uvm_reg_adapter;
    // RAL → APB：把寄存器操作转换为 APB 事务
    function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        apb_seq_item item = apb_seq_item::type_id::create("item");
        item.write = (rw.kind == UVM_WRITE);
        item.addr  = rw.addr[9:0];
        item.data  = rw.data;
        return item;
    endfunction

    // APB → RAL：从 APB 事务提取读回的数据
    function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        apb_seq_item item;
        $cast(item, bus_item);
        rw.kind   = item.write ? UVM_WRITE : UVM_READ;
        rw.addr   = item.addr;
        rw.data   = item.data;
        rw.status = item.slverr ? UVM_NOT_OK : UVM_IS_OK;
    endfunction

endclass
```

---

## 12. 第九步：Scoreboard 记分板

> **位置**：`accel_env_pkg.sv` 中的 `accel_scoreboard` 类

Scoreboard 是自动比对器。它通过 **Analysis Port** 被动接收 Monitor 广播的事务，
维护一个与 DUT 行为相同的 **软件参考模型**，然后比较。

```systemverilog
class accel_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(accel_scoreboard)

    // Analysis Implementation Port：当有事务到来时 UVM 自动调用 write()
    uvm_analysis_imp #(apb_seq_item, accel_scoreboard) mon_imp;

    // 影子寄存器（镜像 DUT 的内部状态）
    logic signed [15:0] a_shadow[$];   // 动态数组（队列）
    logic signed [15:0] b_shadow[$];
    logic signed [31:0] c_observed[$];
    int unsigned m_dim, n_dim, k_dim;

    // 每当 Monitor 广播一个事务，write() 就会被自动调用
    virtual function void write(apb_seq_item item);
        if (item.write) begin
            // 拦截写操作，更新影子状态
            if (item.addr == ADDR_AB_CTRL)    a_shadow.delete();
            if (item.addr[9:7] == 3'b000)     unpack_elements(item.data, a_shadow);
            if (item.addr == ADDR_M_DIM)       m_dim = item.data[7:0];
            // ...
        end else begin
            // 拦截读操作，收集 C 的输出
            if (item.addr[9:8] == 2'b10 && !item.addr[7])
                c_observed.push_back($signed(item.data));

            // 收集够了 M*N 个 C 值，触发比对
            if (c_observed.size() == m_dim * n_dim)
                do_check();
        end
    endfunction

    local function void do_check();
        logic signed [31:0] c_golden[];
        compute_golden(m_dim, n_dim, k_dim, c_golden);  // 计算参考值

        foreach (c_golden[i]) begin
            if (c_observed[i] !== c_golden[i])
                `uvm_error("SB_MISMATCH",
                    $sformatf("C[%0d]: got=%08x expected=%08x", i, c_observed[i], c_golden[i]))
        end
        `uvm_info("SB_PASS", "GEMM check PASSED", UVM_LOW)
    endfunction

endclass
```

### Analysis Port 的工作原理

```
Monitor.ap.write(item)
    │
    │  UVM 自动调用所有连接到此 port 的 write() 函数
    │
    ├──► Scoreboard.mon_imp.write(item)   ← uvm_analysis_imp
    └──► Coverage.analysis_export.write(item)
```

只需在 `connect_phase` 里连接一次，之后每次 Monitor 广播，两个订阅者都会自动收到。

---

## 13. 第十步：Coverage 覆盖率收集器

> **位置**：`accel_env_pkg.sv` 中的 `accel_coverage` 类

`accel_coverage` 扩展自 `uvm_subscriber`，这是一个方便类，
内置了 `analysis_export`（等价于手动写 `uvm_analysis_imp`）。

```systemverilog
class accel_coverage extends uvm_subscriber #(apb_seq_item);
    `uvm_component_utils(accel_coverage)

    // 覆盖组：APB 操作类型 × 地址区域
    covergroup apb_op_cg;
        cp_write: coverpoint cv_write {
            bins write_txn = {1'b1};
            bins read_txn  = {1'b0};
        }
        cp_region: coverpoint cv_addr[9:8] {
            bins ab_region   = {2'b00};   // A/B 数据区
            bins ctrl_region = {2'b01};   // 控制寄存器区
            bins c_region    = {2'b10};   // C 输出区
        }
        // 交叉覆盖：每种操作类型 × 每个地址区域都覆盖到
        cp_op_x_region: cross cp_write, cp_region;
    endgroup : apb_op_cg

    // 覆盖组：矩阵维度
    covergroup accel_dim_cg;
        cp_m: coverpoint cv_m {
            bins sz_1_4  = {[1 : 4]};   // 小矩阵
            bins sz_5_8  = {[5 : 8]};   // 中等矩阵
            bins sz_9_16 = {[9 :16]};   // 大矩阵
        }
        // ... cp_n, cp_k 类似 ...
    endgroup : accel_dim_cg

    // write() 在每个事务到达时被调用
    virtual function void write(apb_seq_item t);
        cv_write = t.write;
        cv_addr  = t.addr;
        apb_op_cg.sample();   // 采样覆盖组
        accel_dim_cg.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("APB op coverage: %.1f%%",
                  apb_op_cg.get_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf("Dimension coverage: %.1f%%",
                  accel_dim_cg.get_coverage()), UVM_NONE)
    endfunction

endclass
```

---

## 14. 第十一步：Environment 环境

> **位置**：`accel_env_pkg.sv` 中的 `accel_env` 类

Environment 是**顶层容器**，把所有组件组装起来，并在 `connect_phase` 中连线。

```systemverilog
class accel_env extends uvm_env;
    `uvm_component_utils(accel_env)

    // 成员：所有组件
    apb_agent                         agent;
    accel_reg_block                   reg_model;
    accel_reg_adapter                 reg_adapter;
    uvm_reg_predictor #(apb_seq_item) reg_predictor;  // RAL 镜像同步器
    accel_scoreboard                  sb;
    accel_coverage                    cov;

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 创建所有子组件
        agent         = apb_agent::type_id::create("agent", this);
        reg_model     = accel_reg_block::type_id::create("reg_model");
        reg_model.build();
        reg_adapter   = accel_reg_adapter::type_id::create("reg_adapter");
        reg_predictor = uvm_reg_predictor #(apb_seq_item)::type_id::create(
                            "reg_predictor", this);
        sb  = accel_scoreboard::type_id::create("sb",  this);
        cov = accel_coverage::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        // 1. 把 RAL 连接到 APB Sequencer（RAL 写操作会通过 Sequencer 发出事务）
        reg_model.default_map.set_sequencer(agent.seqr, reg_adapter);

        // 2. 连接 RAL 预测器（让 RAL 的镜像值跟 Monitor 看到的总线同步）
        reg_predictor.map     = reg_model.default_map;
        reg_predictor.adapter = reg_adapter;
        agent.ap.connect(reg_predictor.bus_in);

        // 3. Scoreboard 和 Coverage 都订阅 Monitor 的 analysis port
        agent.ap.connect(sb.mon_imp);
        agent.ap.connect(cov.analysis_export);
    endfunction

endclass
```

---

## 15. 第十二步：Test 测试类

> **位置**：`accel_tests_pkg.sv`

Test 是 UVM 层次树的**根节点**，由 `run_test()` 根据 `+UVM_TESTNAME` 动态创建。
所有测试都继承自 `accel_base_test`。

### `accel_base_test`：公共框架

```systemverilog
class accel_base_test extends uvm_test;
    `uvm_component_utils(accel_base_test)

    accel_env      env;
    virtual apb_if vif;
    int unsigned M = 4, N = 4, K = 4, DATA_W = 16;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 从 config_db 取 tb_top 注册的接口
        if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "No VIF")

        // 把接口推给 agent 的子组件
        uvm_config_db #(virtual apb_if)::set(this, "env.agent.*", "vif", vif);

        env = accel_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this, "test started");  // 阻止仿真提前结束
        do_test(phase);                                // 调用子类实现的场景
        phase.drop_objection(this, "test done");       // 允许仿真结束
    endtask

    // 子类重写此任务实现具体场景
    protected virtual task do_test(uvm_phase phase); endtask

    // final_phase：打印 PASS / FAIL
    function void final_phase(uvm_phase phase);
        uvm_report_server svr = uvm_report_server::get_server();
        if (svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL) > 0)
            `uvm_error("TEST_FAIL", "FAILED")
        else
            `uvm_info("TEST_PASS", "PASSED", UVM_NONE)
    endfunction

    // 复用的 GEMM 辅助任务：加载 → 计算（scoreboard 自动比对）
    protected task run_gemm(logic signed [15:0] a_flat[], b_flat[],
                            int unsigned m, n, k);
        accel_load_ab_seq  load_seq = accel_load_ab_seq::type_id::create("load_seq");
        accel_compute_seq  comp_seq = accel_compute_seq::type_id::create("comp_seq");

        load_seq.a_flat = a_flat;
        load_seq.b_flat = b_flat;
        load_seq.data_w = DATA_W;
        load_seq.start(env.agent.seqr);  // 在 APB Sequencer 上运行

        comp_seq.m = m;  comp_seq.n = n;  comp_seq.k = k;
        comp_seq.start(env.agent.seqr);
    endtask

endclass
```

### 5 个具体测试

| 测试名 | 场景 | 期望 |
|---|---|---|
| `accel_zero_test` | A=全零，B=随机 | C 必须全零 |
| `accel_identity_test` | A=单位矩阵，B=单位矩阵 | C=单位矩阵 |
| `accel_checkerboard_test` | A/B 交替 ±127 | Scoreboard 参考模型比对 |
| `accel_random_test` | 4 个确定性随机种子 | Scoreboard 比对 |
| `accel_coverage_test` | 随机维度循环，直到维度覆盖率 ≥ 95% | 覆盖率目标 |

最简单的测试只需要重写 `do_test()`：

```systemverilog
class accel_zero_test extends accel_base_test;
    `uvm_component_utils(accel_zero_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    protected virtual task do_test(uvm_phase phase);
        logic signed [15:0] a_flat[] = new[M*K];  // 全零
        logic signed [15:0] b_flat[] = new[K*N];
        foreach (b_flat[i]) b_flat[i] = $signed($urandom());
        run_gemm(a_flat, b_flat, M, N, K);
    endtask

endclass
```

---

## 16. 第十三步：tb_top 顶层模块

> **文件**：[sim/testbenches/accel_questa_uvm/tb_top.sv](../../sim/testbenches/accel_questa_uvm/tb_top.sv)

`tb_top` 是唯一不是 UVM 类的文件，是连接软件（UVM）与硬件（DUT）的桥梁：

```systemverilog
module tb_top;

    // 1. 时钟和复位
    logic clk = 0, reset_int = 1;
    always #5 clk = ~clk;   // 100 MHz

    // 2. 接口实例
    apb_if apb(.clk(clk));
    assign apb.reset_int = reset_int;

    // 3. DUT 实例（参数化，M=N=K=4 用于测试速度）
    accelerator_top #(.DATA_W(16), .ACC_W(32), .M(4), .N(4), .K(4)) dut (
        .clk_in(clk), .reset_int(reset_int),
        .PADDR(apb.PADDR), .PSEL(apb.PSEL), /* ... */
    );

    initial begin
        // 4. 把接口注册到 config_db，所有 UVM 组件都能取到
        uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top*", "vif", apb);

        // 5. 复位 20 个周期
        reset_int = 1;
        repeat(20) @(posedge clk);
        reset_int = 0;

        // 6. 启动 UVM（从 +UVM_TESTNAME 决定运行哪个测试）
        run_test();
    end

    // 7. 超时看门狗
    initial begin
        #10_000_000;
        `uvm_fatal("WATCHDOG", "Simulation timed out after 10ms")
    end

endmodule
```

---

## 17. 三大机制详解

### 1. UVM Factory（工厂）

Factory 让你在运行时**不改代码就能替换组件**。

```systemverilog
// 注册到工厂
`uvm_component_utils(my_driver)

// 通过工厂创建（而不是 new()）
my_driver drv = my_driver::type_id::create("drv", this);

// 在测试中替换实现（不改 env/agent 代码）：
my_fancy_driver::type_id::set_type_override(my_driver::get_type());
```

### 2. UVM Config DB

Config DB 是一个全局键值存储，用于在组件树中传递配置（最常见的是虚拟接口）：

```systemverilog
// 存入（tb_top）：
uvm_config_db #(virtual apb_if)::set(
    null,              // 存入者（null 表示全局）
    "uvm_test_top*",   // 路径通配符（匹配从 uvm_test_top 开始的所有组件）
    "vif",             // 键名
    apb                // 值
);

// 取出（Driver）：
virtual apb_if vif;
uvm_config_db #(virtual apb_if)::get(
    this,   // 取出者（决定搜索路径）
    "",     // 相对路径（空 = 从 this 开始往上找）
    "vif",  // 键名
    vif     // 输出目标
);
```

### 3. UVM Phases（阶段）

UVM 把仿真分为有序阶段，确保所有组件按正确顺序初始化：

```
build_phase       → 创建子组件（从上往下：Test → Env → Agent → Driver/Monitor）
connect_phase     → 连接 ports/exports（从下往上）
start_of_sim_phase→ 仿真开始前的最后准备
run_phase         → 主仿真（并发，objection 机制控制结束时机）
│  pre_reset_phase / reset_phase / post_reset_phase
│  pre_config_phase / config_phase / post_config_phase
│  pre_main_phase / main_phase / post_main_phase (← 通常在这里跑 sequence)
│  pre_shutdown_phase / shutdown_phase / post_shutdown_phase
check_phase       → Scoreboard 最终比对
report_phase      → 打印覆盖率等统计
final_phase       → 最终 PASS/FAIL 判断
```

**Objection 机制**：`run_phase` 不会自动结束，需要组件用 `raise_objection` 表示
"我还有工作要做"，`drop_objection` 表示"我完成了"。当所有 objection 都降下，
仿真推进到下一阶段。

---

## 18. 如何运行测试

### 准备：SSH 到 eikon 服务器

```bash
ssh eikon   # 需要先配置 ~/.ssh/config，参见 docs/guides/
```

### 使用封装脚本（推荐）

```bash
# 完整回归（全部 5 个测试）
bash ~/group5/sim/scripts/run_questa_uvm.sh

# 只编译
bash ~/group5/sim/scripts/run_questa_uvm.sh --target compile

# 只跑一个指定测试
bash ~/group5/sim/scripts/run_questa_uvm.sh --testname accel_random_test

# 跳过编译直接运行（已经 compile + elaborate 过）
bash ~/group5/sim/scripts/run_questa_uvm.sh --target run --no-rebuild

# 打开波形 GUI
bash ~/group5/sim/scripts/run_questa_uvm.sh --target waves --testname accel_zero_test
```

### 直接使用 Makefile

```bash
# 先进入 apptainer 容器（加载 QuestaSim 环境）
cd ~/group5/sim/testbenches/accel_questa_uvm

# 完整流程（compile + elaborate + regress）
make regress

# 单步
make compile
make elaborate
make run TESTNAME=accel_zero_test

# 清理
make clean
```

### 预期输出（全部通过）

```
=== Results: 5 passed, 0 failed ===
```

---

## 19. 如何添加新测试

以下示例：添加一个"对角矩阵"测试，A 和 B 是对角矩阵，验证对角线乘法。

### 第 1 步：在 `accel_tests_pkg.sv` 末尾添加新类

```systemverilog
// =========================================================================
// accel_diagonal_test  –  A=diag(1..4), B=diag(1..4)
// C[i][i] = i*i，非对角元素为 0
// =========================================================================
class accel_diagonal_test extends accel_base_test;
    `uvm_component_utils(accel_diagonal_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    protected virtual task do_test(uvm_phase phase);
        logic signed [15:0] a_flat[];
        logic signed [15:0] b_flat[];

        a_flat = new[M * K];
        b_flat = new[K * N];

        // 全零初始化
        foreach (a_flat[i]) a_flat[i] = '0;
        foreach (b_flat[i]) b_flat[i] = '0;

        // 设置对角元素：A[i][i] = i+1, B[i][i] = i+1
        for (int r = 0; r < M && r < K; r++)
            a_flat[r*K + r] = 16'(r + 1);
        for (int r = 0; r < K && r < N; r++)
            b_flat[r*N + r] = 16'(r + 1);

        `uvm_info(get_type_name(),
            $sformatf("Diagonal test: M=%0d N=%0d K=%0d", M, N, K), UVM_LOW)
        run_gemm(a_flat, b_flat, M, N, K);
        // Scoreboard 会自动计算参考值并比对！
    endtask

endclass
```

### 第 2 步：把新测试加入 `Makefile` 的 `TESTS` 列表

打开 `sim/testbenches/accel_questa_uvm/Makefile`，找到：

```makefile
TESTS := accel_zero_test \
         accel_identity_test \
         accel_checkerboard_test \
         accel_random_test \
         accel_coverage_test
```

改为：

```makefile
TESTS := accel_zero_test \
         accel_identity_test \
         accel_checkerboard_test \
         accel_random_test \
         accel_coverage_test \
         accel_diagonal_test
```

### 第 3 步：同步到 eikon 并运行

```bash
# 在本地同步改动
cd /home/li/repos/group5
rsync -az sim/testbenches/accel_questa_uvm/ eikon:~/group5/sim/testbenches/accel_questa_uvm/

# 在 eikon 上编译并运行新测试
ssh eikon "bash ~/group5/sim/scripts/run_questa_uvm.sh --target compile elaborate run --testname accel_diagonal_test"
```

---

## 20. 常见报错速查

| 报错信息 | 原因 | 解决方法 |
|---|---|---|
| `No virtual interface in config_db` | `tb_top` 没有调用 `uvm_config_db::set`，或路径通配符不匹配 | 检查 `tb_top.sv` 的 `set` 路径，确保包含 `"uvm_test_top*"` |
| `uvm_field_int: Undefined variable 'xxx'` | `uvm_object_utils_begin` 在字段声明**之前** | 把字段声明（`rand logic...`）移到 `uvm_object_utils_begin` 块之前 |
| `near "small": syntax error` | `small`/`medium`/`large` 是 SV 保留字，不能用作 bin 名称 | 改用 `sz_small`、`sz_1_4` 等不与 SV 关键字冲突的名称 |
| `No actual value for formal argument 'name'` | Component 类使用了 `uvm_object_utils` | 改用 `uvm_component_utils` |
| `MTI_HOME: unbound variable` | QuestaSim 模块加载后没有设置 `MTI_HOME` | 脚本里从 `vsim` 路径派生：`MTI_HOME=$(cd $(dirname $(which vsim))/.. && pwd)` |
| `TEST_FAIL: GEMM comparison failed` | RTL 计算结果与参考模型不符 | 检查矩阵维度配置、Scoreboard 的解包逻辑、RTL 的复位时序 |
| `UVM_FATAL WATCHDOG` | 仿真超过 10ms | DUT 挂死（`done` 永远不拉高）；检查 `accel_compute_seq` 的超时轮询 |
| `objection still raised` | `run_phase` 结束前没有调用 `drop_objection` | 确保每个 `raise_objection` 后都有对应的 `drop_objection` |

---

## 参考资料

- [UVM 1.2 Class Reference](https://verificationacademy.com/verification-methodology-reference/uvm/docs_1.2/html/)
- [Verification Academy UVM Cookbook](https://verificationacademy.com/cookbook/uvm)
- 本项目 pyuvm 版本文档：[docs/verification/accel_uvm_tb.md](accel_uvm_tb.md)（Python 实现，逻辑相同）
- APB 内存映射：见 [docs/interface/](../interface/) 或 `accel_env_pkg.sv` 头部注释
