"""Conceptual deployment interfaces. No OS, shell or account implementation lives here."""
from pathlib import Path, PurePosixPath
from typing import Protocol


class Target(Protocol):
    """Internal effect seam. Expansion records calls; execution runs them on a target."""

    def run(self, script: Path, args: tuple[str, ...] = ()) -> None: ...


class Module(Protocol):
    """Planner-facing behaviour shared by deployment modules, not a resource interface."""

    def dependencies(self) -> tuple["Module", ...]: ...
    def ensure(self, target: Target) -> None: ...


class OperatingSystem(Module, Protocol):
    """A prepared operating-system substrate on the target."""

    def identity(self) -> str: ...


class LoginShell(Module, Protocol):
    """One configured login shell. path() is a pure declaration, not host discovery."""

    def path(self) -> PurePosixPath: ...


class Account(Module, Protocol):
    """One configured local account whose ensure transition realizes its bindings."""

    @property
    def name(self) -> str: ...

    @property
    def shell(self) -> LoginShell: ...
