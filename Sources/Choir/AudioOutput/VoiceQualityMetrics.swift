import Foundation

/// Analyzes voice quality and synthesis metrics.
public struct VoiceQualityAnalyzer: Sendable {
    public init() {}

    /// Audio quality metrics.
    public struct QualityMetrics: Sendable, Equatable, Codable {
        /// RMS (root mean square) loudness.
        public let rmsLoudness: Double

        /// Peak level.
        public let peakLevel: Int16

        /// Dynamic range (peak - quiet floor).
        public let dynamicRange: Double

        /// Estimated LUFS (perceptual loudness).
        public let lufs: Double

        /// Signal-to-noise ratio (estimated).
        public let snrEstimate: Double

        /// Clipping percentage (samples above threshold).
        public let clippingPercent: Double

        /// Zero crossings per second (for harmonic content).
        public let zeroCrossingRate: Double

        public init(
            rmsLoudness: Double,
            peakLevel: Int16,
            dynamicRange: Double,
            lufs: Double,
            snrEstimate: Double,
            clippingPercent: Double,
            zeroCrossingRate: Double
        ) {
            self.rmsLoudness = rmsLoudness.isFinite ? rmsLoudness : -60
            self.peakLevel = max(0, peakLevel)
            self.dynamicRange = dynamicRange.isFinite ? max(0, dynamicRange) : 0
            self.lufs = lufs.isFinite ? lufs : -60
            self.snrEstimate = snrEstimate.isFinite ? max(0, snrEstimate) : 0
            self.clippingPercent = clippingPercent.isFinite
                ? min(100, max(0, clippingPercent)) : 0
            self.zeroCrossingRate = zeroCrossingRate.isFinite ? max(0, zeroCrossingRate) : 0
        }

        public var peakDBFS: Double {
            guard peakLevel > 0 else { return -Double.infinity }
            return 20 * log10(Double(peakLevel) / Double(Int16.max))
        }

        public var clippingFraction: Double { clippingPercent / 100 }

        public var isSilent: Bool { peakLevel == 0 }
    }

    /// Analyzes audio quality.
    public func analyzeQuality(_ samples: [Int16], sampleRate: Int) -> QualityMetrics {
        guard !samples.isEmpty else {
            return QualityMetrics(
                rmsLoudness: -60,
                peakLevel: 0,
                dynamicRange: 0,
                lufs: -60,
                snrEstimate: 0,
                clippingPercent: 0,
                zeroCrossingRate: 0
            )
        }

        // Calculate RMS
        let sumSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = sqrt(sumSquares / Double(samples.count))
        let rmsDb = 20.0 * log10(max(rms / 32767.0, 0.00001))

        // Find peak
        // `abs` traps on Int16.min (-32768), an ordinary full-scale sample,
        // so magnitudes are taken as UInt16 throughout.
        let peakMagnitude = samples.map { $0.magnitude }.max() ?? 0

        // Dynamic range
        let minNonZero = samples.filter { $0 != 0 }.map { $0.magnitude }.min() ?? 1
        let dynamicRange = peakMagnitude == 0
            ? 0
            : 20.0 * log10(Double(peakMagnitude) / Double(minNonZero))

        // Estimate LUFS (simplified K-weighting approximation)
        let lufs = rmsDb - 4.0  // Simplified

        // Estimate SNR
        let quietFloor = peakMagnitude / 10
        let snr = peakMagnitude == 0
            ? 0
            : 20.0 * log10(Double(peakMagnitude) / Double(max(quietFloor, 1)))

        // Check clipping (samples above 95% of max)
        let clipThreshold = Int16(32767 * 0.95)
        let clippedSamples = samples.filter { $0.magnitude > clipThreshold.magnitude }.count
        let clippingPercent = Double(clippedSamples) / Double(samples.count) * 100.0

        // Zero crossing rate (for voice presence)
        var zeroCrossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0) != (samples[i-1] >= 0) {
                zeroCrossings += 1
            }
        }
        let zcr = sampleRate > 0
            ? Double(zeroCrossings) / (Double(samples.count) / Double(sampleRate))
            : 0

        return QualityMetrics(
            rmsLoudness: rmsDb,
            // A full-scale negative sample has magnitude 32768, which Int16
            // cannot hold; report it as the nearest representable peak.
            peakLevel: Int16(min(peakMagnitude, UInt16(Int16.max))),
            dynamicRange: dynamicRange,
            lufs: lufs,
            snrEstimate: snr,
            clippingPercent: clippingPercent,
            zeroCrossingRate: zcr
        )
    }

    /// Rates overall audio quality (1-5 stars).
    public func rateQuality(_ metrics: QualityMetrics) -> Double {
        var score = 5.0

        // Penalize bad loudness
        if metrics.lufs < -30 || metrics.lufs > -6 {
            score -= 0.5
        }

        // Penalize clipping
        if metrics.clippingPercent > 0.1 {
            score -= 0.5
        }

        // Penalize low SNR
        if metrics.snrEstimate < 20 {
            score -= 0.5
        }

        // Penalize low dynamic range
        if metrics.dynamicRange < 6 {
            score -= 0.5
        }

        return max(1.0, min(5.0, score))
    }

    /// Generates a quality report.
    public func generateReport(_ samples: [Int16], sampleRate: Int) -> QualityReport {
        let metrics = analyzeQuality(samples, sampleRate: sampleRate)
        let rating = rateQuality(metrics)

        let issues = identifyIssues(metrics)

        return QualityReport(
            metrics: metrics,
            rating: rating,
            issues: issues,
            recommendations: recommendImprovements(metrics, issues: issues)
        )
    }

    /// Identifies quality issues.
    private func identifyIssues(_ metrics: QualityMetrics) -> [String] {
        var issues: [String] = []

        if metrics.clippingPercent > 0.1 {
            issues.append("Audio is clipping (\(String(format: "%.2f", metrics.clippingPercent))% clipped)")
        }

        if metrics.lufs < -30 {
            issues.append("Audio is too quiet (\(String(format: "%.1f", metrics.lufs)) LUFS)")
        } else if metrics.lufs > -6 {
            issues.append("Audio might be too loud (\(String(format: "%.1f", metrics.lufs)) LUFS)")
        }

        if metrics.snrEstimate < 20 {
            issues.append("Low signal-to-noise ratio")
        }

        if metrics.dynamicRange < 6 {
            issues.append("Limited dynamic range")
        }

        return issues
    }

    /// Recommends improvements.
    private func recommendImprovements(_ metrics: QualityMetrics, issues: [String]) -> [String] {
        var recommendations: [String] = []

        if metrics.clippingPercent > 0.1 {
            recommendations.append("Reduce input level or use soft clipping")
        }

        if metrics.lufs < -30 {
            recommendations.append("Increase volume or apply normalization")
        } else if metrics.lufs > -6 {
            recommendations.append("Apply compression to reduce peaks")
        }

        if metrics.snrEstimate < 20 {
            recommendations.append("Apply noise reduction or high-pass filter")
        }

        if issues.isEmpty {
            recommendations.append("Audio quality looks good!")
        }

        return recommendations
    }
}

/// Complete quality report.
public struct QualityReport: Sendable, Equatable, Codable {
    public let metrics: VoiceQualityAnalyzer.QualityMetrics
    public let rating: Double
    public let issues: [String]
    public let recommendations: [String]

    public init(
        metrics: VoiceQualityAnalyzer.QualityMetrics,
        rating: Double,
        issues: [String],
        recommendations: [String]
    ) {
        self.metrics = metrics
        self.rating = rating.isFinite ? min(5, max(1, rating)) : 1
        self.issues = issues
        self.recommendations = recommendations
    }

    public var hasIssues: Bool { !issues.isEmpty }
    public var issueCount: Int { issues.count }
    public var isRecommendedForUse: Bool { rating >= 4 && issues.isEmpty }

    public var ratingStars: String {
        let safeRating = rating.isFinite ? min(5, max(1, rating)) : 1
        let fullStars = Int(safeRating)
        let hasHalf = fullStars < 5 && safeRating.truncatingRemainder(dividingBy: 1) >= 0.5
        let empty = 5 - fullStars - (hasHalf ? 1 : 0)

        let full = String(repeating: "⭐", count: fullStars)
        let half = hasHalf ? "✨" : ""
        let emptyStars = String(repeating: "☆", count: empty)

        return full + half + emptyStars
    }

    public var summary: String {
        """
        Audio Quality Report
        \(ratingStars) \(String(format: "%.1f", rating))/5.0

        Metrics:
        • Loudness: \(String(format: "%.1f", metrics.lufs)) LUFS
        • Peak: \(metrics.peakLevel == 0 ? "−∞" : String(format: "%.1f", metrics.peakDBFS)) dBFS
        • Dynamic Range: \(String(format: "%.1f", metrics.dynamicRange)) dB
        • SNR: \(String(format: "%.1f", metrics.snrEstimate)) dB
        • Clipping: \(String(format: "%.2f", metrics.clippingPercent))%

        \(issues.isEmpty ? "No issues detected." : "Issues:\n" + issues.map { "⚠ " + $0 }.joined(separator: "\n"))

        \(recommendations.map { "✓ " + $0 }.joined(separator: "\n"))
        """
    }
}
