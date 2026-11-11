import Foundation

/// A soft bell, in the manner of a singing bowl, made from a few decaying
/// tones. It is computed, so the app ships no sound file.
public enum Bell {
    public static let sampleRate = 44_100.0

    /// One partial of the bell: a frequency ratio to the base tone, how loud
    /// it is, and how many seconds it takes to fade to about a third.
    private struct Partial {
        var ratio: Double
        var level: Double
        var decay: Double
    }

    /// Ratios close to those of a struck metal bowl. Each partial is doubled
    /// slightly out of tune, which gives the slow shimmer of a real bowl.
    private static let partials = [
        Partial(ratio: 1.0, level: 1.0, decay: 2.6),
        Partial(ratio: 2.71, level: 0.45, decay: 1.7),
        Partial(ratio: 5.15, level: 0.18, decay: 0.9),
        Partial(ratio: 8.43, level: 0.06, decay: 0.5),
    ]

    private static let baseFrequency = 220.0
    private static let strikeLength = 6.0
    private static let strikeSpacing = 2.4
    private static let peak = 0.5

    /// Mono samples between -1 and 1. `strikes` is how many times the bell is struck.
    public static func samples(strikes: Int = 1) -> [Float] {
        let strikes = max(1, min(strikes, 4))
        let total = Int((strikeLength + Double(strikes - 1) * strikeSpacing) * sampleRate)
        var mix = [Double](repeating: 0, count: total)

        for strike in 0..<strikes {
            let offset = Int(Double(strike) * strikeSpacing * sampleRate)
            for i in 0..<Int(strikeLength * sampleRate) {
                let t = Double(i) / sampleRate
                // A short, rounded attack, so the strike never clicks.
                let attack = t < 0.015 ? 0.5 - 0.5 * cos(.pi * t / 0.015) : 1
                var value = 0.0
                for partial in partials {
                    let frequency = baseFrequency * partial.ratio
                    let envelope = exp(-t / partial.decay)
                    value += partial.level * envelope * 0.5
                        * (sin(2 * .pi * frequency * t) + sin(2 * .pi * (frequency + 0.7) * t))
                }
                mix[offset + i] += value * attack
            }
        }

        // Fade the tail to silence and scale to a gentle level.
        let fade = Int(0.5 * sampleRate)
        for i in 0..<fade {
            mix[total - 1 - i] *= Double(i) / Double(fade)
        }
        let loudest = mix.map(abs).max() ?? 1
        let scale = loudest > 0 ? peak / loudest : 0
        return mix.map { Float($0 * scale) }
    }

    /// The same sound as a 16-bit mono WAV file, ready to hand to an audio player.
    public static func wav(strikes: Int = 1) -> Data {
        let samples = samples(strikes: strikes)
        let dataSize = UInt32(samples.count * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                      // format chunk size
        append(UInt16(1))                       // PCM
        append(UInt16(1))                       // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2)          // bytes per second
        append(UInt16(2))                       // bytes per frame
        append(UInt16(16))                      // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        for sample in samples {
            append(Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded()))
        }
        return data
    }
}
