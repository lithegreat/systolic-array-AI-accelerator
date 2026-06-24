"""Virtual sequencer for the accelerator UVM environment."""

from pyuvm import uvm_sequencer


class AccelVSequencer(uvm_sequencer):
    """Holds handles to sub-sequencers so virtual sequences can coordinate."""

    def __init__(self, name, parent):
        super().__init__(name, parent)
        # Populated by AccelEnv.connect_phase
        self.apb_seqr = None
