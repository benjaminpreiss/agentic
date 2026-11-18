# Tumbleweed systemd-networkd module (not deployable yet)

Implements the `networking@1` method contract on an **already-installed** openSUSE Tumbleweed system, without Nix. This package has **no instance or transition request** yet, so the current introduction plan does not run it.

- `inspect`: reports the selected interface's live MAC, link/addresses and default IPv4 route; nothing in that observation persists by assumption.
- `configure`: requires root, an already-active `systemd-networkd`, no active NetworkManager or wicked, a disposable VM and verified console. Validates the selected interface/MAC and DHCP or static IPv4/CIDR, gateway and space-separated IPv4 DNS inputs. Stages only `/etc/systemd/network/10-agentic.network`, refusing an existing unmanaged file. **It does not reload/reconfigure networkd.** The file could still be picked up by a later external restart.

Inputs are `interface_name`, `network_mac`, `network_mode` (`dhcp` or `static`), `static_ipv4`, `gateway_ipv4`, `dns_servers`. For DHCP the last three are empty strings. Stage configuration on a disposable VM only. Before a separate activation transition is written, define independent external SSH verification, timed rollback, and console recovery. Never invoke this method on the development host or treat its output as evidence of external reachability.
