import Foundation

struct MetadataPromptBlueprint {
    var baseInstruction: String
    var fieldInstructions: [MetadataField: String]

    func toDocument() -> String {
        var lines: [String] = []
        lines.append("# Litrix Prompt Blueprint")
        lines.append("# 说明：")
        lines.append("# 1) [BASE] 是 AI 全局背景设定。")
        lines.append("# 2) [FIELD:<name>] 是字段级规则。")
        lines.append("# 3) 程序会按“BASE + 选中字段规则”自动拼接提示词，以节省 token。")
        lines.append("")
        lines.append("[BASE]")
        lines.append(baseInstruction)
        lines.append("[/BASE]")
        lines.append("")

        for field in MetadataField.allCases {
            lines.append("# FIELD: \(field.rawValue)")
            lines.append("[FIELD:\(field.rawValue)]")
            lines.append(fieldInstructions[field] ?? Self.defaultFieldInstruction(for: field))
            lines.append("[/FIELD]")
            lines.append("")
        }

        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n"
    }

    func composedPrompt(for fields: [MetadataField]) -> String {
        let normalizedFields = fields.isEmpty ? MetadataField.allCases : fields
        let keySpec = normalizedFields
            .map { #"\"\#($0.rawValue)\":\"\""# }
            .joined(separator: ",")

        let fieldRules = normalizedFields
            .map { field in
                let instruction = (fieldInstructions[field] ?? Self.defaultFieldInstruction(for: field))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "- \(field.rawValue): \(instruction)"
            }
            .joined(separator: "\n")

        return """
        \(baseInstruction.trimmingCharacters(in: .whitespacesAndNewlines))

        你现在收到的是自动组合提示词：全局设定 + 字段级规则。

        本次仅提取以下字段，且只输出合法 JSON（不要 Markdown、不要解释）：
        {\(keySpec)}

        字段规则：
        \(fieldRules)
        """
    }

    static func fromDocument(_ text: String) -> MetadataPromptBlueprint? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        guard let base = extractSection(named: "BASE", from: normalized) else {
            return nil
        }

        var fieldInstructions: [MetadataField: String] = [:]
        for field in MetadataField.allCases {
            guard let instruction = extractSection(named: "FIELD:\(field.rawValue)", from: normalized) else {
                continue
            }
            let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                fieldInstructions[field] = trimmed
            }
        }

        return MetadataPromptBlueprint(
            baseInstruction: base.trimmingCharacters(in: .whitespacesAndNewlines),
            fieldInstructions: fieldInstructions
        )
    }

    static var `default`: MetadataPromptBlueprint {
        var fieldInstructions: [MetadataField: String] = [:]
        for field in MetadataField.allCases {
            fieldInstructions[field] = defaultFieldInstruction(for: field)
        }

        return MetadataPromptBlueprint(
            baseInstruction: """
            你是 Litrix 文献元数据助手。你会收到“文件名”和“PDF 文本片段”。
            你的工作不仅是提取，还要在必要时做高质量总结，并按字段规则规范化输出。

            全局行为标准：
            1) 证据优先级：正文/方法/结果 > 摘要 > 文件名。不得臆造。
            2) 字段无法确认时，返回空字符串 ""，不要输出 N/A、unknown、null、"-"。
            3) 输出必须是可直接解析的 JSON，且只包含本次要求的键；不要 Markdown、不要解释。
            4) 除 impactFactor 字段外，不要联网；impactFactor 允许联网核验期刊分区与影响因子。
            5) 术语表达：优先中文，关键术语保留英文原词于括号中（如：结构方程模型（SEM））。
            6) 分点字段使用 1️⃣ 2️⃣ 3️⃣ 编号；每点短而具体，避免空洞表述。
            7) 若字段要求“从原文总结”，必须基于可见证据，不得无依据扩写。
            8) 错误处理：若文本有 OCR 噪声或格式错乱，先做最小纠正再提取；若冲突无法判定，留空。
            """,
            fieldInstructions: fieldInstructions
        )
    }

    private static func extractSection(named name: String, from text: String) -> String? {
        let startTag = "[\(name)]"
        let endTag = "[/\(name.components(separatedBy: ":").first ?? name)]"

        guard let startRange = text.range(of: startTag) else { return nil }

        let searchRange = startRange.upperBound..<text.endIndex
        guard let endRange = text.range(of: endTag, range: searchRange) else { return nil }

        return String(text[startRange.upperBound..<endRange.lowerBound])
    }

    private static func defaultFieldInstruction(for field: MetadataField) -> String {
        switch field {
        case .title:
            return "提取论文标题原文，保留大小写；清理多余换行与首尾标点。"
        case .englishTitle:
            return "从文献中提取文献的英语标题，优先从原文提取，原文不存在时，翻译中文标题。"
        case .authors:
            return "authors 输出为单个字符串；多个作者用 \", \" 连接（例如 \"A, B, C\"）。"
        case .authorsEnglish:
            return "从文献中提取文献的所有作者的英语姓名，用 \", \" 分割，优先从原文提取，原文不存在时，翻译中文姓名。"
        case .year:
            return "优先输出四位年份；不确定时留空。"
        case .source:
            return "source 需输出完整来源名称；期刊写全称，会议写正式会议全称。"
        case .doi:
            return "仅提取明确 DOI（如 10.xxxx/xxxx）；不确定或缺失时留空。"
        case .abstractText:
            return "优先提取原文摘要；若缺失可基于原文核心内容写 2-4 句高信息密度摘要。"
        case .volume:
            return "从原文提取卷号，输出数字或原文卷号写法；不确定留空。"
        case .issue:
            return "从原文提取期号，输出数字或原文期号写法；不确定留空。"
        case .pages:
            return "从原文提取页码范围，格式如 \"231-239\"；单页可写 \"231\"；不确定留空。"
        case .paperType:
            return "根据原文与来源判断文献类型：期刊/会议/电子文献等，输出中文类型名。"
        case .rqs:
            return """
            优先提取原文明确研究问题并补充英文翻译。
            若原文无明确研究问题，可基于原文证据总结，并在该条末尾添加 🤖。
            格式：1️⃣ 问题中文？Question in English; 2️⃣ ...
            """
        case .conclusion:
            return "从原文提取结论并分点概述；每点 <=50 字，句子需具体有信息量。"
        case .results:
            return "从原文提取主要研究结果并分点概述；每点 <=50 字，强调方向、效应或关键发现。"
        case .category:
            return "根据研究性质归类，可多标签，用逗号分隔，例如：Empirical Research, Literature Review。"
        case .keywords:
            return """
            从原文提取关键词；若无明确关键词则留空。
            输出格式：中文术语（English term），多个关键词用 \", \" 分隔。
            """
        case .impactFactor:
            return """
            允许联网查询并核验期刊信息（仅本字段可联网）。
            需整理：JCR 分区、中国期刊等级（如北大核心/CSSCI）、索引分类（如 SCI/SSCI）、影响因子。
            输出格式：Q1, SCI, CSSCI, 17.3
            若仅查到部分信息，按已知项输出并省略未知项；完全无法确认则留空。
            """
        case .samples:
            return "提取样本信息，格式：N=总样本，n1=组1，n2=组2；综述/理论文可写文献数。"
        case .participantType:
            return "用一句话概括参与者类型并给英文翻译，例如：一线在职教师（Frontline in-service teachers）。"
        case .variables:
            return """
            从原文提取变量并分类，变量内部用 \", \" 分隔。
            英文变量名需翻译成中文，并在括号保留英文。
            示例：1️⃣ 自变量：自我效能（Self-efficacy）；2️⃣ 因变量：AI 依赖（AI addiction）
            若有中介/调节/控制变量，按同样格式补充。
            """
        case .dataCollection:
            return "从原文提取数据收集方式，格式：方式*样本量：数据内容。可多条分点。"
        case .dataAnalysis:
            return "从原文提取数据分析方法，格式示例：描述性统计（Descriptive Statistics），结构方程模型（SEM）。"
        case .methodology:
            return "提取研究方法论并中英对应，格式：定量研究（quantitative research），行动研究（action research）。"
        case .theoreticalFoundation:
            return "提取理论基础并中英对应，格式：I-PACE模型（I-PACE model），认知学徒制（Cognitive Apprenticeship）。"
        case .educationalLevel:
            return "提取被试教育阶段并中英对应，格式：小学（primary school），大学（higher education）。"
        case .country:
            return "提取国家并添加国旗，格式：🇨🇳中国（China），🇸🇬新加坡（Singapore）。"
        case .limitations:
            return "从原文提取研究局限并分点概述；每点 <=50 字，需明确方法/样本/外推等限制。"
        }
    }
}
