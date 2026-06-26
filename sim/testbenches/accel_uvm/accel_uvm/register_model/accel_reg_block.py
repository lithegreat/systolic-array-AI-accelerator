"""Register block for the accelerator control-unit register map."""

from pyuvm import uvm_reg_block, uvm_reg_map

from .accel_regs import (
    CtrlReg,
    StatusReg,
    MDimReg,
    NDimReg,
    KDimReg,
    IntEnReg,
    IntStatReg,
)

# Absolute APB addresses (APB_AW=10, CTRL region at PADDR[9:8]=2'b01)
CTRL_BASE = 0x100
OFF_CTRL = 0x00
OFF_STATUS = 0x04
OFF_M_DIM = 0x08
OFF_N_DIM = 0x0C
OFF_INT_EN = 0x10
OFF_INT_STAT = 0x14
OFF_K_DIM = 0x18


class AccelRegBlock(uvm_reg_block):
    """UVM register block for accelerator_top control registers."""

    def __init__(self, name="accel_reg_block"):
        super().__init__(name)
        self.ctrl = None
        self.status = None
        self.m_dim = None
        self.n_dim = None
        self.k_dim = None
        self.int_en = None
        self.int_stat = None

    def build(self):
        # One flat address map; base_addr=0 (absolute addresses in add_reg)
        self.def_map = uvm_reg_map("map")
        self.def_map.configure(self, 0)

        # Instantiate registers
        self.ctrl = CtrlReg("ctrl")
        self.status = StatusReg("status")
        self.m_dim = MDimReg("m_dim")
        self.n_dim = NDimReg("n_dim")
        self.k_dim = KDimReg("k_dim")
        self.int_en = IntEnReg("int_en")
        self.int_stat = IntStatReg("int_stat")

        # configure(parent_block, offset_hex_str, has_coverage_str)
        self.ctrl.configure(self, hex(CTRL_BASE + OFF_CTRL), "")
        self.status.configure(self, hex(CTRL_BASE + OFF_STATUS), "")
        self.m_dim.configure(self, hex(CTRL_BASE + OFF_M_DIM), "")
        self.n_dim.configure(self, hex(CTRL_BASE + OFF_N_DIM), "")
        self.k_dim.configure(self, hex(CTRL_BASE + OFF_K_DIM), "")
        self.int_en.configure(self, hex(CTRL_BASE + OFF_INT_EN), "")
        self.int_stat.configure(self, hex(CTRL_BASE + OFF_INT_STAT), "")

        # Map registers (offset from map base = absolute address since base=0)
        self.def_map.add_reg(self.ctrl, hex(CTRL_BASE + OFF_CTRL), "RW")
        self.def_map.add_reg(self.status, hex(CTRL_BASE + OFF_STATUS), "RW")
        self.def_map.add_reg(self.m_dim, hex(CTRL_BASE + OFF_M_DIM), "RW")
        self.def_map.add_reg(self.n_dim, hex(CTRL_BASE + OFF_N_DIM), "RW")
        self.def_map.add_reg(self.k_dim, hex(CTRL_BASE + OFF_K_DIM), "RW")
        self.def_map.add_reg(self.int_en, hex(CTRL_BASE + OFF_INT_EN), "RW")
        self.def_map.add_reg(self.int_stat, hex(CTRL_BASE + OFF_INT_STAT), "W1C")

        self.set_lock()
