"""cocotb tests for control_unit (APB regfile + compute FSM)."""

from __future__ import annotations

import os

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

CTRL_START = 1 << 0
CTRL_SOFTRST = 1 << 1
STATUS_BUSY = 1 << 0
STATUS_DONE = 1 << 1


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
    assert (await apb.read(REG_M_DIM)) == 4
    assert (await apb.read(REG_N_DIM)) == 4
    assert (await apb.read(REG_K_DIM)) == 4

    await apb.write(REG_M_DIM, 8)
    await apb.write(REG_N_DIM, 16)
    await apb.write(REG_K_DIM, 32)
    assert (await apb.read(REG_M_DIM)) == 8
    assert (await apb.read(REG_N_DIM)) == 16
    assert (await apb.read(REG_K_DIM)) == 32

    await apb.write(REG_INT_EN, 0x1)
    assert (await apb.read(REG_INT_EN)) == 0x1


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
