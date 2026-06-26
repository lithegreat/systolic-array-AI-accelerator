"""Trigger the accelerator compute pass and poll STATUS.done.

Resets the C-buffer read pointer, programs M/N/K, asserts start, then
polls STATUS.done with a configurable timeout.
"""

import os

from .accel_base_seq import AccelBaseSeq

# Absolute APB addresses
CTRL_BASE = 0x100
C_BASE = 0x200

OFF_CTRL = 0x00  # CTRL[0]=start, CTRL[1]=softrst
OFF_STATUS = 0x04  # STATUS[0]=busy, STATUS[1]=done (W1C)
OFF_M_DIM = 0x08
OFF_N_DIM = 0x0C
OFF_K_DIM = 0x18
OFF_C_CTRL = 0x80  # C-buffer control, bit[0]=reset read pointer

CTRL_START = 1 << 0
STATUS_DONE = 1 << 1

_POLL_MAX = 200_000  # guard against infinite loops


class AccelComputeSeq(AccelBaseSeq):
    """Program dimensions, start compute, wait for done."""

    def __init__(self, name="accel_compute_seq"):
        super().__init__(name)
        self.m = int(os.environ.get("M", "16"))
        self.n = int(os.environ.get("N", "16"))
        self.k = int(os.environ.get("K", "16"))

    async def body(self):
        # Reset C-buffer read pointer before a new run
        await self.do_apb_write(C_BASE | OFF_C_CTRL, 0x1)

        # Program tile dimensions (RTL clamps to physical array size)
        await self.do_apb_write(CTRL_BASE | OFF_M_DIM, self.m)
        await self.do_apb_write(CTRL_BASE | OFF_N_DIM, self.n)
        await self.do_apb_write(CTRL_BASE | OFF_K_DIM, self.k)

        # Assert start (self-clearing bit)
        await self.do_apb_write(CTRL_BASE | OFF_CTRL, CTRL_START)

        # Poll until done
        for _ in range(_POLL_MAX):
            status = await self.do_apb_read(CTRL_BASE | OFF_STATUS)
            if status & STATUS_DONE:
                break
        else:
            raise AssertionError(
                f"AccelComputeSeq: STATUS.done not set within {_POLL_MAX} polls "
                f"(M={self.m} N={self.n} K={self.k})"
            )

        # Clear done flag (W1C)
        await self.do_apb_write(CTRL_BASE | OFF_STATUS, STATUS_DONE)
