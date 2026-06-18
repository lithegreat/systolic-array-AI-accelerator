"""cocotb tests for control_unit (APB regfile + compute FSM)."""

from __future__ import annotations


import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from apb_bfm import ApbMaster

# Register offsets must match accel_pkg.sv
REG_CTRL = 0x00
REG_STATUS = 0x04
REG_M_DIM = 0x08
REG_N_DIM = 0x0C
REG_INT_EN = 0x10
REG_INT_STAT = 0x14
REG_K_DIM = 0x18
REG_BUILD_INFO = 0x1C
REG_HW_STATUS = 0x20
REG_PERF_CTRL = 0x24
REG_PERF_CYCLES = 0x28
REG_PERF_APB_WRITES = 0x2C
REG_PERF_APB_READS = 0x30
REG_PERF_IN_STALLS = 0x34
REG_PERF_OUT_STALLS = 0x38

CTRL_START = 1 << 0
CTRL_SOFTRST = 1 << 1
STATUS_BUSY = 1 << 0
STATUS_DONE = 1 << 1
PERF_CLEAR = 1 << 0
HW_STATUS_IN_STALL_SEEN = 1 << 1
HW_STATUS_OUT_STALL_SEEN = 1 << 2
HW_STATUS_COUNTER_OVERFLOW = 1 << 3


class CtrlApb(ApbMaster):
    """ApbMaster variant for control_unit (uses clk_in instead of clk)."""

    def __init__(self, dut) -> None:
        # Avoid base class accessing dut.clk; we'll override.
        self.dut = dut
        self.p = ""
        for n in ("PSEL", "PENABLE", "PWRITE", "PADDR", "PWDATA"):
            getattr(self.dut, n).value = 0

    async def _edge(self) -> None:
        await RisingEdge(self.dut.clk_in)

    async def write(self, addr, data):  # type: ignore[override]
        self.dut.PADDR.value = int(addr)
        self.dut.PWDATA.value = int(data)
        self.dut.PWRITE.value = 1
        self.dut.PSEL.value = 1
        self.dut.PENABLE.value = 0
        await self._edge()
        self.dut.PENABLE.value = 1
        await self._edge()
        self.dut.PSEL.value = 0
        self.dut.PENABLE.value = 0
        self.dut.PWRITE.value = 0

    async def read(self, addr):  # type: ignore[override]
        self.dut.PADDR.value = int(addr)
        self.dut.PWRITE.value = 0
        self.dut.PSEL.value = 1
        self.dut.PENABLE.value = 0
        await self._edge()
        self.dut.PENABLE.value = 1
        await Timer(1, unit="ns")
        rdata = int(self.dut.PRDATA.value)
        await self._edge()
        self.dut.PSEL.value = 0
        self.dut.PENABLE.value = 0
        return rdata


async def reset_dut(dut) -> None:
    dut.reset_int.value = 1
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0
    dut.PADDR.value = 0
    dut.PWDATA.value = 0
    dut.array_done.value = 0
    dut.perf_apb_write.value = 0
    dut.perf_apb_read.value = 0
    dut.perf_input_stall.value = 0
    dut.perf_output_stall.value = 0
    dut.irq_en_4.value = 1
    dut.ss_ctrl_4.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk_in)
    dut.reset_int.value = 0
    await RisingEdge(dut.clk_in)


@cocotb.test()
async def test_register_rw(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    # Defaults match accel_pkg defaults.
    assert (await apb.read(REG_M_DIM)) == 16
    assert (await apb.read(REG_N_DIM)) == 16
    assert (await apb.read(REG_K_DIM)) == 16
    assert (await apb.read(REG_BUILD_INFO)) == 0x08101010

    await apb.write(REG_M_DIM, 8)
    await apb.write(REG_N_DIM, 16)
    await apb.write(REG_K_DIM, 32)
    assert (await apb.read(REG_M_DIM)) == 8
    assert (await apb.read(REG_N_DIM)) == 16
    assert (await apb.read(REG_K_DIM)) == 16

    await apb.write(REG_INT_EN, 0x1)
    assert (await apb.read(REG_INT_EN)) == 0x1

    # Runtime dimensions are clamped into 1..physical when idle.
    await apb.write(REG_M_DIM, 0)
    await apb.write(REG_N_DIM, 999)
    await apb.write(REG_K_DIM, 0)
    assert (await apb.read(REG_M_DIM)) == 1
    assert (await apb.read(REG_N_DIM)) == 16
    assert (await apb.read(REG_K_DIM)) == 1


@cocotb.test()
async def test_start_busy_done_irq(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    await apb.write(REG_INT_EN, 0x1)

    # Pulse start.
    await apb.write(REG_CTRL, CTRL_START)

    # Should observe array_start asserted within a couple of cycles.
    saw_start = False
    for _ in range(5):
        await RisingEdge(dut.clk_in)
        if int(dut.array_start.value):
            saw_start = True
    assert saw_start, "array_start was never asserted"

    # Status should be busy.
    status = await apb.read(REG_STATUS)
    assert status & STATUS_BUSY, f"expected BUSY, got 0x{status:x}"

    # Acknowledge with array_done.
    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0

    # Wait for FSM to settle.
    for _ in range(5):
        await RisingEdge(dut.clk_in)

    status = await apb.read(REG_STATUS)
    assert status & STATUS_DONE, f"expected DONE, got 0x{status:x}"
    assert not (status & STATUS_BUSY), f"BUSY should be cleared, got 0x{status:x}"

    # IRQ should be high.
    assert int(dut.irq_4.value) == 1, "irq_4 should be set"

    # Clear via INT_STAT W1C.
    await apb.write(REG_INT_STAT, 0x1)
    await RisingEdge(dut.clk_in)
    assert int(dut.irq_4.value) == 0, "irq_4 should clear after W1C"


@cocotb.test()
async def test_soft_reset(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    # Start a compute and immediately soft-reset.
    await apb.write(REG_CTRL, CTRL_START)
    await RisingEdge(dut.clk_in)
    await apb.write(REG_CTRL, CTRL_SOFTRST)
    for _ in range(5):
        await RisingEdge(dut.clk_in)

    status = await apb.read(REG_STATUS)
    assert not (status & STATUS_BUSY), f"soft reset should clear BUSY: 0x{status:x}"
    assert not (status & STATUS_DONE), f"soft reset should clear DONE: 0x{status:x}"


@cocotb.test()
async def test_start_while_busy_is_ignored(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    await apb.write(REG_CTRL, CTRL_START)
    for _ in range(3):
        await RisingEdge(dut.clk_in)

    status = await apb.read(REG_STATUS)
    assert status & STATUS_BUSY, f"expected BUSY before second start, got 0x{status:x}"

    await apb.write(REG_CTRL, CTRL_START)
    saw_second_start = False
    for _ in range(5):
        await RisingEdge(dut.clk_in)
        saw_second_start |= bool(int(dut.array_start.value))
    assert not saw_second_start, "CTRL.start while BUSY should not re-issue array_start"

    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0


@cocotb.test()
async def test_dimension_writes_ignored_while_busy(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    await apb.write(REG_M_DIM, 4)
    await apb.write(REG_N_DIM, 5)
    await apb.write(REG_K_DIM, 6)
    await apb.write(REG_CTRL, CTRL_START)
    for _ in range(3):
        await RisingEdge(dut.clk_in)
    await apb.write(REG_M_DIM, 7)
    await apb.write(REG_N_DIM, 8)
    await apb.write(REG_K_DIM, 9)
    assert (await apb.read(REG_M_DIM)) == 4
    assert (await apb.read(REG_N_DIM)) == 5
    assert (await apb.read(REG_K_DIM)) == 6

    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0


@cocotb.test()
async def test_status_done_w1c(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    await apb.write(REG_CTRL, CTRL_START)
    for _ in range(3):
        await RisingEdge(dut.clk_in)
    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk_in)

    status = await apb.read(REG_STATUS)
    assert status & STATUS_DONE, f"expected DONE before W1C, got 0x{status:x}"
    await apb.write(REG_STATUS, STATUS_DONE)
    status = await apb.read(REG_STATUS)
    assert not (status & STATUS_DONE), f"DONE should clear after W1C, got 0x{status:x}"


@cocotb.test()
async def test_read_ctrl_and_int_stat_registers(dut) -> None:
    """Read REG_CTRL, REG_INT_STAT, and an unmapped address to hit the read-mux default."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    # Read REG_CTRL (should be 0 after reset, start bit self-clears).
    ctrl_val = await apb.read(REG_CTRL)
    assert ctrl_val == 0, f"REG_CTRL after reset should be 0, got 0x{ctrl_val:x}"

    # Run a complete start->done cycle to set INT_STAT.
    await apb.write(REG_INT_EN, 0x1)
    await apb.write(REG_CTRL, CTRL_START)
    for _ in range(5):
        await RisingEdge(dut.clk_in)
    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_in)

    # Read REG_INT_STAT: INT_DONE_BIT should be set.
    int_stat = await apb.read(REG_INT_STAT)
    assert int_stat & 0x1, (
        f"REG_INT_STAT should have bit 0 set after done, got 0x{int_stat:x}"
    )

    # Read an unmapped address (e.g. 0xFC) → default branch returns 0.
    unmapped = await apb.read(0xFC)
    assert unmapped == 0, f"unmapped read should return 0, got 0x{unmapped:x}"


@cocotb.test()
async def test_perf_and_status_registers(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    await apb.write(REG_PERF_CTRL, PERF_CLEAR)
    assert (await apb.read(REG_PERF_CYCLES)) == 0
    assert (await apb.read(REG_PERF_APB_WRITES)) == 0
    assert (await apb.read(REG_PERF_APB_READS)) == 0

    dut.perf_apb_write.value = 1
    await RisingEdge(dut.clk_in)
    dut.perf_apb_write.value = 0
    dut.perf_apb_read.value = 1
    await RisingEdge(dut.clk_in)
    dut.perf_apb_read.value = 0

    assert (await apb.read(REG_PERF_APB_WRITES)) == 1
    assert (await apb.read(REG_PERF_APB_READS)) == 1

    await apb.write(REG_CTRL, CTRL_START)
    for _ in range(3):
        await RisingEdge(dut.clk_in)

    dut.perf_input_stall.value = 1
    await RisingEdge(dut.clk_in)
    dut.perf_input_stall.value = 0

    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk_in)

    cycles = await apb.read(REG_PERF_CYCLES)
    in_stalls = await apb.read(REG_PERF_IN_STALLS)
    out_stalls = await apb.read(REG_PERF_OUT_STALLS)
    hw_status = await apb.read(REG_HW_STATUS)

    assert cycles > 0, "PERF_CYCLES should count the active compute window"
    assert in_stalls == 1, f"expected one input stall, got {in_stalls}"
    assert out_stalls == 0, f"expected no output stalls, got {out_stalls}"
    assert hw_status & HW_STATUS_IN_STALL_SEEN, "input-stall sticky bit should be set"
    assert not (hw_status & HW_STATUS_OUT_STALL_SEEN), (
        "output-stall sticky bit should be clear"
    )
    assert not (hw_status & HW_STATUS_COUNTER_OVERFLOW), (
        "overflow sticky bit should be clear"
    )


@cocotb.test()
async def test_start_while_busy(dut) -> None:
    """Writing CTRL.start while the FSM is in C_BUSY must be ignored."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    # Kick off a first compute.
    await apb.write(REG_CTRL, CTRL_START)

    # Wait a couple of cycles so the FSM leaves C_ISSUE and enters C_BUSY.
    for _ in range(5):
        await RisingEdge(dut.clk_in)

    status = await apb.read(REG_STATUS)
    assert status & STATUS_BUSY, f"expected BUSY, got 0x{status:x}"

    # Try to issue a *second* start while still BUSY — it should be ignored.
    await apb.write(REG_CTRL, CTRL_START)

    # Complete the first compute via array_done.
    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_in)

    # The FSM should land in DONE exactly once (not start a second compute).
    status = await apb.read(REG_STATUS)
    assert status & STATUS_DONE, f"expected DONE after first compute, got 0x{status:x}"
    assert not (status & STATUS_BUSY), f"BUSY should be clear, got 0x{status:x}"


@cocotb.test()
async def test_irq_masked_when_disabled(dut) -> None:
    """irq_4 must stay low when INT_EN[0]=0 or irq_en_4=0, even after done."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    # --- Case 1: INT_EN disabled, irq_en_4 enabled ---
    dut.irq_en_4.value = 1
    await apb.write(REG_INT_EN, 0x0)  # done-interrupt enable OFF

    await apb.write(REG_CTRL, CTRL_START)
    for _ in range(5):
        await RisingEdge(dut.clk_in)
    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_in)

    assert int(dut.irq_4.value) == 0, "irq_4 should be 0 when INT_EN[0]=0"

    # --- Case 2: INT_EN enabled, irq_en_4 disabled ---
    # Soft-reset to get back to IDLE cleanly.
    await apb.write(REG_CTRL, CTRL_SOFTRST)
    for _ in range(5):
        await RisingEdge(dut.clk_in)

    dut.irq_en_4.value = 0
    await apb.write(REG_INT_EN, 0x1)  # done-interrupt enable ON

    await apb.write(REG_CTRL, CTRL_START)
    for _ in range(5):
        await RisingEdge(dut.clk_in)
    dut.array_done.value = 1
    await RisingEdge(dut.clk_in)
    dut.array_done.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_in)

    assert int(dut.irq_4.value) == 0, "irq_4 should be 0 when irq_en_4=0"


@cocotb.test()
async def test_back_to_back_compute(dut) -> None:
    """Two consecutive start→done cycles must both complete correctly."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_dut(dut)
    apb = CtrlApb(dut)

    for iteration in range(2):
        # Clear any leftover DONE status from the previous iteration.
        await apb.write(REG_STATUS, STATUS_DONE)

        await apb.write(REG_CTRL, CTRL_START)
        # Wait for array_start.
        for _ in range(5):
            await RisingEdge(dut.clk_in)

        status = await apb.read(REG_STATUS)
        assert status & STATUS_BUSY, (
            f"iter {iteration}: expected BUSY, got 0x{status:x}"
        )

        # Signal completion.
        dut.array_done.value = 1
        await RisingEdge(dut.clk_in)
        dut.array_done.value = 0
        for _ in range(5):
            await RisingEdge(dut.clk_in)

        status = await apb.read(REG_STATUS)
        assert status & STATUS_DONE, (
            f"iter {iteration}: expected DONE, got 0x{status:x}"
        )
        assert not (status & STATUS_BUSY), (
            f"iter {iteration}: BUSY should be clear, got 0x{status:x}"
        )
