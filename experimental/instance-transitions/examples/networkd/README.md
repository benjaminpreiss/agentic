# Explicit Python dependency of Tumbleweed networkd

This is a **disposable-VM-only planning example**, not a ready-to-run network deployment. `instances/network.json` contains intentionally unusable example interface/MAC inputs. Do not run its generated script against any machine. It does not activate networkd settings or test/recover external SSH access.

From `experimental/instance-transitions/`:

```sh
python3 plan.py --requests examples/networkd/requests/introduction.json --expand --instances examples/networkd/instances
python3 plan.py --requests examples/networkd/requests/introduction.json --script --instances examples/networkd/instances > networkd.generated.sh
sh -n networkd.generated.sh
```

The plan must order `host → packages → python → network`. The Python transition calls the **bound package-manager instance's** `install(package)` method with `package: "python3"` supplied by the request's selected transition, then the Python instance's `inspect`. Only after that may the network transition call its bound Python instance's `inspect` and the networkd instance's `configure`. The networking **interface** depends only on the OS. Its **systemd-networkd module** additionally requires the `python-runtime` interface, binds to a particular Python instance and obtains its declared interpreter path. The Tumbleweed Python **module** depends on a package-manager instance. No version of Python is assumed preinstalled on the target.

`configure` stages `/etc/systemd/network/10-agentic.network`; it refuses to switch from a competing manager, overwrite an unmanaged file, or reload networking. A separate activation transition would need console access, a timed rollback and an independently verified *new* SSH connection before it could be considered for a disposable VM. The checks here were performed locally against JSON and shell syntax; **no VM execution or network change has been performed**.
