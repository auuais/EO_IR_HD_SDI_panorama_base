#!/usr/bin/env python3
import csv
import json
import sys
from pathlib import Path


CTRL_BITS = {
    "app_en": (0, 0),
    "app_cmd": (1, 3),
    "app_addr_lo": (4, 19),
    "app_rdy": (20, 20),
    "app_wdf_wren": (21, 21),
    "app_wdf_rdy": (22, 22),
    "app_rd_data_valid": (23, 23),
    "accept": (24, 24),
    "cmd": (25, 27),
    "useAdr": (28, 28),
    "dBufAdr": (29, 33),
    "mcRdCAS": (34, 34),
    "mcWrCAS": (35, 35),
    "mcCasSlot": (36, 37),
    "mcCasSlot2": (38, 38),
    "winInjTxn": (39, 39),
    "gt_data_ready": (40, 40),
    "per_rd_done": (41, 41),
    "rd_data_en_phy2mc": (42, 42),
    "rd_data_addr_phy2mc": (43, 47),
    "rd_data_en_mc2ni": (48, 48),
    "rd_data_addr_mc2ni": (49, 53),
    "en_vtc": (54, 54),
    "stop_gate_tracking_req": (55, 55),
    "stop_gate_tracking_ack": (56, 56),
    "ref_req": (57, 57),
    "ref_ack": (58, 58),
    "zq_req": (59, 59),
    "zq_ack": (60, 60),
    "wrDataEn": (61, 61),
}


def parse_hex(value):
    value = (value or "0").strip()
    if value in ("", "X", "x"):
        return 0
    return int(value.replace("_", ""), 16)


def get_bits(value, lo, hi):
    mask = (1 << (hi - lo + 1)) - 1
    return (value >> lo) & mask


def find_col(fieldnames, pattern):
    matches = [name for name in fieldnames if pattern in name]
    return matches[0] if matches else None


def decode_file(path):
    with path.open(newline="") as f:
        rows = list(csv.reader(f))
    if len(rows) < 3:
        raise ValueError(f"{path}: not enough rows")

    fieldnames = rows[0]
    data_rows = [dict(zip(fieldnames, row)) for row in rows[2:]]

    ctrl_col = find_col(fieldnames, "dbg_bus_1[63:0]")
    phy_col = find_col(fieldnames, "dbg_bus_2[127:64]")
    mc_col = find_col(fieldnames, "dbg_bus_3[191:128]")
    app_bus_col = find_col(fieldnames, "dbg_bus[255:192]")
    app_data_col = find_col(fieldnames, "c0_ddr4_app_rd_data[63:0]")
    sample_col = "Sample in Window"

    if not ctrl_col:
        raise ValueError(f"{path}: no dbg_bus_1[63:0] control column found")

    counts = {name: 0 for name in CTRL_BITS}
    transitions = {name: 0 for name in CTRL_BITS}
    last = {}
    events = []
    read_valid_events = []
    nonzero_ctrl = 0

    for row in data_rows:
        sample = int(row.get(sample_col, "0"))
        ctrl = parse_hex(row.get(ctrl_col))
        if ctrl:
            nonzero_ctrl += 1

        decoded = {name: get_bits(ctrl, lo, hi) for name, (lo, hi) in CTRL_BITS.items()}
        for name, value in decoded.items():
            if value:
                counts[name] += 1
            if name in last and last[name] != value:
                transitions[name] += 1
            last[name] = value

        interesting = [
            "app_en",
            "app_rd_data_valid",
            "accept",
            "mcRdCAS",
            "mcWrCAS",
            "winInjTxn",
            "gt_data_ready",
            "per_rd_done",
            "rd_data_en_phy2mc",
            "rd_data_en_mc2ni",
        ]
        if any(decoded[name] for name in interesting):
            events.append({
                "sample": sample,
                "ctrl": f"{ctrl:016x}",
                **{name: decoded[name] for name in interesting},
                "app_cmd": decoded["app_cmd"],
                "cmd": decoded["cmd"],
                "app_addr_lo": decoded["app_addr_lo"],
                "dBufAdr": decoded["dBufAdr"],
                "phy_addr": decoded["rd_data_addr_phy2mc"],
                "mc_addr": decoded["rd_data_addr_mc2ni"],
            })

        if decoded["app_rd_data_valid"]:
            read_valid_events.append({
                "sample": sample,
                "ctrl": f"{ctrl:016x}",
                "phy_low64": row.get(phy_col, "") if phy_col else "",
                "mc_low64": row.get(mc_col, "") if mc_col else "",
                "app_bus_low64": row.get(app_bus_col, "") if app_bus_col else "",
                "app_probe_low64": row.get(app_data_col, "") if app_data_col else "",
                "phy_addr": decoded["rd_data_addr_phy2mc"],
                "mc_addr": decoded["rd_data_addr_mc2ni"],
            })

    return {
        "file": str(path),
        "samples": len(data_rows),
        "nonzero_ctrl_samples": nonzero_ctrl,
        "counts": counts,
        "transitions": transitions,
        "first_events": events[:32],
        "read_valid_events": read_valid_events[:32],
        "read_valid_count": len(read_valid_events),
    }


def main(argv):
    if len(argv) < 2:
        print("usage: codex_decode_mig_vt.py ila_capture_mig_vt_*.csv", file=sys.stderr)
        return 2
    results = [decode_file(Path(arg)) for arg in argv[1:]]
    print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
