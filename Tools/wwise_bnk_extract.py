#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract embedded media (.wem) from Wwise .bnk soundbanks.

Fast bulk replacement for running quickbms' wwise_bnk_extractor.bms once per
bank: walks the BKHD/DIDX/DATA chunks and writes every media entry as
"<id>.wem" into --out (entries already present are skipped, which also
deduplicates media shared between banks).

  python wwise_bnk_extract.py --banks "Banks*" --out media
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


def find_chunks(data: bytes) -> Tuple[Dict[bytes, Tuple[int, int]], str]:
    """Map chunk id -> (payload offset, payload size); detects LE/BE banks."""
    result: Dict[bytes, Tuple[int, int]] = {}
    off = 0
    endian = "<"
    first = True
    while off + 8 <= len(data):
        cid = data[off:off + 4]
        if first or cid == b"BKHD":
            # BKHD size is small either way; the sane reading wins
            be = struct.unpack_from(">I", data, off + 4)[0]
            le = struct.unpack_from("<I", data, off + 4)[0]
            endian = ">" if be < le else "<"
            first = False
        size = struct.unpack_from(endian + "I", data, off + 4)[0]
        if size == 0 or off + 8 + size > len(data):
            break
        result.setdefault(cid, (off + 8, size))
        off += 8 + size
    return result, endian


def extract_bank(path: Path, out: Path, overwrite: bool) -> Tuple[int, int]:
    """Return (files written, files skipped)."""
    data = path.read_bytes()
    chunks, endian = find_chunks(data)
    if b"DIDX" not in chunks or b"DATA" not in chunks:
        return (0, 0)
    didx_off, didx_size = chunks[b"DIDX"]
    data_off, data_size = chunks[b"DATA"]
    if didx_size % 12:
        print(f"warning: {path.name}: DIDX size {didx_size} not a multiple of 12", file=sys.stderr)
    written = skipped = 0
    for pos in range(didx_off, didx_off + didx_size - 11, 12):
        media_id, offset, size = struct.unpack_from(endian + "III", data, pos)
        if size == 0:
            continue  # streamed / empty
        if offset + size > data_size:
            print(f"warning: {path.name}: media {media_id} outside DATA section", file=sys.stderr)
            continue
        target = out / f"{media_id}.wem"
        if target.exists() and not overwrite:
            skipped += 1
            continue
        target.write_bytes(data[data_off + offset:data_off + offset + size])
        written += 1
    return written, skipped


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--banks", dest="specs", nargs="+", required=True,
                        help="bank files, folders or globs (relative to cwd)")
    parser.add_argument("--out", type=Path, required=True, help="output folder")
    parser.add_argument("--overwrite", action="store_true", help="rewrite existing media")
    parser.add_argument("--limit", type=int, default=0, help="stop after N banks (debug)")
    args = parser.parse_args(argv)

    args.out.mkdir(parents=True, exist_ok=True)
    banks: List[Path] = []
    for spec in args.specs:
        p = Path(spec)
        if p.is_dir():
            banks.extend(sorted(p.rglob("*.bnk")))
        elif p.is_file():
            banks.append(p)
        else:
            import glob as _glob
            for x in sorted(_glob.glob(spec, recursive=True)):
                xp = Path(x)
                if xp.is_dir():
                    banks.extend(sorted(xp.rglob("*.bnk")))
                elif xp.is_file():
                    banks.append(xp)
    if args.limit:
        banks = banks[:args.limit]
    seen: set = set()
    banks = [b for b in banks if not (b in seen or seen.add(b))]
    if not banks:
        print("no banks found", file=sys.stderr)
        return 1

    total_w = total_s = empty = 0
    for i, bank in enumerate(banks, 1):
        try:
            written, skipped = extract_bank(bank, args.out, args.overwrite)
        except OSError as exc:
            print(f"error: {bank}: {exc}", file=sys.stderr)
            continue
        if written == 0 and skipped == 0:
            empty += 1
        total_w += written
        total_s += skipped
        if i % 2000 == 0:
            print(f"  ... {i}/{len(banks)} banks")
    print(f"banks processed : {len(banks)}")
    print(f"media written   : {total_w}")
    print(f"media skipped   : {total_s} (already extracted)")
    print(f"banks w/o media : {empty}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
