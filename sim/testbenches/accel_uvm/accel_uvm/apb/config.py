"""APB agent configuration object."""

from pyuvm import uvm_object


class ApbConfig(uvm_object):
    """Holds the virtual interface and width parameters for the APB agent."""

    def __init__(self, name="apb_cfg"):
        super().__init__(name)
        # DUT signal interface set by the test (AccelVif instance)
        self.vif = None
        self.addr_width = 10
        self.data_width = 32
