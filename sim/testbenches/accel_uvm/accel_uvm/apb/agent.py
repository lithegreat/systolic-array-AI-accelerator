"""APB agent – bundles driver, monitor, and sequencer."""

from pyuvm import uvm_agent

from .driver import ApbDriver
from .monitor import ApbMonitor
from .sequencer import ApbSequencer


class ApbAgent(uvm_agent):
    def __init__(self, name, parent):
        super().__init__(name, parent)
        self.driver = None
        self.monitor = None
        self.sequencer = None

    def build_phase(self):
        super().build_phase()
        self.sequencer = ApbSequencer("sequencer", self)
        self.driver = ApbDriver("driver", self)
        self.monitor = ApbMonitor("monitor", self)

    def connect_phase(self):
        super().connect_phase()
        self.driver.seq_item_port.connect(self.sequencer.seq_item_export)
