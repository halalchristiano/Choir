#!/usr/bin/env python3
"""Extract mono, unstretched Audacity clips in XML block order.

Audacity stores int24 samples in 32-bit containers; WAV PCM24 is packed.
This explicitly converts that representation instead of copying raw bytes.
Requires project XML exported by the official audacity-project-tools utility.
The project database is opened immutable/read-only. Originals are untouched.
"""
import argparse
import hashlib
import json
import re
import sqlite3
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
import soundfile as sf


def main():
    p = argparse.ArgumentParser()
    p.add_argument("project", type=Path)
    p.add_argument("xml", type=Path)
    p.add_argument("out", type=Path)
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    xml = args.xml.read_text()
    duplicates = []

    def clean_tag(match):
        tag, attrs = match.group(1), match.group(2)
        pairs = re.findall(r'([A-Za-z_][\w:.-]*)="([^"]*)"', attrs)
        if len(dict(pairs)) == len(pairs):
            return match.group(0)
        duplicates.append({"tag": tag, "attributes": [k for k, _ in pairs if sum(x == k for x, _ in pairs) > 1]})
        # The exported wavetrack has spectral gain followed by track gain.
        # Audacity's project reader also uses the last occurrence.
        suffix = "/" if attrs.rstrip().endswith("/") else ""
        return "<" + tag + " " + " ".join(f'{k}="{v}"' for k, v in dict(pairs).items()) + suffix + ">"

    xml = re.sub(r"<([A-Za-z_][\w:.-]*)\b([^>]*)>", clean_tag, xml)
    root = ET.fromstring(xml)
    ns = "{http://audacity.sourceforge.net/xml/}"
    con = sqlite3.connect(args.project.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)
    assert con.execute("PRAGMA quick_check").fetchone()[0] == "ok"
    report = []
    for track_index, track in enumerate(root.findall(ns + "wavetrack")):
        sr = int(track.attrib["rate"])
        assert track.attrib.get("linked", "0") == "0", "Linked stereo tracks need explicit channel handling"
        for clip_index, clip in enumerate(track.findall(ns + "waveclip")):
            assert float(clip.attrib.get("clipStretchRatio", "1")) == 1
            assert float(clip.attrib.get("centShift", "0")) == 0
            sequences = clip.findall(ns + "sequence")
            assert len(sequences) == 1, "Only mono sequences are supported"
            seq = sequences[0]
            first = round(float(clip.attrib.get("trimLeft", "0")) * sr)
            last = int(seq.attrib["numsamples"]) - round(float(clip.attrib.get("trimRight", "0")) * sr)
            target = args.out / f"{track_index}_{track.attrib['name']}_{clip_index}_{clip.attrib['name']}.wav"
            temporary = target.with_suffix(".tmp.wav")
            written, peak, energy = 0, 0., 0.
            with sf.SoundFile(temporary, "w", samplerate=sr, channels=1, subtype="PCM_24") as out:
                for block in seq.findall(ns + "waveblock"):
                    start = int(block.attrib["start"])
                    length = int(block.attrib["length"])
                    block_id = int(block.attrib["blockid"])
                    a, z = max(start, first), min(start + length, last)
                    if a >= z:
                        continue
                    assert a == first + written, "Non-contiguous or misordered clip blocks"
                    if block_id < 0:
                        samples = np.zeros(z - a, dtype=np.float32)
                    else:
                        fmt, blob = con.execute("SELECT sampleformat,samples FROM sampleblocks WHERE blockid=?", (block_id,)).fetchone()
                        if fmt == 0x00040001:
                            samples = np.frombuffer(blob, dtype="<i4").astype(np.float32) / 8388608.
                        elif fmt == 0x00020001:
                            samples = np.frombuffer(blob, dtype="<i2").astype(np.float32) / 32768.
                        elif fmt == 0x0004000F:
                            samples = np.frombuffer(blob, dtype="<f4")
                        else:
                            raise ValueError(f"Unsupported sample format {fmt}")
                        samples = samples[a - start:z - start]
                    assert len(samples) == z - a and np.isfinite(samples).all()
                    peak = max(peak, float(np.max(np.abs(samples))))
                    energy += float(np.sum(samples.astype(np.float64) ** 2))
                    out.write(samples)
                    written += len(samples)
            assert written == last - first
            temporary.replace(target)
            row = {"audio": str(target), "frames": written, "seconds": written / sr,
                   "peak": peak, "rms": (energy / written) ** .5,
                   "block_order": "project_xml", "int24_conversion": "signed_32_bit_container_to_packed_PCM24"}
            report.append(row)
            print(json.dumps(row), flush=True)
    (args.out.parent / "extraction-report.json").write_text(json.dumps({"project": str(args.project), "duplicate_xml_attributes_normalized": duplicates, "clips": report}, indent=2))


if __name__ == "__main__":
    main()
