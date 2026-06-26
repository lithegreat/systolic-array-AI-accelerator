"""APB transaction sequence item."""

from enum import IntEnum
from pyuvm import uvm_sequence_item


class ApbOp(IntEnum):
    WRITE = 0
    READ = 1


class ApbSeqItem(uvm_sequence_item):
    """One APB read or write transaction."""

    def __init__(self, name="apb_item"):
        super().__init__(name)
        self.op = ApbOp.WRITE
        self.addr = 0
        self.data = 0  # wdata on write; rdata captured on read
        self.slverr = 0

    def __str__(self):
        return (
            f"{self.get_name()}: op={self.op.name} "
            f"addr=0x{self.addr:03x} data=0x{self.data:08x} "
            f"slverr={self.slverr}"
        )
