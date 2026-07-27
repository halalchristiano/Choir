# Voice Blending & Interpolation Guide

Create smooth transitions between CHOIR's 32 voices for character development, age progression, gender shifting, and dynamic voice effects.

## Understanding Voice Blending

Voice blending **interpolates** between two voice profiles by smoothly transitioning their acoustic parameters.

```swift
let blender = VoiceBlender()

// Blend from male narrator to female narrator (0.0 = male, 1.0 = female)
for blend in stride(from: 0.0, through: 1.0, by: 0.1) {
    let audio = try await engine.synthesize(
        text: "Hear my voice change...",
        voice: .narratorMasculine,
        voiceBlend: blend,
        targetVoice: .narratorFeminine
    )
    audioPlayer.enqueue(audio)
}
```

## Basic Blending Patterns

### Gender Transition

```swift
// Gradually shift from masculine to feminine voice
func genderTransition(text: String, steps: Int = 10) async throws {
    for i in 0...steps {
        let blend = Double(i) / Double(steps)  // 0.0 → 1.0
        
        let audio = try await engine.synthesize(
            text: text,
            voice: .narratorMasculine,
            voiceBlend: blend,
            targetVoice: .narratorFeminine
        )
        
        audioPlayer.enqueue(audio)
        print("Step \(i): \(String(format: "%.0f%%", blend * 100)) feminine")
    }
}

// Usage
try await genderTransition(text: "I am changing...")
```

### Age Progression

Create aging effect by blending across age bands:

```swift
// Child → Teenager → Young Adult → Middle-Aged → Elderly
let ageProgression = [
    .childFeminine,
    .teenageFeminine,
    .youngAdultFeminine,
    .middleAgedFeminine,
    .elderlyFeminine
]

func ageProgression(text: String) async throws {
    for i in 0..<(ageProgression.count - 1) {
        let current = ageProgression[i]
        let next = ageProgression[i + 1]
        
        // Blend within age transition (3 steps each)
        for step in 0...3 {
            let blend = Double(step) / 3.0
            
            let audio = try await engine.synthesize(
                text: text,
                voice: current,
                voiceBlend: blend,
                targetVoice: next
            )
            
            audioPlayer.enqueue(audio)
        }
    }
}
```

### Character Voice Morphing

Smooth transitions for game/animation characters:

```swift
// Transform narration between character voices
func characterTransition(text: String, from: Voice, to: Voice) async throws {
    let steps = 20  // Smooth 20-step transition
    
    for i in 0...steps {
        let blend = Double(i) / Double(steps)
        
        let audio = try await engine.synthesize(
            text: text,
            voice: from,
            voiceBlend: blend,
            targetVoice: to
        )
        
        // Add slight effects during transition
        let chain = AudioEffectChain()
            .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6.0)))
        
        let processed = chain.process(audio.audioBuffer.samples)
        audioPlayer.enqueue(processed)
    }
}

// Usage
try await characterTransition(
    text: "Transforming...",
    from: .characterGrufMasculine,
    to: .characterWitchyFeminine
)
```

## Advanced Blending Techniques

### Multi-Dimensional Blending

Blend across multiple voices simultaneously:

```swift
// Create "voice triangle": blend between 3 voices
func triVoiceBlend(
    text: String,
    voice1: Voice,
    voice2: Voice,
    voice3: Voice,
    samples: Int = 50
) async throws {
    // Iterate through 2D interpolation space
    for i in 0..<samples {
        for j in 0..<(samples - i) {
            let w1 = Double(i) / Double(samples)
            let w2 = Double(j) / Double(samples)
            let w3 = 1.0 - w1 - w2
            
            // Blend voice1 + voice2 (w1)
            let blended12 = try await engine.synthesize(
                text: text,
                voice: voice1,
                voiceBlend: w1,
                targetVoice: voice2
            )
            
            // Then blend with voice3 (w3)
            // Note: Requires sequential blending; full tri-blend 
            // coming in future versions
            audioPlayer.enqueue(blended12.audioBuffer.samples)
        }
    }
}
```

### Parametric Voice Control

Blend + adjust parameters for fine-grained control:

```swift
// Transition AND change pitch/speed simultaneously
func dynamicTransition(
    text: String,
    from: Voice,
    to: Voice,
    steps: Int = 20
) async throws {
    for i in 0...steps {
        let blend = Double(i) / Double(steps)
        
        // Pitch increases as voice changes
        let pitchShift = -12.0 + (blend * 24.0)  // -12 to +12
        
        // Rate decreases (slower as we shift)
        let rate = 1.5 - (blend * 0.5)  // 1.5 → 1.0
        
        let audio = try await engine.synthesize(
            text: text,
            voice: from,
            voiceBlend: blend,
            targetVoice: to,
            parameters: SynthesisParameters(
                pitchShift: pitchShift,
                rate: rate
            )
        )
        
        audioPlayer.enqueue(audio)
    }
}
```

### Emotional Intensity Blending

Combine voice blending with emotion parameters:

```swift
// Voice transforms while emotional intensity increases
func emotionalArcBlend(
    text: String,
    fromVoice: Voice,
    toVoice: Voice,
    fromEmotion: Double,
    toEmotion: Double
) async throws {
    let steps = 30
    
    for i in 0...steps {
        let progress = Double(i) / Double(steps)
        
        // Blend voices
        let voiceBlend = progress
        
        // Ramp emotion
        let emotion = fromEmotion + (toEmotion - fromEmotion) * progress
        
        let audio = try await engine.synthesize(
            text: text,
            voice: fromVoice,
            voiceBlend: voiceBlend,
            targetVoice: toVoice,
            parameters: SynthesisParameters(
                emotionalIntensity: emotion
            )
        )
        
        audioPlayer.enqueue(audio)
    }
}

// Example: Calm to angry transformation
try await emotionalArcBlend(
    text: "You won't believe what happened...",
    fromVoice: .narratorFeminine,
    toVoice: .villainFeminine1,
    fromEmotion: 0.2,  // Calm
    toEmotion: 0.9     // Angry
)
```

## Real-Time Streaming Blends

Blend while streaming for responsive UX:

```swift
// Stream with live voice blending
func streamingVoiceBlend(
    text: String,
    from: Voice,
    to: Voice
) async throws {
    let startTime = Date()
    let totalDuration: TimeInterval = 2.0  // 2-second blend
    
    try await engine.streamSynthesis(
        text: text,
        voice: from,
        onChunk: { chunk in
            // Calculate current blend based on elapsed time
            let elapsed = Date().timeIntervalSince(startTime)
            let blend = min(1.0, elapsed / totalDuration)
            
            // In production, would apply blend to chunk
            // For now, chunks are pre-blended during synthesis
            audioPlayer.enqueue(chunk.samples)
        }
    )
}
```

## Perceptual Quality

### Smooth Blends

Best voice pairs for natural-sounding blends:

**High Quality (imperceptible transitions):**
- narratorMasculine ↔ narratorFeminine
- youngAdult* ↔ middleAged* (same gender)
- child* → teenager* → youngAdult* (age progression)
- villain* pairs (designed for character work)

**Medium Quality (some artifacts):**
- youngAdult* ↔ elderly* (large age gap)
- Character voices to standard voices
- Neutral voices to gendered voices

**Lower Quality (noticeable artifacts):**
- Very disparate voices (e.g., child to elderly directly)
- Robot voice to human voices
- Witchy to gruff

### Quality Tips

1. **Gradual transitions**: More steps = smoother = higher CPU
   - 5 steps: Noticeably stepped
   - 10-20 steps: Smooth transitions (recommended)
   - 50+ steps: Very smooth, high CPU cost

2. **Duration matters**: Slower blends sound more natural
   ```swift
   // Slow, smooth transition (recommended)
   for i in 0...20 {  // 20 steps over ~2 seconds
       let blend = Double(i) / 20.0
       // ...
   }
   
   // Fast transition (noticeable, acceptable for effects)
   for i in 0...5 {   // 5 steps over ~500ms
       let blend = Double(i) / 5.0
       // ...
   }
   ```

3. **Match parameters**: Align pitch/rate to destination voice
   ```swift
   // Natural blend: adjust pitch as voice changes
   let pitchShift = -12.0 + (blend * 12.0)  // Gradually raise
   
   // Less natural: static pitch during voice change
   let pitchShift = 0.0  // Clashes with voice timbre
   ```

## Performance Considerations

### CPU Cost

- **Blending itself**: Negligible (just parameter interpolation)
- **Synthesis**: Full cost per step (e.g., 20 steps = 20× synthesis cost)
- **Memory**: Linear with step count

### Optimization Strategies

```swift
// Strategy 1: Fewer steps for quick feedback
func fastBlend(text: String, from: Voice, to: Voice) async throws {
    for i in 0...5 {  // Only 5 steps (50ms each)
        let blend = Double(i) / 5.0
        let audio = try await engine.synthesize(text: text, voice: from, voiceBlend: blend, targetVoice: to)
        audioPlayer.enqueue(audio)
    }
}

// Strategy 2: More steps for high-quality cutscenes
func cinematicBlend(text: String, from: Voice, to: Voice) async throws {
    for i in 0...50 {  // 50 steps (smooth)
        let blend = Double(i) / 50.0
        let audio = try await engine.synthesize(text: text, voice: from, voiceBlend: blend, targetVoice: to)
        audioPlayer.enqueue(audio)
    }
}

// Strategy 3: Cache results for repeated blends
var blendCache: [String: [AudioBuffer]] = [:]

func cachedBlend(text: String, from: Voice, to: Voice) async throws {
    let cacheKey = "\(text)_\(from)_\(to)"
    
    if let cached = blendCache[cacheKey] {
        for audio in cached {
            audioPlayer.enqueue(audio)
        }
        return
    }
    
    var results: [AudioBuffer] = []
    for i in 0...20 {
        let blend = Double(i) / 20.0
        let audio = try await engine.synthesize(text: text, voice: from, voiceBlend: blend, targetVoice: to)
        results.append(audio.audioBuffer)
        audioPlayer.enqueue(audio)
    }
    
    blendCache[cacheKey] = results
}
```

## Use Cases

### Games & Interactive Media
- Character voice transformations (human → werewolf)
- Emotional state changes (calm → angry)
- Age progression (young NPC ages over game time)
- Dialogue variants for character customization

### Audiobooks & Narration
- Character distinction (narrator blends to each character)
- Emotional arcs (narrator mood evolves)
- Gender-neutral narration options (smooth transition)

### Accessibility
- Voice adjustability for users with hearing differences
- Age/gender inclusive options
- Familiar voice variants

### Creative Applications
- AI character synthesis with custom voice personalities
- Voice dubbing with smooth character transitions
- Real-time voice filters and effects

## Troubleshooting

### "Blended audio sounds robotic"
- **Cause**: Voice pair mismatch or insufficient steps
- **Fix**: Use 15+ steps, choose voices from same age band/gender
- ```swift
  for i in 0...15 {  // Increased from 5
      let blend = Double(i) / 15.0
      // ...
  }
  ```

### "Pitch jumps during transition"
- **Cause**: Not adjusting pitch to match target voice
- **Fix**: Ramp pitch alongside voice blend
- ```swift
  let pitchShift = -6.0 + (blend * 6.0)  // Align with voice
  ```

### "Blending takes too long"
- **Cause**: Too many steps or slow synthesis
- **Fix**: Reduce steps, use streaming for long texts
- ```swift
  for i in 0...10 {  // Reduced from 50
      let blend = Double(i) / 10.0
      // ...
  }
  ```

### "Audio levels change during blend"
- **Cause**: Different voice profiles have different loudness
- **Fix**: Apply normalization to each chunk
- ```swift
  let chain = AudioEffectChain()
      .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6.0)))
  let normalized = chain.process(audio.audioBuffer.samples)
  ```

## Examples Library

Complete working examples:

1. **Simple gender transition** (10 lines)
2. **Age progression** (20 lines)
3. **Character transformation** (15 lines)
4. **Real-time emotional arc** (25 lines)
5. **Streaming blend** (20 lines)

See [ChoirDemo.swift](./Sources/Choir/Demo/ChoirDemo.swift) for runnable examples.

## API Reference

```swift
// Voice blending parameters in SynthesisParameters
public struct SynthesisParameters {
    public var voiceBlend: Double = 0.0  // 0.0 = fromVoice, 1.0 = toVoice
    public var blendCurve: BlendCurve = .linear  // .linear, .easeIn, .easeOut, .easeInOut
}

// StreamSynthesis with blending
try await engine.streamSynthesis(
    text: String,
    voice: Voice,                    // Starting voice
    voiceBlend: Double,              // 0.0 → 1.0
    targetVoice: Voice,              // Destination voice
    parameters: SynthesisParameters,
    onChunk: (AudioChunk) -> Void
)
```

---

See also: [Getting Started](./GETTING_STARTED.md), [Streaming Guide](./STREAMING.md), [Platforms](./PLATFORMS.md)
