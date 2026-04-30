"""cocotb tests for matrix_buffer_ab (APB write + streaming read)."""

from __future__ import annotations

import os
import random

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from apb_bfm import ApbMaster
from golden import pack_words, random_matrix, to_signed, to_unsigned

M = int(os.environ.get("M", "4"))
N = int(os.environ.get("N", "4"))
K = int(os.environ.get("K", "4"))
DATA_W = int(os.environ.get("DATA_W", "16"))
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
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def write_matrix(apb: ApbMaster, base: int, flat) -> None:
    for word in pack_words(flat, DATA_W, APB_DW):
        await apb.write(base, word)


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
    a_bus_w = M * DATA_W
    b_bus_w = N * DATA_W
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
            assert a_vec[i] == int(
                a[i, k]
            ), f"a beat {k} lane {i}: dut={a_vec[i]} ref={a[i,k]}"
        for j in range(N):
            assert b_vec[j] == int(
                b[k, j]
            ), f"b beat {k} lane {j}: dut={b_vec[j]} ref={b[k,j]}"


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
