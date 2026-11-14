"""Concrete implementations of the conceptual interfaces in interfaces_v1.py."""
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import re

from interfaces_v1 import LoginShell, Module, OperatingSystem, Target

SCRIPTS = Path(__file__).resolve().parent / "scripts"


def _shell_path(shell: LoginShell) -> str:
    path = shell.path()
    if not isinstance(path, PurePosixPath) or not path.is_absolute() or ".." in path.parts:
        raise ValueError("login-shell path must be absolute and contain no parent traversal")
    return str(path)


@dataclass(frozen=True)
class OpenSuseTumbleweed:
    """An OperatingSystem implementation; its guard runs before dependent modules."""

    def identity(self) -> str:
        return "opensuse-tumbleweed"

    def dependencies(self) -> tuple[Module, ...]:
        return ()

    def ensure(self, target: Target) -> None:
        target.run(SCRIPTS / "opensuse-ensure.sh")


@dataclass(frozen=True)
class ZshOnTumbleweed:
    """A LoginShell implementation with an explicit, static path declaration."""

    os: OperatingSystem

    def path(self) -> PurePosixPath:
        return PurePosixPath("/usr/bin/zsh")

    def dependencies(self) -> tuple[Module, ...]:
        return (self.os,)

    def ensure(self, target: Target) -> None:
        target.run(SCRIPTS / "zsh-ensure.sh", (_shell_path(self),))


@dataclass(frozen=True)
class LinuxLocalAccount:
    """An Account implementation shared by configured account instances."""

    name: str
    os: OperatingSystem
    shell: LoginShell

    def dependencies(self) -> tuple[Module, ...]:
        return (self.os, self.shell)

    def ensure(self, target: Target) -> None:
        if self.name == "root" or not re.fullmatch(r"[a-z][a-z0-9-]*", self.name):
            raise ValueError("invalid unprivileged account name")
        target.run(SCRIPTS / "account-ensure.sh", (self.name, _shell_path(self.shell)))
