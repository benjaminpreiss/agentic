"""A configured, named module instance in one deployment."""
from dataclasses import dataclass
from typing import Generic, TypeVar
from interfaces_v1 import Module

T = TypeVar("T", bound=Module, covariant=True)


@dataclass(frozen=True)
class Instance(Generic[T]):
    name: str
    module: T
