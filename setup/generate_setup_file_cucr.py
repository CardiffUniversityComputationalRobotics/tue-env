#! /usr/bin/env python3

from typing import List

import os
import sys
import traceback


class SetupGenerator:
    def __init__(self, cucr_env_dir=None):
        if cucr_env_dir is None:
            cucr_env_dir = os.environ["CUCR_ENV_DIR"]
        if not cucr_env_dir:
            raise ValueError("'cucr_env_dir' can't be empty as it would resolve to '/'")
        self._cucr_env_dir = cucr_env_dir
        self._cucr_dependencies_dir = os.path.join(self._cucr_env_dir, ".env", "dependencies")
        cucr_env_targets_dir = os.environ["CUCR_ENV_TARGETS_DIR"]
        if not cucr_env_targets_dir:
            raise ValueError("'cucr_env_targets_dir' can't be empty as it would resolve to '/'")
        self._cucr_env_targets_dir = cucr_env_targets_dir

        self._visited_targets = set()

    def generate_setup_file(self) -> None:
        installed_targets_dir = os.path.join(self._cucr_env_dir, ".env", "installed")

        lines = ["#! /usr/bin/env bash\n", "# This file was auto-generated by cucr-get. Do not change this file.\n"]

        if os.path.isdir(self._cucr_dependencies_dir):
            for target in os.listdir(installed_targets_dir):
                lines.extend(self._generate_setup_file_rec(target))

        setup_dir = os.path.join(self._cucr_env_dir, ".env", "setup")
        os.makedirs(setup_dir, exist_ok=True)
        setup_file = os.path.join(setup_dir, "target_setup.bash")
        with open(setup_file, "w") as f:
            f.writelines(lines)

    def _generate_setup_file_rec(self, target: str) -> List[str]:
        if target in self._visited_targets:
            return []

        self._visited_targets.add(target)

        target_dep_file = os.path.join(self._cucr_dependencies_dir, target)
        if not os.path.isfile(target_dep_file):
            return []

        with open(target_dep_file, "r") as dep_f:
            deps = dep_f.readlines()

        lines = []
        for dep in map(lambda x: x.strip(), deps):
            # You shouldn't depend on yourself
            if dep == target:
                continue
            lines.extend(self._generate_setup_file_rec(dep))

        target_setup_file = os.path.join(self._cucr_env_targets_dir, target, "setup")
        if os.path.isfile(target_setup_file):
            rel_target_setup_file = os.path.relpath(target_setup_file, self._cucr_env_dir)
            lines.append(f"source ${{CUCR_ENV_DIR}}/{rel_target_setup_file}\n")

        return lines


def main() -> int:
    try:
        generator = SetupGenerator()
        generator.generate_setup_file()
    except Exception as e:
        print(f"ERROR: Could not generate setup file: {repr(e)}\n{traceback.format_exc()}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
