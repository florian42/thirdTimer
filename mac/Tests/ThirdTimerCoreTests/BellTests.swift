import Foundation
import Testing
import ThirdTimerCore

struct BellTests {
    func loudness(_ samples: ArraySlice<Float>) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    @Test func theBellIsGentleAndNeverClips() {
        let samples = Bell.samples()
        let peak = samples.map(abs).max() ?? 0
        #expect(peak <= 0.5001)
        #expect(peak > 0.4)
    }

    @Test func itStartsAndEndsInSilenceSoItNeverClicks() {
        let samples = Bell.samples()
        #expect(abs(samples[0]) < 0.001)
        #expect(abs(samples[samples.count - 1]) < 0.001)
    }

    @Test func itRingsOutAndFadesAway() {
        let samples = Bell.samples()
        let second = Int(Bell.sampleRate)
        #expect(samples.count == 6 * second)
        let first = loudness(samples[0..<second])
        let last = loudness(samples[(5 * second)...])
        #expect(first > 5 * last)
    }

    @Test func twoStrikesLastLongerThanOne() {
        #expect(Bell.samples(strikes: 2).count > Bell.samples(strikes: 1).count)
    }

    @Test func theWavFileIsWellFormed() {
        let wav = Bell.wav()
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        #expect(wav.count == 44 + Bell.samples().count * 2)
    }
}
