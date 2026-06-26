"""Base test for the accelerator UVM testbench.

Responsibilities:
  - Create AccelVif (DUT signal handle container)
  - Populate AccelConfig and push it to ConfigDB
  - Instantiate AccelEnv
  - Start a 100 MHz clock
  - Assert / release active-high reset (5 cycles)

Derived tests should:
  1. Decorate with ``@pyuvm.test()``
  2. Override ``run_phase`` as::

         async def run_phase(self):
             self.raise_objection()
             await super().run_phase()   # clock + reset, base drops its own objection
             # … test-specific sequences …
             self.drop_objection()
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from pyuvm import uvm_test, ConfigDB

from .config import AccelConfig
from .env import AccelEnv


_CLK_PERIOD_NS = 10  # 100 MHz


class AccelVif:
    """Thin container that maps DUT cocotb handles to stable attribute names."""

    def __init__(self, dut):
        self.clk = dut.clk_in
        self.rst = dut.reset_int
        self.PADDR = dut.PADDR
        self.PSEL = dut.PSEL
        self.PENABLE = dut.PENABLE
        self.PWRITE = dut.PWRITE
        self.PWDATA = dut.PWDATA
        self.PRDATA = dut.PRDATA
        self.PREADY = dut.PREADY
        self.PSLVERR = dut.PSLVERR
        self.irq_en_4 = dut.irq_en_4
        self.ss_ctrl_4 = dut.ss_ctrl_4
        self.irq_4 = dut.irq_4


class AccelBaseTest(uvm_test):
    """Base test: sets up DUT clock/reset and the UVM environment."""

    def __init__(self, name="accel_base_test", parent=None):
        super().__init__(name, parent)
        self.dut = cocotb.top
        self.vif = None
        self.cfg = None
        self.env = None

    def build_phase(self):
        super().build_phase()

        self.vif = AccelVif(self.dut)

        self.cfg = AccelConfig.create("cfg")
        self.cfg.vif = self.vif
        self.cfg.M = int(os.environ.get("M", "16"))
        self.cfg.N = int(os.environ.get("N", "16"))
        self.cfg.K = int(os.environ.get("K", "16"))
        self.cfg.DATA_W = int(os.environ.get("DATA_W", "8"))
        self.cfg.ACC_W = int(os.environ.get("ACC_W", "32"))

        ConfigDB().set(self, "env", "cfg", self.cfg)
        self.env = AccelEnv("env", self)

    async def run_phase(self):
        """Start clock, apply reset, return.  Derived tests wrap this."""
        self.raise_objection()

        # Clock
        cocotb.start_soon(Clock(self.vif.clk, _CLK_PERIOD_NS, "ns").start())

        # Assert reset (active-high) and idle the APB bus
        self.vif.rst.value = 1
        self.vif.PSEL.value = 0
        self.vif.PENABLE.value = 0
        self.vif.PWRITE.value = 0
        self.vif.PADDR.value = 0
        self.vif.PWDATA.value = 0
        self.vif.irq_en_4.value = 0
        self.vif.ss_ctrl_4.value = 0

        await ClockCycles(self.vif.clk, 5)
        self.vif.rst.value = 0
        await ClockCycles(self.vif.clk, 2)

        self.drop_objection()
