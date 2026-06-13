"""Shared helpers for cocotb testbenches.

Provides signed conversion utilities, deterministic random matrix generation,
and a NumPy reference matrix-multiply that mirrors the wrap-around behaviour
of the RTL accumulator (DATA_W signed inputs, ACC_W signed accumulator).
"""

from __future__ import annotations

import random
from typing import Iterable, List

import numpy as np


# -----------------------------------------------------------------------------
# Signed <-> unsigned conversion (for slicing into bus values)
# -----------------------------------------------------------------------------
def to_signed(value: int, width: int) -> int:
    """Interpret the low `width` bits of `value` as a signed integer."""
    mask = (1 << width) - 1
    value &= mask
    sign_bit = 1 << (width - 1)
    return value - (1 << width) if value & sign_bit else value


def to_unsigned(value: int, width: int) -> int:
    """Encode a signed integer into the low `width` bits as two's complement."""
    return value & ((1 << width) - 1)


# -----------------------------------------------------------------------------
# Deterministic random matrix helpers
# -----------------------------------------------------------------------------
def random_matrix(rows: int, cols: int, data_w: int, rng: random.Random) -> np.ndarray:
    """Return a deterministic random signed integer matrix of given width."""
    lo = -(1 << (data_w - 1))
    hi = (1 << (data_w - 1)) - 1
    flat = [rng.randint(lo, hi) for _ in range(rows * cols)]
    return np.array(flat, dtype=np.int64).reshape(rows, cols)


# -----------------------------------------------------------------------------
# Reference matmul with explicit ACC_W wrap (matches RTL accumulator behaviour)
# -----------------------------------------------------------------------------
def matmul_ref(a: np.ndarray, b: np.ndarray, acc_w: int) -> np.ndarray:
    """Compute `a @ b` and wrap each element into a signed `acc_w`-bit range."""
    raw = a.astype(np.int64) @ b.astype(np.int64)
    mask = (1 << acc_w) - 1
    sign = 1 << (acc_w - 1)
    wrapped = np.vectorize(lambda v: ((v & mask) ^ sign) - sign)(raw)
    return wrapped.astype(np.int64)


# -----------------------------------------------------------------------------
# APB-style packing for matrix buffer writes (DATA_W in {8,16,32})
# -----------------------------------------------------------------------------
def pack_words(values: Iterable[int], data_w: int, apb_dw: int = 32) -> List[int]:
    """Pack a row-major flat sequence into `apb_dw`-bit words, little-element-first."""
    per_word = apb_dw // data_w
    assert apb_dw % data_w == 0, "apb_dw must be a multiple of data_w"
    mask = (1 << data_w) - 1
    out: List[int] = []
    buf: List[int] = []
    for v in values:
        buf.append(to_unsigned(v, data_w))
        if len(buf) == per_word:
            word = 0
            for i, e in enumerate(buf):
                word |= (e & mask) << (i * data_w)
            out.append(word)
            buf = []
    if buf:
        # pad the partial word with zeros
        word = 0
        for i, e in enumerate(buf):
            word |= (e & ((1 << data_w) - 1)) << (i * data_w)
        out.append(word)
    return out


def unpack_word(word: int, data_w: int, count: int) -> List[int]:
    """Unpack a packed word into `count` signed elements."""
    mask = (1 << data_w) - 1
    return [to_signed((word >> (i * data_w)) & mask, data_w) for i in range(count)]
