import Foundation

/// A chapter marker embedded in an exported audio container.
public struct AudioChapterMark: Sendable, Equatable, Codable {
    public let title: String
    public let startTimeSeconds: Double

    public init(title: String, startTimeSeconds: Double) {
        self.title = title
        self.startTimeSeconds = startTimeSeconds
    }
}

/// Optional caller-supplied tags for exported files (AUD-011).
public struct AudioFileMetadata: Sendable, Equatable, Codable {
    public var title: String?
    public var artist: String?
    public var voice: String?
    public var chapters: [AudioChapterMark]

    public init(
        title: String? = nil,
        artist: String? = nil,
        voice: String? = nil,
        chapters: [AudioChapterMark] = []
    ) {
        self.title = title
        self.artist = artist
        self.voice = voice
        self.chapters = chapters
    }

    public var isEmpty: Bool {
        [title, artist, voice].allSatisfy { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        } && chapters.isEmpty
    }
}

/// Optional processing applied immediately before file encoding.
public enum AudioExportPreset: Sendable, Equatable, Codable {
    /// Preserve the supplied PCM exactly.
    case unprocessed

    /// Apply CHOIR's opt-in broadcast chain (AUD-022).
    case broadcast

    func process(_ audio: AudioBuffer) throws -> AudioBuffer {
        switch self {
        case .unprocessed:
            try audio.validate()
            return audio
        case .broadcast:
            return try AudioEffectChain
                .broadcast(sampleRate: audio.format.sampleRate)
                .process(audio)
        }
    }
}

/// Encodes PCM audio to various formats.
public struct AudioEncoder: Sendable {
    /// Bytes in the canonical PCM WAV header emitted by this encoder.
    public static let wavHeaderSize = 44

    public init() {}

    /// Predicts the encoded size without allocating a WAV payload.
    public func estimatedWAVByteCount(
        for buffer: AudioBuffer,
        metadata: AudioFileMetadata? = nil
    ) throws -> Int {
        try buffer.format.validate()
        guard buffer.isFrameAligned else {
            throw ChoirError.audioEncodingFailed(
                reason: "Interleaved sample count must be divisible by the channel count")
        }
        let dataByteCount = buffer.samples.count.multipliedReportingOverflow(
            by: MemoryLayout<Int16>.size)
        guard !dataByteCount.overflow,
              UInt64(dataByteCount.partialValue) <= UInt64(UInt32.max) - 36 else {
            throw ChoirError.audioEncodingFailed(reason: "Audio is too large for a RIFF/WAV file")
        }
        let metadataChunks = try makeWAVMetadataChunks(
            metadata, format: buffer.format, frameCount: buffer.frameCount)
        let (total, totalOverflow) = Self.wavHeaderSize
            .addingReportingOverflow(dataByteCount.partialValue)
        guard !totalOverflow else {
            throw ChoirError.audioEncodingFailed(reason: "Audio is too large for a RIFF/WAV file")
        }
        let (withMetadata, metadataOverflow) = total.addingReportingOverflow(metadataChunks.count)
        guard !metadataOverflow,
              UInt64(withMetadata) <= UInt64(UInt32.max) + 8 else {
            throw ChoirError.audioEncodingFailed(reason: "Audio is too large for a RIFF/WAV file")
        }
        return withMetadata
    }

    /// Encodes PCM audio to WAV format.
    ///
    /// - Parameters:
    ///   - buffer: Audio buffer containing PCM samples.
    /// - Returns: WAV encoded data.
    public func encodeWAV(
        _ buffer: AudioBuffer,
        metadata: AudioFileMetadata? = nil
    ) throws -> Data {
        try buffer.format.validate()
        guard buffer.isFrameAligned else {
            throw ChoirError.audioEncodingFailed(
                reason: "Interleaved sample count must be divisible by the channel count")
        }
        let dataByteCount = buffer.samples.count.multipliedReportingOverflow(
            by: MemoryLayout<Int16>.size)
        guard !dataByteCount.overflow,
              UInt64(dataByteCount.partialValue) <= UInt64(UInt32.max) - 36 else {
            throw ChoirError.audioEncodingFailed(reason: "Audio is too large for a RIFF/WAV file")
        }

        let metadataChunks = try makeWAVMetadataChunks(
            metadata, format: buffer.format, frameCount: buffer.frameCount)
        let estimatedSize = try estimatedWAVByteCount(for: buffer, metadata: metadata)
        let riffSize = estimatedSize - 8

        var wavData = Data()
        wavData.reserveCapacity(estimatedSize)

        // RIFF header
        wavData.append(Data("RIFF".utf8))
        wavData.append(UInt32(riffSize).littleEndianData)
        wavData.append(Data("WAVE".utf8))

        // fmt subchunk
        wavData.append(Data("fmt ".utf8))
        wavData.append(UInt32(16).littleEndianData)  // Subchunk1Size
        wavData.append(UInt16(1).littleEndianData)   // AudioFormat (1 = PCM)
        wavData.append(UInt16(buffer.format.channels).littleEndianData)
        wavData.append(UInt32(buffer.format.sampleRate).littleEndianData)
        let byteRate = UInt32(
            UInt64(buffer.format.sampleRate)
                * UInt64(buffer.format.channels)
                * UInt64(buffer.format.bitDepth)
                / 8)
        wavData.append(byteRate.littleEndianData)
        let blockAlign = UInt16(buffer.format.channels * buffer.format.bitDepth / 8)
        wavData.append(blockAlign.littleEndianData)
        wavData.append(UInt16(buffer.format.bitDepth).littleEndianData)

        // Optional INFO and cue/label chunks. They precede sample data so the
        // ordinary no-metadata path remains the canonical 44-byte WAV.
        wavData.append(metadataChunks)

        // data subchunk
        wavData.append(Data("data".utf8))
        wavData.append(UInt32(dataByteCount.partialValue).littleEndianData)

        // Sample data
        for sample in buffer.samples {
            wavData.append(sample.littleEndianData)
        }

        return wavData
    }

    /// Encodes frame-aligned streaming chunks into one WAV payload.
    ///
    /// A final chunk, when present, must be last. Explicit timestamps must not
    /// move backwards or overlap the preceding timestamped chunk.
    public func encodeWAV(chunks: [AudioChunk], format: AudioFormat) throws -> Data {
        try format.validate()
        var combined: [Int16] = []
        var previousEndTimestamp: Double?

        for (index, chunk) in chunks.enumerated() {
            try chunk.validate(format: format)
            if chunk.isFinal, index != chunks.index(before: chunks.endIndex) {
                throw ChoirError.audioEncodingFailed(reason: "A final audio chunk must be last")
            }
            if let timestamp = chunk.timestamp,
               let previousEndTimestamp,
               timestamp < previousEndTimestamp {
                throw ChoirError.audioEncodingFailed(
                    reason: "Audio chunk timestamps must be monotonic and non-overlapping")
            }
            if let end = chunk.endTimestamp(format: format) {
                previousEndTimestamp = end
            }
            let (newCount, overflow) = combined.count.addingReportingOverflow(chunk.samples.count)
            guard !overflow else {
                throw ChoirError.audioEncodingFailed(reason: "Combined audio is too large")
            }
            combined.reserveCapacity(newCount)
            combined.append(contentsOf: chunk.samples)
        }

        return try encodeWAV(AudioBuffer(samples: combined, format: format))
    }

    /// Encodes PCM audio to raw format (no header).
    ///
    /// - Parameters:
    ///   - buffer: Audio buffer containing PCM samples.
    /// - Returns: Raw PCM data.
    public func encodeRaw(_ buffer: AudioBuffer) -> Data {
        var rawData = Data()
        rawData.reserveCapacity(buffer.byteCount)

        for sample in buffer.samples {
            rawData.append(sample.littleEndianData)
        }

        return rawData
    }

    /// Validates the PCM format and frame alignment before raw encoding.
    public func encodeRawValidated(_ buffer: AudioBuffer) throws -> Data {
        try buffer.validate()
        return encodeRaw(buffer)
    }

    /// Reports that MP3 encoding is unavailable in the current package.
    public func encodeMP3(_ buffer: AudioBuffer, quality: Int = 128) throws -> Data {
        _ = buffer
        try validateBitrate(quality)
        throw ChoirError.audioEncodingFailed(
            reason: "MP3 encoding is not available in this build")
    }

    /// Reports that AAC encoding is unavailable in the current package.
    public func encodeAAC(_ buffer: AudioBuffer, quality: Int = 128) throws -> Data {
        _ = buffer
        try validateBitrate(quality)
        throw ChoirError.audioEncodingFailed(
            reason: "AAC encoding is not available in this build")
    }

    /// Reports that FLAC encoding is unavailable in the current package.
    public func encodeFLAC(_ buffer: AudioBuffer) throws -> Data {
        _ = buffer
        throw ChoirError.audioEncodingFailed(
            reason: "FLAC encoding is not available in this build")
    }

    private func validateBitrate(_ bitrate: Int) throws {
        guard 8...320 ~= bitrate else {
            throw ChoirError.invalidParameter(
                parameter: "bitrate", reason: "Bitrate must be within 8...320 kbps")
        }
    }

    private func makeWAVMetadataChunks(
        _ metadata: AudioFileMetadata?,
        format: AudioFormat,
        frameCount: Int
    ) throws -> Data {
        guard let metadata, !metadata.isEmpty else { return Data() }
        let duration = format.sampleRate > 0
            ? Double(frameCount) / Double(format.sampleRate) : 0
        let chapters = try validatedChapters(metadata.chapters, duration: duration)
        var chunks = Data()

        var informationPayload = Data("INFO".utf8)
        appendINFO(tag: "INAM", value: metadata.title, to: &informationPayload)
        appendINFO(tag: "IART", value: metadata.artist, to: &informationPayload)
        appendINFO(tag: "ICMT", value: metadata.voice.map { "Voice: \($0)" }, to: &informationPayload)
        if informationPayload.count > 4 {
            appendRIFFChunk(id: "LIST", payload: informationPayload, to: &chunks)
        }

        guard !chapters.isEmpty else { return chunks }
        var cuePayload = Data()
        cuePayload.append(UInt32(chapters.count).littleEndianData)
        for (index, chapter) in chapters.enumerated() {
            let identifier = UInt32(index + 1)
            let sampleOffset = min(
                UInt64(UInt32.max),
                UInt64((chapter.startTimeSeconds * Double(format.sampleRate)).rounded()))
            cuePayload.append(identifier.littleEndianData)
            cuePayload.append(UInt32(sampleOffset).littleEndianData)
            cuePayload.append(Data("data".utf8))
            cuePayload.append(UInt32(0).littleEndianData)
            cuePayload.append(UInt32(0).littleEndianData)
            cuePayload.append(UInt32(sampleOffset).littleEndianData)
        }
        appendRIFFChunk(id: "cue ", payload: cuePayload, to: &chunks)

        var labelsPayload = Data("adtl".utf8)
        for (index, chapter) in chapters.enumerated() {
            var label = Data()
            label.append(UInt32(index + 1).littleEndianData)
            label.append(contentsOf: sanitizedTagValue(chapter.title).utf8)
            label.append(0)
            appendRIFFChunk(id: "labl", payload: label, to: &labelsPayload)
        }
        appendRIFFChunk(id: "LIST", payload: labelsPayload, to: &chunks)
        return chunks
    }

    private func validatedChapters(
        _ chapters: [AudioChapterMark], duration: Double
    ) throws -> [AudioChapterMark] {
        var previous = -Double.infinity
        for chapter in chapters {
            guard !chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ChoirError.invalidParameter(
                    parameter: "chapters", reason: "Chapter titles must not be empty")
            }
            guard chapter.startTimeSeconds.isFinite,
                  chapter.startTimeSeconds >= 0,
                  chapter.startTimeSeconds <= duration else {
                throw ChoirError.invalidParameter(
                    parameter: "chapters", reason: "Chapter times must fall within the audio")
            }
            guard chapter.startTimeSeconds >= previous else {
                throw ChoirError.invalidParameter(
                    parameter: "chapters", reason: "Chapter times must be monotonically ordered")
            }
            previous = chapter.startTimeSeconds
        }
        return chapters
    }

    private func appendINFO(tag: String, value: String?, to data: inout Data) {
        guard let value else { return }
        let sanitized = sanitizedTagValue(value)
        guard !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var payload = Data(sanitized.utf8)
        payload.append(0)
        appendRIFFChunk(id: tag, payload: payload, to: &data)
    }

    private func appendRIFFChunk(id: String, payload: Data, to data: inout Data) {
        data.append(Data(id.utf8.prefix(4)))
        data.append(UInt32(payload.count).littleEndianData)
        data.append(payload)
        if payload.count.isMultiple(of: 2) == false { data.append(0) }
    }

    private func sanitizedTagValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\0", with: "")
    }
}

// MARK: - Little Endian Encoding Extensions

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

extension UInt64 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }
}

extension Int16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Int16>.size)
    }
}
