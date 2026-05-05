import Foundation

enum EasyScholarError: LocalizedError {
    case missingAPIKey
    case missingPublicationName
    case invalidURL
    case requestFailed(String)
    case invalidResponse
    case noRankData

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在“影响因子”的列设置中填写 easyScholar 密钥。"
        case .missingPublicationName:
            return "这篇文献缺少期刊/来源名称，无法查询 easyScholar。"
        case .invalidURL:
            return "easyScholar 请求地址无效。"
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return "easyScholar 返回了无法识别的数据。"
        case .noRankData:
            return "easyScholar 没有返回可用的期刊等级数据。"
        }
    }
}

struct EasyScholarService {
    private static let endpoint = URL(string: "https://easyscholar.cc/open/getPublicationRank")!

    static func fetchOfficialRank(
        publicationName: String,
        secretKey: String
    ) async throws -> [String: String] {
        let name = publicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw EasyScholarError.missingPublicationName }

        let key = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw EasyScholarError.missingAPIKey }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "secretKey", value: key),
            URLQueryItem(name: "publicationName", value: name)
        ]
        guard let url = components?.url else { throw EasyScholarError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw EasyScholarError.requestFailed("easyScholar 请求失败（HTTP \(httpResponse.statusCode)）。")
        }

        let decoded = try JSONDecoder().decode(EasyScholarResponse.self, from: data)
        if let message = decoded.responseMessage, decoded.isFailure {
            throw EasyScholarError.requestFailed(message)
        }
        guard let all = decoded.data?.officialRank?.all, !all.isEmpty else {
            throw EasyScholarError.noRankData
        }

        let result = all.reduce(into: [String: String]()) { partialResult, pair in
            guard let value = pair.value.displayString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            partialResult[pair.key] = value
        }
        guard !result.isEmpty else { throw EasyScholarError.noRankData }
        return result
    }

    static func formattedImpactFactor(
        from ranks: [String: String],
        fields rawFields: String,
        abbreviations rawAbbreviations: String
    ) -> String {
        let requestedFields = parseRequestedFields(rawFields)
        let abbreviations = parseAbbreviations(rawAbbreviations)
        var parts: [String] = []

        for field in requestedFields {
            guard let match = rankValue(in: ranks, for: field) else { continue }
            let value = normalizedRankValue(match.value)
            guard shouldDisplayRankValue(value) else { continue }

            let label = displayLabel(for: field, matchedKey: match.key)
            let abbreviation = abbreviationValue(
                for: label,
                matchedKey: match.key,
                abbreviations: abbreviations
            )

            if isPresenceRankValue(value, label: label, matchedKey: match.key) {
                parts.append(abbreviation.isEmpty ? label : abbreviation)
            } else if abbreviation.isEmpty {
                parts.append(value)
            } else {
                parts.append("\(abbreviation) \(value)")
            }
        }

        return parts.joined(separator: ", ")
    }

    static func parseRequestedFields(_ raw: String) -> [String] {
        let fields = raw
            .split(whereSeparator: { separator in
                separator == "," || separator == "\n" || separator == "，" || separator == ";"
            })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return fields.isEmpty
            ? ["cssci", "sciif", "sci", "utd24", "ajg", "sciBase", "ssci", "pku", "复合影响因子"]
            : fields
    }

    static func parseAbbreviations(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = raw.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "，" })
        for pair in pairs {
            let text = String(pair).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[normalizedToken(key)] = value
        }
        return result
    }

    private static func rankValue(in ranks: [String: String], for field: String) -> (key: String, value: String)? {
        let normalizedRanks = ranks.reduce(into: [String: (key: String, value: String)]()) { partialResult, pair in
            partialResult[normalizedToken(pair.key)] = (pair.key, pair.value)
        }

        let aliases = aliases(for: field)
        for alias in aliases {
            if let value = normalizedRanks[normalizedToken(alias)] {
                return value
            }
        }

        return nil
    }

    private static func aliases(for field: String) -> [String] {
        let normalized = normalizedToken(field)
        let aliases: [String: [String]] = [
            "CSSCI": ["cssci", "CSSCI", "南大核心", "CSSCI来源期刊", "CSSCI扩展版", "cssciExt", "cssci扩展版"],
            "SCIIF": ["sciif", "SCIIF", "SCIIF(5)", "sciif5", "SCI IF", "影响因子", "JIF", "Impact Factor"],
            "SCI": ["sci", "SCI", "JCR", "SCI分区", "JCR分区"],
            "UTD24": ["utd24", "UTD24", "UTD"],
            "AJG": ["ajg", "AJG", "ABS"],
            "SCIBASE": ["sciBase", "SCI基础版", "中科院分区基础版", "基础版"],
            "SSCI": ["ssci", "SSCI"],
            "PKU": ["pku", "北大中文核心", "北大核心"],
            "复合影响因子": ["复合影响因子", "compoundIF", "compoundImpactFactor", "compositeImpactFactor"]
        ]

        if let known = aliases[normalized] {
            return known + [field]
        }
        return [field]
    }

    private static func displayLabel(for field: String, matchedKey: String) -> String {
        let normalized = normalizedToken(field)
        let labels: [String: String] = [
            "CSSCI": matchedKey.localizedCaseInsensitiveContains("扩") ? "CSSCI扩展版" : "CSSCI",
            "SCIIF": normalizedToken(matchedKey).contains("5") ? "SCIIF(5)" : "SCIIF",
            "SCI": "SCI",
            "UTD24": "UTD24",
            "AJG": "AJG",
            "SCIBASE": "SCI基础版",
            "SSCI": "SSCI",
            "PKU": "北大中文核心",
            "复合影响因子": "复合影响因子"
        ]
        return labels[normalized] ?? field
    }

    private static func abbreviationValue(
        for label: String,
        matchedKey: String,
        abbreviations: [String: String]
    ) -> String {
        abbreviations[normalizedToken(label)]
            ?? abbreviations[normalizedToken(matchedKey)]
            ?? label
    }

    private static func normalizedRankValue(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"^\s*[\[\(]?\s*["']?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldDisplayRankValue(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty
            && normalized != "false"
            && normalized != "null"
            && normalized != "none"
            && normalized != "-"
            && normalized != "无"
    }

    private static func isPresenceRankValue(_ value: String, label: String, matchedKey: String) -> Bool {
        let normalized = normalizedToken(value)
        let labelToken = normalizedToken(label)
        let keyToken = normalizedToken(matchedKey)
        return normalized == "TRUE"
            || normalized == "YES"
            || normalized == "1"
            || normalized == labelToken
            || normalized == keyToken
            || normalized.contains(labelToken)
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }
}

private struct EasyScholarResponse: Decodable {
    var code: FlexibleJSON?
    var success: FlexibleJSON?
    var msg: String?
    var message: String?
    var data: EasyScholarData?

    var responseMessage: String? {
        let raw = msg ?? message
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var isFailure: Bool {
        if let success = success?.boolValue {
            return !success
        }
        if let code = code?.stringValue,
           let intCode = Int(code),
           intCode != 0 && intCode != 200 {
            return true
        }
        return false
    }
}

private struct EasyScholarData: Decodable {
    var officialRank: EasyScholarOfficialRank?
}

private struct EasyScholarOfficialRank: Decodable {
    var all: [String: FlexibleJSON]?
}

private enum FlexibleJSON: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([FlexibleJSON])
    case object([String: FlexibleJSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([FlexibleJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: FlexibleJSON].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "true" { return true }
            if normalized == "false" { return false }
            return nil
        default:
            return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return values.compactMap(\.displayString).joined(separator: " ")
        case .object:
            return displayString
        case .null:
            return nil
        }
    }

    var displayString: String? {
        switch self {
        case .object(let object):
            let preferredKeys = ["rank", "value", "name", "level", "partition", "zone", "if", "impactFactor"]
            for key in preferredKeys {
                if let value = object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value.displayString,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            let joined = object
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .compactMap { _, value in value.displayString }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")
            return joined.isEmpty ? nil : joined
        default:
            return stringValue
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
