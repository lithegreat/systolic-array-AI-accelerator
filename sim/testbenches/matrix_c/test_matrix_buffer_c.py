"""cocotb tests for matrix_buffer_c (capture from array + APB read-back)."""

from __future__ import annotations

import os
import random

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from apb_bfm import ApbMaster
from golden import to_signed, to_unsigned

M = int(os.environ.get("M", "16"))
N = int(os.environ.get("N", "16"))
ACC_W = int(os.environ.get("ACC_W", "32"))
APB_DW = 32

OFF_DATA = 0x00
OFF_CTRL = 0x80


async def reset_dut(dut) -> None:
    dut.rst_n.value = 0
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0
    dut.PADDR.value = 0
    dut.PWDATA.value = 0
    dut.c_in_valid.value = 0
    dut.c_data_in.value = 0
    dut.c_row_in.value = 0
    dut.c_col_in.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_capture_then_readout(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    rng = random.Random(0xFEED)
    expected = {}
    # Inject MxN values in arbitrary order.
    coords = [(i, j) for i in range(M) for j in range(N)]
    rng.shuffle(coords)
    for i, j in coords:
        v = rng.randrange(-(1 << (ACC_W - 1)), (1 << (ACC_W - 1)))
        expected[(i, j)] = v
        dut.c_data_in.value = to_unsigned(v, ACC_W)
        dut.c_row_in.value = i
        dut.c_col_in.value = j
        dut.c_in_valid.value = 1
        await RisingEdge(dut.clk)
    dut.c_in_valid.value = 0
    await RisingEdge(dut.clk)

    # Read back row-major.
    for i in range(M):
        for j in range(N):
            word = await apb.read(OFF_DATA)
            ref = expected[(i, j)]
            ref_u = to_unsigned(ref, ACC_W) & ((1 << APB_DW) - 1)
            assert word == ref_u, f"C[{i},{j}] dut=0x{word:x} ref=0x{ref_u:x}"


@cocotb.test()
async def test_ctrl_read_capture_full_flag(dut) -> None:
    """Read CTRL register: full flag (bit 1) should be 0 initially, 1 after M*N captures."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    # Before any captures: full flag must be 0.
    ctrl_val = await apb.read(OFF_CTRL)
    assert not (ctrl_val & 0x2), f"capture_full should be 0 initially, got 0x{ctrl_val:x}"

    # Inject exactly M*N values to fill the buffer.
    for i in range(M):
        for j in range(N):
            dut.c_data_in.value = i * N + j
            dut.c_row_in.value = i
            dut.c_col_in.value = j
            dut.c_in_valid.value = 1
            await RisingEdge(dut.clk)
    dut.c_in_valid.value = 0
    await RisingEdge(dut.clk)

    # After M*N captures: full flag must be 1.
    ctrl_val = await apb.read(OFF_CTRL)
    assert ctrl_val & 0x2, f"capture_full should be 1 after {M*N} captures, got 0x{ctrl_val:x}"


@cocotb.test()
async def test_reset_pointer_via_ctrl(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    # Inject a single known value at C[0,0].
    dut.c_data_in.value = 0xDEAD
    dut.c_row_in.value = 0
    dut.c_col_in.value = 0
    dut.c_in_valid.value = 1
    await RisingEdge(dut.clk)
    dut.c_in_valid.value = 0
    await RisingEdge(dut.clk)

    # Read once, advancing the pointer.
    w0 = await apb.read(OFF_DATA)
    assert w0 == 0xDEAD
    w1 = await apb.read(OFF_DATA)
    assert w1 == 0  # pointer moved to C[0,1] which is 0

    # Reset pointer.
    await apb.write(OFF_CTRL, 0x1)
    w0b = await apb.read(OFF_DATA)
    assert w0b == 0xDEAD, f"after CTRL reset, expected 0xDEAD got 0x{w0b:x}"
