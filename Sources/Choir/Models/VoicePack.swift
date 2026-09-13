import Foundation

// MARK: - Manifest

/// The manifest inside a `.choirvoice` bundle (MaintenanceManual §9, DST-001).
///
/// A voice pack is a directory: `manifest.json` plus the model files it names.
/// Every field here exists to stop a specific failure at load time rather than
/// at synthesis time, where it would surface as audio that is subtly wrong:
///
/// - `engineVersion` and `phonemeInventoryVersion` stop a pack trained against
///   one engine or phoneme set from loading against another, where phoneme
///   indices would silently address the wrong sounds.
/// - `files[].sha256` stops a truncated download or a swapped model file from
///   loading and producing plausible-sounding garbage.
/// - `speaker.consent` stops a voice built from a real person from loading
///   without a recorded release saying what it may be used for.
public struct VoicePackManifest: Sendable, Equatable, Codable {
    /// The only schema this engine reads.
    public static let supportedSchemaVersion = 1

    public var schemaVersion: Int
    /// Stable, reverse-DNS-style identifier, e.g. `"studio.bothmade.evan"`.
    public var packID: String
    /// Version of the voice asset itself, `major.minor.patch`. Distinct from the
    /// package and engine versions: retraining a voice changes this and nothing
    /// else.
    public var packVersion: String
    /// Must equal `Choir.engineVersion`.
    public var engineVersion: UInt64
    /// Oldest CHOIR package version able to run this pack, `major.minor.patch`.
    public var minimumPackageVersion: String
    /// Native rate the models were trained at. Informational for bindings; the
    /// vocoder is responsible for producing the engine's requested rate.
    public var sampleRate: Int
    /// Must equal `PhonemeInventory.version`.
    public var phonemeInventoryVersion: Int
    /// `Voice` identifiers this pack renders, e.g. `"choir.adult.male.orion"`.
    public var voiceIDs: [String]
    public var files: [File]
    public var speaker: Speaker

    public init(
        schemaVersion: Int = VoicePackManifest.supportedSchemaVersion,
        packID: String,
        packVersion: String,
        engineVersion: UInt64 = Choir.engineVersion,
        minimumPackageVersion: String = Choir.version,
        sampleRate: Int,
        phonemeInventoryVersion: Int = PhonemeInventory.version,
        voiceIDs: [String],
        files: [File],
        speaker: Speaker
    ) {
        self.schemaVersion = schemaVersion
        self.packID = packID
        self.packVersion = packVersion
        self.engineVersion = engineVersion
        self.minimumPackageVersion = minimumPackageVersion
        self.sampleRate = sampleRate
        self.phonemeInventoryVersion = phonemeInventoryVersion
        self.voiceIDs = voiceIDs
        self.files = files
        self.speaker = speaker
    }

    /// One file inside the bundle.
    public struct File: Sendable, Equatable, Codable {
        public enum Role: String, Sendable, Codable, CaseIterable {
            /// Phonemes and prosody to acoustic features. Optional: an
            /// end-to-end model has no separate acoustic stage.
            case acousticModel
            /// Features (or, end to end, phonemes) to waveform. Required.
            case vocoder
            /// Anything else the binding needs, such as a config or lexicon.
            case auxiliary
        }

        /// Relative to the bundle root, using `/`.
        public var path: String
        /// Lowercase hex SHA-256 of the file's contents.
        public var sha256: String
        public var role: Role

        public init(path: String, sha256: String, role: Role) {
            self.path = path
            self.sha256 = sha256
            self.role = role
        }
    }

    /// Whose voice this is, and on what terms.
    public struct Speaker: Sendable, Equatable, Codable {
        public enum Kind: String, Sendable, Codable {
            /// An original synthetic design with no real-person source (VOX-G-002).
            case designed
            /// Trained on recordings of an identifiable person.
            case realPerson
        }

        public var kind: Kind
        public var displayName: String
        /// Required when `kind` is `.realPerson`.
        public var consent: Consent?

        public init(kind: Kind, displayName: String, consent: Consent? = nil) {
            self.kind = kind
            self.displayName = displayName
            self.consent = consent
        }
    }

    /// The release a real speaker signed.
    ///
    /// The engine cannot read a contract, so this records what the contract
    /// says in a form the engine can hold a pack to: that one exists, when it
    /// was signed, what it permits, and whether output must be labelled.
    public struct Consent: Sendable, Equatable, Codable {
        /// Where the signed release is kept, e.g. a document ID or file name.
        public var releaseReference: String
        /// `yyyy-MM-dd`.
        public var signedOn: String
        /// Plain-language permitted uses, e.g. `"commercial voice pack"`.
        public var permittedUses: [String]
        /// Must be `true` for a real person: every export is labelled synthetic.
        public var requiresSyntheticDisclosure: Bool

        public init(
            releaseReference: String,
            signedOn: String,
            permittedUses: [String],
            requiresSyntheticDisclosure: Bool = true
        ) {
            self.releaseReference = releaseReference
            self.signedOn = signedOn
            self.permittedUses = permittedUses
            self.requiresSyntheticDisclosure = requiresSyntheticDisclosure
        }
    }
}

// MARK: - Errors

/// Why a voice pack was refused.
///
/// Kept separate from `ChoirError` so that adding a reason here never breaks an
/// application's exhaustive switch over the engine's public error type. At the
/// engine boundary these surface as `ChoirError.modelLoadFailed`.
public enum VoicePackError: Error, Equatable, Sendable, CustomStringConvertible {
    case notADirectory(path: String)
    case manifestMissing(path: String)
    case manifestUnreadable(reason: String)
    case unsupportedSchema(found: Int, supported: Int)
    case invalidField(field: String, reason: String)
    case engineVersionMismatch(pack: UInt64, engine: UInt64)
    case phonemeInventoryMismatch(pack: Int, engine: Int)
    case requiresNewerPackage(required: String, current: String)
    case unknownVoice(identifier: String)
    case duplicateVoice(identifier: String)
    case duplicateFile(path: String)
    case unsafePath(path: String)
    case missingFile(path: String)
    case checksumMismatch(path: String, expected: String, actual: String)
    case missingRole(VoicePackManifest.File.Role)
    case consentRequired(speaker: String)
    case incompleteConsent(reason: String)

    public var description: String {
        switch self {
        case .notADirectory(let path):
            return "\(path) is not a voice pack directory"
        case .manifestMissing(let path):
            return "no \(VoicePack.manifestFileName) in \(path)"
        case .manifestUnreadable(let reason):
            return "the manifest could not be read: \(reason)"
        case .unsupportedSchema(let found, let supported):
            return "manifest schema \(found) is not supported; this engine reads schema \(supported)"
        case .invalidField(let field, let reason):
            return "manifest field '\(field)' is invalid: \(reason)"
        case .engineVersionMismatch(let pack, let engine):
            return "pack was built for engine version \(pack); this engine is version \(engine)"
        case .phonemeInventoryMismatch(let pack, let engine):
            return "pack uses phoneme inventory \(pack); this engine uses \(engine), so phoneme indices would address the wrong sounds"
        case .requiresNewerPackage(let required, let current):
            return "pack requires CHOIR \(required) or later; this is \(current)"
        case .unknownVoice(let identifier):
            return "pack names unknown voice '\(identifier)'"
        case .duplicateVoice(let identifier):
            return "pack names voice '\(identifier)' more than once"
        case .duplicateFile(let path):
            return "pack lists '\(path)' more than once"
        case .unsafePath(let path):
            return "file path '\(path)' escapes the pack directory"
        case .missingFile(let path):
            return "pack file '\(path)' is missing"
        case .checksumMismatch(let path, let expected, let actual):
            return "'\(path)' is corrupt or was replaced: expected SHA-256 \(expected), found \(actual)"
        case .missingRole(let role):
            return "pack has no \(role.rawValue) file"
        case .consentRequired(let speaker):
            return "'\(speaker)' is a real person and the pack has no consent record"
        case .incompleteConsent(let reason):
            return "consent record is incomplete: \(reason)"
        }
    }
}

// MARK: - Verified pack

/// A voice pack whose manifest, files and consent have all been verified.
///
/// There is no way to construct one without passing `load(from:)`, so holding
/// a `VoicePack` is proof the checks ran.
public struct VoicePack: Sendable, Equatable {
    public static let fileExtension = "choirvoice"
    public static let manifestFileName = "manifest.json"

    public let manifest: VoicePackManifest
    public let rootURL: URL
    /// Changes whenever anything that affects rendered audio changes: pack
    /// identity, version, or the bytes of any file. Include it in synthesis
    /// cache keys, or a retrained voice will be served stale cached audio.
    public let identity: String

    private init(manifest: VoicePackManifest, rootURL: URL, identity: String) {
        self.manifest = manifest
        self.rootURL = rootURL
        self.identity = identity
    }

    /// The voices this pack renders.
    public var voices: [Voice] {
        manifest.voiceIDs.compactMap(Voice.voice(withIdentifier:))
    }

    public var isRealPerson: Bool {
        manifest.speaker.kind == .realPerson
    }

    /// The label every export from this pack must carry, or nil if none is
    /// required.
    public var syntheticDisclosure: String? {
        let consentRequires = manifest.speaker.consent?.requiresSyntheticDisclosure ?? false
        guard isRealPerson || consentRequires else { return nil }
        return "Synthetic speech generated by CHOIR from the voice of "
            + "\(manifest.speaker.displayName) (\(manifest.packID) \(manifest.packVersion))."
    }

    /// Location of the first file with this role.
    public func url(for role: VoicePackManifest.File.Role) -> URL? {
        manifest.files.first { $0.role == role }
            .map { rootURL.appendingPathComponent($0.path) }
    }

    /// Reads and verifies a pack.
    ///
    /// - Parameters:
    ///   - url: the `.choirvoice` directory.
    ///   - now: the date consent is checked against; injectable for tests.
    /// - Throws: `VoicePackError` naming the first check that failed.
    public static func load(from url: URL, now: Date = Date()) throws -> VoicePack {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw VoicePackError.notADirectory(path: url.path)
        }

        let manifestURL = url.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw VoicePackError.manifestMissing(path: url.path)
        }

        let manifest: VoicePackManifest
        do {
            manifest = try JSONDecoder().decode(
                VoicePackManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw VoicePackError.manifestUnreadable(reason: "\(error)")
        }

        try validateCompatibility(manifest)
        try validateIdentity(manifest)
        try validateVoices(manifest)
        try validateSpeaker(manifest, now: now)
        try validateFiles(manifest, root: url)

        return VoicePack(manifest: manifest, rootURL: url,
                         identity: identity(of: manifest))
    }

    // MARK: Validation

    private static func validateCompatibility(_ manifest: VoicePackManifest) throws {
        guard manifest.schemaVersion == VoicePackManifest.supportedSchemaVersion else {
            throw VoicePackError.unsupportedSchema(
                found: manifest.schemaVersion,
                supported: VoicePackManifest.supportedSchemaVersion)
        }
        guard manifest.engineVersion == Choir.engineVersion else {
            throw VoicePackError.engineVersionMismatch(
                pack: manifest.engineVersion, engine: Choir.engineVersion)
        }
        guard manifest.phonemeInventoryVersion == PhonemeInventory.version else {
            throw VoicePackError.phonemeInventoryMismatch(
                pack: manifest.phonemeInventoryVersion, engine: PhonemeInventory.version)
        }
        guard let required = SemanticVersion(manifest.minimumPackageVersion) else {
            throw VoicePackError.invalidField(
                field: "minimumPackageVersion", reason: "expected major.minor.patch")
        }
        if let current = SemanticVersion(Choir.version), current < required {
            throw VoicePackError.requiresNewerPackage(
                required: manifest.minimumPackageVersion, current: Choir.version)
        }
        guard manifest.sampleRate > 0 else {
            throw VoicePackError.invalidField(field: "sampleRate", reason: "must be positive")
        }
    }

    private static func validateIdentity(_ manifest: VoicePackManifest) throws {
        let id = manifest.packID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id == manifest.packID,
              id.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else {
            throw VoicePackError.invalidField(
                field: "packID", reason: "use letters, digits, '.', '_' and '-' only")
        }
        guard SemanticVersion(manifest.packVersion) != nil else {
            throw VoicePackError.invalidField(
                field: "packVersion", reason: "expected major.minor.patch")
        }
    }

    private static func validateVoices(_ manifest: VoicePackManifest) throws {
        guard !manifest.voiceIDs.isEmpty else {
            throw VoicePackError.invalidField(field: "voiceIDs", reason: "must name at least one voice")
        }
        var seen = Set<String>()
        for identifier in manifest.voiceIDs {
            guard seen.insert(identifier).inserted else {
                throw VoicePackError.duplicateVoice(identifier: identifier)
            }
            guard Voice.voice(withIdentifier: identifier) != nil else {
                throw VoicePackError.unknownVoice(identifier: identifier)
            }
        }
    }

    private static func validateSpeaker(_ manifest: VoicePackManifest, now: Date) throws {
        let speaker = manifest.speaker
        guard !speaker.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoicePackError.invalidField(field: "speaker.displayName", reason: "must not be empty")
        }
        guard speaker.kind == .realPerson else { return }

        guard let consent = speaker.consent else {
            throw VoicePackError.consentRequired(speaker: speaker.displayName)
        }
        guard !consent.releaseReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoicePackError.incompleteConsent(reason: "no release reference")
        }
        let uses = consent.permittedUses.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !uses.isEmpty, !uses.contains(where: \.isEmpty) else {
            throw VoicePackError.incompleteConsent(reason: "permitted uses must be listed")
        }
        guard let signed = parseDate(consent.signedOn) else {
            throw VoicePackError.incompleteConsent(reason: "signedOn must be yyyy-MM-dd")
        }
        // A release dated after today was not signed when this pack was built.
        guard signed <= now else {
            throw VoicePackError.incompleteConsent(reason: "signedOn is in the future")
        }
        // A real person's voice can say anything once trained, including
        // things they never said. Labelling output is not optional for one.
        guard consent.requiresSyntheticDisclosure else {
            throw VoicePackError.incompleteConsent(
                reason: "a real person's voice must require synthetic disclosure")
        }
    }

    private static func validateFiles(_ manifest: VoicePackManifest, root: URL) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        var seen = Set<String>()

        for file in manifest.files {
            guard seen.insert(file.path).inserted else {
                throw VoicePackError.duplicateFile(path: file.path)
            }
            guard isSafeRelativePath(file.path) else {
                throw VoicePackError.unsafePath(path: file.path)
            }
            let fileURL = root.appendingPathComponent(file.path)
            // Checked again after resolution, so a symlink inside the bundle
            // cannot point a verified name at a file outside it.
            let resolved = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(rootPath + "/") else {
                throw VoicePackError.unsafePath(path: file.path)
            }
            let hex = file.sha256.lowercased()
            guard hex.count == 64, hex == file.sha256,
                  hex.allSatisfy({ $0.isHexDigit }) else {
                throw VoicePackError.invalidField(
                    field: "files[\(file.path)].sha256",
                    reason: "expected 64 lowercase hex characters")
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw VoicePackError.missingFile(path: file.path)
            }
            let actual: String
            do {
                actual = try SHA256Hasher.hexDigest(fileAt: fileURL)
            } catch {
                throw VoicePackError.missingFile(path: file.path)
            }
            guard actual == hex else {
                throw VoicePackError.checksumMismatch(path: file.path, expected: hex, actual: actual)
            }
        }

        guard manifest.files.contains(where: { $0.role == .vocoder }) else {
            throw VoicePackError.missingRole(.vocoder)
        }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else {
            return nil
        }
        return date
    }

    private static func identity(of manifest: VoicePackManifest) -> String {
        var canonical = "\(manifest.packID)\n\(manifest.packVersion)\n\(manifest.engineVersion)\n"
        for file in manifest.files.sorted(by: { $0.path < $1.path }) {
            canonical += "\(file.path):\(file.sha256):\(file.role.rawValue)\n"
        }
        return "\(manifest.packID)@\(manifest.packVersion)#"
            + SHA256Hasher.hexDigest(Data(canonical.utf8))
    }
}

// MARK: - Library

/// The voice packs installed in one directory.
///
/// Scanning never throws for a bad pack: one corrupt download should not stop
/// every other voice from loading. Refused packs are kept, with their reason,
/// so an application can show why a voice it expected is missing.
public struct VoicePackLibrary: Sendable {
    public struct Rejection: Sendable, Equatable {
        public let url: URL
        public let error: VoicePackError
    }

    public let directory: URL
    /// Verified packs, highest version first.
    public let packs: [VoicePack]
    public let rejected: [Rejection]

    public init(directory: URL, now: Date = Date()) {
        self.directory = directory
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        var packs: [VoicePack] = []
        var rejected: [Rejection] = []
        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == VoicePack.fileExtension {
            do {
                packs.append(try VoicePack.load(from: url, now: now))
            } catch let error as VoicePackError {
                rejected.append(Rejection(url: url, error: error))
            } catch {
                rejected.append(Rejection(
                    url: url, error: .manifestUnreadable(reason: "\(error)")))
            }
        }

        self.packs = packs.sorted { lhs, rhs in
            let l = SemanticVersion(lhs.manifest.packVersion)
            let r = SemanticVersion(rhs.manifest.packVersion)
            if l != r, let l, let r { return l > r }
            return lhs.manifest.packID < rhs.manifest.packID
        }
        self.rejected = rejected
    }

    /// The highest-version verified pack that renders `voice`.
    public func pack(for voice: Voice) -> VoicePack? {
        packs.first { $0.manifest.voiceIDs.contains(voice.identifier) }
    }
}

// MARK: - Binding models to a pack

/// Turns a verified pack's files into running models.
///
/// A pack format cannot know a model's tensor names, input layout or which
/// half of an end-to-end network plays which role; that is decided when the
/// model is trained and converted (TRAINING.md). So the binding is supplied by
/// the code that knows the model, and receives only packs that have already
/// passed verification.
public struct VoicePackModelBinding: Sendable {
    public typealias Models = (acoustic: any AcousticModelProtocol, vocoder: any VocoderProtocol)

    private let make: @Sendable (VoicePack) throws -> Models

    public init(_ make: @escaping @Sendable (VoicePack) throws -> Models) {
        self.make = make
    }

    public func models(for pack: VoicePack) throws -> Models {
        try make(pack)
    }
}

extension SynthesisPipeline {
    /// A pipeline rendering through a verified voice pack.
    public static func voicePack(
        _ pack: VoicePack,
        binding: VoicePackModelBinding,
        audioFormat: AudioFormat = AudioFormat()
    ) throws -> SynthesisPipeline {
        let models: VoicePackModelBinding.Models
        do {
            models = try binding.models(for: pack)
        } catch let error as ChoirError {
            throw error
        } catch {
            throw ChoirError.modelLoadFailed(
                reason: "voice pack \(pack.manifest.packID) could not be bound: \(error)")
        }
        return SynthesisPipeline(
            acousticModel: models.acoustic,
            vocoder: models.vocoder,
            audioFormat: audioFormat)
    }
}

/// What an engine is actually rendering with.
///
/// MaintenanceManual §10 requires that production and development output be
/// impossible to confuse. A mock-backed engine and a trained voice both return
/// an `AudioBuffer`; this is how an application, a log or a benchmark tells
/// them apart.
public enum SynthesisSource: Sendable, Equatable {
    /// The default development pipeline: a test tone, not speech.
    case developmentMock
    /// The rule-based formant synthesizer: speech-structured, not a product voice.
    case formant
    /// A verified voice pack.
    case voicePack(id: String, version: String)
    /// A pipeline supplied by the caller, whose models the engine cannot see.
    case customPipeline

    public var isProductionVoice: Bool {
        if case .voicePack = self { return true }
        return false
    }
}

// MARK: - Versions

/// `major.minor.patch`, compared numerically so "0.10.0" sorts after "0.9.0".
struct SemanticVersion: Comparable, Sendable {
    let parts: [Int]

    init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy(\.isNumber), let value = Int(piece) else {
                return nil
            }
            parts.append(value)
        }
        self.parts = parts
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}
