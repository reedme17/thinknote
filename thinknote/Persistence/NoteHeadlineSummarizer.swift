import Foundation
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

enum NoteCardHeadlinePolicy {
    static let horizontalPadding: CGFloat = 18
    static let summaryFontSize: CGFloat = 18
    static let chineseSummaryFontSize: CGFloat = 16
    static let summaryLineSpacing: CGFloat = 2
    static let maxLines = 5

    static func normalizedHeadlineSource(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func containsCJKCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value) ||
            (0x2A700...0x2B73F).contains(scalar.value) ||
            (0x2B740...0x2B81F).contains(scalar.value) ||
            (0x2B820...0x2CEAF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    static func shouldSummarizeForCard(_ text: String, columnWidth: CGFloat = fallbackColumnWidth()) -> Bool {
        let normalized = normalizedHeadlineSource(text)
        guard !normalized.isEmpty else { return false }

        let availableWidth = max(columnWidth - horizontalPadding * 2, 0)
        guard availableWidth > 0 else { return false }

        let font = summaryFont(for: normalized)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = summaryLineSpacing

        let boundingRect = NSAttributedString(
            string: normalized,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        .boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let maxHeight = ceil(
            CGFloat(maxLines) * font.lineHeight
            + CGFloat(max(maxLines - 1, 0)) * summaryLineSpacing
        )
        return ceil(boundingRect.height) > maxHeight
    }

    static func sanitizedCardHeadline(_ headline: String, fallback: String) -> String {
        let normalized = normalizedHeadlineSource(headline)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        guard !normalized.isEmpty else {
            return normalizedHeadlineSource(fallback)
        }
        return headlineThatFitsCard(normalized)
    }

    private static func headlineThatFitsCard(_ headline: String) -> String {
        guard shouldSummarizeForCard(headline) else { return headline }

        var words = headline.split(separator: " ").map(String.init)
        if words.count > 1 {
            while words.count > 1 {
                words.removeLast()
                let candidate = words.joined(separator: " ")
                if !shouldSummarizeForCard(candidate) {
                    return candidate
                }
            }
        }

        var candidate = headline
        while candidate.count > 1 && shouldSummarizeForCard(candidate) {
            candidate.removeLast()
        }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func summaryFont(for text: String) -> UIFont {
        let fontSize = containsCJKCharacters(text) ? chineseSummaryFontSize : summaryFontSize
        return UIFont(name: "DavidLibre-Regular", size: fontSize)
        ?? UIFont.systemFont(ofSize: fontSize)
    }

    private static func fallbackColumnWidth() -> CGFloat {
        max((currentScreenBounds().width - 52) * 0.5, 0)
    }

    private static func currentScreenBounds() -> CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map(\.screen.bounds)
            .first ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }
}

protocol NoteHeadlineSummarizing: Sendable {
    func cardHeadline(for text: String) async throws -> String?
}

final class LocalFoundationModelHeadlineSummarizer: NoteHeadlineSummarizing {
    func cardHeadline(for text: String) async throws -> String? {
        let normalized = NoteCardHeadlinePolicy.normalizedHeadlineSource(text)
        guard NoteCardHeadlinePolicy.shouldSummarizeForCard(normalized) else {
            return nil
        }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                return nil
            }

            let session = LanguageModelSession(
                model: model,
                instructions: """
                You write quiet, faithful card headlines for personal notes.
                Preserve the user's meaning and language.
                Respond in the same primary language as the note.
                Return one short line only.
                Do not add explanation, quotation marks, bullets, prefixes, or ellipses.
                """
            )
            let response = try await session.respond(to: """
            Rewrite this note into a concise card headline that fits in five short lines.
            Stay close to the original wording.
            Use the same primary language as the note.

            Note:
            \(normalized)
            """)
            return NoteCardHeadlinePolicy.sanitizedCardHeadline(response.content, fallback: normalized)
        }
#endif

        return nil
    }
}
