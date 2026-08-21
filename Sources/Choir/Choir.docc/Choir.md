# ``Choir``

Build offline speech-synthesis integrations for Apple platforms.

## Overview

CHOIR is a Swift package for an entirely on-device text-to-speech pipeline. It
contains a linguistic front end, prosody utilities, 32 stable voice profiles,
synthesis APIs, timing metadata, audio processing, caching primitives, and a
benchmark harness.

> Important: Version 0.16 is pre-alpha infrastructure. The default
> ``ChoirEngine`` uses ``MockAcousticModel`` and ``MockVocoder`` and produces a
> test waveform, not intelligible speech. No trained 32-voice model or
> production vocoder ships in the package. Treat examples as integration and
> API exercises until production assets pass the documented quality and device
> gates.

Start with <doc:GettingStarted>, then choose an API tier in <doc:APITiers>.
Before making a platform or production claim, read
<doc:PlatformDifferences> and <doc:MaintenanceManual>.

## Topics

### Start here

- <doc:GettingStarted>
- <doc:APITiers>
- <doc:CheatSheet>
- <doc:DocumentationStatus>

### Design speech

- <doc:VoiceBook>
- <doc:SSMLCReference>
- <doc:PhonemeInventoryReference>
- ``Voice``
- ``VoiceProfile``
- ``SynthesisParameters``
- ``SpeakingStyle``

### Integrate a product

- <doc:IntegrationRecipes>
- <doc:AccessibilityIntegration>
- <doc:PlatformDifferences>
- <doc:ResponsibleUse>

### Maintain and extend CHOIR

- <doc:MaintenanceManual>
- <doc:ExtendingChoir>
- ``AcousticModelProtocol``
- ``VocoderProtocol``
- ``ReferenceDevice``
- ``BenchmarkHarness``

### Synthesize and inspect results

- ``ChoirEngine``
- ``SynthesisInput``
- ``SynthesisResult``
- ``SynthesisMetadata``
- ``DurationEstimator``
- ``ChoirError``

### Text processing

- ``LinguisticFrontend``
- ``TextNormalizer``
- ``Phonemizer``
- ``PronunciationDictionary``
- ``UserLexicon``
- ``ScriptureNormalizer``
- ``SSMLCParser``
- ``PhonemeInventory``

### Audio and delivery

- ``AudioBuffer``
- ``AudioEncoder``
- ``AudioFilters``
- ``AudioEffectChain``
- ``StreamingOptions``
- ``AudioChunk``
- ``AssetCache``
