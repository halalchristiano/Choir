# Extending CHOIR Safely

Add voices, languages, and expression styles without invalidating stable IDs,
existing caches, or reproducible builds.

## Compatibility rules

Treat these values as persistent data contracts:

- `Voice.rawValue` and profile identifiers;
- existing conditioning IDs within a model-family schema;
- ARPAbet and IPA symbol meanings;
- public style identifiers and parameter semantics;
- serialized enum cases and manifest schema versions;
- seeded output within a released audio-engine version;
- content-addressed cache key inputs.

Additive does not mean harmless. Any addition that changes normalization,
phonemization, prosody, model inputs, or audio output must either preserve old
behavior under versioning or bump the relevant engine/cache schema.

## Add a voice

1. Choose a permanent reverse-DNS-style identifier; never recycle one.
2. Add a ``Voice`` case and append a conditioning ID. Do not renumber existing
   IDs.
3. Supply a complete ``VoiceProfile``: identity, age/gender cell, villain flag,
   character, uses, F0 median/range, formant scale, tilt, breathiness,
   roughness, tempo, and pitch dynamism.
4. Establish licensed training data and provenance.
5. Train the shared conditioning space; do not ship a metadata-only profile as
   an audible voice.
6. Define and validate its artifact-free customization envelope.
7. Run intelligibility, quality, distinctness, long-form, and every envelope
   corner test.
8. Add its Voice Book page, three demo passages, reviewed audio demos, and
   migration note.
9. Update asset manifests, size budgets, cache/engine version decisions,
   showcase gallery, and golden-audio corpus.

Adding a 33rd profile changes the SRS's balanced grid and is a product-version
decision, not a routine metadata edit.

## Add a language

Keep language concerns behind explicit, versioned front-end components:

1. define a language/accent identifier selected by API rather than guessed;
2. define or extend a public phoneme inventory without changing existing
   symbol meanings;
3. implement language-specific normalization, sentence segmentation, G2P,
   stress, lexicon lookup, and SSML `say-as` behavior;
4. add an explicit grapheme/phoneme encoding table and append model indices;
5. train multilingual/language conditioning and test every retained voice or
   document an intentionally separate voice set;
6. create held-out G2P, heteronym, numbers/dates, names, punctuation, and
   long-form corpora with native-speaker review;
7. version user-lexicon entries with language so identical spelling cannot
   collide across languages;
8. include language/accent, front-end version, lexicon version, and inventory
   version in deterministic/cache inputs;
9. add documentation, migration notes, and a fallback policy for mixed text.

Priority languages named by the requirements are Ecclesiastical Latin, Dutch,
German, and Hungarian. The current English-focused front end is not proof that
these are merely data additions; the boundaries above are the architectural
contract that prevents a rewrite.

## Add an emotion style

1. Assign a stable lowercase style ID and human-readable name.
2. Define its semantic intent independently from any one voice.
3. Add trained conditioning rather than a pitch-only preset.
4. Specify the intensity-zero behavior and transition/interpolation rules.
5. Evaluate every voice at representative intensities and clamp unsafe
   combinations with a diagnostic.
6. Decide whether the style changes seeded output and therefore requires an
   engine-version/cache migration.
7. Add SSML-C parsing only after the runtime can realize it; unsupported
   `<style>` markup must not be silently advertised.
8. Add Voice Book pairing guidance, examples, tests, and listening evidence.

The existing ``SpeakingStyle`` values are parameter presets. They are not a
substitute for the eight trained emotion styles required for production.

## Evolve schemas and caches

Use monotonically increasing manifest/schema versions. Readers may accept old
schemas through an explicit migration; they must reject unknown future schemas
with a typed error. Never include a newly defaulted field in a cache key
without deciding how existing entries migrate.

When output changes, bump the separate engine version once it exists, keep old
cache entries isolated, and publish the expected invalidation/storage impact.
When output does not change, prove it with seeded golden comparisons before
preserving the engine version.

## Deprecate without breaking

Deprecate identifiers before removal, supply a mechanical replacement, retain
decoding/migration support for persisted values, and remove only at an allowed
major-version boundary. A display-name change may be additive; a stable ID
change is breaking.

Follow <doc:MaintenanceManual> for training, conversion, benchmarks, OS-beta
smoke tests, release evidence, and rollback.
