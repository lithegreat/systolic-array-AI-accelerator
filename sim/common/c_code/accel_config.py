#!/usr/bin/env python3
"""Canonical accelerator build variants shared by scripts and generated tests."""

from __future__ import annotations

import argparse
import json
import shlex
from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class AcceleratorConfig:
    """Build-time accelerator geometry and arithmetic parameters."""

    name: str
    m: int
    n: int
    k: int
    data_w: int
    acc_w: int
    description: str

    def __post_init__(self) -> None:
        if self.m <= 0 or self.n <= 0 or self.k <= 0:
            raise ValueError(f"{self.name}: dimensions must be positive")
        if self.data_w not in (8, 16, 32):
            raise ValueError(f"{self.name}: DATA_W must be one of 8, 16, 32")
        if 32 % self.data_w != 0:
            raise ValueError(f"{self.name}: DATA_W must divide the 32-bit APB bus")
        if self.acc_w != 32:
            raise ValueError(
                f"{self.name}: only ACC_W=32 is supported by firmware today"
            )

    @property
    def is_square_tile(self) -> bool:
        return self.m == self.n == self.k

    @property
    def elem_ctype(self) -> str:
        return {8: "int8_t", 16: "int16_t", 32: "int32_t"}[self.data_w]

    @property
    def golden_ctype(self) -> str:
        return {32: "int32_t"}[self.acc_w]

    def to_shell(self) -> str:
        """Emit shell assignments suitable for eval in trusted repo scripts."""
        values = {
            "ACCEL_VARIANT": self.name,
            "ACCEL_M": self.m,
            "ACCEL_N": self.n,
            "ACCEL_K": self.k,
            "ACCEL_DATA_W": self.data_w,
            "ACCEL_ACC_W": self.acc_w,
            "ACCEL_DESCRIPTION": self.description,
        }
        if self.is_square_tile:
            values["ACCEL_DIM"] = self.m
        return "\n".join(
            f"{key}={shlex.quote(str(value))}" for key, value in values.items()
        )


DEFAULT_VARIANT = "int8_16x16"

VARIANTS: dict[str, AcceleratorConfig] = {
    "int8_32x32": AcceleratorConfig(
        name="int8_32x32",
        m=32,
        n=32,
        k=32,
        data_w=8,
        acc_w=32,
        description="Temporary 32x32 test variant",
    ),
    "int8_16x16": AcceleratorConfig(
        name="int8_16x16",
        m=16,
        n=16,
        k=16,
        data_w=8,
        acc_w=32,
        description="Default full-size INT8 accelerator used by local and SoC simulation.",
    ),
    "int8_8x8": AcceleratorConfig(
        name="int8_8x8",
        m=8,
        n=8,
        k=8,
        data_w=8,
        acc_w=32,
        description="PYNQ-Z1-friendly INT8 accelerator build that fits the xc7z020.",
    ),
    "int16_16x16": AcceleratorConfig(
        name="int16_16x16",
        m=16,
        n=16,
        k=16,
        data_w=16,
        acc_w=32,
        description="Legacy wider datapath variant for arithmetic and resource comparisons.",
    ),
}


def get_variant(name: str) -> AcceleratorConfig:
    try:
        return VARIANTS[name]
    except KeyError as exc:
        names = ", ".join(sorted(VARIANTS))
        raise ValueError(
            f"unknown accelerator variant '{name}' (choose one of: {names})"
        ) from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--variant",
        default=DEFAULT_VARIANT,
        help=f"accelerator variant (default: {DEFAULT_VARIANT})",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="list available variants and exit",
    )
    parser.add_argument(
        "--format",
        choices=("json", "shell"),
        default="json",
        help="output format for the selected variant",
    )
    args = parser.parse_args()

    if args.list:
        for variant in VARIANTS.values():
            print(
                f"{variant.name}: M={variant.m} N={variant.n} K={variant.k} "
                f"DATA_W={variant.data_w} ACC_W={variant.acc_w} - {variant.description}"
            )
        return 0

    try:
        variant = get_variant(args.variant)
    except ValueError as exc:
        parser.error(str(exc))
    if args.format == "shell":
        print(variant.to_shell())
    else:
        print(json.dumps(asdict(variant), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
