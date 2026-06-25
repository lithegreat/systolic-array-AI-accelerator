"""APB sequencer."""

from pyuvm import uvm_sequencer


class ApbSequencer(uvm_sequencer):
    def __init__(self, name, parent):
        super().__init__(name, parent)
