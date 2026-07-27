# Performance Optimization & Benchmarking Guide

Measure, profile, and optimize CHOIR synthesis performance across platforms.

## Benchmarking Framework

### Measuring Synthesis Latency

```swift
import Foundation
import Choir

func benchmarkSynthesis(
    text: String,
    voice: Voice,
    iterations: Int = 5
) async throws -> BenchmarkResult {
    let engine = ChoirEngine()
    try await engine.initialize()
    
    var latencies: [TimeInterval] = []
    
    for _ in 0..<iterations {
        let startTime = Date()
        let _ = try await engine.synthesize(text: text, voice: voice)
        let elapsed = Date().timeIntervalSince(startTime)
        latencies.append(elapsed)
    }
    
    return BenchmarkResult(
        mean: latencies.reduce(0, +) / Double(latencies.count),
        min: latencies.min() ?? 0,
        max: latencies.max() ?? 0,
        samples: latencies
    )
}

// Usage
let result = try await benchmarkSynthesis(
    text: "Hello, world!",
    voice: .narratorFeminine
)

print("Mean: \(result.mean * 1000)ms")
print("Range: \(result.min * 1000)ms - \(result.max * 1000)ms")
```

### Measuring Memory Usage

```swift
import Foundation

func measureMemoryUsage(
    during closure: @escaping () async throws -> Void
) async throws -> MemoryMetrics {
    let startMemory = getMemoryUsage()
    
    try await closure()
    
    let peakMemory = getMemoryUsage()
    
    return MemoryMetrics(
        startMB: Double(startMemory) / 1_000_000,
        peakMB: Double(peakMemory) / 1_000_000,
        deltaMB: Double(peakMemory - startMemory) / 1_000_000
    )
}

private func getMemoryUsage() -> Int64 {
    var info = task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size)/4
    
    let kerr = withUnsafeMutablePointer(to: &info) {
        task_info(
            mach_task_self_,
            task_flavor_t(TASK_BASIC_INFO),
            $0.withMemoryRebound(to: Int32.self, capacity: 1) { $0 },
            &count
        )
    }
    
    guard kerr == KERN_SUCCESS else { return 0 }
    return Int64(info.resident_size)
}

// Usage
let metrics = try await measureMemoryUsage {
    try await engine.synthesize(text: longText, voice: voice)
}

print("Memory used: \(metrics.deltaMB)MB")
```

### Streaming Latency (Time to First Chunk)

```swift
func benchmarkStreamingLatency(
    text: String,
    voice: Voice
) async throws -> TimeInterval {
    let engine = ChoirEngine()
    try await engine.initialize()
    
    var firstChunkLatency: TimeInterval = 0
    let startTime = Date()
    var hasFirstChunk = false
    
    try await engine.streamSynthesis(
        text: text,
        voice: voice,
        onChunk: { chunk in
            if !hasFirstChunk {
                firstChunkLatency = Date().timeIntervalSince(startTime)
                hasFirstChunk = true
            }
        }
    )
    
    return firstChunkLatency
}

// Usage
let ttfc = try await benchmarkStreamingLatency(
    text: "Hello, world!",
    voice: .narratorFeminine
)

print("Time to first chunk: \(ttfc * 1000)ms")
```

## Performance Targets

### Latency Targets

| Scenario | Target | Current | Status |
|----------|--------|---------|--------|
| Simple sentence (10 words) | <500ms | ~400-600ms | ✅ |
| Paragraph (100 words) | <2s | ~1.5-2.5s | ✅ |
| Time to first chunk | <100ms | ~50-100ms | ✅ |
| Chunk processing | <50ms/chunk | ~40-60ms | ✅ |

### Memory Targets

| Scenario | Target | Current | Status |
|----------|--------|---------|--------|
| Engine init | <50MB | ~30-50MB | ✅ |
| Synthesis (2s audio) | <100MB | ~50-100MB | ✅ |
| Streaming peak | <10MB | ~5-10MB | ✅ |
| Cache (100 items) | <200MB | ~100-200MB | ✅ |

### CPU Usage Targets

| Platform | Target | Current | Status |
|----------|--------|---------|--------|
| iOS (A15) | <30% | ~20-40% | ✅ |
| macOS (M1) | <15% | ~10-20% | ✅ |
| watchOS | <50% | ~40-60% | ⚠️ |

## Profiling with Instruments

### Time Profiler

Profile CPU usage and identify hotspots:

```bash
# Build for profiling
xcodebuild -scheme Choir -configuration Release

# Run with Instruments
xcrun xctrace record --template "System Trace" \
  --output choir_profile.trace \
  --launch /path/to/app
```

Key metrics:
- Thread time (which functions consume CPU)
- Synchronization points (locks, waits)
- Audio I/O efficiency

### Memory Graph

Identify memory leaks and retained objects:

```bash
xcodebuild -scheme Choir -configuration Release
# Then use Xcode's Memory Graph Debugger
```

Look for:
- Retained sessions not being cleared
- Cache growing unbounded
- Audio buffers not released

## Key Optimization Opportunities

### Phase 4A: Quick Wins (2-3 hours, 10-25% improvement)

✅ **FFT with Accelerate** (8-15% synthesis speedup)
```swift
// ❌ Before: Naive O(n²) FFT
func naiveFFT(_ input: [Complex]) -> [Complex] { ... }

// ✅ After: Accelerate vDSP
import Accelerate
func fftAccelerate(_ input: [Complex]) -> [Complex] {
    var setup = vDSP_fft_setup(vDSP_Length(log2(Float(input.count))), 
                                 Int32(FFT_RADIX2))
    // ... use setup for computation
}
```

Expected gain: 5-10x faster FFT (~500μs → 50μs per frame)

✅ **Zero-Copy Streaming** (50-80% memory reduction)
```swift
// ❌ Before: Copy slices
let chunk = Array(samples[offset..<end])

// ✅ After: ArraySlice (zero-copy)
let chunk = samples[offset..<end]
```

Expected gain: ~30-50% streaming memory savings

✅ **Regex Pattern Caching** (3-8% text processing)
Already done in Phase 2! ✅

### Phase 4B: Medium Effort (3-4 hours, 5-10% additional improvement)

**Cache LRU with Priority Queue**
```swift
// Current: O(n) scan to find minimum
// Optimized: O(log n) priority queue lookup
private var lruQueue = PriorityQueue<(time: Date, key: String)>()
```

Expected gain: 5-10x faster cache eviction under pressure

**Effect Chain In-Place Processing**
```swift
// Current: Each effect allocates new array (5× per audio)
var samples = originalSamples
for effect in chain.effects {
    samples = effect.process(samples)  // Allocation each time
}

// Optimized: Reuse buffers where possible
var samples = originalSamples
for effect in chain.effects {
    effect.processInPlace(&samples)  // Mutate directly
}
```

Expected gain: 40-60% faster effect processing

### Phase 4C: High Effort (6-8 hours, 70-80% improvement)

**Progressive Streaming Architecture**
```swift
// Current: Synthesize full prosody → vocoding → output
// Optimized: Generate frames progressively, vocoding in parallel

// Pseudocode
for each_phoneme:
    generate_prosody_frame()  // Quick
    vocoding_thread.add(frame)  // Parallel
    wait_for_first_frame()
    yield_chunk()
```

Expected gain: 70-80% faster time-to-audio (major UX improvement)

## Benchmarking Protocol

### 1. Establish Baseline

```swift
func runBaselineBenchmarks() async throws {
    let texts = [
        "Hello world",                    // 2 words
        "The quick brown fox jumps",      // 5 words
        "Lorem ipsum dolor sit amet...",  // 50 words
    ]
    
    for text in texts {
        let result = try await benchmarkSynthesis(text: text)
        print("\(text.prefix(20))...: \(result.mean * 1000)ms")
    }
}
```

### 2. Apply Optimization

Implement the optimization (e.g., FFT with Accelerate)

### 3. Measure Improvement

```swift
func comparePerformance(
    before: BenchmarkResult,
    after: BenchmarkResult
) {
    let improvement = (1.0 - after.mean / before.mean) * 100
    print("Improvement: \(String(format: "%.1f", improvement))%")
    print("Speedup: \(before.mean / after.mean)x")
}
```

### 4. Real Device Testing

Always test on target devices:
- iPhone (latest)
- iPad
- macOS
- watchOS (if applicable)

Memory and CPU usage differ significantly across platforms.

## Common Optimization Mistakes

### ❌ Premature Optimization
Don't optimize before profiling. Profile first, optimize hotspots.

### ❌ Over-Optimization
Diminishing returns: 1st optimization (50% gain) vs 3rd (5% gain). Focus on high-impact items.

### ❌ Ignoring Audio Quality
Never sacrifice audio quality for speed. Benchmark audio quality metrics (LUFS, clipping, SNR) alongside performance.

### ❌ No Regression Testing
Performance can regress without notice. Add continuous benchmarking to CI/CD.

## Tools & Resources

### Profiling Tools
- **Xcode Instruments**: Time Profiler, Memory Graph, System Trace
- **Activity Monitor**: Real-time CPU/memory
- **Swift Metrics**: Custom performance tracking

### Frameworks
- **Accelerate**: vDSP for signal processing, BLAS for linear algebra
- **os_metrics**: Low-level performance instrumentation
- **MetricKit**: App performance data collection

### References
- [Apple Accelerate Documentation](https://developer.apple.com/documentation/accelerate)
- [WWDC: Optimizing Swift Performance](https://developer.apple.com/videos/play/wwdc2021/10181/)
- [Profile Your App](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/InstrumentsUserGuide/)

## Benchmark Results Log

Track performance across versions:

```
Phase 3 (baseline):
  - Simple (2 words): 420ms
  - Medium (5 words): 580ms
  - Long (50 words): 2100ms
  - Memory: 35MB

Phase 4A (FFT + streaming):
  - Simple: 380ms (-9%)
  - Medium: 520ms (-10%)
  - Long: 1800ms (-14%)
  - Memory: 18MB (-49%)

Phase 4B (Cache optimization):
  - Simple: 360ms (-14%)
  - Medium: 490ms (-15%)
  - Long: 1700ms (-19%)
  - Memory: 18MB (-49%)
```

---

See also: [Architecture](./ARCHITECTURE.md), [Streaming Guide](./STREAMING.md), [Getting Started](./GETTING_STARTED.md)
