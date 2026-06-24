"""Accelerator UVM environment.

Builds:
  - APB agent (active)
  - Register model (AccelRegBlock) connected via adapter to APB sequencer
  - Virtual sequencer (exposes apb_seqr to virtual sequences)
"""

from pyuvm import uvm_env, ConfigDB

from .apb.agent import ApbAgent
from .apb.config import ApbConfig
from .register_model.accel_reg_block import AccelRegBlock
from .register_model.accel_reg_adapter import AccelRegAdapter
from .vsequencer import AccelVSequencer


class AccelEnv(uvm_env):
    def __init__(self, name, parent):
        super().__init__(name, parent)
        self.apb_agent = None
        self.vseqr = None
        self.reg_model = None
        self.reg_adapter = None
        self.cfg = None

    def build_phase(self):
        super().build_phase()
        self.cfg = ConfigDB().get(self, "", "cfg")

        # Propagate APB config to agent sub-components via ConfigDB
        apb_cfg = ApbConfig.create("apb_cfg")
        apb_cfg.vif = self.cfg.vif
        ConfigDB().set(self, "apb_agent.*", "apb_cfg", apb_cfg)

        self.apb_agent = ApbAgent("apb_agent", self)
        self.vseqr = AccelVSequencer("vseqr", self)

        # Build the register model (not locked yet – connect_phase finalises it)
        self.reg_model = AccelRegBlock("reg_model")
        self.reg_model.build()
        self.reg_adapter = AccelRegAdapter("reg_adapter")

    def connect_phase(self):
        super().connect_phase()
        # Wire virtual sequencer → APB sequencer
        self.vseqr.apb_seqr = self.apb_agent.sequencer
        # Wire register model → APB sequencer via adapter
        self.reg_model.def_map.set_sequencer(self.apb_agent.sequencer)
        self.reg_model.def_map.set_adapter(self.reg_adapter)
