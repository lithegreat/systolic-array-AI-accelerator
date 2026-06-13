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

from golden import matmul_ref, pack_words, random_matrix, to_signed

M = int(os.environ.get("M", "16"))
N = int(os.environ.get("N", "16"))
K = int(os.environ.get("K", "16"))
DATA_W = int(os.environ.get("DATA_W", "8"))
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


def pad_to_hw(mat: np.ndarray, hw_rows: int, hw_cols: int) -> np.ndarray:
    """Zero-pad a matrix to the hardware tile dimensions."""
    r, c = mat.shape
    out = np.zeros((hw_rows, hw_cols), dtype=mat.dtype)
    out[:r, :c] = mat
    return out


async def run_submatmul(
    dut, a_sub: np.ndarray, b_sub: np.ndarray, m: int, n: int, k: int
) -> np.ndarray:
    """Run a (m x k) @ (k x n) matmul on the 16x16 HW via zero-padding.

    Returns only the meaningful (m x n) top-left block of the result.
    """
    a_hw = pad_to_hw(a_sub, M, K)
    b_hw = pad_to_hw(b_sub, K, N)
    c_hw = await run_matmul(dut, a_hw, b_hw)
    return c_hw[:m, :n]


@cocotb.test()
async def test_top_random_matmul(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    rng = random.Random(0x1234)
    for trial in range(3):
        a = random_matrix(M, K, 8, rng).astype(np.int64)
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

    # Distinct A values constrained to the signed DATA_W range so they survive
    # element packing unchanged (identity B must return A bit-for-bit). For
    # DATA_W >= 9 this is the plain 1..M*K ramp; at INT8 it folds into [0,127].
    a = (np.arange(1, M * K + 1, dtype=np.int64) % (1 << (DATA_W - 1))).reshape(M, K)
    b = np.eye(K, N, dtype=np.int64)
    ref = matmul_ref(a, b, ACC_W)
    got = await run_matmul(dut, a, b)
    assert np.array_equal(got, ref), f"identity mismatch:\nref=\n{ref}\ngot=\n{got}"


@cocotb.test()
async def test_top_4x4_matmul(dut) -> None:
    """4x4 matrix multiply on 16x16 HW via zero-padding, 8-bit inputs."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    dim = 4
    rng = random.Random(0x4444)
    for trial in range(3):
        a = random_matrix(dim, dim, 8, rng).astype(np.int64)
        b = random_matrix(dim, dim, 8, rng).astype(np.int64)
        ref = matmul_ref(a, b, ACC_W)
        got = await run_submatmul(dut, a, b, dim, dim, dim)
        if not np.array_equal(got, ref):
            cocotb.log.error(f"4x4 trial {trial}: mismatch")
            cocotb.log.error(f"ref=\n{ref}")
            cocotb.log.error(f"got=\n{got}")
            raise AssertionError(f"4x4 matmul mismatch on trial {trial}")


@cocotb.test()
async def test_top_8x8_matmul(dut) -> None:
    """8x8 matrix multiply on 16x16 HW via zero-padding, 8-bit inputs."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    dim = 8
    rng = random.Random(0x8888)
    for trial in range(3):
        a = random_matrix(dim, dim, 8, rng).astype(np.int64)
        b = random_matrix(dim, dim, 8, rng).astype(np.int64)
        ref = matmul_ref(a, b, ACC_W)
        got = await run_submatmul(dut, a, b, dim, dim, dim)
        if not np.array_equal(got, ref):
            cocotb.log.error(f"8x8 trial {trial}: mismatch")
            cocotb.log.error(f"ref=\n{ref}")
            cocotb.log.error(f"got=\n{got}")
            raise AssertionError(f"8x8 matmul mismatch on trial {trial}")


@cocotb.test()
async def test_top_4bit_inputs(dut) -> None:
    """16x16 matmul with 4-bit signed inputs sign-extended to 16-bit."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    rng = random.Random(0x0004)
    for trial in range(3):
        a = random_matrix(M, K, 4, rng).astype(np.int64)
        b = random_matrix(K, N, 4, rng).astype(np.int64)
        ref = matmul_ref(a, b, ACC_W)
        got = await run_matmul(dut, a, b)
        if not np.array_equal(got, ref):
            cocotb.log.error(f"4-bit trial {trial}: mismatch")
            raise AssertionError(f"4-bit input matmul mismatch on trial {trial}")


@cocotb.test()
async def test_top_8bit_inputs(dut) -> None:
    """16x16 matmul with 8-bit signed inputs sign-extended to 16-bit."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    rng = random.Random(0x0008)
    for trial in range(3):
        a = random_matrix(M, K, 8, rng).astype(np.int64)
        b = random_matrix(K, N, 8, rng).astype(np.int64)
        ref = matmul_ref(a, b, ACC_W)
        got = await run_matmul(dut, a, b)
        if not np.array_equal(got, ref):
            cocotb.log.error(f"8-bit trial {trial}: mismatch")
            raise AssertionError(f"8-bit input matmul mismatch on trial {trial}")


@cocotb.test()
async def test_top_4x4_4bit(dut) -> None:
    """4x4 matmul with 4-bit inputs on 16x16 HW."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    dim = 4
    rng = random.Random(0x0044)
    a = random_matrix(dim, dim, 4, rng).astype(np.int64)
    b = random_matrix(dim, dim, 4, rng).astype(np.int64)
    ref = matmul_ref(a, b, ACC_W)
    got = await run_submatmul(dut, a, b, dim, dim, dim)
    assert np.array_equal(got, ref), f"4x4 4-bit mismatch:\nref=\n{ref}\ngot=\n{got}"


@cocotb.test()
async def test_top_8x8_4bit(dut) -> None:
    """8x8 matmul with 4-bit inputs on 16x16 HW."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    dim = 8
    rng = random.Random(0x0084)
    a = random_matrix(dim, dim, 4, rng).astype(np.int64)
    b = random_matrix(dim, dim, 4, rng).astype(np.int64)
    ref = matmul_ref(a, b, ACC_W)
    got = await run_submatmul(dut, a, b, dim, dim, dim)
    assert np.array_equal(got, ref), f"8x8 4-bit mismatch:\nref=\n{ref}\ngot=\n{got}"


REG_INT_EN = 0x10
REG_INT_STAT = 0x14


@cocotb.test()
async def test_top_irq_path(dut) -> None:
    """Exercise irq_en_4/ss_ctrl_4/irq_4 toggle and the interrupt register path."""
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    # Drive ss_ctrl_4 to a non-zero value (toggles the port).
    dut.ss_ctrl_4.value = 0xAB

    # Enable the done-interrupt inside the control unit.
    await apb_write(dut, CTRL_BASE | REG_INT_EN, 0x1)

    # Enable the SoC-level IRQ gate.
    dut.irq_en_4.value = 1

    # Run a minimal identity matmul to trigger done. Zero-pad to the full
    # hardware tile so the compute runs on defined data (the banks are not
    # cleared on reset).
    rng = random.Random(0xABC0)
    a = pad_to_hw(random_matrix(1, 1, 8, rng).astype(np.int64), M, K)
    b = pad_to_hw(random_matrix(1, 1, 8, rng).astype(np.int64), K, N)
    await run_matmul(dut, a, b)

    # irq_4 should now be high (interrupt fired).
    assert int(dut.irq_4.value) == 1, (
        "irq_4 should be asserted after done with irq_en_4=1"
    )

    # Clear the interrupt via W1C on INT_STAT.
    await apb_write(dut, CTRL_BASE | REG_INT_STAT, 0x1)
    for _ in range(3):
        await RisingEdge(dut.clk_in)
    assert int(dut.irq_4.value) == 0, "irq_4 should deassert after W1C on INT_STAT"

    # Restore irq_en_4 low (toggles back).
    dut.irq_en_4.value = 0
    dut.ss_ctrl_4.value = 0


@cocotb.test()
async def test_top_unmapped_region(dut) -> None:
    """An access to an unmapped APB region must terminate (no bus stall).

    PADDR[9:8]==2'b11 (e.g. 0x300) matches no subordinate; the top-level
    decoder must still assert PREADY (and PSLVERR) so the bus does not hang.
    """
    cocotb.start_soon(Clock(dut.clk_in, 10, unit="ns").start())
    await reset_top(dut)

    unmapped = 0x300

    # Read access to the unmapped region.
    dut.PADDR.value = unmapped
    dut.PWRITE.value = 0
    dut.PSEL.value = 1
    dut.PENABLE.value = 0
    await RisingEdge(dut.clk_in)
    dut.PENABLE.value = 1
    await Timer(1, unit="ns")
    assert int(dut.PREADY.value) == 1, "PREADY must be high for unmapped read"
    assert int(dut.PSLVERR.value) == 1, "PSLVERR must flag unmapped read"
    await RisingEdge(dut.clk_in)
    dut.PSEL.value = 0
    dut.PENABLE.value = 0

    # Write access to the unmapped region.
    dut.PADDR.value = unmapped
    dut.PWDATA.value = 0xDEADBEEF
    dut.PWRITE.value = 1
    dut.PSEL.value = 1
    dut.PENABLE.value = 0
    await RisingEdge(dut.clk_in)
    dut.PENABLE.value = 1
    await Timer(1, unit="ns")
    assert int(dut.PREADY.value) == 1, "PREADY must be high for unmapped write"
    assert int(dut.PSLVERR.value) == 1, "PSLVERR must flag unmapped write"
    await RisingEdge(dut.clk_in)
    dut.PSEL.value = 0
    dut.PENABLE.value = 0
    dut.PWRITE.value = 0
