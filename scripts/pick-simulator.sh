#!/usr/bin/env bash
# Prints the UDID of the first available iPhone simulator on the newest iOS runtime.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
def ver(k):
    tail = k.rsplit("iOS-", 1)
    if len(tail) != 2: return None
    return tuple(int(p) for p in tail[1].split("-") if p.isdigit())
runtimes = sorted((k for k in data if ver(k) is not None), key=ver, reverse=True)
for k in runtimes:
    for d in data[k]:
        if d["name"].startswith("iPhone") and d.get("isAvailable", True):
            print(d["udid"]); sys.exit(0)
sys.stderr.write("no available iPhone simulator found\n"); sys.exit(1)
'
