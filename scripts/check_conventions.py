#!/usr/bin/env python3
import os
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


def main():
    if_exit_code = check_interface_naming()
    root_exit_code = check_root_files()

    sys.exit(if_exit_code or root_exit_code)


if __name__ == "__main__":
    main()
