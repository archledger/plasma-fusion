# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""DRM fdinfo accounting; unavailable counters are omitted, never replaced with zero."""


def _quantity(value, units, *, unitless_zero=False):
    parts = value.split()
    # xe emits unitless zero for empty memory regions.
    if unitless_zero and parts == ["0"]:
        return 0
    if len(parts) != 2 or parts[1] not in units:
        return None
    try:
        number = int(parts[0])
    except ValueError:
        return None
    return number * units[parts[1]] if number >= 0 else None


def summarize(records):
    clients = {}
    for text in records:
        fields = {}
        for line in (text or "").splitlines():
            key, colon, value = line.partition(":")
            if colon:
                fields[key.strip()] = value.strip()
        try:
            client = int(fields["drm-client-id"])
        except (KeyError, ValueError):
            continue
        if client < 0:
            continue
        # Client IDs are scoped to a device; repeated FDs of that client share its accounting.
        identity = (fields.get("drm-driver", ""), fields.get("drm-pdev", ""), client)
        if identity in clients:
            continue
        sample = {}
        for metric, prefix, units in (
            ("gpu_ns", "drm-engine-", {"ns": 1}),
            ("gem_total_kB", "drm-total-", {"B": 1 / 1024, "KiB": 1, "MiB": 1024, "GiB": 1024**2}),
            ("gem_resident_kB", "drm-resident-", {"B": 1 / 1024, "KiB": 1, "MiB": 1024, "GiB": 1024**2}),
        ):
            values = [_quantity(value, units, unitless_zero=metric != "gpu_ns") for key, value in fields.items()
                      if key.startswith(prefix)
                      and not key.startswith(("drm-engine-capacity-", "drm-total-cycles-"))]
            if values and all(value is not None for value in values):
                sample[metric] = sum(values)
        clients[identity] = sample
    if not clients:
        return None
    # A partial sum would under-report usage if another client lacks this counter type.
    result = {metric: sum(sample[metric] for sample in clients.values())
              for metric in ("gpu_ns", "gem_total_kB", "gem_resident_kB")
              if all(metric in sample for sample in clients.values())}
    return result or None
