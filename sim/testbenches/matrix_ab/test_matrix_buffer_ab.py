"""cocotb tests for matrix_buffer_ab (APB write + streaming read)."""

from __future__ import annotations

import os
import random

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from apb_bfm import ApbMaster
from golden import pack_words, random_matrix, to_signed

M = int(os.environ.get("M", "16"))
N = int(os.environ.get("N", "16"))
K = int(os.environ.get("K", "16"))
DATA_W = int(os.environ.get("DATA_W", "8"))
APB_DW = 32
EPW = APB_DW // DATA_W

OFF_A = 0x00
OFF_B = 0x40
OFF_CTRL = 0x80


async def reset_dut(dut) -> None:
    dut.rst_n.value = 0
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0
    dut.PADDR.value = 0
    dut.PWDATA.value = 0
    dut.mat_start.value = 0
    dut.sys_ready.value = 0
    dut.cfg_m_dim.value = M
    dut.cfg_n_dim.value = N
    dut.cfg_k_dim.value = K
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def write_matrix(apb: ApbMaster, base: int, flat) -> None:
    for word in pack_words(flat, DATA_W, APB_DW):
        await apb.write(base, word)


async def apb_write_sample_error(dut, addr: int, data: int) -> tuple[int, int]:
    dut.PADDR.value = int(addr)
    dut.PWDATA.value = int(data) & 0xFFFFFFFF
    dut.PWRITE.value = 1
    dut.PSEL.value = 1
    dut.PENABLE.value = 0
    await RisingEdge(dut.clk)
    dut.PENABLE.value = 1
    await Timer(1, unit="ns")
    ready = int(dut.PREADY.value)
    err = int(dut.PSLVERR.value)
    await RisingEdge(dut.clk)
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0
    return ready, err


def lane(bits: int, idx: int, width: int) -> int:
    return to_signed((bits >> (idx * width)) & ((1 << width) - 1), width)


@cocotb.test()
async def test_apb_write_then_stream(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    rng = random.Random(0xCAFE)
    a = random_matrix(M, K, DATA_W, rng)
    b = random_matrix(K, N, DATA_W, rng)

    await write_matrix(apb, OFF_A, list(a.flatten()))
    await write_matrix(apb, OFF_B, list(b.flatten()))

    # Trigger streaming.
    dut.sys_ready.value = 1
    dut.mat_start.value = 1
    await RisingEdge(dut.clk)
    dut.mat_start.value = 0

    # Collect K beats.
    captured = []
    cycles = 0
    while len(captured) < K:
        cycles += 1
        assert cycles < 100, "stream timeout"
        await Timer(1, unit="ns")
        if int(dut.mat_valid.value) and int(dut.sys_ready.value):
            a_bus = int(dut.a_col.value)
            b_bus = int(dut.b_row.value)
            a_vec = [lane(a_bus, i, DATA_W) for i in range(M)]
            b_vec = [lane(b_bus, j, DATA_W) for j in range(N)]
            captured.append((a_vec, b_vec))
        await RisingEdge(dut.clk)

    dut.sys_ready.value = 0

    # Compare.
    for k, (a_vec, b_vec) in enumerate(captured):
        for i in range(M):
            assert a_vec[i] == int(a[i, k]), (
                f"a beat {k} lane {i}: dut={a_vec[i]} ref={a[i, k]}"
            )
        for j in range(N):
            assert b_vec[j] == int(b[k, j]), (
                f"b beat {k} lane {j}: dut={b_vec[j]} ref={b[k, j]}"
            )


@cocotb.test()
async def test_ctrl_reset_pointer(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    # Write garbage, then reset, then write proper data; only the proper data
    # should be readable.
    await write_matrix(apb, OFF_A, [0x1111] * (M * K))
    # Reset pointers via CTRL bit 0.
    await apb.write(OFF_CTRL, 0x1)

    rng = random.Random(0x5EED)
    a = random_matrix(M, K, DATA_W, rng)
    b = random_matrix(K, N, DATA_W, rng)
    await write_matrix(apb, OFF_A, list(a.flatten()))
    await write_matrix(apb, OFF_B, list(b.flatten()))

    dut.sys_ready.value = 1
    dut.mat_start.value = 1
    await RisingEdge(dut.clk)
    dut.mat_start.value = 0

    captured = []
    while len(captured) < K:
        await Timer(1, unit="ns")
        if int(dut.mat_valid.value) and int(dut.sys_ready.value):
            captured.append(int(dut.a_col.value))
        await RisingEdge(dut.clk)

    for k, bus in enumerate(captured):
        for i in range(M):
            assert lane(bus, i, DATA_W) == int(a[i, k])


@cocotb.test()
async def test_ctrl_read_full_flags(dut) -> None:
    """Read CTRL register: A-full (bit 1) and B-full (bit 2) after filling both matrices."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    # Before loading: both flags must be 0.
    ctrl_val = await apb.read(OFF_CTRL)
    assert not (ctrl_val & 0x6), f"full flags should be 0 initially, got 0x{ctrl_val:x}"

    # Fill A (M*K elements) and B (K*N elements).
    rng = random.Random(0xF011)
    a = random_matrix(M, K, DATA_W, rng)
    b = random_matrix(K, N, DATA_W, rng)
    await write_matrix(apb, OFF_A, list(a.flatten()))
    await write_matrix(apb, OFF_B, list(b.flatten()))

    # After filling: A-full (bit 1) and B-full (bit 2) must both be set.
    ctrl_val = await apb.read(OFF_CTRL)
    assert ctrl_val & 0x2, f"A-full flag (bit 1) should be set, got 0x{ctrl_val:x}"
    assert ctrl_val & 0x4, f"B-full flag (bit 2) should be set, got 0x{ctrl_val:x}"

    await apb.write(OFF_CTRL, 0x1)
    ctrl_val = await apb.read(OFF_CTRL)
    assert not (ctrl_val & 0x6), (
        f"full flags should clear after pointer reset, got 0x{ctrl_val:x}"
    )


@cocotb.test()
async def test_write_overrun_sets_pslverr(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    await write_matrix(apb, OFF_A, [1] * (M * K))
    ready, err = await apb_write_sample_error(dut, OFF_A, 0)
    assert ready == 1, "overrun write should still complete"
    assert err == 1, "A overrun write should raise PSLVERR"

    await apb.write(OFF_CTRL, 0x1)
    await write_matrix(apb, OFF_B, [1] * (K * N))
    ready, err = await apb_write_sample_error(dut, OFF_B, 0)
    assert ready == 1, "overrun write should still complete"
    assert err == 1, "B overrun write should raise PSLVERR"


@cocotb.test()
async def test_overwrite_a_past_full(dut) -> None:
    """Writing to A bank beyond M*K elements must assert PSLVERR."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    # Fill A exactly to capacity.
    rng = random.Random(0xAAAA)
    a = random_matrix(M, K, DATA_W, rng)
    await write_matrix(apb, OFF_A, list(a.flatten()))

    # Confirm A-full is set.
    ctrl_val = await apb.read(OFF_CTRL)
    assert ctrl_val & 0x2, f"A-full should be set, got 0x{ctrl_val:x}"

    # One more APB write to A — should trigger PSLVERR.
    dut.PADDR.value = int(OFF_A)
    dut.PWDATA.value = 0xDEAD
    dut.PWRITE.value = 1
    dut.PSEL.value = 1
    dut.PENABLE.value = 0
    await RisingEdge(dut.clk)
    dut.PENABLE.value = 1
    await Timer(1, unit="ns")
    assert int(dut.PSLVERR.value) == 1, "PSLVERR should be 1 on A bank overflow"
    await RisingEdge(dut.clk)
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0


@cocotb.test()
async def test_overwrite_b_past_full(dut) -> None:
    """Writing to B bank beyond K*N elements must assert PSLVERR."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    # Fill B exactly to capacity.
    rng = random.Random(0xBBBB)
    b = random_matrix(K, N, DATA_W, rng)
    await write_matrix(apb, OFF_B, list(b.flatten()))

    # Confirm B-full is set.
    ctrl_val = await apb.read(OFF_CTRL)
    assert ctrl_val & 0x4, f"B-full should be set, got 0x{ctrl_val:x}"

    # One more APB write to B — should trigger PSLVERR.
    dut.PADDR.value = int(OFF_B)
    dut.PWDATA.value = 0xBEEF
    dut.PWRITE.value = 1
    dut.PSEL.value = 1
    dut.PENABLE.value = 0
    await RisingEdge(dut.clk)
    dut.PENABLE.value = 1
    await Timer(1, unit="ns")
    assert int(dut.PSLVERR.value) == 1, "PSLVERR should be 1 on B bank overflow"
    await RisingEdge(dut.clk)
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0


@cocotb.test()
async def test_stream_holds_under_backpressure(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    a = np.arange(M * K, dtype=np.int64).reshape(M, K) % (1 << (DATA_W - 1))
    b = (np.arange(K * N, dtype=np.int64).reshape(K, N) + 1) % (1 << (DATA_W - 1))
    await write_matrix(apb, OFF_A, list(a.flatten()))
    await write_matrix(apb, OFF_B, list(b.flatten()))

    dut.sys_ready.value = 0
    dut.mat_start.value = 1
    await RisingEdge(dut.clk)
    dut.mat_start.value = 0

    await Timer(1, unit="ns")
    assert int(dut.mat_valid.value) == 1, (
        "mat_valid should assert even while back-pressured"
    )
    first_a = int(dut.a_col.value)
    first_b = int(dut.b_row.value)
    for _ in range(3):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        assert int(dut.a_col.value) == first_a, "A beat changed while sys_ready=0"
        assert int(dut.b_row.value) == first_b, "B beat changed while sys_ready=0"

    dut.sys_ready.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    for i in range(M):
        assert lane(first_a, i, DATA_W) == int(a[i, 0])
    for j in range(N):
        assert lane(first_b, j, DATA_W) == int(b[0, j])


@cocotb.test()
async def test_backpressure_stalls_stream(dut) -> None:
    """Toggling sys_ready low mid-stream must stall without data corruption."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    rng = random.Random(0xBACE)
    a = random_matrix(M, K, DATA_W, rng)
    b = random_matrix(K, N, DATA_W, rng)

    await write_matrix(apb, OFF_A, list(a.flatten()))
    await write_matrix(apb, OFF_B, list(b.flatten()))

    # Trigger streaming.
    dut.mat_start.value = 1
    dut.sys_ready.value = 0  # start with backpressure
    await RisingEdge(dut.clk)
    dut.mat_start.value = 0

    # Collect K beats with random backpressure.
    captured = []
    bp_rng = random.Random(0xBEEE)
    cycles = 0
    while len(captured) < K:
        cycles += 1
        assert cycles < 300, "stream timeout under backpressure"

        # Randomly toggle backpressure: ~30 % of cycles stalled.
        dut.sys_ready.value = bp_rng.choices([0, 1], weights=[3, 7])[0]
        await Timer(1, unit="ns")
        if int(dut.mat_valid.value) and int(dut.sys_ready.value):
            a_bus = int(dut.a_col.value)
            b_bus = int(dut.b_row.value)
            a_vec = [lane(a_bus, i, DATA_W) for i in range(M)]
            b_vec = [lane(b_bus, j, DATA_W) for j in range(N)]
            captured.append((a_vec, b_vec))
        await RisingEdge(dut.clk)

    dut.sys_ready.value = 0

    # Compare all K beats.
    for k, (a_vec, b_vec) in enumerate(captured):
        for i in range(M):
            assert a_vec[i] == int(a[i, k]), (
                f"backpressure: a beat {k} lane {i}: dut={a_vec[i]} ref={a[i, k]}"
            )
        for j in range(N):
            assert b_vec[j] == int(b[k, j]), (
                f"backpressure: b beat {k} lane {j}: dut={b_vec[j]} ref={b[k, j]}"
            )


@cocotb.test()
async def test_runtime_compact_tile_stream(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    apb = ApbMaster(dut)

    runtime_m = min(5, M)
    runtime_n = min(7, N)
    runtime_k = min(3, K)
    dut.cfg_m_dim.value = runtime_m
    dut.cfg_n_dim.value = runtime_n
    dut.cfg_k_dim.value = runtime_k

    a = np.arange(runtime_m * runtime_k, dtype=np.int64).reshape(runtime_m, runtime_k)
    b = (
        np.arange(runtime_k * runtime_n, dtype=np.int64).reshape(runtime_k, runtime_n)
        + 1
    )
    a %= 1 << (DATA_W - 1)
    b %= 1 << (DATA_W - 1)

    await write_matrix(apb, OFF_A, list(a.flatten()))
    await write_matrix(apb, OFF_B, list(b.flatten()))

    ctrl_val = await apb.read(OFF_CTRL)
    assert ctrl_val & 0x2, f"runtime A-full should be set, got 0x{ctrl_val:x}"
    assert ctrl_val & 0x4, f"runtime B-full should be set, got 0x{ctrl_val:x}"

    dut.sys_ready.value = 1
    dut.mat_start.value = 1
    await RisingEdge(dut.clk)
    dut.mat_start.value = 0

    captured = []
    while len(captured) < runtime_k:
        await Timer(1, unit="ns")
        if int(dut.mat_valid.value) and int(dut.sys_ready.value):
            captured.append((int(dut.a_col.value), int(dut.b_row.value)))
        await RisingEdge(dut.clk)

    for k_idx, (a_bus, b_bus) in enumerate(captured):
        for row in range(M):
            expected = int(a[row, k_idx]) if row < runtime_m else 0
            assert lane(a_bus, row, DATA_W) == expected
        for col in range(N):
            expected = int(b[k_idx, col]) if col < runtime_n else 0
            assert lane(b_bus, col, DATA_W) == expected
