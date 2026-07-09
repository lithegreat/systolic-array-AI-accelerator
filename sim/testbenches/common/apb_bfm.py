"""Minimal cocotb APB master BFM (zero-wait subordinate)."""

from __future__ import annotations

from cocotb.triggers import RisingEdge, Timer


class ApbMaster:
    def __init__(self, dut, prefix: str = "") -> None:
        self.dut = dut
        self.p = prefix
        # Initialise to idle.
        self._set("PSEL", 0)
        self._set("PENABLE", 0)
        self._set("PWRITE", 0)
        self._set("PADDR", 0)
        self._set("PWDATA", 0)

    def _sig(self, name: str):
        return getattr(self.dut, self.p + name)

    def _set(self, name: str, val) -> None:
        try:
            self._sig(name).value = int(val)
        except AttributeError:
            pass

    async def write(self, addr: int, data: int) -> None:
        # SETUP
        self._set("PADDR", addr)
        self._set("PWDATA", data)
        self._set("PWRITE", 1)
        self._set("PSEL", 1)
        self._set("PENABLE", 0)
        await RisingEdge(self.dut.clk)
        # ACCESS
        self._set("PENABLE", 1)
        await RisingEdge(self.dut.clk)
        # IDLE
        self._set("PSEL", 0)
        self._set("PENABLE", 0)
        self._set("PWRITE", 0)

    async def read(self, addr: int) -> int:
        self._set("PADDR", addr)
        self._set("PWRITE", 0)
        self._set("PSEL", 1)
        self._set("PENABLE", 0)
        await RisingEdge(self.dut.clk)
        self._set("PENABLE", 1)
        await Timer(1, units="ns")
        rdata = int(self._sig("PRDATA").value)
        await RisingEdge(self.dut.clk)
        self._set("PSEL", 0)
        self._set("PENABLE", 0)
        return rdata
