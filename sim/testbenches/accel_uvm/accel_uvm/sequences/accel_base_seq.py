"""Base accelerator sequence with APB read/write helpers.

Sub-sequences start on the APB sequencer directly (or via a virtual
sequencer that exposes `apb_seqr`). The helpers below keep boilerplate
out of the concrete sequence bodies.
"""

from pyuvm import uvm_sequence

from ..apb.seq_item import ApbOp, ApbSeqItem


class AccelBaseSeq(uvm_sequence):
    """Provides do_apb_write / do_apb_read helpers."""

    def __init__(self, name="accel_base_seq"):
        super().__init__(name)

    async def do_apb_write(self, addr: int, data: int) -> None:
        """Issue one APB write transaction on the bound sequencer."""
        item = ApbSeqItem.create(f"wr_0x{addr:03x}")
        item.op = ApbOp.WRITE
        item.addr = addr
        item.data = data & 0xFFFF_FFFF
        await self.start_item(item)
        await self.finish_item(item)

    async def do_apb_read(self, addr: int) -> int:
        """Issue one APB read transaction; returns the captured data."""
        item = ApbSeqItem.create(f"rd_0x{addr:03x}")
        item.op = ApbOp.READ
        item.addr = addr
        item.data = 0
        await self.start_item(item)
        await self.finish_item(item)
        return item.data
