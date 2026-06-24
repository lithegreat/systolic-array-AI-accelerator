"""APB monitor – observes completed transactions and broadcasts on analysis port."""

from cocotb.triggers import RisingEdge
from pyuvm import uvm_monitor, uvm_analysis_port, ConfigDB

from .seq_item import ApbOp, ApbSeqItem


class ApbMonitor(uvm_monitor):
    """Samples the APB bus when PSEL & PENABLE & PREADY are all 1."""

    def __init__(self, name, parent):
        super().__init__(name, parent)
        self.ap = None
        self.cfg = None

    def build_phase(self):
        super().build_phase()
        self.ap = uvm_analysis_port("ap", self)
        self.cfg = ConfigDB().get(self, "", "apb_cfg")

    async def run_phase(self):
        vif = self.cfg.vif
        while True:
            await RisingEdge(vif.clk)
            # Sample at the end of ACCESS phase
            if int(vif.PSEL.value) and int(vif.PENABLE.value) and int(vif.PREADY.value):
                item = ApbSeqItem.create("mon_item")
                item.op = ApbOp.WRITE if int(vif.PWRITE.value) else ApbOp.READ
                item.addr = int(vif.PADDR.value)
                item.slverr = int(vif.PSLVERR.value)
                item.data = (
                    int(vif.PWDATA.value)
                    if item.op == ApbOp.WRITE
                    else int(vif.PRDATA.value)
                )
                self.ap.write(item)
