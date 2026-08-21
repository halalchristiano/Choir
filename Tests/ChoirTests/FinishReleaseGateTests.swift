import Foundation
import Testing
@testable import Choir

@Suite("Repository-enforceable release gates")
struct FinishReleaseGateTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftSources() throws -> [(URL, String)] {
        let sourceRoot = repositoryRoot.appendingPathComponent("Sources", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else {
            throw ChoirError.unknown("Could not enumerate package sources")
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return (url, try String(contentsOf: url, encoding: .utf8))
        }
    }

    @Test("SEC-001/TST-007: runtime source contains no networking surface")
    func noNetworkingSurface() throws {
        let forbidden = [
            "import Network", "import CFNetwork", "URLSession",
            "NWConnection", "NWListener", "CFStreamCreatePairWithSocket",
            "getaddrinfo(", "socket(",
        ]
        for (url, source) in try swiftSources() {
            for token in forbidden {
                #expect(
                    !source.contains(token),
                    "\(url.lastPathComponent) contains forbidden networking token \(token)")
            }
        }
    }

    @Test("PKG-007: runtime source contains no dynamic/private API escape hatch")
    func noPrivateAPIEscapeHatch() throws {
        let forbidden = [
            "dlopen(", "dlsym(", "performSelector", "NSSelectorFromString",
            "class_getInstanceMethod", "method_exchangeImplementations",
        ]
        for (url, source) in try swiftSources() {
            for token in forbidden {
                #expect(
                    !source.contains(token),
                    "\(url.lastPathComponent) contains private/dynamic API token \(token)")
            }
        }
    }

    @Test("SEC-005: runtime exposes no speaker-encoder or voice-cloning input")
    func noVoiceCloningSurface() throws {
        let normalizedSources = try swiftSources()
            .map { $0.1 }
            .joined(separator: "\n")
            .lowercased()
        for forbidden in ["speakerencoder", "speaker_encoder", "voiceclone", "voice_clone"] {
            #expect(!normalizedSources.contains(forbidden))
        }
    }

    @Test("DOC-001: DocC entry point links all required foundation articles")
    func docCFoundationArticlesAreLinked() throws {
        let catalog = repositoryRoot
            .appendingPathComponent("Sources/Choir/Choir.docc/Choir.md")
        let source = try String(contentsOf: catalog, encoding: .utf8)
        for article in [
            "GettingStarted", "APITiers", "PlatformDifferences",
            "AccessibilityIntegration", "ResponsibleUse",
        ] {
            #expect(source.contains("<doc:\(article)>"), "Choir.md does not link \(article)")
            let file = catalog.deletingLastPathComponent().appendingPathComponent("\(article).md")
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test("DST-001: package and audio-engine versions are independently exposed")
    func separatePackageAndEngineVersions() {
        #expect(!Choir.version.isEmpty)
        #expect(Choir.engineVersion > 0)
    }
}
