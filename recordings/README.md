# Recordings

Working directory for voice recording sessions. Audio files here are **not**
committed — see `.gitignore`. They are large, they are the raw asset, and they
belong in your own backup, not in the repository history.

- `raw/` — exported WAVs straight out of Audacity, untouched.
- `wav/` — split single-utterance files, produced from `raw/`.
- `metadata.csv` — the manifest, generated from the split.

Export from Audacity as **24-bit PCM WAV** into `raw/`. Do not rename or edit.
