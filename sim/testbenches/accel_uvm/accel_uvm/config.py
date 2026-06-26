"""Top-level configuration object for the accelerator UVM testbench."""

from pyuvm import uvm_object


class AccelConfig(uvm_object):
    """Holds DUT interface handle and GEMM parameters."""

    def __init__(self, name="accel_cfg"):
        super().__init__(name)
        # AccelVif instance – populated by the test before build_phase
        self.vif = None
        # GEMM tile dimensions (overridable via env vars)
        self.M = 16
        self.N = 16
        self.K = 16
        self.DATA_W = 8
        self.ACC_W = 32
