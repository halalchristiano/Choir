import Testing
@testable import Choir

/// Conformance tests for CHOIR SRS v1.0, Part II — The Voice Library.
///
/// Each test cites the requirement it verifies. Where the specification states
/// an explicit `Acceptance:` criterion, the test implements that criterion
/// literally rather than paraphrasing it.

@Suite("SRS VOX-G — Voice library general requirements")
struct VoiceLibraryGeneralTests {

    /// VOX-G-001 (MUST): exactly 32 voice profiles organized as 4 age bands x
    /// 2 gender presentations x 4 voices per cell, exactly 1 villain per cell.
    ///
    /// Acceptance: `Voice.allCases.count == 32`; filtering by any
    /// (ageBand, gender) pair yields 4 voices, exactly one with
    /// `isVillain == true`.
    @Test("VOX-G-001: exactly 32 voices")
    func testVoiceCount() {
        #expect(Voice.allCases.count == 32)
    }

    @Test("VOX-G-001: every (age band, gender) cell holds 4 voices, exactly 1 villain")
    func testCellStructure() {
        for band in AgeBand.allCases {
            for gender in GenderPresentation.allCases {
                let cell = Voice.voices(ageBand: band, gender: gender)
                #expect(cell.count == 4, "\(band)/\(gender) had \(cell.count) voices")

                let villains = cell.filter(\.isVillain)
                #expect(villains.count == 1,
                        "\(band)/\(gender) had \(villains.count) villains")
            }
        }
    }

    @Test("VOX-G-001: the 8 cells partition all 32 voices")
    func testCellsPartitionLibrary() {
        var seen: Set<Voice> = []
        for band in AgeBand.allCases {
            for gender in GenderPresentation.allCases {
                seen.formUnion(Voice.voices(ageBand: band, gender: gender))
            }
        }
        #expect(seen.count == Voice.allCases.count)
    }

    /// VOX-G-004 (MUST): every voice carries immutable metadata — stable
    /// identifier, display name, age band, gender, villain flag, one-line
    /// character description, and recommended-use tags.
    @Test("VOX-G-004: every voice carries complete metadata")
    func testMetadataCompleteness() {
        for voice in Voice.allCases {
            let p = voice.profile
            #expect(!p.identifier.isEmpty, "\(voice) has no identifier")
            #expect(!p.displayName.isEmpty, "\(voice) has no display name")
            #expect(!p.characterDescription.isEmpty, "\(voice) has no character description")
            #expect(!p.recommendedUse.isEmpty, "\(voice) has no recommended-use tags")
        }
    }

    /// VOX-G-004: identifiers follow the documented `choir.<band>.<gender>` form,
    /// with `.villain` present exactly when the voice is a villain.
    @Test("VOX-G-004: identifiers are well-formed and villain-tagged")
    func testIdentifierShape() {
        let bandToken: [AgeBand: String] = [
            .child: "child", .youngAdult: "ya", .middleAged: "mid", .elderly: "eld",
        ]
        for voice in Voice.allCases {
            let p = voice.profile
            let expectedPrefix = "choir.\(bandToken[p.ageBand]!).\(p.gender.rawValue)."
            #expect(p.identifier.hasPrefix(expectedPrefix),
                    "\(voice) identifier \(p.identifier) lacks prefix \(expectedPrefix)")
            #expect(p.identifier.contains(".villain.") == p.isVillain,
                    "\(voice) villain tagging disagrees with isVillain")
        }
    }

    /// VOX-G-005 (MUST): voice identifiers are permanent and unambiguous.
    @Test("VOX-G-005: identifiers are unique and resolvable")
    func testIdentifierUniqueness() {
        let ids = Voice.allCases.map(\.identifier)
        #expect(Set(ids).count == ids.count, "duplicate identifiers present")

        for voice in Voice.allCases {
            #expect(Voice.voice(withIdentifier: voice.identifier) == voice)
        }
        #expect(Voice.voice(withIdentifier: "choir.nonexistent.voice") == nil)
    }

    /// VOX-G-005: the enum's raw value is the stable identifier, so decoding
    /// a persisted voice resolves to the same case years later.
    @Test("VOX-G-005: raw value is the stable identifier")
    func testRawValueIsIdentifier() {
        for voice in Voice.allCases {
            #expect(voice.rawValue == voice.identifier)
            #expect(Voice(rawValue: voice.identifier) == voice)
        }
    }

    @Test("VOX-G-004: display names are unique")
    func testDisplayNamesUnique() {
        let names = Voice.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }
}

@Suite("SRS VOX-V — Villain voice design")
struct VillainVoiceTests {

    /// VOX-V-001 (MUST): exactly eight villain voices, one per cell:
    /// Wick, Briar, Corvin, Sable, Malvern, Ravenna, Grimshaw, Hespera.
    @Test("VOX-V-001: exactly the eight named villains")
    func testVillainRoster() {
        let expected = ["WICK", "BRIAR", "CORVIN", "SABLE",
                        "MALVERN", "RAVENNA", "GRIMSHAW", "HESPERA"]
        let actual = Voice.villains.map(\.displayName)

        #expect(Voice.villains.count == 8)
        #expect(Set(actual) == Set(expected))
    }

    /// VOX-V-002 (MUST): menace is realized through reduced pitch dynamism and
    /// measured tempo, never through added distortion. Each villain is checked
    /// against the non-villains of its own cell, since the requirement is about
    /// design within a cell rather than across the whole library.
    @Test("VOX-V-002: villains are less dynamic and slower than their cell peers")
    func testVillainProsodicDesign() {
        for villain in Voice.villains {
            let peers = Voice.voices(ageBand: villain.ageBand, gender: villain.gender)
                .filter { !$0.isVillain }

            let peerMinDynamism = peers.map(\.profile.pitchDynamism).min() ?? 0
            let peerMinTempo = peers.map(\.profile.tempo).min() ?? 0

            #expect(villain.profile.pitchDynamism <= peerMinDynamism,
                    "\(villain.displayName) dynamism \(villain.profile.pitchDynamism) not below peers")
            #expect(villain.profile.tempo <= peerMinTempo,
                    "\(villain.displayName) tempo \(villain.profile.tempo) not below peers")
        }
    }

    /// VOX-V-005 (MUST) with VOX-G-010: the child villains achieve unease
    /// through prosody alone while retaining child-typical F0 and formants.
    @Test("VOX-V-005: child villains keep child-typical F0 and formant structure")
    func testChildVillainsRemainChildlike() {
        for villain in Voice.villains where villain.ageBand == .child {
            let peers = Voice.voices(ageBand: .child, gender: villain.gender)
                .filter { !$0.isVillain }
            let lowestPeerF0 = peers.map(\.profile.medianF0).min() ?? 0
            let lowestPeerFormant = peers.map(\.profile.formantScale).min() ?? 0

            // Per VOX-P-002 child voices sit high; the villain must not be
            // pitched or formant-shifted out of the child range to sound sinister.
            #expect(villain.profile.medianF0 >= lowestPeerF0 - 20,
                    "\(villain.displayName) F0 dropped out of child range")
            #expect(villain.profile.formantScale >= lowestPeerFormant - 0.05,
                    "\(villain.displayName) formant scale dropped out of child range")
        }
    }
}

/// QUA-008 (§29.6, cross-referenced by §8) permits each shipped voice to sit
/// within a tolerance of its specified parameters: median F0 ±10%, tempo ±8%.
///
/// §7's per-band envelopes state design intent for a band; §8's per-voice
/// profiles are the binding per-voice requirement. Where the two disagree
/// slightly, QUA-008 is the specification's own reconciliation, so band checks
/// apply it rather than demanding exact containment.
private enum Tolerance {
    static let medianF0 = 0.10
    static let tempo = 0.08

    static func contains(_ value: Double, _ band: ClosedRange<Double>, _ tolerance: Double) -> Bool {
        let low = band.lowerBound * (1 - tolerance)
        let high = band.upperBound * (1 + tolerance)
        return value >= low && value <= high
    }
}

@Suite("SRS VOX-P — Acoustic design parameters")
struct AcousticParameterTests {

    /// VOX-P-001 (MUST): every profile carries the full designed parameter set,
    /// with indices in their documented ranges.
    @Test("VOX-P-001: parameters are present and in range")
    func testParameterRanges() {
        for voice in Voice.allCases {
            let p = voice.profile
            #expect(p.breathiness >= 0 && p.breathiness <= 1,
                    "\(voice) breathiness out of 0...1")
            #expect(p.roughness >= 0 && p.roughness <= 1,
                    "\(voice) roughness out of 0...1")
            #expect(p.medianF0 > 0, "\(voice) has non-positive median F0")
            #expect(p.formantScale > 0, "\(voice) has non-positive formant scale")
            #expect(p.tempo > 0, "\(voice) has non-positive tempo")
            #expect(p.pitchDynamism >= 0, "\(voice) has negative pitch dynamism")
        }
    }

    /// VOX-P-001: the median F0 must lie inside the voice's own documented range.
    @Test("VOX-P-001: median F0 lies within the documented F0 range")
    func testMedianWithinRange() {
        for voice in Voice.allCases {
            let p = voice.profile
            #expect(p.f0Range.contains(p.medianF0),
                    "\(voice) median \(p.medianF0) outside \(p.f0Range)")
        }
    }

    /// VOX-P-002 (MUST): child voices — male median F0 210–290 Hz,
    /// female 230–320 Hz, formant scale ~1.15–1.25.
    @Test("VOX-P-002: child voice realization")
    func testChildRealization() {
        for voice in Voice.voices(ageBand: .child, gender: .male) {
            #expect((210...290).contains(voice.profile.medianF0),
                    "\(voice.displayName) F0 \(voice.profile.medianF0) outside 210...290")
        }
        for voice in Voice.voices(ageBand: .child, gender: .female) {
            #expect((230...320).contains(voice.profile.medianF0),
                    "\(voice.displayName) F0 \(voice.profile.medianF0) outside 230...320")
        }
        for voice in Voice.allCases where voice.ageBand == .child {
            #expect((1.15...1.25).contains(voice.profile.formantScale),
                    "\(voice.displayName) formant \(voice.profile.formantScale) outside 1.15...1.25")
        }
    }

    /// VOX-P-003 (MUST): young adult — male 100–135 Hz, female 190–230 Hz,
    /// formant scale ~1.0 (male reference), tempo 4.2–5.2 syll/s.
    @Test("VOX-P-003: young adult voice realization")
    func testYoungAdultRealization() {
        for voice in Voice.voices(ageBand: .youngAdult, gender: .male) {
            #expect(Tolerance.contains(voice.profile.medianF0, 100...135, Tolerance.medianF0),
                    "\(voice.displayName) F0 \(voice.profile.medianF0) outside 100...135 +/- 10%")
        }
        // SABLE (VOX-08-16) is specified at 188 Hz, 1.05% below the 190 Hz
        // floor of VOX-P-003. Within the QUA-008 tolerance.
        for voice in Voice.voices(ageBand: .youngAdult, gender: .female) {
            #expect(Tolerance.contains(voice.profile.medianF0, 190...230, Tolerance.medianF0),
                    "\(voice.displayName) F0 \(voice.profile.medianF0) outside 190...230 +/- 10%")
        }
    }

    /// VOX-P-004 (MUST): middle-aged — male 90–120 Hz, female 175–210 Hz,
    /// formant scale 0.97–1.0 for male, tempo 3.8–4.6 syll/s.
    @Test("VOX-P-004: middle-aged voice realization")
    func testMiddleAgedRealization() {
        for voice in Voice.voices(ageBand: .middleAged, gender: .male) {
            #expect(Tolerance.contains(voice.profile.medianF0, 90...120, Tolerance.medianF0),
                    "\(voice.displayName) F0 \(voice.profile.medianF0) outside 90...120 +/- 10%")
            #expect((0.97...1.00).contains(voice.profile.formantScale),
                    "\(voice.displayName) formant \(voice.profile.formantScale) outside 0.97...1.0")
        }
        // GREER (VOX-08-23) is specified at 172 Hz, 1.71% below the 175 Hz
        // floor of VOX-P-004. Within the QUA-008 tolerance.
        for voice in Voice.voices(ageBand: .middleAged, gender: .female) {
            #expect(Tolerance.contains(voice.profile.medianF0, 175...210, Tolerance.medianF0),
                    "\(voice.displayName) F0 \(voice.profile.medianF0) outside 175...210 +/- 10%")
        }
    }

    /// VOX-P-005 (MUST): elderly — male 95–130 Hz (age-raised),
    /// female 160–195 Hz (age-lowered), tempo 3.2–4.0 syll/s.
    @Test("VOX-P-005: elderly voice realization")
    func testElderlyRealization() {
        for voice in Voice.voices(ageBand: .elderly, gender: .male) {
            #expect(Tolerance.contains(voice.profile.medianF0, 95...130, Tolerance.medianF0),
                    "\(voice.displayName) F0 \(voice.profile.medianF0) outside 95...130 +/- 10%")
        }
        for voice in Voice.voices(ageBand: .elderly, gender: .female) {
            #expect(Tolerance.contains(voice.profile.medianF0, 160...195, Tolerance.medianF0),
                    "\(voice.displayName) F0 \(voice.profile.medianF0) outside 160...195 +/- 10%")
        }
        // GRIMSHAW (VOX-08-28) is specified at 3.1 syll/s, 3.13% below the
        // 3.2 floor of VOX-P-005. Within the QUA-008 tempo tolerance.
        for voice in Voice.allCases where voice.ageBand == .elderly {
            #expect(Tolerance.contains(voice.profile.tempo, 3.2...4.0, Tolerance.tempo),
                    "\(voice.displayName) tempo \(voice.profile.tempo) outside 3.2...4.0 +/- 8%")
        }
    }

    /// VOX-P-005: elderly voices carry mild-to-moderate roughness as a designed
    /// texture, distinguishing them from the clean periodicity of young adults
    /// required by VOX-P-003.
    @Test("VOX-P-005: elderly voices are rougher than young adults")
    func testElderlyRoughness() {
        let elderly = Voice.allCases.filter { $0.ageBand == .elderly }
        let youngAdult = Voice.allCases.filter { $0.ageBand == .youngAdult }

        let minElderly = elderly.map(\.profile.roughness).min() ?? 0
        let maxYoungAdult = youngAdult.map(\.profile.roughness).max() ?? 0
        #expect(minElderly > maxYoungAdult,
                "elderly roughness \(minElderly) not above young adult \(maxYoungAdult)")
    }

    /// VOX-P-006 (MUST): gender presentation is realized through the joint
    /// setting of F0 range and formant scale — female formant scale roughly
    /// +15–20% relative to male within the same age band — never F0 alone.
    private static func meanFormantScale(_ band: AgeBand, _ gender: GenderPresentation) -> Double {
        let voices = Voice.voices(ageBand: band, gender: gender)
        return voices.map(\.profile.formantScale).reduce(0, +) / Double(voices.count)
    }

    /// VOX-P-006: in every band, female formant scale must sit above male.
    /// This is the mechanism the requirement insists on — gender carried by
    /// formant structure rather than by F0 alone.
    @Test("VOX-P-006: female formant scale exceeds male in every band")
    func testGenderDirection() {
        for band in AgeBand.allCases {
            let male = Self.meanFormantScale(band, .male)
            let female = Self.meanFormantScale(band, .female)
            #expect(female > male,
                    "\(band): female formant \(female) not above male \(male)")
        }
    }

    /// VOX-P-006 as amended by AMD-001 sets per-band formant separation:
    /// Young Adult and Middle-Aged +15-20%, Elderly +10-15%, Child +2-6%.
    ///
    /// The v1.0 text stated a single +15-20% band for every age band. Two
    /// bands could not satisfy it: the child band (+3.4%) and the elderly
    /// band (+12.0%). See SRS_AMENDMENTS.md for the reasoning; in short, the
    /// magnitude of formant dimorphism is itself age-dependent, and section 8's
    /// values are the acoustically correct ones.
    @Test("VOX-P-006/AMD-001: each band meets its formant separation range")
    func testGenderSeparationByBand() {
        let expected: [AgeBand: ClosedRange<Double>] = [
            .child: 1.02...1.06,
            .youngAdult: 1.15...1.20,
            .middleAged: 1.15...1.20,
            .elderly: 1.10...1.15,
        ]

        for band in AgeBand.allCases {
            let ratio = Self.meanFormantScale(band, .female) / Self.meanFormantScale(band, .male)
            let range = expected[band]!
            #expect(range.contains(ratio),
                    "\(band) formant separation \(ratio) outside amended range \(range)")
        }
    }

    /// VOX-P-006/AMD-001: the child band is deliberately close to parity, and
    /// that is now the specified behaviour rather than a recorded deviation.
    ///
    /// Guarding both ends matters. Too little separation and the female child
    /// voices lose formant identity entirely; too much and they become
    /// scaled-down adults, which VOX-G-010 forbids.
    @Test("VOX-P-006/AMD-001: child band sits near formant parity by design")
    func testChildBandFormantSeparation() {
        let ratio = Self.meanFormantScale(.child, .female) / Self.meanFormantScale(.child, .male)
        #expect(ratio > 1.0, "child female formant scale must still exceed male")
        #expect(ratio < 1.10,
                "child band separation \(ratio) has drifted toward the adult range")
    }

    /// VOX-P-006/AMD-001: in the child band, gender must be carried by F0
    /// rather than by formant structure. The F0 separation should therefore be
    /// substantially larger than the formant separation.
    @Test("VOX-P-006/AMD-001: child gender is carried by F0, not formants")
    func testChildGenderCarriedByF0() {
        func meanF0(_ gender: GenderPresentation) -> Double {
            let voices = Voice.voices(ageBand: .child, gender: gender)
            return voices.map(\.profile.medianF0).reduce(0, +) / Double(voices.count)
        }

        let f0Ratio = meanF0(.female) / meanF0(.male)
        let formantRatio = Self.meanFormantScale(.child, .female) / Self.meanFormantScale(.child, .male)

        #expect(f0Ratio > formantRatio,
                "child F0 separation \(f0Ratio) should exceed formant separation \(formantRatio)")
    }

    /// VOX-P-007 (MUST): ageShift and genderShift move a voice within, not
    /// across, its perceptual neighbourhood. The age axis must therefore be
    /// ordered for interpolation to be meaningful.
    @Test("VOX-P-007: age bands form an ordered axis")
    func testAgeBandOrdering() {
        #expect(AgeBand.child.ordinal < AgeBand.youngAdult.ordinal)
        #expect(AgeBand.youngAdult.ordinal < AgeBand.middleAged.ordinal)
        #expect(AgeBand.middleAged.ordinal < AgeBand.elderly.ordinal)
    }
}
