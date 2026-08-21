import Foundation

/// Encodes PCM audio to various formats.
public struct AudioEncoder: Sendable {
    public init() {}

    /// Encodes PCM audio to WAV format.
    ///
    /// - Parameters:
    ///   - buffer: Audio buffer containing PCM samples.
    /// - Returns: WAV encoded data.
    public func encodeWAV(_ buffer: AudioBuffer) throws -> Data {
        try buffer.format.validate()
        guard buffer.samples.count % buffer.format.channels == 0 else {
            throw ChoirError.audioEncodingFailed(
                reason: "Interleaved sample count must be divisible by the channel count")
        }
        let dataByteCount = buffer.samples.count.multipliedReportingOverflow(by: 2)
        guard !dataByteCount.overflow,
              dataByteCount.partialValue <= Int(UInt32.max) - 36 else {
            throw ChoirError.audioEncodingFailed(reason: "Audio is too large for a RIFF/WAV file")
        }

        var wavData = Data()

        // RIFF header
        let chunkSize = 36 + dataByteCount.partialValue
        wavData.append(Data("RIFF".utf8))
        wavData.append(UInt32(chunkSize).littleEndianData)
        wavData.append(Data("WAVE".utf8))

        // fmt subchunk
        wavData.append(Data("fmt ".utf8))
        wavData.append(UInt32(16).littleEndianData)  // Subchunk1Size
        wavData.append(UInt16(1).littleEndianData)   // AudioFormat (1 = PCM)
        wavData.append(UInt16(buffer.format.channels).littleEndianData)
        wavData.append(UInt32(buffer.format.sampleRate).littleEndianData)
        let byteRate = UInt32(buffer.format.sampleRate * buffer.format.channels * buffer.format.bitDepth / 8)
        wavData.append(byteRate.littleEndianData)
        let blockAlign = UInt16(buffer.format.channels * buffer.format.bitDepth / 8)
        wavData.append(blockAlign.littleEndianData)
        wavData.append(UInt16(buffer.format.bitDepth).littleEndianData)

        // data subchunk
        wavData.append(Data("data".utf8))
        wavData.append(UInt32(dataByteCount.partialValue).littleEndianData)

        // Sample data
        for sample in buffer.samples {
            wavData.append(sample.littleEndianData)
        }

        return wavData
    }

    /// Encodes PCM audio to raw format (no header).
    ///
    /// - Parameters:
    ///   - buffer: Audio buffer containing PCM samples.
    /// - Returns: Raw PCM data.
    public func encodeRaw(_ buffer: AudioBuffer) -> Data {
        var rawData = Data()

        for sample in buffer.samples {
            rawData.append(sample.littleEndianData)
        }

        return rawData
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

extension Int16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Int16>.size)
    }
}
