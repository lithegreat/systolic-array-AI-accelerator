"""Register field and register class definitions for accelerator_top.

Address map (absolute, APB_AW=10):
  Control unit region (PADDR[9:8]=2'b01 → 0x100–0x1FF):
    0x100  CTRL      [0]=start  [1]=softrst
    0x104  STATUS    [0]=busy   [1]=done (W1C)
    0x108  M_DIM     [31:0] matrix A rows
    0x10C  N_DIM     [31:0] matrix B cols
    0x110  INT_EN    [0]=done-IRQ enable
    0x114  INT_STAT  [0]=done-IRQ pending (W1C)
    0x118  K_DIM     [31:0] reduction depth
"""

from pyuvm import uvm_reg, uvm_reg_field


class CtrlReg(uvm_reg):
    """CTRL register: bit[0]=start (SC), bit[1]=softrst (SC)."""

    def __init__(self, name="ctrl", reg_width=32):
        super().__init__(name, reg_width)
        self.start = None
        self.softrst = None

    def build(self):
        self.start = uvm_reg_field("start")
        self.softrst = uvm_reg_field("softrst")
        # configure(parent, n_bits, lsb_pos, access, volatile, reset)
        self.start.configure(self, 1, 0, "RW", True, 0)
        self.softrst.configure(self, 1, 1, "RW", True, 0)


class StatusReg(uvm_reg):
    """STATUS register: bit[0]=busy (RO), bit[1]=done (W1C)."""

    def __init__(self, name="status", reg_width=32):
        super().__init__(name, reg_width)
        self.busy = None
        self.done = None

    def build(self):
        self.busy = uvm_reg_field("busy")
        self.done = uvm_reg_field("done")
        self.busy.configure(self, 1, 0, "RO", True, 0)
        self.done.configure(self, 1, 1, "W1C", True, 0)


class MDimReg(uvm_reg):
    """M_DIM register: number of rows (clamped to physical M by RTL)."""

    def __init__(self, name="m_dim", reg_width=32):
        super().__init__(name, reg_width)
        self.value = None

    def build(self):
        self.value = uvm_reg_field("value")
        self.value.configure(self, 32, 0, "RW", False, 16)


class NDimReg(uvm_reg):
    """N_DIM register: number of columns."""

    def __init__(self, name="n_dim", reg_width=32):
        super().__init__(name, reg_width)
        self.value = None

    def build(self):
        self.value = uvm_reg_field("value")
        self.value.configure(self, 32, 0, "RW", False, 16)


class KDimReg(uvm_reg):
    """K_DIM register: reduction depth."""

    def __init__(self, name="k_dim", reg_width=32):
        super().__init__(name, reg_width)
        self.value = None

    def build(self):
        self.value = uvm_reg_field("value")
        self.value.configure(self, 32, 0, "RW", False, 16)


class IntEnReg(uvm_reg):
    """INT_EN register: bit[0]=done-IRQ enable."""

    def __init__(self, name="int_en", reg_width=32):
        super().__init__(name, reg_width)
        self.done_en = None

    def build(self):
        self.done_en = uvm_reg_field("done_en")
        self.done_en.configure(self, 1, 0, "RW", False, 0)


class IntStatReg(uvm_reg):
    """INT_STAT register: bit[0]=done-IRQ pending (W1C)."""

    def __init__(self, name="int_stat", reg_width=32):
        super().__init__(name, reg_width)
        self.done_irq = None

    def build(self):
        self.done_irq = uvm_reg_field("done_irq")
        self.done_irq.configure(self, 1, 0, "W1C", True, 0)
