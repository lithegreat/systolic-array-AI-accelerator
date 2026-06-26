"""Read matrix C back from the output buffer via APB.

After the sequence completes, ``c_matrix`` holds the result as a numpy
int64 array of shape (M, N).
"""

from __future__ import annotations

import os

import numpy as np

from golden import to_signed  # provided via sim/testbenches/common

from .accel_base_seq import AccelBaseSeq

C_BASE = 0x200
OFF_C_DATA = 0x00  # read C elements (auto-inc ptr)

_ACC_W = int(os.environ.get("ACC_W", "32"))
_M = int(os.environ.get("M", "16"))
_N = int(os.environ.get("N", "16"))


class AccelReadCSeq(AccelBaseSeq):
    """Drain M×N 32-bit words from the C output buffer."""

    def __init__(self, name="accel_read_c_seq"):
        super().__init__(name)
        self.m = _M
        self.n = _N
        self.acc_w = _ACC_W
        self.c_matrix: np.ndarray | None = None  # filled by body()

    async def body(self):
        c_flat = []
        for _ in range(self.m * self.n):
            word = await self.do_apb_read(C_BASE | OFF_C_DATA)
            c_flat.append(to_signed(word, self.acc_w))
        self.c_matrix = np.array(c_flat, dtype=np.int64).reshape(self.m, self.n)
