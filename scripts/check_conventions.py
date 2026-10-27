#!/usr/bin/env python3
import glob
import os
import re
import sys


def check_interface_naming():
    interface_dir = os.path.join("docs", "interface")
    if not os.path.exists(interface_dir):
        print(f"Error: Directory {interface_dir} does not exist.")
        return 1

    exit_code = 0
    for filename in os.listdir(interface_dir):
        filepath = os.path.join(interface_dir, filename)

        # Skip directories
        if not os.path.isfile(filepath):
            continue

        # Skip README.md (case-insensitive check)
        if filename.lower() == "readme.md":
            continue

        # Check if the name ends with _if (excluding the extension)
        name, _ = os.path.splitext(filename)
        if not name.endswith("_if"):
            print(
                f"Error: Interface file '{filename}' does not end with '_if'. Rename it to '{name}_if{os.path.splitext(filename)[1]}'."
            )
            exit_code = 1

    if exit_code == 0:
        print("Success: All interface files follow the '_if' naming convention.")

    return exit_code


def check_root_files():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    allowed_files = {"readme.md", "requirements.txt", "agents.md"}
    ignored_dirs = {"bin"}
    exit_code = 0
    for filename in os.listdir(root_dir):
        filepath = os.path.join(root_dir, filename)
        if filename in ignored_dirs:
            continue
        if not os.path.isfile(filepath):
            continue
        if filename.startswith("."):
            continue
        if filename.lower() in allowed_files:
            continue
        print(
            f"Error: Invalid file in root directory '{filename}'. "
            "Only README.md, AGENTS.md, requirements.txt, and hidden files "
            "(.) are allowed."
        )
        exit_code = 1

    if exit_code == 0:
        print("Success: Root directory contains only allowed files.")

    return exit_code


def read_goals(path):
    goals = {}
    with open(path) as f:
        for line in f:
            m = re.match(r'([A-Z][A-Z0-9_]*)=("[^"]*"|[^\s#]*)', line)
            if m:
                goals[m.group(1)] = m.group(2).strip('"')
    return goals


def check_asic_goals():
    """asic/common/goals.env is the source of truth; keep the SDC in sync."""
    goals_path = os.path.join("asic", "common", "goals.env")
    if not os.path.isfile(goals_path):
        print(f"Error: {goals_path} does not exist.")
        return 1

    goals = read_goals(goals_path)
    required = (
        "DIE_SIDE_UM",
        "CORE_OFFSET_UM",
        "PIN_LAYERS",
        "CLOCK_MHZ",
        "MAX_UTIL_PCT",
        "GATES_MODE",
        "FLOORPLAN_CORE_SIDE_UM",
    )
    missing = [k for k in required if k not in goals]
    if missing:
        print(f"Error: {goals_path} lacks keys: {', '.join(missing)}")
        return 1

    exit_code = 0
    period = 1000.0 / float(goals["CLOCK_MHZ"])
    for sdc in glob.glob(os.path.join("asic", "common", "sdc", "*.sdc")):
        with open(sdc) as f:
            for m in re.finditer(r"create_clock\b.*?-period\s+([0-9.]+)", f.read()):
                if abs(float(m.group(1)) - period) > 1e-6:
                    print(
                        f"Error: {sdc} clock period {m.group(1)} ns does not match "
                        f"CLOCK_MHZ={goals['CLOCK_MHZ']} ({period:g} ns) in {goals_path}."
                    )
                    exit_code = 1

    if goals["GATES_MODE"] not in ("warn", "fail"):
        print(f"Error: GATES_MODE must be warn or fail in {goals_path}.")
        exit_code = 1

    if exit_code == 0:
        print("Success: ASIC goals are complete and consistent with the SDC.")

    return exit_code


def main():
    if_exit_code = check_interface_naming()
    root_exit_code = check_root_files()
    goals_exit_code = check_asic_goals()

    sys.exit(if_exit_code or root_exit_code or goals_exit_code)


if __name__ == "__main__":
    main()
