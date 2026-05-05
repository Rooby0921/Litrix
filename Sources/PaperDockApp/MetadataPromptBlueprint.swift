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

        Litrix 强制输出合约：
        1) 先定位论文首页/题名页/摘要页的元数据区，再提取标题、作者、来源、年份、DOI；忽略页眉页脚、数据库下载页、版权说明、引用列表和文件名噪声。
        2) title 必须是论文标题，不得把期刊名、栏目名、网页标题、文件名、Running head 或 “Contents lists available...” 当标题。
        3) authors/authorsEnglish 只保留作者姓名；删除单位、邮箱、ORCID、通讯作者说明、脚注编号和上标；多个作者统一用英文逗号+空格连接。
        4) doi 只输出规范 DOI 主体，格式为 10.xxxx/xxxx；删除 https://doi.org/、doi:、空格、结尾句号/逗号/括号。
        5) year 只输出四位出版年份；不要输出提交/接收日期，除非没有出版年份。
        6) 引文必要字段优先级：若 DOI、Crossref/publisher 信息、引用推荐格式、期刊卷期页行或会议出版信息中出现 source/volume/issue/pages，必须优先提取这些字段。
        7) volume/issue/pages 不允许根据年份、会议名称或 DOI 猜测；找不到明确证据时填空字符串 ""，不要输出 unknown、N/A、待补、Add Pages。
        8) 输出前自检：键名必须完全匹配、不得多键少键、不得输出 null/unknown/N/A；不确定必须是空字符串 ""。
        9) abstractText 保留原文摘要语言；chineseAbstract 必须始终是中文摘要。
        10) 所有字段必须输出纯文本；删除 HTML/XML 标签和上标标记，例如 <scp>Al</scp> 应输出为 Al。

        本次仅提取以下字段，且只输出合法 JSON（不要 Markdown、不要解释）：
        {\(keySpec)}

        JSON 合法性要求：
        1) 输出必须能被标准 JSON 解析器直接解析，不能只是“看起来像 JSON”。
        2) 字段值中如果需要引用英文短语，优先使用中文弯引号 “ ”；不要在字符串值内部直接输出未转义的英文双引号。
        3) 如果必须保留英文双引号，必须写成 JSON 转义形式 \\\"，例如：Revisiting \\\"The Power of Feedback\\\" from the perspective of the learner。
        4) 字段值中的换行必须写成 \\n，不要在字符串内部输出真实换行。

        字段规则：
        \(fieldRules)

        引文字段严格示例（只学习格式；实际输出仍然只包含本次字段）：
        例1：原文/元数据为 "Computers & Education, 214(3), 15-29. DOI: 10.1016/j.compedu.2025.105123"
        输出字段应为：{"source":"Computers & Education","volume":"214","issue":"3","pages":"15-29","doi":"10.1016/j.compedu.2025.105123"}
        例2：原文/元数据为 "Proceedings of the CHI Conference on Human Factors in Computing Systems, pp. 1-18. https://doi.org/10.1145/3706598.3714103"
        输出字段应为：{"source":"Proceedings of the CHI Conference on Human Factors in Computing Systems","volume":"","issue":"","pages":"1-18","doi":"10.1145/3706598.3714103"}
        例3：原文/元数据为 "Proceedings of the ACM on Human-Computer Interaction 8, CSCW1, Article 145, 1-32"
        输出字段应为：{"source":"Proceedings of the ACM on Human-Computer Interaction","volume":"8","issue":"CSCW1","pages":"1-32"}

        标准示例（示例只用于学习格式；不要照抄内容；实际输出也必须只包含本次字段）：
        \(Self.exampleJSON(for: normalizedFields))
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
            你是 Litrix 文献元数据助手。你会收到“文件名”和“文献文本片段/已有条目信息”。
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
            9) JSON 转义：字段值中若需要引用英文短语，优先使用中文弯引号 “ ”；不要在字符串内部直接输出未转义的英文双引号。
            10) 若必须保留英文双引号，必须写成 JSON 转义形式 \\\"；字段值中的换行必须写成 \\n。
            11) 标题/作者/DOI 为高优先级字段：标题不得混入期刊名或页眉；作者不得混入单位、邮箱、ORCID、通讯作者说明；DOI 必须规范化为 10.xxxx/xxxx。
            12) 所有字段必须输出纯文本；删除 HTML/XML 标签和上标标记，例如 <scp>Al</scp> 应输出为 Al。
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

    private static func exampleJSON(for fields: [MetadataField]) -> String {
        let lines = fields.map { field in
            #"  "\#(field.rawValue)":"\#(jsonEscaped(exampleValue(for: field)))""#
        }
        return "{\n\(lines.joined(separator: ",\n"))\n}"
    }

    private static func exampleValue(for field: MetadataField) -> String {
        switch field {
        case .title:
            return "Teachers' generative AI use and professional agency in higher education"
        case .englishTitle:
            return "Teachers' generative AI use and professional agency in higher education"
        case .authors:
            return "Li Wei, Maria Santos, Chen Yu"
        case .authorsEnglish:
            return "Wei Li, Maria Santos, Yu Chen"
        case .year:
            return "2025"
        case .source:
            return "Computers & Education"
        case .doi:
            return "10.1016/j.compedu.2025.105123"
        case .abstractText:
            return "This study examines how teachers use generative AI and how such use relates to professional agency."
        case .chineseAbstract:
            return "本研究考察教师如何使用生成式人工智能，以及这种使用如何关联教师专业能动性。"
        case .volume:
            return "214"
        case .issue:
            return "3"
        case .pages:
            return "15-29"
        case .paperType:
            return "期刊文章"
        case .rqs:
            return "1️⃣ 教师如何将生成式AI融入教学准备？How do teachers integrate generative AI into lesson preparation?"
        case .conclusion:
            return "1️⃣ 生成式AI主要强化备课效率，但教师专业判断仍决定最终教学设计。"
        case .results:
            return "1️⃣ 高AI自我效能教师更倾向于将AI用于反馈生成与材料改写。"
        case .category:
            return "Empirical Research"
        case .impactFactor:
            return "Q1, SSCI, 11.2"
        case .samples:
            return "N=642名教师"
        case .participantType:
            return "高校教师（Higher education teachers）"
        case .variables:
            return "1️⃣ 自变量：AI自我效能（AI self-efficacy）；2️⃣ 因变量：专业能动性（Professional agency）"
        case .dataCollection:
            return "1️⃣ 在线问卷*642：AI使用频率、教学任务、专业能动性。"
        case .dataAnalysis:
            return "描述性统计（Descriptive Statistics），结构方程模型（SEM）"
        case .methodology:
            return "定量研究（quantitative research）"
        case .theoreticalFoundation:
            return "教师专业能动性理论（Teacher professional agency theory）"
        case .educationalLevel:
            return "高等教育（higher education）"
        case .country:
            return "🇨🇳中国（China）"
        case .keywords:
            return "生成式人工智能（Generative AI）, 教师专业能动性（Teacher professional agency）"
        case .limitations:
            return "1️⃣ 横断面数据无法确认AI使用与专业能动性的因果方向。"
        }
    }

    private static func jsonEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func defaultFieldInstruction(for field: MetadataField) -> String {
        switch field {
        case .title:
            return "提取论文标题原文，保留大小写；清理多余换行与首尾标点；不得输出期刊名、网页标题、文件名、页眉或 Running head。"
        case .englishTitle:
            return "从文献中提取文献的英语标题，优先从原文提取，原文不存在时，翻译中文标题。"
        case .authors:
            return "authors 输出为单个字符串；仅保留作者姓名，删除单位、邮箱、ORCID、通讯作者说明和脚注编号；多个作者用 \", \" 连接（例如 \"A, B, C\"）。"
        case .authorsEnglish:
            return "从文献中提取文献的所有作者的英语姓名，用 \", \" 分割；仅保留姓名，删除单位、邮箱、ORCID、通讯作者说明和脚注编号；优先从原文提取，原文不存在时，翻译中文姓名。"
        case .year:
            return "优先输出四位年份；不确定时留空。"
        case .source:
            return "source 需输出完整来源名称；期刊写全称，会议写正式会议/论文集全称。不得把 DOI、URL、页码、卷期、数据库提示词或网页导航混入 source。"
        case .doi:
            return "仅提取明确 DOI；输出规范主体（如 10.xxxx/xxxx），删除 https://doi.org/、doi:、空格和结尾标点；不确定或缺失时留空。"
        case .abstractText:
            return "优先提取原文摘要；必须保留原文摘要语言，原文是中文就输出中文，原文是英文就输出英文，不要为了该字段翻译成英文；若缺失可基于原文核心内容按原文主要语言写 2-4 句高信息密度摘要。"
        case .chineseAbstract:
            return "输出中文摘要。若原文摘要是中文，可提取并适度整理；若原文摘要是英文或其他语言，翻译/概述为中文；若原文没有摘要，基于正文核心内容写 2-4 句中文摘要。"
        case .volume:
            return """
            从明确出版信息中提取卷号，仅输出卷号本身。
            可识别格式：214(3):15-29 中 volume=214；Vol. 8, No. 2 中 volume=8；Proceedings of the ACM on HCI 8 CSCW1 中 volume=8。
            会议论文如果没有卷号，必须填空字符串 ""；不得用年份、会议届次或 DOI 推断。
            """
        case .issue:
            return """
            从明确出版信息中提取期号/number，仅输出期号本身。
            可识别格式：214(3):15-29 中 issue=3；Vol. 8, No. 2 中 issue=2；Proceedings of the ACM on HCI 8 CSCW1 中 issue=CSCW1。
            会议论文如果没有期号，必须填空字符串 ""；不得输出会议名称或栏目说明。
            """
        case .pages:
            return """
            从明确页码或文章编号中提取 pages。
            页码范围统一使用半角连字符，如 "231-239"、"1-18"；单页写 "231"。
            ACM/Frontiers 等文章编号若无页码但有 Article/eLocator，可输出 "Article 145" 或 "e12345"；若同时有 "1-18"，优先输出 "1-18"。
            不得把 PDF 总页数、引用列表页码、章节编号或 DOI 尾号当 pages。
            """
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
