import Foundation
import MurmurCore
import Redact

/// Finds personal details in the transcript with Desert Ant Redact, as time spans over the words.
enum RedactionFinder {
    static func find(in words: [MurmurCore.Word]) async throws -> [RedactedSpan] {
        var spans: [RedactedSpan] = []
        for paragraph in Merge.paragraphs(words) {
            let run = Array(words[paragraph.range]).filter { !$0.isFiller }
            let (text, ranges) = Redactor.text(of: run)
            guard !text.isEmpty else { continue }
            let result = try await Engines.shared.redact.redaction(of: text)
            for item in result.items {
                let lo = text.distance(from: text.startIndex, to: item.range.lowerBound)
                let hi = text.distance(from: text.startIndex, to: item.range.upperBound)
                guard let span = Redactor.span(words: run, ranges: ranges, chars: lo..<hi,
                                               category: category(item.label), original: item.original) else { continue }
                // A given name followed by a surname is one name.
                if let last = spans.last, last.category == span.category, span.start - last.end < 0.6 {
                    spans[spans.count - 1].end = span.end
                    spans[spans.count - 1].original += " " + span.original
                } else {
                    spans.append(span)
                }
            }
        }
        return spans
    }

    static func category(_ label: Label) -> String {
        switch label {
        case .givenName, .surname: "name"
        case .streetName, .buildingNumber, .secondaryAddress, .city, .state, .zipCode: "address"
        case .email: "email"
        case .phone: "phone"
        case .creditCard, .bankAccount, .routingNumber: "account"
        case .ipAddress, .url: "link"
        case .governmentID, .passport, .driversLicense, .taxID, .ssn: "ID"
        case .imei: "device"
        case .org: "organisation"
        }
    }
}
