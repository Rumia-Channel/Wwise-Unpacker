#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Decode Wwise media (.wem, or carved .wav) to OGG / WAV / MP3.

Vorbis media go through the bundled ww2ogg + revorb; PCM/ADPCM media are handed
to the bundled ffmpeg (and PCM copies straight to .wav). Anything the tools
cannot decode is reported with its codec name.

  python decode_wem.py --dir "Tools/Decoding" --out OGG --format ogg --recursive
  python decode_wem.py --dir "Tools/Decoding" --out WAV --format wav --recursive
  python decode_wem.py --dir "Tools/Decoding" --out MP3 --format mp3 --recursive

`--ext` selects what counts as input (default "wem"; classic carving produces
".wav", so use --ext wem,wav there).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

TOOLS = Path(__file__).resolve().parent

# Wwise media codecs (fmt chunk tags; from vgmstream's meta/wwise.c)
CODECS = {
    0x0001: "PCM",
    0x0002: "ADPCM (IMA/PTADPCM)",
    0x0069: "ADPCM (IMA)",
    0x0161: "XWMA (WMAv2)",
    0x0162: "XWMA (WMAPro)",
    0x0165: "XMA2",
    0x0166: "XMA",
    0xAAC0: "AAC",
    0xFFF0: "DSP",
    0xFFFB: "HEVAG",
    0xFFFC: "ATRAC9",
    0xFFFE: "PCM (authoring)",
    0xFFFF: "Wwise Vorbis",
    0x3039: "Wwise Opus (OPUSNX)",
    0x3040: "Wwise Opus",
    0x3041: "Wwise Opus (OPUS_WEM)",
    0x8311: "Wwise PTADPCM",
}
VORBIS_TAG = 0xFFFF
PCM_TAGS = {0x0001, 0xFFFE}
FFMPEG_ARGS = {
    "wav": ["-c:a", "pcm_s16le"],
    "mp3": ["-acodec", "libmp3lame", "-q:a", "0"],
}


def sniff_codec(path: Path) -> Tuple[int, str]:
    """Read the RIFF fmt chunk codec so skipped files can be explained."""
    try:
        head = path.open("rb").read(256)
    except OSError:
        return (0, "unreadable")
    if head[:4] not in (b"RIFF", b"RIFX"):
        return (0, "not RIFF")
    pos = head.find(b"fmt ")
    if pos < 0 or pos + 10 > len(head):
        return (0, "unknown")
    codec = int.from_bytes(head[pos + 8:pos + 10], "big" if head[:4] == b"RIFX" else "little")
    return (codec, CODECS.get(codec, f"codec 0x{codec:04x}"))


def run(cmd: List[str]) -> Tuple[int, str]:
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    except OSError as exc:
        return 1, str(exc)
    if proc.returncode != 0:
        lines = (proc.stderr or proc.stdout or "").strip().splitlines()
        return proc.returncode, lines[-1] if lines else "failed"
    return 0, ""


def decode_one(wem: Path, target: Path, fmt: str, codebook: Optional[Path],
               ww2ogg: Path, revorb: Path, ffmpeg: Path, tmp_dir: Path) -> Tuple[str, str]:
    """Returns (status, message) with status in ok/copied/skip/error."""
    tag, codec_name = sniff_codec(wem)
    target.parent.mkdir(parents=True, exist_ok=True)

    if tag == VORBIS_TAG:
        scratch = tmp_dir / (wem.stem + ".ogg")
        scratch.parent.mkdir(parents=True, exist_ok=True)
        cmd = [str(ww2ogg), str(wem)]
        if codebook:
            cmd += ["--pcb", str(codebook)]
        cmd += ["-o", str(scratch)]
        rc, msg = run(cmd)
        if rc or not scratch.exists():
            return "skip", f"{wem.name}: ww2ogg failed ({msg})"
        run([str(revorb), str(scratch)])
        if fmt == "ogg":
            scratch.replace(target)
            return "ok", ""
        rc, msg = run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y",
                       "-i", str(scratch), *FFMPEG_ARGS[fmt], str(target)])
        scratch.unlink(missing_ok=True)
        if rc or not target.exists():
            return "skip", f"{wem.name}: ffmpeg failed ({msg})"
        return "ok", ""

    if fmt == "wav" and tag in PCM_TAGS:
        target.write_bytes(wem.read_bytes())
        return "copied", ""

    rc, msg = run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y",
                   "-i", str(wem), *(FFMPEG_ARGS.get(fmt, FFMPEG_ARGS["wav"])), str(target)])
    if rc or not target.exists():
        return "skip", f"{wem.name}: {codec_name} not decodable ({msg})"
    return "ok", ""


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", type=Path, required=True, help="folder with .wem/.wav files")
    parser.add_argument("--out", type=Path, required=True, help="output folder")
    parser.add_argument("--format", choices=("ogg", "wav", "mp3"), default="ogg")
    parser.add_argument("--ext", default="wem", help="input extensions (default: wem)")
    parser.add_argument("--recursive", action="store_true", help="decode subfolders too")
    parser.add_argument("--codebook", type=Path, default=TOOLS / "packed_codebooks_aoTuV_603.bin",
                        help="packed codebook for ww2ogg (default: bundled aoTuV 6.03)")
    parser.add_argument("--ww2ogg", type=Path, default=TOOLS / "ww2ogg.exe")
    parser.add_argument("--revorb", type=Path, default=TOOLS / "revorb.exe")
    parser.add_argument("--ffmpeg", type=Path, default=TOOLS / "ffmpeg.exe")
    parser.add_argument("--limit", type=int, default=0, help="stop after N files (debug)")
    args = parser.parse_args(argv)

    exts = {e.strip().lower().lstrip(".") for e in args.ext.split(",") if e.strip()}
    it = args.dir.rglob("*") if args.recursive else args.dir.glob("*")
    sources: List[Path] = sorted(p for p in it if p.is_file() and p.suffix.lower().lstrip(".") in exts)
    if args.limit:
        sources = sources[:args.limit]
    if not sources:
        print(f"no {sorted(exts)} files under {args.dir}", file=sys.stderr)
        return 1

    tmp_dir = args.out / ".wem-tmp"
    done = copied = skipped = failed = 0
    skip_codecs: Dict[str, int] = {}
    for i, src in enumerate(sources, 1):
        rel = src.relative_to(args.dir)
        target = (args.out / rel).with_suffix("." + args.format)
        if target.exists():
            skipped += 1
            continue
        status, message = decode_one(src, target, args.format, args.codebook,
                                     args.ww2ogg, args.revorb, args.ffmpeg, tmp_dir)
        if status == "ok":
            done += 1
        elif status == "copied":
            copied += 1
        else:
            _tag, codec_name = sniff_codec(src)
            skip_codecs[codec_name] = skip_codecs.get(codec_name, 0) + 1
            if status == "skip":
                skipped += 1
            else:
                failed += 1
            print(message, file=sys.stderr)
        if i % 200 == 0:
            print(f"  ... {i}/{len(sources)} ({done} decoded)")
    for leftover in sorted(tmp_dir.rglob("*")):
        if leftover.is_file():
            leftover.unlink(missing_ok=True)
    for d in sorted(tmp_dir.rglob("*"), reverse=True):
        if d.is_dir():
            d.rmdir()
    tmp_dir.rmdir()
    print(f"decoded : {done} (+{copied} PCM copied)" if copied else f"decoded : {done}")
    print(f"skipped : {skipped} (existing output or unsupported media)")
    for codec_name, count in sorted(skip_codecs.items(), key=lambda kv: -kv[1]):
        print(f"          {codec_name}: {count}")
    if skip_codecs and any(c != "Wwise Vorbis" for c in skip_codecs):
        print("          note: unsupported codecs need another decoder (vgmstream reads them)")
    print(f"errors  : {failed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
