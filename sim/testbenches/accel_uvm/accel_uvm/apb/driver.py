"""APB producer driver – converts ApbSeqItems into pin-level activity."""

from cocotb.triggers import RisingEdge
from pyuvm import uvm_driver, ConfigDB

from .seq_item import ApbOp


class ApbDriver(uvm_driver):
    """Drives APB SETUP→ACCESS phases and waits for PREADY."""

    def __init__(self, name, parent):
        super().__init__(name, parent)
        self.cfg = None

    def build_phase(self):
        super().build_phase()
        self.cfg = ConfigDB().get(self, "", "apb_cfg")

    async def run_phase(self):
        vif = self.cfg.vif
        # Idle bus
        vif.PSEL.value = 0
        vif.PENABLE.value = 0
        vif.PWRITE.value = 0
        vif.PADDR.value = 0
        vif.PWDATA.value = 0

        while True:
            item = await self.seq_item_port.get_next_item()
            await self._drive(item)
            self.seq_item_port.item_done()

    async def _drive(self, item):
        vif = self.cfg.vif

        # SETUP phase – present address/control before clock edge
        await RisingEdge(vif.clk)
        vif.PADDR.value = item.addr
        vif.PWDATA.value = item.data if item.op == ApbOp.WRITE else 0
        vif.PWRITE.value = 1 if item.op == ApbOp.WRITE else 0
        vif.PSEL.value = 1
        vif.PENABLE.value = 0

        # ACCESS phase – assert PENABLE
        await RisingEdge(vif.clk)
        vif.PENABLE.value = 1

        # Poll PREADY (accelerator returns PREADY=1 in the same cycle)
        await RisingEdge(vif.clk)
        while not int(vif.PREADY.value):
            await RisingEdge(vif.clk)

        # Capture response
        item.slverr = int(vif.PSLVERR.value)
        if item.op == ApbOp.READ:
            item.data = int(vif.PRDATA.value)

        # Return bus to idle
        vif.PSEL.value = 0
        vif.PENABLE.value = 0
