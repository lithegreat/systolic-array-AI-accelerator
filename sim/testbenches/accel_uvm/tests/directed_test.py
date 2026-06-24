"""Directed UVM tests for accelerator_top.

Tests
-----
AccelZeroTest       A = 0 matrix → C must be all zeros.
AccelIdentityTest   A = identity, B = arbitrary → C must equal B (for K=M=N).
AccelCheckerTest    Checkerboard A and B, verifies against Python golden model.
"""

import os

import numpy as np
import pyuvm
from cocotb.triggers import ClockCycles

from accel_uvm.base_test import AccelBaseTest
from accel_uvm.sequences import AccelLoadABSeq, AccelComputeSeq, AccelReadCSeq
from golden import matmul_ref, random_matrix

import random as _random

M = int(os.environ.get("M", "16"))
N = int(os.environ.get("N", "16"))
K = int(os.environ.get("K", "16"))
DATA_W = int(os.environ.get("DATA_W", "8"))
ACC_W = int(os.environ.get("ACC_W", "32"))


async def _run_gemm(test, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Helper: load A/B, compute, read C – all on the APB sequencer."""
    seqr = test.env.apb_agent.sequencer

    load = AccelLoadABSeq.create("load")
    load.a_matrix = a
    load.b_matrix = b
    await load.start(seqr)

    compute = AccelComputeSeq.create("compute")
    compute.m = a.shape[0]
    compute.n = b.shape[1]
    compute.k = a.shape[1]
    await compute.start(seqr)

    readout = AccelReadCSeq.create("readout")
    readout.m = a.shape[0]
    readout.n = b.shape[1]
    await readout.start(seqr)

    return readout.c_matrix


@pyuvm.test()
class AccelZeroTest(AccelBaseTest):
    """A = 0, B = random → C must be all zeros."""

    async def run_phase(self):
        self.raise_objection()
        await super().run_phase()  # clock + reset

        rng = _random.Random(0xDEAD)
        a = np.zeros((M, K), dtype=np.int64)
        b = random_matrix(K, N, DATA_W, rng)

        c_dut = await _run_gemm(self, a, b)
        c_ref = matmul_ref(a, b, ACC_W)

        assert np.array_equal(c_dut, c_ref), (
            f"AccelZeroTest FAIL:\nDUT=\n{c_dut}\nREF=\n{c_ref}"
        )
        self.logger.info("AccelZeroTest PASS")

        await ClockCycles(self.vif.clk, 4)
        self.drop_objection()


@pyuvm.test()
class AccelIdentityTest(AccelBaseTest):
    """A = identity, B = identity → C = identity (square case)."""

    async def run_phase(self):
        self.raise_objection()
        await super().run_phase()

        dim = min(M, N, K)
        a = np.eye(dim, dtype=np.int64)
        b = np.eye(dim, dtype=np.int64)

        c_dut = await _run_gemm(self, a, b)
        c_ref = matmul_ref(a, b, ACC_W)

        assert np.array_equal(c_dut, c_ref), (
            f"AccelIdentityTest FAIL:\nDUT=\n{c_dut}\nREF=\n{c_ref}"
        )
        self.logger.info("AccelIdentityTest PASS")

        await ClockCycles(self.vif.clk, 4)
        self.drop_objection()


@pyuvm.test()
class AccelCheckerboardTest(AccelBaseTest):
    """Checkerboard A × checkerboard B compared against golden reference."""

    async def run_phase(self):
        self.raise_objection()
        await super().run_phase()

        lo = -(1 << (DATA_W - 1))
        hi = (1 << (DATA_W - 1)) - 1

        a = np.fromfunction(
            lambda r, c: np.where(((r + c) % 2) == 0, hi, lo),
            (M, K),
            dtype=int,
        ).astype(np.int64)
        b = np.fromfunction(
            lambda r, c: np.where(((r + c) % 2) == 0, lo, hi),
            (K, N),
            dtype=int,
        ).astype(np.int64)

        c_dut = await _run_gemm(self, a, b)
        c_ref = matmul_ref(a, b, ACC_W)

        assert np.array_equal(c_dut, c_ref), (
            f"AccelCheckerboardTest FAIL:\nDUT=\n{c_dut}\nREF=\n{c_ref}"
        )
        self.logger.info("AccelCheckerboardTest PASS")

        await ClockCycles(self.vif.clk, 4)
        self.drop_objection()
