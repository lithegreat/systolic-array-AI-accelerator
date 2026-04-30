"""Cycle-accurate Python golden model for mac_pe.

Mirrors the RTL exactly:
    on rising edge,
        if !rst_n: acc, a_out, b_out -> 0
        elif en:
            a_out <- a_in
            b_out <- b_in
            acc   <- (a_in*b_in) if clear_acc else (acc + a_in*b_in)
"""

from __future__ import annotations

from dataclasses import dataclass


def _wrap(value: int, width: int) -> int:
    mask = (1 << width) - 1
    sign = 1 << (width - 1)
    return ((value & mask) ^ sign) - sign


@dataclass
class MacPeGolden:
    data_w: int = 16
    acc_w: int = 32

    def __post_init__(self) -> None:
        self.acc = 0
        self.a_out = 0
        self.b_out = 0

    def reset(self) -> None:
        self.acc = 0
        self.a_out = 0
        self.b_out = 0

    def step(
        self, a_in: int, b_in: int, en: int, clear_acc: int, rst_n: int = 1
    ) -> None:
        if not rst_n:
            self.reset()
            return
        if not en:
            return
        product = _wrap(a_in, self.data_w) * _wrap(b_in, self.data_w)
        if clear_acc:
            self.acc = _wrap(product, self.acc_w)
        else:
            self.acc = _wrap(self.acc + product, self.acc_w)
        self.a_out = _wrap(a_in, self.data_w)
        self.b_out = _wrap(b_in, self.data_w)

    @property
    def pe_out(self) -> int:
        return self.acc
