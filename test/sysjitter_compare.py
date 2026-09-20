#!/usr/bin/env python3
"""Compare two sysjitter runs (baseline vs tuned) per core.

Usage: sysjitter_compare.py BASELINE.txt TUNED.txt
"""
import sys

METRICS = [
    ("int_n", "interrupts"),
    ("int_n_per_sec", "int/s"),
    ("int_mean(ns)", "mean ns"),
    ("int_99(ns)", "p99 ns"),
    ("int_9999(ns)", "p99.99 ns"),
    ("int_max(ns)", "max ns"),
    ("int_total(%)", "total %"),
]


def parse(path):
    """sysjitter prints one row per metric: 'key: v0 v1 v2 ...', one column per core."""
    rows = {}
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 2 or not parts[0].endswith(":"):
                continue
            rows[parts[0][:-1]] = parts[1:]
    if "core_i" not in rows:
        sys.exit(f"{path}: no sysjitter table found (is the run complete?)")
    cores = rows["core_i"]
    return {c: {k: v[i] for k, v in rows.items() if i < len(v)} for i, c in enumerate(cores)}, rows


def num(v):
    try:
        return float(v)
    except ValueError:
        return None


def main(base_path, tuned_path):
    base, base_rows = parse(base_path)
    tuned, tuned_rows = parse(tuned_path)
    cores = [c for c in base if c in tuned]
    if not cores:
        sys.exit("no common cores between the two runs")

    print(f"baseline: {base_path}  (runtime {base_rows.get('runtime(s)', ['?'])[0]} s, threshold {base_rows.get('threshold(ns)', ['?'])[0]} ns)")
    print(f"tuned:    {tuned_path}  (runtime {tuned_rows.get('runtime(s)', ['?'])[0]} s, threshold {tuned_rows.get('threshold(ns)', ['?'])[0]} ns)")
    print()

    hdr = f"{'metric':<12}{'core':>6}{'baseline':>14}{'tuned':>14}{'change':>10}"
    print(hdr)
    print("-" * len(hdr))
    for key, label in METRICS:
        for c in cores:
            b, t = base[c].get(key), tuned[c].get(key)
            if b is None or t is None:
                continue
            bn, tn = num(b), num(t)
            if bn is None or tn is None:
                change = ""
            elif bn == 0:
                change = "same" if tn == 0 else "worse"
            else:
                change = f"{(tn - bn) / bn * 100:+.0f}%"
            print(f"{label:<12}{c:>6}{b:>14}{t:>14}{change:>10}")
        print()

    # headline
    def total(run, key):
        return sum(num(run[c].get(key, "0")) or 0 for c in cores)

    def worst(run, key):
        return max((num(run[c].get(key, "0")) or 0) for c in cores)

    print("summary over cores", ",".join(cores))
    print(f"  total interrupts : {total(base, 'int_n'):.0f} -> {total(tuned, 'int_n'):.0f}")
    print(f"  worst max ns     : {worst(base, 'int_max(ns)'):.0f} -> {worst(tuned, 'int_max(ns)'):.0f}")
    print(f"  worst p99.99 ns  : {worst(base, 'int_9999(ns)'):.0f} -> {worst(tuned, 'int_9999(ns)'):.0f}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
