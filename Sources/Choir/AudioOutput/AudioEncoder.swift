import Foundation

/// Encodes PCM audio to various formats.
public struct AudioEncoder: Sendable {
    public init() {}

    /// Encodes PCM audio to WAV format.
    ///
    /// - Parameters:
    ///   - buffer: Audio buffer containing PCM samples.
    /// - Returns: WAV encoded data.
    public func encodeWAV(_ buffer: AudioBuffer) -> Data {
        var wavData = Data()

        // RIFF header
        let chunkSize = 36 + buffer.samples.count * 2
        wavData.append("RIFF".data(using: .utf8)!)
        wavData.append(UInt32(chunkSize).littleEndianData)
        wavData.append("WAVE".data(using: .utf8)!)

        // fmt subchunk
        wavData.append("fmt ".data(using: .utf8)!)
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
        wavData.append("data".data(using: .utf8)!)
        wavData.append(UInt32(buffer.samples.count * 2).littleEndianData)

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

    /// Stub for MP3 encoding (requires external library).
    public func encodeMP3(_ buffer: AudioBuffer, quality: Int = 128) -> Data {
        // TODO: Implement MP3 encoding using lame or similar library
        // For now, return empty data
        return Data()
    }

    /// Stub for AAC encoding (requires AudioToolbox framework).
    public func encodeAAC(_ buffer: AudioBuffer, quality: Int = 128) -> Data {
        // TODO: Implement AAC encoding using AudioToolbox
        // For now, return empty data
        return Data()
    }

    /// Stub for FLAC encoding.
    public func encodeFLAC(_ buffer: AudioBuffer) -> Data {
        // TODO: Implement FLAC encoding
        // For now, return empty data
        return Data()
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
