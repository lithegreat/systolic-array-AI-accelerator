#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# gen_accel_data.py -- generate a self-checking GEMM test vector header for the
# systolic-array accelerator firmware (Didactic-SoC/sw/accel/accel.c).
#
# This mirrors the methodology of sim/common/c_code/main_gemm.c (random signed
# inputs + a precomputed golden reference), but sizes the problem for the
# accelerator the firmware actually drives: a single fixed ACC_M x ACC_N x ACC_K
# pass with DATA_W-bit signed elements.
#
# The hardware computes the standard product C = A * B
#   C[i][j] = sum_k A[i][k] * B[k][j]
# with signed DATA_W x DATA_W multiplies accumulated in a 32-bit register that
# wraps in two's complement (no saturation -- see rtl/MAC/mac_pe.sv).  The golden
# reference below reproduces that exact wrap so it matches the RTL bit-for-bit,
# even when the accumulated dot product overflows 32 bits.
#
# Usage:
#   python3 sim/common/c_code/gen_accel_data.py [--variant int8_16x16] [--seed N]
# Regenerate the header whenever the accelerator build variant changes.
# -----------------------------------------------------------------------------
import argparse
from pathlib import Path

import numpy as np

from accel_config import DEFAULT_VARIANT, get_variant

DEFAULT_SEED = 0xACCE
DEFAULT_CASE = "random"
CASES = (
    "random",
    "zero",
    "identity",
    "checkerboard",
    "maxpos",
    "minneg",
    "minmax",
)
# This file lives at sim/common/c_code/gen_accel_data.py, so the repo root is
# four parents up; the generated header lands in the Didactic-SoC submodule.
OUT_PATH = (
    Path(__file__).resolve().parents[3]
    / "Didactic-SoC"
    / "sw"
    / "accel"
    / "accel_gemm_data.h"
)


def wrap_signed(values: np.ndarray, bits: int) -> np.ndarray:
    """Reduce integer values into a signed two's-complement field of `bits`."""
    mod = 1 << bits
    half = 1 << (bits - 1)
    return ((values + half) % mod) - half


def fmt_rows(flat: np.ndarray, cols: int, indent: str = "    ") -> str:
    """Format a flat array as comma-separated rows of `cols` values."""
    lines = []
    for r in range(0, len(flat), cols):
        chunk = ", ".join(str(int(v)) for v in flat[r : r + cols])
        lines.append(f"{indent}{chunk},")
    return "\n".join(lines)


def make_matrices(
    cfg, rng: np.random.Generator, case: str
) -> tuple[np.ndarray, np.ndarray]:
    """Generate A/B matrices for a named deterministic test case."""
    lo = -(1 << (cfg.data_w - 1))
    hi = 1 << (cfg.data_w - 1)  # exclusive upper bound -> max = hi - 1
    max_val = hi - 1

    if case == "random":
        a = rng.integers(lo, hi, size=(cfg.m, cfg.k), dtype=np.int64)
        b = rng.integers(lo, hi, size=(cfg.k, cfg.n), dtype=np.int64)
    elif case == "zero":
        a = np.zeros((cfg.m, cfg.k), dtype=np.int64)
        b = np.zeros((cfg.k, cfg.n), dtype=np.int64)
    elif case == "identity":
        a = np.zeros((cfg.m, cfg.k), dtype=np.int64)
        b = rng.integers(lo, hi, size=(cfg.k, cfg.n), dtype=np.int64)
        for idx in range(min(cfg.m, cfg.k)):
            a[idx, idx] = 1
    elif case == "checkerboard":
        a = np.fromfunction(
            lambda row, col: np.where(((row + col) % 2) == 0, max_val, lo),
            (cfg.m, cfg.k),
            dtype=int,
        ).astype(np.int64)
        b = np.fromfunction(
            lambda row, col: np.where(((row + col) % 2) == 0, lo, max_val),
            (cfg.k, cfg.n),
            dtype=int,
        ).astype(np.int64)
    elif case == "maxpos":
        a = np.full((cfg.m, cfg.k), max_val, dtype=np.int64)
        b = np.full((cfg.k, cfg.n), max_val, dtype=np.int64)
    elif case == "minneg":
        a = np.full((cfg.m, cfg.k), lo, dtype=np.int64)
        b = np.full((cfg.k, cfg.n), lo, dtype=np.int64)
    elif case == "minmax":
        a = np.fromfunction(
            lambda row, col: np.where((col % 2) == 0, lo, max_val),
            (cfg.m, cfg.k),
            dtype=int,
        ).astype(np.int64)
        b = np.fromfunction(
            lambda row, col: np.where((row % 2) == 0, max_val, lo),
            (cfg.k, cfg.n),
            dtype=int,
        ).astype(np.int64)
    else:
        raise ValueError(f"unknown test case '{case}'")

    return a, b


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--variant",
        default=DEFAULT_VARIANT,
        help=f"accelerator build variant (default: {DEFAULT_VARIANT})",
    )
    ap.add_argument(
        "--seed",
        type=lambda s: int(s, 0),
        default=DEFAULT_SEED,
        help=f"PRNG seed (default 0x{DEFAULT_SEED:X})",
    )
    ap.add_argument(
        "--case",
        choices=CASES,
        default=DEFAULT_CASE,
        help=f"matrix pattern to generate (default: {DEFAULT_CASE})",
    )
    ap.add_argument(
        "--list-cases",
        action="store_true",
        help="list supported matrix patterns and exit",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=OUT_PATH,
        help=f"output header path (default: {OUT_PATH})",
    )
    args = ap.parse_args()

    if args.list_cases:
        for case in CASES:
            print(case)
        return 0

    cfg = get_variant(args.variant)

    rng = np.random.default_rng(args.seed)
    a, b = make_matrices(cfg, rng, args.case)

    # Golden product with the same two's-complement 32-bit wrap as the RTL MAC.
    c = wrap_signed(a @ b, cfg.acc_w)

    a_flat = a.reshape(-1)  # row-major A[i*K + k]
    b_flat = b.reshape(-1)  # row-major B[k*N + j]
    c_flat = c.reshape(-1)  # row-major C[i*N + j]

    header = f"""\
#ifndef __ACCEL_GEMM_DATA_H__
#define __ACCEL_GEMM_DATA_H__

#include <stdint.h>

/*
 * Auto-generated by sim/common/c_code/gen_accel_data.py
 * Variant: {cfg.name}, case: {args.case} (seed 0x{args.seed:X}).
 * Do not edit by hand; rerun the generator instead.
 *
 * Random signed {cfg.data_w}-bit GEMM test vectors for the systolic-array
 * accelerator.  The golden matrix is C = A * B with
 *   C[i][j] = sum_k A[i][k] * B[k][j]
 * accumulated in 32-bit two's-complement arithmetic (wraps, no saturation),
 * matching rtl/MAC/mac_pe.sv exactly.
 *
 * Layout (row-major, matching the hardware buffers):
 *   A[i][k] -> accel_A[i * ACC_K + k]
 *   B[k][j] -> accel_B[k * ACC_N + j]
 *   C[i][j] -> accel_golden[i * ACC_N + j]
 */

#define ACC_VARIANT "{cfg.name}"
#define ACC_M {cfg.m}
#define ACC_N {cfg.n}
#define ACC_K {cfg.k}
#define ACC_DATA_W {cfg.data_w}
#define ACC_ACC_W {cfg.acc_w}

static const {cfg.elem_ctype} accel_A[ACC_M * ACC_K] = {{
{fmt_rows(a_flat, cfg.k)}
}};

static const {cfg.elem_ctype} accel_B[ACC_K * ACC_N] = {{
{fmt_rows(b_flat, cfg.n)}
}};

static const {cfg.golden_ctype} accel_golden[ACC_M * ACC_N] = {{
{fmt_rows(c_flat, cfg.n)}
}};

#endif /* __ACCEL_GEMM_DATA_H__ */
"""

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(header)
    print(
        f"wrote {args.out} "
        f"(variant {cfg.name}, case {args.case}, seed 0x{args.seed:X}, "
        f"{cfg.m}x{cfg.n}x{cfg.k}, DATA_W={cfg.data_w})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
