import Foundation

struct QuestionOption: Codable, Equatable {
    let label: String
    let description: String?
}

struct QuestionItem: Codable, Equatable {
    let question: String
    let header: String?
    let multiSelect: Bool
    let options: [QuestionOption]

    enum CodingKeys: String, CodingKey {
        case question, header, multiSelect, options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        question    = try c.decode(String.self, forKey: .question)
        header      = try c.decodeIfPresent(String.self, forKey: .header)
        multiSelect = (try? c.decode(Bool.self, forKey: .multiSelect)) ?? false
        options     = (try? c.decode([QuestionOption].self, forKey: .options)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(question, forKey: .question)
        try c.encodeIfPresent(header, forKey: .header)
        try c.encode(multiSelect, forKey: .multiSelect)
        try c.encode(options, forKey: .options)
    }
}

struct PendingQuestion: Identifiable, Equatable {
    let id: String
    let sessionId: String
    let questions: [QuestionItem]
    let receivedAt: Date

    static func == (lhs: PendingQuestion, rhs: PendingQuestion) -> Bool {
        lhs.id == rhs.id
    }
}
