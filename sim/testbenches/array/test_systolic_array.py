"""cocotb testbench for systolic_array (output-stationary, M=N=K=4)."""

from __future__ import annotations

import os
import random

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from golden import random_matrix, to_signed, to_unsigned
from golden_array import expected_drain

M = int(os.environ.get("M", "16"))
N = int(os.environ.get("N", "16"))
K = int(os.environ.get("K", "16"))
DATA_W = int(os.environ.get("DATA_W", "8"))
ACC_W = int(os.environ.get("ACC_W", "32"))


def pack_vec(values, width: int) -> int:
    """Pack values[0]..values[L-1] LSB-first into a single bus word."""
    word = 0
    for i, v in enumerate(values):
        word |= to_unsigned(int(v), width) << (i * width)
    return word


async def reset_dut(dut) -> None:
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.cfg_m_dim.value = M
    dut.cfg_n_dim.value = N
    dut.cfg_k_dim.value = K
    dut.in_valid.value = 0
    dut.out_ready.value = 0
    dut.a_col.value = 0
    dut.b_row.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def run_one_tile(
    dut, a: np.ndarray, b: np.ndarray, throttle: bool = False
) -> dict:
    """Drive a single matmul through the array; return the captured drain dict."""
    expected = expected_drain(a, b, ACC_W)

    # Make sure the previous tile's S_DONE pulse has elapsed and we are back in IDLE.
    dut.in_valid.value = 0
    dut.out_ready.value = 0
    # Wait until the array is observed idle (out_valid=0 stably).
    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.out_valid.value) == 0 and int(dut.done.value) == 0:
            break

    # Pulse start.
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await Timer(1, unit="ns")

    # Feed K column slices of A and row slices of B.
    captured = {}
    fed = 0
    rng = random.Random(0xBEEF)
    max_cycles = (M + N + K) * 4 + M * N * 4 + 50
    cycles = 0
    saw_done = False

    while not saw_done:
        cycles += 1
        assert cycles < max_cycles, f"timeout: fed={fed}, captured={len(captured)}"
        # Set output ready (with optional throttle).
        if throttle:
            dut.out_ready.value = rng.choice([0, 1])
        else:
            dut.out_ready.value = 1

        # Set input vector if still loading.
        if fed < K:
            a_col = a[:, fed]  # column fed of A
            b_row = b[fed, :]  # row fed of B
            dut.a_col.value = pack_vec(a_col, DATA_W)
            dut.b_row.value = pack_vec(b_row, DATA_W)
            dut.in_valid.value = 1
        else:
            dut.in_valid.value = 0
            dut.a_col.value = 0
            dut.b_row.value = 0

        # Sample combinational handshake values BEFORE the edge.
        await Timer(1, unit="ns")
        in_ready_now = int(dut.in_ready.value)
        in_valid_now = int(dut.in_valid.value)
        out_valid_now = int(dut.out_valid.value)
        out_ready_now = int(dut.out_ready.value)
        c_row_data_now = int(dut.c_row_data.value)
        c_row_now = int(dut.c_row.value)

        await RisingEdge(dut.clk)

        if fed < K and in_ready_now and in_valid_now:
            fed += 1
        if out_valid_now and out_ready_now:
            # Unpack the N accumulators of this row (column 0 in low bits).
            for col in range(N):
                word = (c_row_data_now >> (col * ACC_W)) & ((1 << ACC_W) - 1)
                value = to_signed(word, ACC_W)
                assert (
                    c_row_now,
                    col,
                ) not in captured, f"duplicate drain at ({c_row_now},{col})"
                captured[(c_row_now, col)] = value
        if int(dut.done.value):
            saw_done = True

    dut.out_ready.value = 0
    dut.in_valid.value = 0

    assert len(captured) == M * N, f"only captured {len(captured)} of {M * N}"

    # Compare.
    for value, row, col in expected:
        got = captured.get((row, col))
        assert got is not None, f"missing C[{row},{col}]"
        assert got == value, f"C[{row},{col}] dut={got} ref={value}"

    return captured


@cocotb.test()
async def test_identity_b_returns_a(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    # A values constrained to the signed DATA_W range so they survive element
    # packing unchanged (identity B returns A). Plain 1..M*K ramp for DATA_W>=9;
    # folds into [0,127] at INT8.
    a = (np.arange(1, M * K + 1, dtype=np.int64) % (1 << (DATA_W - 1))).reshape(M, K)
    b = np.eye(K, N, dtype=np.int64)
    await run_one_tile(dut, a, b)


@cocotb.test()
async def test_random_matmul(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    rng = random.Random(0xA11CE)
    for _ in range(5):
        # Use a smaller dynamic range so accumulator wrap is rare but tested.
        a = random_matrix(M, K, DATA_W, rng)
        b = random_matrix(K, N, DATA_W, rng)
        await run_one_tile(dut, a, b)


@cocotb.test()
async def test_back_to_back(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    rng = random.Random(0xBABE)
    for _ in range(3):
        a = random_matrix(M, K, DATA_W, rng)
        b = random_matrix(K, N, DATA_W, rng)
        await run_one_tile(dut, a, b)


@cocotb.test()
async def test_backpressure(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    rng = random.Random(0xDEAD)
    a = random_matrix(M, K, DATA_W, rng)
    b = random_matrix(K, N, DATA_W, rng)
    await run_one_tile(dut, a, b, throttle=True)
