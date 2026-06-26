"""Load matrices A and B into the input buffer via APB.

Set ``a_matrix`` and ``b_matrix`` (numpy int64 arrays, shapes M×K and K×N)
before starting the sequence on the APB sequencer.
"""

from __future__ import annotations

import os

import numpy as np

from golden import pack_words  # provided via sim/testbenches/common

from .accel_base_seq import AccelBaseSeq

# APB address offsets (accelerator_top memory map)
AB_BASE = 0x000
OFF_A_DATA = 0x00  # write A elements (auto-inc ptr)
OFF_B_DATA = 0x40  # write B elements (auto-inc ptr)
OFF_AB_CTRL = 0x80  # bit[0]=reset write pointers

_DATA_W = int(os.environ.get("DATA_W", "8"))
_APB_DW = 32


class AccelLoadABSeq(AccelBaseSeq):
    """Resets the A/B write pointers then streams A and B row-major."""

    def __init__(self, name="accel_load_ab_seq"):
        super().__init__(name)
        self.a_matrix: np.ndarray | None = None  # shape (M, K), dtype int64
        self.b_matrix: np.ndarray | None = None  # shape (K, N), dtype int64
        self.data_w = _DATA_W

    async def body(self):
        assert self.a_matrix is not None, "Set a_matrix before starting AccelLoadABSeq"
        assert self.b_matrix is not None, "Set b_matrix before starting AccelLoadABSeq"

        # Reset write pointers in the A/B buffer
        await self.do_apb_write(AB_BASE | OFF_AB_CTRL, 0x1)

        # Stream A (row-major, packed into 32-bit APB words)
        a_flat = self.a_matrix.flatten().tolist()
        for word in pack_words(a_flat, self.data_w, _APB_DW):
            await self.do_apb_write(AB_BASE | OFF_A_DATA, word)

        # Stream B (row-major)
        b_flat = self.b_matrix.flatten().tolist()
        for word in pack_words(b_flat, self.data_w, _APB_DW):
            await self.do_apb_write(AB_BASE | OFF_B_DATA, word)
