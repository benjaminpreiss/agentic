"""Deployment composition root: these objects are configured module instances."""
from deployment import Instance
from interfaces_v1 import Account, LoginShell, Module, OperatingSystem
from modules import LinuxLocalAccount, OpenSuseTumbleweed, ZshOnTumbleweed

host: Instance[OperatingSystem] = Instance("host", OpenSuseTumbleweed())
interactive: Instance[LoginShell] = Instance("interactive", ZshOnTumbleweed(os=host.module))
agentic: Instance[Account] = Instance(
    "agentic", LinuxLocalAccount(name="agentic", os=host.module, shell=interactive.module)
)

DEPLOYMENT: tuple[Instance[Module], ...] = (host, interactive, agentic)
