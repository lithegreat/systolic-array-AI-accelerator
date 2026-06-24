"""Register adapter: bridges uvm_reg_bus_op ↔ ApbSeqItem."""

from pyuvm import uvm_reg_adapter, access_e, status_t, uvm_sequence

from ..apb.seq_item import ApbOp, ApbSeqItem


class AccelRegAdapter(uvm_reg_adapter):
    def __init__(self, name="accel_reg_adapter"):
        super().__init__(name)
        self.parent_sequence = uvm_sequence()

    def reg2bus(self, rw):
        item = ApbSeqItem.create("apb_item")
        item.op = ApbOp.READ if rw.kind == access_e.UVM_READ else ApbOp.WRITE
        # rw.addr arrives as a hex string in pyuvm
        raw_addr = rw.addr
        if isinstance(raw_addr, str):
            item.addr = int(raw_addr, 16)
        else:
            item.addr = int(raw_addr)
        item.data = rw.data
        return item

    def bus2reg(self, bus_item, rw):
        rw.kind = access_e.UVM_READ if bus_item.op == ApbOp.READ else access_e.UVM_WRITE
        rw.addr = bus_item.addr
        rw.data = int(bus_item.data) if bus_item.data is not None else 0
        rw.status = status_t.IS_OK if bus_item.slverr == 0 else status_t.IS_NOT_OK
