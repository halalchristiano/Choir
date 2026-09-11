import Foundation
import Testing
@testable import Choir

@Suite("Natural-language speech planning")
struct NaturalLanguageProcessingTests {
    private let planner = ContextualSpeechPlanner()

    @Test("Classifies questions and their emotional context")
    func questionAndEmotion() throws {
        let plan = planner.plan(normalizedWords: ["why", "are", "you", "afraid?"])
        let utterance = try #require(plan.utterances.first)

        #expect(utterance.intent == .question)
        #expect(utterance.emotion == .fearful)
        #expect(utterance.confidence > 0.5)
        #expect(plan.inferredBoundaries[3] == .major)
    }

    @Test("Finds contrastive focus instead of stressing every word")
    func contrastiveFocus() throws {
        let plan = planner.plan(normalizedWords: [
            "i", "did", "not", "say", "he", "stole", "the", "money.",
        ])

        #expect(plan.cue(forWord: 2)?.emphasis == .moderate)
        #expect(plan.cue(forWord: 3)?.emphasis == .strong)
        #expect(plan.cue(forWord: 7)?.emphasis == .moderate)
        #expect(plan.cue(forWord: 5) == nil)
    }

    @Test("Separates quoted dialogue from its attribution")
    func dialogueDetection() throws {
        let plan = planner.plan(normalizedWords: [
            "\"stay", "here!\"", "she", "said.",
        ])

        #expect(plan.utterances.count == 2)
        #expect(plan.utterances[0].isDialogue)
        #expect(!plan.utterances[1].isDialogue)
        #expect(plan.cue(forWord: 0)?.isDialogue == true)
        #expect(plan.cue(forWord: 1)?.isDialogue == true)
        #expect(plan.cue(forWord: 2)?.isDialogue != true)
    }

    @Test("Infers clause boundaries from punctuation and discourse")
    func clauseBoundaries() {
        let plan = planner.plan(normalizedWords: [
            "we", "waited,", "but", "the", "door", "never", "opened.",
        ])

        #expect(plan.inferredBoundaries[1] == .minor)
        #expect(plan.inferredBoundaries[6] == .major)
    }

    @Test("Linguistic front end publishes a contextual speech plan")
    func frontendIntegration() throws {
        let transcript = try LinguisticFrontend().process(
            "I did not say he stole the money.")
        let plan = try #require(transcript.speechPlan)
        let sayIndex = try #require(transcript.wordTexts.firstIndex(of: "say"))

        #expect(plan.cue(forWord: sayIndex)?.emphasis == .strong)
        let start = transcript.wordBoundaries[sayIndex]
        let end = sayIndex + 1 < transcript.wordBoundaries.count
            ? transcript.wordBoundaries[sayIndex + 1]
            : transcript.phonemes.count
        #expect(transcript.phonemes[start..<end].contains {
            $0.isVowel && $0.stress == 2
        })
    }

    @Test("NLP can be disabled for literal delivery")
    func disabledConfiguration() throws {
        let frontend = LinguisticFrontend(
            speechPlanner: ContextualSpeechPlanner(configuration: .disabled))
        let transcript = try frontend.process("Why are you afraid?")

        #expect(transcript.speechPlan == nil)
    }

    @Test("Question intent produces a rising terminal contour and H boundary")
    func questionProsody() throws {
        let frontend = LinguisticFrontend()
        let predictor = ProsodyPredictor(basePitch: 120, pitchRange: (60, 300))
        let question = try frontend.process("You are coming?")
        let statement = try frontend.process("You are coming.")
        let parameters = SynthesisParameters(emotionalIntensity: 0, seed: 4)

        let questionProsody = predictor.predictProsody(
            for: question, with: parameters)
        let statementProsody = predictor.predictProsody(
            for: statement, with: parameters)

        #expect(
            (questionProsody.pitchContour.points.last?.value ?? 0)
                > (statementProsody.pitchContour.points.last?.value ?? 0))
        #expect(questionProsody.phonemes.last?.prosody.boundaryTone == "H%")
        #expect(statementProsody.phonemes.last?.prosody.boundaryTone == "L%")
    }

    @Test("Contextual emotion changes pacing and energy")
    func emotionProsody() {
        let phonemes = [Phoneme("æ", stress: 1)]
        let neutralPlan = ContextualSpeechPlan(utterances: [
            PlannedUtterance(
                startWordIndex: 0, endWordIndex: 0,
                intent: .statement, emotion: .neutral),
        ])
        let sadPlan = ContextualSpeechPlan(utterances: [
            PlannedUtterance(
                startWordIndex: 0, endWordIndex: 0,
                intent: .statement, emotion: .sad),
        ])
        let neutral = PhoneticTranscription(
            phonemes: phonemes,
            originalText: "loss",
            wordBoundaries: [0],
            wordTexts: ["loss"],
            speechPlan: neutralPlan)
        let sad = PhoneticTranscription(
            phonemes: phonemes,
            originalText: "loss",
            wordBoundaries: [0],
            wordTexts: ["loss"],
            speechPlan: sadPlan)
        let predictor = ProsodyPredictor(basePitch: 120, pitchRange: (60, 300))
        let parameters = SynthesisParameters(emotionalIntensity: 0, seed: 9)
        let neutralProsody = predictor.predictProsody(for: neutral, with: parameters)
        let sadProsody = predictor.predictProsody(for: sad, with: parameters)

        #expect(sadProsody.durations[0] > neutralProsody.durations[0])
        #expect(
            (sadProsody.energyContour.points.first?.value ?? 0)
                < (neutralProsody.energyContour.points.first?.value ?? 0))
    }
}
