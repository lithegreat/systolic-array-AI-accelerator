"""End-to-end cocotb test for accelerator_top.

Programs the accelerator over APB:
  1. Write A and B matrices to the input buffer (offsets 0x00 / 0x40).
  2. Trigger a compute via control_unit.CTRL.start.
  3. Poll STATUS.done.
  4. Read C back from the output buffer.
  5. Compare against numpy reference.
"""

from __future__ import annotations

import os
import random

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from golden import matmul_ref, pack_words, random_matrix, to_signed, to_unsigned

M = int(os.environ.get("M", "16"))
N = int(os.environ.get("N", "16"))
K = int(os.environ.get("K", "16"))
DATA_W = int(os.environ.get("DATA_W", "16"))
ACC_W = int(os.environ.get("ACC_W", "32"))

# Address regions
AB_BASE = 0x000
CTRL_BASE = 0x100
C_BASE = 0x200

OFF_A_DATA = 0x00
OFF_B_DATA = 0x40
OFF_AB_CTRL = 0x80
OFF_C_DATA = 0x00
OFF_C_CTRL = 0x80

REG_CTRL = 0x00
REG_STATUS = 0x04

CTRL_START = 1 << 0
STATUS_DONE = 1 << 1
STATUS_BUSY = 1 << 0


async def apb_write(dut, addr: int, data: int) -> None:
    dut.PADDR.value = int(addr)
    dut.PWDATA.value = int(data) & 0xFFFFFFFF
    dut.PWRITE.value = 1
    dut.PSEL.value = 1
    dut.PENABLE.value = 0
    await RisingEdge(dut.clk_in)
    dut.PENABLE.value = 1
    await RisingEdge(dut.clk_in)
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0


async def apb_read(dut, addr: int) -> int:
    dut.PADDR.value = int(addr)
    dut.PWRITE.value = 0
    dut.PSEL.value = 1
    dut.PENABLE.value = 0
    await RisingEdge(dut.clk_in)
    dut.PENABLE.value = 1
    await Timer(1, unit="ns")
    val = int(dut.PRDATA.value)
    await RisingEdge(dut.clk_in)
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    return val


async def reset_top(dut) -> None:
    dut.reset_int.value = 1
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0
    dut.PADDR.value = 0
    dut.PWDATA.value = 0
    dut.irq_en_4.value = 0
    dut.ss_ctrl_4.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_in)
    dut.reset_int.value = 0
    await RisingEdge(dut.clk_in)


async def write_matrix(dut, base: int, off: int, flat) -> None:
    for word in pack_words(flat, DATA_W, 32):
        await apb_write(dut, base | off, word)


async def run_matmul(dut, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    # Reset write pointers in input buffer (between runs).
    await apb_write(dut, AB_BASE | OFF_AB_CTRL, 0x1)
    # Reset read pointer in output buffer.
    await apb_write(dut, C_BASE | OFF_C_CTRL, 0x1)

    # Load A and B (row-major).
    await write_matrix(dut, AB_BASE, OFF_A_DATA, list(a.flatten()))
    await write_matrix(dut, AB_BASE, OFF_B_DATA, list(b.flatten()))

    # Trigger compute.
    await apb_write(dut, CTRL_BASE | REG_CTRL, CTRL_START)

    # Poll STATUS.done.
    for _ in range(2000):
        s = await apb_read(dut, CTRL_BASE | REG_STATUS)
        if s & STATUS_DONE:
            break
    else:
        raise AssertionError("STATUS.done was never asserted")

    # Acknowledge done by W1C (so next run starts clean).
    await apb_write(dut, CTRL_BASE | REG_STATUS, STATUS_DONE)

    # Read back C row-major.
    c = np.zeros((M, N), dtype=np.int64)
    for i in range(M):
        for j in range(N):
            word = await apb_read(dut, C_BASE | OFF_C_DATA)
            c[i, j] = to_signed(word, 32)
    return c


@cocotb.test()
async def test_top_random_matmul(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    rng = random.Random(0x1234)
    # Use a small dynamic range so 32-bit APB readout matches the full
    # accumulator value (no truncation needed).
    for trial in range(3):
        a = random_matrix(M, K, 8, rng).astype(np.int64)  # use 8-bit signed values
        b = random_matrix(K, N, 8, rng).astype(np.int64)
        ref = matmul_ref(a, b, ACC_W)
        got = await run_matmul(dut, a, b)
        if not np.array_equal(got, ref):
            cocotb.log.error(f"trial {trial}: mismatch")
            cocotb.log.error(f"a=\n{a}")
            cocotb.log.error(f"b=\n{b}")
            cocotb.log.error(f"ref=\n{ref}")
            cocotb.log.error(f"got=\n{got}")
            raise AssertionError(f"matmul mismatch on trial {trial}")


@cocotb.test()
async def test_top_identity(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    a = np.arange(1, M * K + 1, dtype=np.int64).reshape(M, K)
    b = np.eye(K, N, dtype=np.int64)
    ref = matmul_ref(a, b, ACC_W)
    got = await run_matmul(dut, a, b)
    assert np.array_equal(got, ref), f"identity mismatch:\nref=\n{ref}\ngot=\n{got}"
