"""cocotb testbench for mac_pe.

Drives random and directed stimulus and compares every cycle against the
Python golden model in `golden_mac`.
"""

from __future__ import annotations

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from golden import to_signed, to_unsigned  # type: ignore  # provided via PYTHONPATH
from golden_mac import MacPeGolden

DATA_W = int(os.environ.get("DATA_W", "8"))
ACC_W = int(os.environ.get("ACC_W", "32"))


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.en.value = 0
    dut.clear_acc.value = 0
    dut.a_in.value = 0
    dut.b_in.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def _check(dut, golden: MacPeGolden) -> None:
    a_out_dut = to_signed(int(dut.a_out.value), DATA_W)
    b_out_dut = to_signed(int(dut.b_out.value), DATA_W)
    pe_out_dut = to_signed(int(dut.pe_out.value), ACC_W)
    assert a_out_dut == golden.a_out, (
        f"a_out mismatch dut={a_out_dut} ref={golden.a_out}"
    )
    assert b_out_dut == golden.b_out, (
        f"b_out mismatch dut={b_out_dut} ref={golden.b_out}"
    )
    assert pe_out_dut == golden.pe_out, (
        f"pe_out mismatch dut={pe_out_dut} ref={golden.pe_out}"
    )


@cocotb.test()
async def test_reset_clears_outputs(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    assert int(dut.pe_out.value) == 0
    assert int(dut.a_out.value) == 0
    assert int(dut.b_out.value) == 0


@cocotb.test()
async def test_directed_simple_accumulate(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    golden = MacPeGolden(DATA_W, ACC_W)

    # First cycle initialises with clear_acc.
    pairs = [(3, 4, 1), (2, 5, 0), (-1, 7, 0), (10, -3, 0)]
    for a, b, clr in pairs:
        dut.a_in.value = to_unsigned(a, DATA_W)
        dut.b_in.value = to_unsigned(b, DATA_W)
        dut.en.value = 1
        dut.clear_acc.value = clr
        await RisingEdge(dut.clk)
        golden.step(a, b, en=1, clear_acc=clr)
        await Timer(1, unit="ns")  # let combinational outputs settle
        _check(dut, golden)


@cocotb.test()
async def test_random_stream(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    golden = MacPeGolden(DATA_W, ACC_W)
    rng = random.Random(0xC0FFEE)
    lo = -(1 << (DATA_W - 1))
    hi = (1 << (DATA_W - 1)) - 1
    for i in range(500):
        a = rng.randint(lo, hi)
        b = rng.randint(lo, hi)
        en = rng.choice([0, 1, 1, 1])
        clr = 1 if i == 0 else rng.choice([0, 0, 0, 0, 1])
        dut.a_in.value = to_unsigned(a, DATA_W)
        dut.b_in.value = to_unsigned(b, DATA_W)
        dut.en.value = en
        dut.clear_acc.value = clr
        await RisingEdge(dut.clk)
        golden.step(a, b, en=en, clear_acc=clr)
        await Timer(1, unit="ns")
        _check(dut, golden)


@cocotb.test()
async def test_signed_extremes(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    golden = MacPeGolden(DATA_W, ACC_W)
    lo = -(1 << (DATA_W - 1))
    hi = (1 << (DATA_W - 1)) - 1
    seq = [(lo, lo, 1), (hi, hi, 0), (lo, hi, 0), (-1, 1, 0)]
    for a, b, clr in seq:
        dut.a_in.value = to_unsigned(a, DATA_W)
        dut.b_in.value = to_unsigned(b, DATA_W)
        dut.en.value = 1
        dut.clear_acc.value = clr
        await RisingEdge(dut.clk)
        golden.step(a, b, en=1, clear_acc=clr)
        await Timer(1, unit="ns")
        _check(dut, golden)
