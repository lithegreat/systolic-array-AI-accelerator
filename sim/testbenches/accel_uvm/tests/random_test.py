"""Random UVM tests for accelerator_top.

Runs GEMM with multiple random seeds and compares results against a
Python reference model (with explicit ACC_W two's-complement wrap).
"""

import os
import random as _random

import numpy as np
import pyuvm
from cocotb.triggers import ClockCycles

from accel_uvm.base_test import AccelBaseTest
from accel_uvm.sequences import AccelLoadABSeq, AccelComputeSeq, AccelReadCSeq
from golden import matmul_ref, random_matrix

M = int(os.environ.get("M", "16"))
N = int(os.environ.get("N", "16"))
K = int(os.environ.get("K", "16"))
DATA_W = int(os.environ.get("DATA_W", "8"))
ACC_W = int(os.environ.get("ACC_W", "32"))

_SEEDS = (0x1234, 0xACCE, 0xBEEF, 0xC0DE)


async def _run_gemm(test, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Load A/B, trigger compute, drain C."""
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
class AccelRandomTest(AccelBaseTest):
    """Random A×B for multiple seeds; each result compared to golden."""

    async def run_phase(self):
        self.raise_objection()
        await super().run_phase()  # clock + reset

        for seed in _SEEDS:
            rng = _random.Random(seed)
            a = random_matrix(M, K, DATA_W, rng)
            b = random_matrix(K, N, DATA_W, rng)

            c_dut = await _run_gemm(self, a, b)
            c_ref = matmul_ref(a, b, ACC_W)

            assert np.array_equal(c_dut, c_ref), (
                f"AccelRandomTest seed=0x{seed:04x} FAIL\n"
                f"DUT[:4,:4]=\n{c_dut[:4, :4]}\n"
                f"REF[:4,:4]=\n{c_ref[:4, :4]}"
            )
            self.logger.info(f"AccelRandomTest seed=0x{seed:04x} PASS")

        await ClockCycles(self.vif.clk, 4)
        self.drop_objection()
