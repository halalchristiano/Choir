# Responsible Use

Integrate synthetic speech without misleading listeners or exposing source
text.

## Disclose synthetic media

For published media, clearly disclose that the voice is synthetic wherever a
reasonable listener could mistake it for a recording of a person. Keep the
disclosure near the audio, in credits or metadata, and in an accessible text
alternative. Preserve provenance when clips are re-exported or syndicated.

Do not identify a CHOIR profile as a real performer. The 32 profiles are
original metadata identities. This package intentionally exposes no speaker
encoder or real-person voice-cloning API.

## Obtain rights and consent

Only use training audio, reference material, scripts, and characters under
terms that permit the intended commercial and distribution use. Record the
source, consent or license, permitted uses, restrictions, and deletion terms
in the model provenance manifest described in <doc:MaintenanceManual>.

Do not use synthetic speech to impersonate a person, bypass authorization,
fabricate consent, harass, defraud, or conceal the origin of political,
journalistic, testimonial, or evidentiary media.

## Protect text and diagnostics

CHOIR is designed for local operation, but the consuming app controls its own
analytics, crash reports, file sync, backups, and logging. At normal logging
levels, record only a stable error code, operation name, package/engine/model
versions, durations, and non-sensitive counters. Never log input text,
pronunciation entries, marks, file names derived from text, or generated audio
without an explicit developer-only opt-in.

If the app adds a cache, expose inspection and purge controls and document
whether items are backed up or synced. Treat Scripture notes, manuscripts,
translations, dialogue, and accessibility content as user data.

## Design for accessibility

Synthetic speech must not fight assistive speech. Leave audio-session policy
to the app, honor VoiceOver and system interruptions, and offer captions or a
transcript wherever speech communicates material information. See
<doc:AccessibilityIntegration>.

## Suggested disclosure copy

> This audio was generated on device using a synthetic voice. It is not a
> recording or imitation of a named person.

Adapt the wording to the medium and applicable law. This note is engineering
guidance, not legal advice.
