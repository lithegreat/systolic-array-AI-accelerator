# pyuvm Testbench for `accelerator_top`

> **Status**: implemented and passing (4/4 tests green on Verilator 5.046).
> **Simulator**: Verilator with `--timing` (the default for all `sim/` testbenches).
> **Framework**: [pyuvm](https://pyuvm.github.io/pyuvm/) 4.0.1 on top of cocotb 2.0.

---

## 1. Purpose

The UVM testbench at `sim/testbenches/accel_uvm/` verifies the full
`accelerator_top` APB interface at the transaction level using the Universal
Verification Methodology (UVM) in Python.  It complements the existing plain-cocotb
testbench (`sim/testbenches/top/`) by adding:

- A reusable **APB UVC** (sequence-item → driver → monitor → sequencer → agent).
- A **Register Abstraction Layer (RAL)** model of the control-unit register map.
- Reusable **sequences** that load matrices, trigger compute, and drain results.
- A **virtual sequencer** for coordinating multi-step scenarios.
- Constrained-random stimulus with automatic golden-model comparison.

---

## 2. Directory layout

```
sim/testbenches/accel_uvm/
├── Makefile                         # entry point: SIM=verilator MODULE=tests.*
└── accel_uvm/                       # Python package – top on PYTHONPATH
    ├── apb/                         # APB UVC
    │   ├── seq_item.py              # ApbSeqItem  (op, addr, data, slverr)
    │   ├── driver.py                # ApbDriver   (SETUP → ACCESS → PREADY)
    │   ├── monitor.py               # ApbMonitor  (samples completed transactions)
    │   ├── sequencer.py             # ApbSequencer
    │   ├── agent.py                 # ApbAgent    (driver + monitor + sequencer)
    │   └── config.py                # ApbConfig   (vif, addr/data widths)
    ├── register_model/              # RAL (Register Abstraction Layer)
    │   ├── accel_regs.py            # uvm_reg subclasses (Ctrl, Status, MDim, …)
    │   ├── accel_reg_block.py       # AccelRegBlock – uvm_reg_block, base 0x100
    │   └── accel_reg_adapter.py     # AccelRegAdapter – bridges RAL ↔ ApbSeqItem
    ├── sequences/                   # Reusable test sequences
    │   ├── accel_base_seq.py        # do_apb_write() / do_apb_read() helpers
    │   ├── accel_load_ab_seq.py     # AccelLoadABSeq  – stream A and B over APB
    │   ├── accel_compute_seq.py     # AccelComputeSeq – set dims, start, poll done
    │   └── accel_read_c_seq.py      # AccelReadCSeq   – drain C output buffer
    ├── config.py                    # AccelConfig  (vif handle + M/N/K/DATA_W/ACC_W)
    ├── env.py                       # AccelEnv     (agent + RAL + virtual sequencer)
    ├── vsequencer.py                # AccelVSequencer
    └── base_test.py                 # AccelBaseTest (clock 100 MHz, reset, env)
tests/
    ├── directed_test.py             # AccelZeroTest, AccelIdentityTest, AccelCheckerboardTest
    └── random_test.py               # AccelRandomTest (4 random seeds)
```

---

## 3. UVM component hierarchy

```
uvm_test_top  (AccelZeroTest / AccelRandomTest / …)
└── AccelEnv
    ├── ApbAgent
    │   ├── ApbSequencer  ←── sequences send items here
    │   ├── ApbDriver     ←── drives PADDR/PSEL/PENABLE/PWRITE/PWDATA
    │   └── ApbMonitor    ──► analysis port (observed transactions)
    ├── AccelVSequencer   (apb_seqr handle for virtual sequences)
    └── AccelRegBlock     (RAL: ctrl, status, m_dim, n_dim, k_dim, int_en, int_stat)
         └── AccelRegAdapter  (reg ↔ ApbSeqItem bridge)
```

---

## 4. Register model (RAL)

The RAL covers the **control-unit register region** (`PADDR[9:8] = 2'b01`, absolute
base `0x100`):

| Register   | Offset | Key fields |
|------------|--------|------------|
| `ctrl`     | `0x100` | `start` [0] (SC), `softrst` [1] (SC) |
| `status`   | `0x104` | `busy` [0] (RO), `done` [1] (W1C) |
| `m_dim`    | `0x108` | rows of A / C |
| `n_dim`    | `0x10C` | columns of B / C |
| `int_en`   | `0x110` | `done_en` [0] |
| `int_stat` | `0x114` | `done_irq` [0] (W1C) |
| `k_dim`    | `0x118` | reduction depth |

The streaming FIFO ports (A data @ `0x000`, B data @ `0x040`, C data @ `0x200`) are
accessed directly in sequences via `do_apb_write` / `do_apb_read` helpers — they do
not fit the RAL paradigm.

---

## 5. Test descriptions

| Test class | Module | Scenario |
|------------|--------|----------|
| `AccelZeroTest` | `directed_test` | A = 0, B = random → C must be all-zeros |
| `AccelIdentityTest` | `directed_test` | A = I, B = I → C = I (square tile) |
| `AccelCheckerboardTest` | `directed_test` | Alternating ±127 patterns; compares against Python golden |
| `AccelRandomTest` | `random_test` | 4 random seeds (0x1234, 0xACCE, 0xBEEF, 0xC0DE); all seeds must match `matmul_ref()` |

All tests use the shared `golden.matmul_ref()` helper (from `sim/testbenches/common/golden.py`)
which replicates the RTL accumulator's signed 32-bit wrap-around arithmetic.

---

## 6. Running the testbench

### Prerequisites

```bash
# One-time venv setup (from repo root)
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements/sim.txt   # includes pyuvm>=4.0.1
```

### Run all UVM tests

```bash
cd sim/testbenches/accel_uvm
make
```

### Override tile dimensions

```bash
make M=8 N=8 K=8
```

### Run via the top-level pytest runner

```bash
# from repo root
source .venv/bin/activate
pytest sim/test_runner.py -k accel_uvm -v
```

---

## 7. Writing new tests

1. Create a new file under `tests/`.
2. Import `AccelBaseTest` and the sequences you need.
3. Decorate your class with `@pyuvm.test()`.
4. Follow the `raise_objection / await super().run_phase() / … / drop_objection` pattern.

```python
import pyuvm
from accel_uvm.base_test import AccelBaseTest
from accel_uvm.sequences import AccelLoadABSeq, AccelComputeSeq, AccelReadCSeq

@pyuvm.test()
class MyNewTest(AccelBaseTest):
    async def run_phase(self):
        self.raise_objection()
        await super().run_phase()          # starts clock and reset

        seqr = self.env.apb_agent.sequencer

        load = AccelLoadABSeq.create("load")
        load.a_matrix = my_a
        load.b_matrix = my_b
        await load.start(seqr)

        compute = AccelComputeSeq.create("compute")
        await compute.start(seqr)

        readout = AccelReadCSeq.create("readout")
        await readout.start(seqr)

        assert ...  # compare readout.c_matrix with golden

        self.drop_objection()
```

5. Add the module to the `MODULE` list in `sim/testbenches/accel_uvm/Makefile`.

---

## 8. Design decisions

| Decision | Rationale |
|----------|-----------|
| **Verilator** instead of Icarus | Icarus is not installed; Verilator 5.x + `--timing` supports all required cocotb/pyuvm features |
| **Standalone APB UVC** | Avoids coupling to `Didactic-SoC/verification/student_ss/`; the student-SS UVC targets Icarus and has many GPIO-specific dependencies |
| **RAL only for control regs** | Streaming FIFO ports are not addressable registers and are better expressed as sequences |
| **Sequences on APB sequencer directly** | Keeps the testbench simple; virtual sequences coordinate sub-sequences without adding indirection for single-agent scenarios |
