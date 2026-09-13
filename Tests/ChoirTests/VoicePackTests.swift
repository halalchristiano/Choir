import Foundation
import Testing
@testable import Choir

// MARK: - Fixtures

/// Builds a real `.choirvoice` bundle on disk, with real checksums, so every
/// test exercises the same load path an installed voice pack takes.
private struct PackFixture {
    let directory: URL
    let url: URL
    var manifest: VoicePackManifest

    static let orion = Voice.orion.identifier

    init(
        name: String = "test",
        kind: VoicePackManifest.Speaker.Kind = .designed,
        consent: VoicePackManifest.Consent? = nil,
        version: String = "1.0.0",
        voiceIDs: [String] = [PackFixture.orion],
        directory: URL? = nil
    ) throws {
        let directory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("choir-pack-\(UUID().uuidString)")
        self.directory = directory
        self.url = directory.appendingPathComponent("\(name).\(VoicePack.fileExtension)")
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("models"), withIntermediateDirectories: true)

        let acoustic = Data((0..<4_096).map { UInt8($0 % 251) })
        let vocoder = Data((0..<9_000).map { UInt8(($0 * 7) % 253) })
        try acoustic.write(to: url.appendingPathComponent("models/acoustic.bin"))
        try vocoder.write(to: url.appendingPathComponent("models/vocoder.bin"))

        manifest = VoicePackManifest(
            packID: "studio.test.\(name)",
            packVersion: version,
            sampleRate: 22_050,
            voiceIDs: voiceIDs,
            files: [
                .init(path: "models/acoustic.bin",
                      sha256: SHA256Hasher.hexDigest(acoustic), role: .acousticModel),
                .init(path: "models/vocoder.bin",
                      sha256: SHA256Hasher.hexDigest(vocoder), role: .vocoder),
            ],
            speaker: .init(kind: kind, displayName: "Test Speaker", consent: consent))
        try write()
    }

    func write() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url.appendingPathComponent(VoicePack.manifestFileName))
    }

    mutating func edit(_ change: (inout VoicePackManifest) -> Void) throws {
        change(&manifest)
        try write()
    }

    func load(now: Date = Date()) throws -> VoicePack {
        try VoicePack.load(from: url, now: now)
    }

    static let validConsent = VoicePackManifest.Consent(
        releaseReference: "release-2026-09-13.pdf",
        signedOn: "2026-09-01",
        permittedUses: ["commercial voice pack"])
}

private func expectRejection(
    _ expected: VoicePackError,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> Void
) {
    do {
        try body()
        Issue.record("expected \(expected), but the pack loaded", sourceLocation: sourceLocation)
    } catch let error as VoicePackError {
        #expect(error == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected VoicePackError, got \(error)", sourceLocation: sourceLocation)
    }
}

/// Midday on a fixed date, so consent-date checks do not depend on the clock.
private let fixedNow: Date = {
    var components = DateComponents()
    components.year = 2026; components.month = 9; components.day = 13; components.hour = 12
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: components)!
}()

// MARK: - SHA-256

@Suite("SHA-256 for voice pack verification")
struct SHA256HasherTests {

    @Test("Matches the published test vectors")
    func testVectors() {
        #expect(SHA256Hasher.hexDigest(Data())
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256Hasher.hexDigest(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // Two blocks: the padding must spill into a second block.
        #expect(SHA256Hasher.hexDigest(
            Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    /// Model files arrive in arbitrary chunks; every split must agree.
    @Test("Chunked input produces the same digest as one-shot input")
    func testChunking() {
        let data = Data((0..<1_000).map { UInt8(($0 * 31) % 256) })
        let expected = SHA256Hasher.hexDigest(data)
        for chunk in [1, 13, 63, 64, 65, 128, 999] {
            var hasher = SHA256Hasher()
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunk, data.count)
                hasher.update(data.subdata(in: offset..<end))
                offset = end
            }
            #expect(hasher.finalizeHex() == expected, "chunk size \(chunk)")
        }
    }

    @Test("A file read in small chunks hashes the same as its bytes")
    func testFileDigest() throws {
        let data = Data((0..<10_000).map { UInt8($0 % 256) })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("choir-sha-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try SHA256Hasher.hexDigest(fileAt: url, chunkSize: 97)
            == SHA256Hasher.hexDigest(data))
    }
}

// MARK: - Loading

@Suite("Voice pack loading and verification")
struct VoicePackLoadingTests {

    @Test("A valid designed pack loads and resolves its voices and files")
    func testValidDesignedPack() throws {
        let fixture = try PackFixture()
        let pack = try fixture.load()
        #expect(pack.voices == [.orion])
        #expect(!pack.isRealPerson)
        #expect(pack.syntheticDisclosure == nil)
        #expect(pack.url(for: .vocoder)?.lastPathComponent == "vocoder.bin")
        #expect(pack.identity.hasPrefix("studio.test.test@1.0.0#"))
    }

    @Test("A real person with a complete release loads and requires a label")
    func testValidRealPersonPack() throws {
        let fixture = try PackFixture(kind: .realPerson, consent: PackFixture.validConsent)
        let pack = try fixture.load(now: fixedNow)
        #expect(pack.isRealPerson)
        let label = try #require(pack.syntheticDisclosure)
        #expect(label.contains("Synthetic speech"))
        #expect(label.contains("Test Speaker"))
    }

    @Test("Identity changes when model bytes change, and not otherwise")
    func testIdentity() throws {
        var fixture = try PackFixture()
        let first = try fixture.load().identity
        #expect(try fixture.load().identity == first, "identity must be stable")

        let replacement = Data(repeating: 9, count: 100)
        try replacement.write(to: fixture.url.appendingPathComponent("models/vocoder.bin"))
        try fixture.edit { $0.files[1].sha256 = SHA256Hasher.hexDigest(replacement) }
        #expect(try fixture.load().identity != first,
                "a retrained model must not reuse the old identity, or caches serve stale audio")
    }

    @Test("Refuses a path that is not a pack")
    func testNotAPack() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-\(UUID().uuidString).choirvoice")
        expectRejection(.notADirectory(path: missing.path)) {
            _ = try VoicePack.load(from: missing)
        }
    }

    @Test("Refuses a pack without a manifest, or with an unreadable one")
    func testManifest() throws {
        let fixture = try PackFixture()
        let manifestURL = fixture.url.appendingPathComponent(VoicePack.manifestFileName)

        try Data("{ not json".utf8).write(to: manifestURL)
        #expect(throws: VoicePackError.self) { try fixture.load() }

        try FileManager.default.removeItem(at: manifestURL)
        expectRejection(.manifestMissing(path: fixture.url.path)) { _ = try fixture.load() }
    }

    @Test("Refuses packs built for a different schema, engine or phoneme set")
    func testCompatibility() throws {
        var fixture = try PackFixture()

        try fixture.edit { $0.schemaVersion = 2 }
        expectRejection(.unsupportedSchema(found: 2, supported: 1)) { _ = try fixture.load() }

        try fixture.edit { $0.schemaVersion = 1; $0.engineVersion = Choir.engineVersion + 1 }
        expectRejection(.engineVersionMismatch(pack: Choir.engineVersion + 1, engine: Choir.engineVersion)) {
            _ = try fixture.load()
        }

        try fixture.edit { $0.engineVersion = Choir.engineVersion; $0.phonemeInventoryVersion = 99 }
        expectRejection(.phonemeInventoryMismatch(pack: 99, engine: PhonemeInventory.version)) {
            _ = try fixture.load()
        }

        try fixture.edit { $0.phonemeInventoryVersion = PhonemeInventory.version
                           $0.minimumPackageVersion = "99.0.0" }
        expectRejection(.requiresNewerPackage(required: "99.0.0", current: Choir.version)) {
            _ = try fixture.load()
        }
    }

    @Test("Refuses malformed identity and version fields")
    func testIdentityFields() throws {
        var fixture = try PackFixture()
        try fixture.edit { $0.packVersion = "1.0" }
        #expect(throws: VoicePackError.self) { try fixture.load() }

        try fixture.edit { $0.packVersion = "1.0.0"; $0.packID = "has spaces" }
        #expect(throws: VoicePackError.self) { try fixture.load() }
    }

    @Test("Refuses unknown, duplicate or missing voices")
    func testVoices() throws {
        var fixture = try PackFixture()
        try fixture.edit { $0.voiceIDs = ["choir.nobody"] }
        expectRejection(.unknownVoice(identifier: "choir.nobody")) { _ = try fixture.load() }

        try fixture.edit { $0.voiceIDs = [PackFixture.orion, PackFixture.orion] }
        expectRejection(.duplicateVoice(identifier: PackFixture.orion)) { _ = try fixture.load() }

        try fixture.edit { $0.voiceIDs = [] }
        #expect(throws: VoicePackError.self) { try fixture.load() }
    }

    /// The failures a checksum exists to catch: a truncated download, or a
    /// model file swapped after the manifest was written.
    @Test("Refuses corrupt, missing or duplicated files")
    func testFiles() throws {
        var fixture = try PackFixture()
        let vocoderURL = fixture.url.appendingPathComponent("models/vocoder.bin")
        let good = try Data(contentsOf: vocoderURL)

        try Data(good.prefix(100)).write(to: vocoderURL)
        let truncated = SHA256Hasher.hexDigest(Data(good.prefix(100)))
        expectRejection(.checksumMismatch(
            path: "models/vocoder.bin",
            expected: fixture.manifest.files[1].sha256,
            actual: truncated)) { _ = try fixture.load() }

        try FileManager.default.removeItem(at: vocoderURL)
        expectRejection(.missingFile(path: "models/vocoder.bin")) { _ = try fixture.load() }

        try good.write(to: vocoderURL)
        try fixture.edit { $0.files.append($0.files[0]) }
        expectRejection(.duplicateFile(path: "models/acoustic.bin")) { _ = try fixture.load() }

        try fixture.edit { $0.files = [$0.files[0]] }
        expectRejection(.missingRole(.vocoder)) { _ = try fixture.load() }
    }

    @Test("Refuses file paths that escape the pack directory")
    func testUnsafePaths() throws {
        for path in ["../outside.bin", "/etc/hosts", "models/../../x", "models\\x.bin", "models//x", "./x"] {
            #expect(!VoicePack.isSafeRelativePath(path), "\(path) should be unsafe")
        }
        #expect(VoicePack.isSafeRelativePath("models/vocoder.bin"))

        var fixture = try PackFixture()
        try fixture.edit { $0.files[1].path = "../vocoder.bin" }
        expectRejection(.unsafePath(path: "../vocoder.bin")) { _ = try fixture.load() }
    }

    @Test("A symlink inside the pack cannot point a verified name outside it")
    func testSymlinkEscape() throws {
        var fixture = try PackFixture()
        let outside = fixture.directory.appendingPathComponent("outside.bin")
        let bytes = Data("outside".utf8)
        try bytes.write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appendingPathComponent("models/link.bin"),
            withDestinationURL: outside)
        try fixture.edit {
            $0.files.append(.init(path: "models/link.bin",
                                  sha256: SHA256Hasher.hexDigest(bytes), role: .auxiliary))
        }
        expectRejection(.unsafePath(path: "models/link.bin")) { _ = try fixture.load() }
    }
}

// MARK: - Consent

@Suite("Voice pack consent")
struct VoicePackConsentTests {

    @Test("A real person's voice without a consent record is refused")
    func testConsentRequired() throws {
        let fixture = try PackFixture(kind: .realPerson, consent: nil)
        expectRejection(.consentRequired(speaker: "Test Speaker")) { _ = try fixture.load(now: fixedNow) }
    }

    @Test("An incomplete release is refused")
    func testIncompleteConsent() throws {
        let cases: [(String, (inout VoicePackManifest.Consent) -> Void)] = [
            ("no release reference", { $0.releaseReference = "  " }),
            ("permitted uses must be listed", { $0.permittedUses = [] }),
            ("permitted uses must be listed", { $0.permittedUses = ["commercial", " "] }),
            ("signedOn must be yyyy-MM-dd", { $0.signedOn = "13/09/2026" }),
            ("signedOn must be yyyy-MM-dd", { $0.signedOn = "2026-02-30" }),
            ("signedOn is in the future", { $0.signedOn = "2026-12-01" }),
            ("a real person's voice must require synthetic disclosure",
             { $0.requiresSyntheticDisclosure = false }),
        ]
        for (reason, change) in cases {
            var consent = PackFixture.validConsent
            change(&consent)
            let fixture = try PackFixture(kind: .realPerson, consent: consent)
            expectRejection(.incompleteConsent(reason: reason)) { _ = try fixture.load(now: fixedNow) }
        }
    }

    @Test("A designed voice needs no consent record")
    func testDesignedNeedsNoConsent() throws {
        let fixture = try PackFixture(kind: .designed, consent: nil)
        #expect(try fixture.load().syntheticDisclosure == nil)
    }
}

// MARK: - Library

@Suite("Voice pack library")
struct VoicePackLibraryTests {

    @Test("Picks the highest version for a voice and reports refused packs")
    func testLibrary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("choir-library-\(UUID().uuidString)")
        _ = try PackFixture(name: "a", version: "1.2.0", directory: directory)
        _ = try PackFixture(name: "b", version: "1.10.0", directory: directory)
        var broken = try PackFixture(name: "c", version: "9.0.0", directory: directory)
        try broken.edit { $0.engineVersion = 0 }
        try Data().write(to: directory.appendingPathComponent("notes.txt"))

        let library = VoicePackLibrary(directory: directory)

        // 1.10.0 is newer than 1.2.0 numerically, though not as a string.
        #expect(library.pack(for: .orion)?.manifest.packVersion == "1.10.0")
        #expect(library.packs.count == 2)
        #expect(library.rejected.count == 1, "the broken pack is reported, not dropped silently")
        #expect(library.rejected.first?.url.lastPathComponent == "c.choirvoice")
        #expect(library.pack(for: .finch) == nil)
    }

    @Test("A missing directory is an empty library, not a crash")
    func testMissingDirectory() {
        let library = VoicePackLibrary(directory: URL(fileURLWithPath: "/no/such/place"))
        #expect(library.packs.isEmpty)
        #expect(library.rejected.isEmpty)
    }

    @Test("Versions compare numerically")
    func testSemanticVersion() {
        #expect(SemanticVersion("0.9.0")! < SemanticVersion("0.10.0")!)
        #expect(SemanticVersion("1.0") == nil)
        #expect(SemanticVersion("1.0.x") == nil)
        #expect(SemanticVersion("1.-1.0") == nil)
    }
}

// MARK: - Engine

@Suite("Voice packs in the engine")
struct VoicePackEngineTests {

    private static let binding = VoicePackModelBinding { _ in
        (acoustic: MockAcousticModel(), vocoder: MockVocoder())
    }

    private struct BindingFailure: Error {}

    @Test("Every engine reports what it renders with")
    func testSources() throws {
        #expect(ChoirEngine().synthesisSource == .developmentMock)
        #expect(ChoirEngine(pipeline: .formant()).synthesisSource == .customPipeline)

        let pack = try PackFixture().load()
        let engine = try ChoirEngine(voicePack: pack, binding: Self.binding)
        #expect(engine.synthesisSource == .voicePack(id: "studio.test.test", version: "1.0.0"))
        #expect(engine.synthesisSource.isProductionVoice)
        #expect(!ChoirEngine().synthesisSource.isProductionVoice)
    }

    @Test("A pack engine synthesizes through the bound models")
    func testSynthesizes() async throws {
        let pack = try PackFixture().load()
        let engine = try ChoirEngine(voicePack: pack, binding: Self.binding)
        try await engine.initialize()
        let audio = try await engine.synthesize(text: "Hello there.", voice: .orion)
        #expect(!audio.samples.isEmpty)
    }

    @Test("A binding failure surfaces as a model load failure")
    func testBindingFailure() throws {
        let pack = try PackFixture().load()
        let failing = VoicePackModelBinding { _ in throw BindingFailure() }
        #expect {
            _ = try ChoirEngine(voicePack: pack, binding: failing)
        } throws: { error in
            guard case ChoirError.modelLoadFailed = error else { return false }
            return true
        }
    }

    @Test("The preferred engine uses a pack when it can, and speaks when it cannot")
    func testPreferred() throws {
        let fixture = try PackFixture()
        let library = VoicePackLibrary(directory: fixture.directory)

        let withPack = try ChoirEngine.preferred(for: .orion, library: library, binding: Self.binding)
        #expect(withPack.synthesisSource.isProductionVoice)

        // No binding, or no pack for this voice: formant, never the test tone.
        #expect(try ChoirEngine.preferred(for: .orion, library: library, binding: nil)
            .synthesisSource == .formant)
        #expect(try ChoirEngine.preferred(for: .finch, library: library, binding: Self.binding)
            .synthesisSource == .formant)
        #expect(try ChoirEngine.preferred(for: .orion, library: nil, binding: nil)
            .synthesisSource == .formant)
    }

    /// An installed but broken voice must be reported, not quietly replaced.
    @Test("The preferred engine does not hide a broken binding")
    func testPreferredDoesNotHideFailure() throws {
        let fixture = try PackFixture()
        let library = VoicePackLibrary(directory: fixture.directory)
        let failing = VoicePackModelBinding { _ in throw BindingFailure() }
        #expect(throws: ChoirError.self) {
            _ = try ChoirEngine.preferred(for: .orion, library: library, binding: failing)
        }
    }

    @Test("Exports from a real person's voice are always labelled synthetic")
    func testDisclosureOnExport() async throws {
        let pack = try PackFixture(kind: .realPerson, consent: PackFixture.validConsent)
            .load(now: fixedNow)
        let engine = try ChoirEngine(voicePack: pack, binding: Self.binding)
        let audio = AudioBuffer(samples: [Int16](repeating: 0, count: 4_800), format: AudioFormat())
        let label = try #require(pack.syntheticDisclosure)

        for metadata in [nil, AudioFileMetadata(title: "Chapter 1"),
                         AudioFileMetadata(syntheticDisclosure: nil)] {
            let output = try await engine.exportAudio(audio, format: .wav, metadata: metadata)
            guard case .wav(let data) = output else {
                Issue.record("expected WAV output")
                continue
            }
            #expect(data.range(of: Data(label.utf8)) != nil,
                    "the label must survive whatever metadata the caller passes")
        }
    }

    @Test("Exports from a designed voice carry no label, and metadata is unchanged")
    func testNoDisclosureForDesignedVoice() async throws {
        let pack = try PackFixture().load()
        let engine = try ChoirEngine(voicePack: pack, binding: Self.binding)
        let audio = AudioBuffer(samples: [Int16](repeating: 0, count: 4_800), format: AudioFormat())
        let output = try await engine.exportAudio(audio, format: .wav,
                                                  metadata: AudioFileMetadata(voice: "ORION"))
        guard case .wav(let data) = output else { Issue.record("expected WAV"); return }
        #expect(data.range(of: Data("Synthetic speech".utf8)) == nil)
        #expect(data.range(of: Data("Voice: ORION".utf8)) != nil,
                "the comment tag keeps its original form when there is no disclosure")
    }
}

// MARK: - Cache keys

@Suite("Voice packs in synthesis cache keys")
struct VoicePackCacheKeyTests {

    @Test("Keys without a pack keep exactly the digest they had before packs existed")
    func testUnchangedWithoutPack() {
        let parameters = SynthesisParameters(seed: 7)
        let before = SynthesisCacheKey(text: "Hello", voice: .orion, parameters: parameters)
        let explicitNil = SynthesisCacheKey(
            text: "Hello", voice: .orion, parameters: parameters, voicePackIdentity: nil)
        #expect(before == explicitNil)
    }

    @Test("A different pack, or a retrained one, gets a different key")
    func testPackChangesKey() throws {
        let parameters = SynthesisParameters(seed: 7)
        let none = SynthesisCacheKey(text: "Hello", voice: .orion, parameters: parameters)
        let first = SynthesisCacheKey(
            text: "Hello", voice: .orion, parameters: parameters, voicePackIdentity: "a@1.0.0#x")
        let second = SynthesisCacheKey(
            text: "Hello", voice: .orion, parameters: parameters, voicePackIdentity: "a@1.0.1#y")
        #expect(none != first)
        #expect(first != second)
        #expect(first == SynthesisCacheKey(
            text: "Hello", voice: .orion, parameters: parameters, voicePackIdentity: "a@1.0.0#x"))
    }
}
