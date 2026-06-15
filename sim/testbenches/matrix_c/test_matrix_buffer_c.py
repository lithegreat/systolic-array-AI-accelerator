"""cocotb tests for matrix_buffer_c (capture from array + APB read-back)."""

from __future__ import annotations

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from apb_bfm import ApbMaster
from golden import to_unsigned

M = int(os.environ.get("M", "16"))
N = int(os.environ.get("N", "16"))
ACC_W = int(os.environ.get("ACC_W", "32"))
APB_DW = 32

OFF_DATA = 0x00
OFF_CTRL = 0x80


async def apb_read_sample_error(dut, addr: int) -> tuple[int, int, int]:
    dut.PADDR.value = int(addr)
    dut.PWRITE.value = 0
    dut.PSEL.value = 1
    dut.PENABLE.value = 0
    await RisingEdge(dut.clk)
    dut.PENABLE.value = 1
    await Timer(1, unit="ns")
    data = int(dut.PRDATA.value)
    ready = int(dut.PREADY.value)
    err = int(dut.PSLVERR.value)
    await RisingEdge(dut.clk)
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    return data, ready, err


def pack_row(values, width: int) -> int:
    """Pack N accumulator values LSB-first (column 0 in the low bits)."""
    word = 0
    for j, v in enumerate(values):
        word |= to_unsigned(int(v), width) << (j * width)
    return word


async def reset_dut(dut) -> None:
    dut.rst_n.value = 0
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0
    dut.PADDR.value = 0
    dut.PWDATA.value = 0
    dut.c_in_valid.value = 0
    dut.c_row_data_in.value = 0
    dut.c_row_in.value = 0
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
    # Inject M rows (each a full N-wide beat) in arbitrary row order.
    rows = list(range(M))
    rng.shuffle(rows)
    for i in rows:
        row_vals = [
            rng.randrange(-(1 << (ACC_W - 1)), (1 << (ACC_W - 1))) for _ in range(N)
        ]
        for j in range(N):
            expected[(i, j)] = row_vals[j]
        dut.c_row_data_in.value = pack_row(row_vals, ACC_W)
        dut.c_row_in.value = i
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
    """Read CTRL register: full flag (bit 1) should be 0 initially, 1 after M row captures."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    # Before any captures: full flag must be 0.
    ctrl_val = await apb.read(OFF_CTRL)
    assert not (ctrl_val & 0x2), (
        f"capture_full should be 0 initially, got 0x{ctrl_val:x}"
    )

    # Inject exactly M rows to fill the buffer.
    for i in range(M):
        dut.c_row_data_in.value = pack_row([i * N + j for j in range(N)], ACC_W)
        dut.c_row_in.value = i
        dut.c_in_valid.value = 1
        await RisingEdge(dut.clk)
    dut.c_in_valid.value = 0
    await RisingEdge(dut.clk)

    # After M row captures: full flag must be 1.
    ctrl_val = await apb.read(OFF_CTRL)
    assert ctrl_val & 0x2, (
        f"capture_full should be 1 after {M} row captures, got 0x{ctrl_val:x}"
    )

    await apb.write(OFF_CTRL, 0x1)
    ctrl_val = await apb.read(OFF_CTRL)
    assert not (ctrl_val & 0x2), (
        f"capture_full should clear after reset, got 0x{ctrl_val:x}"
    )


@cocotb.test()
async def test_reset_pointer_via_ctrl(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    # Inject row 0 with C[0,0]=0xDEAD, remaining columns 0.
    row_vals = [0] * N
    row_vals[0] = 0xDEAD
    dut.c_row_data_in.value = pack_row(row_vals, ACC_W)
    dut.c_row_in.value = 0
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


@cocotb.test()
async def test_overread_sets_pslverr(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    for i in range(M):
        dut.c_row_data_in.value = pack_row([i * N + j for j in range(N)], ACC_W)
        dut.c_row_in.value = i
        dut.c_in_valid.value = 1
        await RisingEdge(dut.clk)
    dut.c_in_valid.value = 0
    await RisingEdge(dut.clk)

    for _ in range(M * N):
        _ = await apb.read(OFF_DATA)
    data, ready, err = await apb_read_sample_error(dut, OFF_DATA)
    assert ready == 1, "over-read should still complete"
    assert err == 1, "over-read should raise PSLVERR"
    assert data == 0, f"over-read data should be zero, got 0x{data:x}"


@cocotb.test()
async def test_extra_capture_ignored_after_full(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    first_row = [0x100 + j for j in range(N)]
    for i in range(M):
        row = first_row if i == 0 else [i * N + j for j in range(N)]
        dut.c_row_data_in.value = pack_row(row, ACC_W)
        dut.c_row_in.value = i
        dut.c_in_valid.value = 1
        await RisingEdge(dut.clk)

    dut.c_row_data_in.value = pack_row([0xBAD0 + j for j in range(N)], ACC_W)
    dut.c_row_in.value = 0
    dut.c_in_valid.value = 1
    await RisingEdge(dut.clk)
    dut.c_in_valid.value = 0

    for expected in first_row:
        got = await apb.read(OFF_DATA)
        assert got == expected, f"extra capture overwrote full buffer: got 0x{got:x}"
