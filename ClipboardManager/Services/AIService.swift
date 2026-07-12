import AppKit
import NaturalLanguage
import Vision

/// On-device intelligence for clipboard content, using Apple's Vision and
/// Natural Language frameworks — no network, nothing leaves the Mac.
enum AIService {

    // MARK: - OCR (Vision)

    /// Extracts text from image data using on-device text recognition.
    static func recognizeText(in imageData: Data) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, _ in
                    let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(data: imageData)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    // MARK: - Language (Natural Language)

    /// The localized name of the dominant language of `text`, e.g. "French".
    static func dominantLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return Locale.current.localizedString(forIdentifier: language.rawValue) ?? language.rawValue
    }

    // MARK: - Summary (extractive)

    /// A short extractive summary: scores sentences by the frequency of the
    /// meaningful words they contain and returns the top ones in original order.
    /// Fully on-device and works offline; good for long notes and articles.
    static func summarize(_ text: String, maxSentences: Int = 3) -> String {
        let sentences = split(text, unit: .sentence)
        guard sentences.count > maxSentences else { return text }

        let frequencies = wordFrequencies(in: text)
        let scored = sentences.enumerated().map { index, sentence -> (index: Int, score: Double) in
            let words = split(sentence.lowercased(), unit: .word)
            guard !words.isEmpty else { return (index, 0) }
            let total = words.reduce(0.0) { $0 + (frequencies[$1] ?? 0) }
            return (index, total / Double(words.count))
        }

        let topIndices = scored
            .sorted { $0.score > $1.score }
            .prefix(maxSentences)
            .map(\.index)
            .sorted()

        return topIndices.map { sentences[$0] }.joined(separator: " ")
    }

    // MARK: - Helpers

    private static func split(_ text: String, unit: NLTokenUnit) -> [String] {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { tokens.append(token) }
            return true
        }
        return tokens
    }

    /// Word frequencies, skipping very short/stop-like words, using the tagger to
    /// weight nouns/verbs/adjectives (the content-bearing words).
    private static func wordFrequencies(in text: String) -> [String: Double] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var frequencies: [String: Double] = [:]
        let meaningful: Set<NLTag> = [.noun, .verb, .adjective, .otherWord]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            let word = text[range].lowercased()
            guard word.count > 2, let tag, meaningful.contains(tag) else { return true }
            frequencies[word, default: 0] += 1
            return true
        }
        return frequencies
    }
}
