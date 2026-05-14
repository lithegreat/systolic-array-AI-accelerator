"""Functional golden model for the systolic_array.

This is intentionally not cycle-accurate: it consumes the same matrices the
testbench feeds the DUT and returns the expected (c_data, c_row, c_col) drain
sequence, in the same row-major order the DUT emits.
"""

from __future__ import annotations

from typing import List, Tuple

import numpy as np

from golden import matmul_ref


def expected_drain(
    a: np.ndarray, b: np.ndarray, acc_w: int
) -> List[Tuple[int, int, int]]:
    """Return [(c_value, row, col), ...] in row-major order."""
    c = matmul_ref(a, b, acc_w)
    out: List[Tuple[int, int, int]] = []
    for i in range(c.shape[0]):
        for j in range(c.shape[1]):
            out.append((int(c[i, j]), i, j))
    return out
