# Tumbleweed systemd-networkd module (not deployable yet)

Implements the `networking@1` method contract on an **already-installed** openSUSE Tumbleweed system, without Nix. This package binds `python-runtime@1` for its target-side interpreter (the implementation dependency is not part of the `networking` interface). The separate [networkd example](../../examples/networkd/README.md) selects that Python instance explicitly; the original account introduction plan does not run this module.

- `inspect`: reports the selected interface's live MAC, link/addresses and default IPv4 route; nothing in that observation persists by assumption.
- `configure`: requires root, an already-active `systemd-networkd`, no active NetworkManager or wicked, a disposable VM and verified console. Uses the bound `/usr/bin/python3` to validate the selected interface/MAC and DHCP or static IPv4/CIDR, gateway and space-separated IPv4 DNS inputs. Stages only `/etc/systemd/network/10-agentic.network`, refusing an existing unmanaged file. **It does not reload/reconfigure networkd.** The file could still be picked up by a later external restart.

Inputs are `interface_name`, `network_mac`, `network_mode` (`dhcp` or `static`), `static_ipv4`, `gateway_ipv4`, `dns_servers`. For DHCP the last three are empty strings. Stage configuration on a disposable VM only. Before a separate activation transition is written, define independent external SSH verification, timed rollback, and console recovery. Never invoke this method on the development host or treat its output as evidence of external reachability.
