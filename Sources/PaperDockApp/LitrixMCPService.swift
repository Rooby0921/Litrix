import Foundation
import PDFKit

@MainActor
final class LitrixMCPToolService {
    struct ToolCallPayload {
        var structuredContent: [String: Any]
        var isError: Bool
    }

    private struct FullTextCacheEntry {
        var pdfPath: String
        var modifiedAt: Date?
        var pageCount: Int
        var text: String
        var extractedAt: Date
        var isTruncatedInCache: Bool
    }

    private struct SimilarityScoredPaper {
        var paper: Paper
        var score: Double
        var matchedTerms: [String]
    }

    private struct MetadataFieldDescriptor {
        var name: String
        var displayName: String
        var description: String
        var valueType: String
        var editable: Bool
        var hidden: Bool
        var group: String
        var aliases: [String] = []
        var jsonSchema: [String: Any]
    }

    private enum MetadataUpdateMode: String {
        case merge
        case replace
    }

    private enum ToolServiceError: Error {
        case invalidArguments(String)
        case notFound(String)
        case conflict(String)
        case execution(String)
    }

    private let settings: SettingsStore
    private let store: LibraryStore
    private let isoFormatter = ISO8601DateFormatter()
    private let isoFormatterWithFractionalSeconds = ISO8601DateFormatter()
    private let fileManager = FileManager.default
    private let maximumCachedFullTextLength = 250_000
    private var fullTextCache: [UUID: FullTextCacheEntry] = [:]
    private var fullTextCacheHits = 0
    private var fullTextCacheMisses = 0

    init(settings: SettingsStore, store: LibraryStore) {
        self.settings = settings
        self.store = store
        isoFormatter.formatOptions = [.withInternetDateTime]
        isoFormatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func toolDefinitions() -> [[String: Any]] {
        [
            toolDefinition(
                name: "browse_library_structure",
                description: "Browse Litrix library structure, including system libraries, collections, tags, and counts.",
                schema: [
                    "type": "object",
                    "properties": [
                        "include_counts": [
                            "type": "boolean",
                            "description": "Whether to include item counts for each section."
                        ]
                    ]
                ],
                readOnly: true
            ),
            toolDefinition(
                name: "search_library",
                description: "Search the Litrix library using the built-in search engine, including citation-style queries.",
                schema: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Search text. Supports plain text and citation-style queries."
                        ],
                        "field": [
                            "type": "string",
                            "description": "Optional field restriction such as title, authors, abstractText, chineseAbstract, tags, or collections."
                        ],
                        "scope": [
                            "type": "string",
                            "description": "Optional scope: all, recentReading, zombiePapers, unfiled, missingDOI, missingAttachment, collection:<name>, or tag:<name>."
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of results to return."
                        ]
                    ],
                    "required": ["query"]
                ],
                readOnly: true
            ),
            toolDefinition(
                name: "semantic_search",
                description: "Find related papers using Litrix's local weighted metadata similarity search.",
                schema: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Natural-language topic or concept to search for."
                        ],
                        "scope": [
                            "type": "string",
                            "description": "Optional scope: all, recentReading, zombiePapers, unfiled, missingDOI, missingAttachment, collection:<name>, or tag:<name>."
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of results to return."
                        ]
                    ],
                    "required": ["query"]
                ],
                readOnly: true
            ),
            toolDefinition(
                name: "read_item_metadata",
                description: "Read metadata for a single Litrix item by id, DOI, or exact title.",
                schema: itemSelectorSchema(
                    extraProperties: [:],
                    requiredAnySelector: true
                ),
                readOnly: true
            ),
            toolDefinition(
                name: "describe_metadata_fields",
                description: "List all Litrix metadata fields, including hidden/internal fields, with types, visibility, aliases, and editability.",
                schema: [
                    "type": "object",
                    "properties": [
                        "include_hidden": [
                            "type": "boolean",
                            "description": "Whether to include hidden/internal fields. Defaults to true."
                        ],
                        "editable_only": [
                            "type": "boolean",
                            "description": "Whether to return only editable fields. Defaults to false."
                        ]
                    ]
                ],
                readOnly: true
            ),
            toolDefinition(
                name: "update_item_metadata",
                description: "Update Litrix metadata fields for a single item. Provide only selected fields for targeted updates, or provide every editable field returned by describe_metadata_fields for a full metadata rewrite.",
                schema: itemSelectorSchema(
                    extraProperties: [
                        "mode": [
                            "type": "string",
                            "description": "Optional update mode. merge keeps unspecified fields unchanged. replace clears all editable fields before applying updates."
                        ],
                        "updates": [
                            "type": "object",
                            "description": "Dictionary of metadata fields to update. Field names and types are discoverable via describe_metadata_fields.",
                            "properties": metadataUpdateSchemaProperties(),
                            "additionalProperties": false
                        ]
                    ],
                    required: ["updates"],
                    requiredAnySelector: true
                ),
                readOnly: false
            ),
            toolDefinition(
                name: "read_abstract",
                description: "Read the abstract for a single Litrix item.",
                schema: itemSelectorSchema(
                    extraProperties: [
                        "max_chars": [
                            "type": "integer",
                            "description": "Optional maximum number of characters to return."
                        ]
                    ],
                    requiredAnySelector: true
                ),
                readOnly: true
            ),
            toolDefinition(
                name: "read_fulltext",
                description: "Extract cached or on-demand full text from an attached PDF.",
                schema: itemSelectorSchema(
                    extraProperties: [
                        "start_char": [
                            "type": "integer",
                            "description": "Optional starting character offset."
                        ],
                        "max_chars": [
                            "type": "integer",
                            "description": "Optional maximum number of characters to return."
                        ]
                    ],
                    requiredAnySelector: true
                ),
                readOnly: true
            ),
            toolDefinition(
                name: "search_annotations",
                description: "Search Litrix notes and annotation text across the library.",
                schema: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Text to search for in notes."
                        ],
                        "scope": [
                            "type": "string",
                            "description": "Optional scope: all, recentReading, zombiePapers, unfiled, missingDOI, missingAttachment, collection:<name>, or tag:<name>."
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of results to return."
                        ]
                    ],
                    "required": ["query"]
                ],
                readOnly: true
            ),
            toolDefinition(
                name: "find_similar",
                description: "Find papers similar to a Litrix item based on weighted metadata overlap.",
                schema: itemSelectorSchema(
                    extraProperties: [
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of similar items to return."
                        ]
                    ],
                    requiredAnySelector: true
                ),
                readOnly: true
            ),
            toolDefinition(
                name: "item_details",
                description: "Read a Litrix item with metadata, attachment status, note paths, and optional full-text preview.",
                schema: itemSelectorSchema(
                    extraProperties: [
                        "include_fulltext_preview": [
                            "type": "boolean",
                            "description": "Whether to include a truncated full-text preview."
                        ],
                        "max_chars": [
                            "type": "integer",
                            "description": "Optional maximum characters for the full-text preview."
                        ]
                    ],
                    requiredAnySelector: true
                ),
                readOnly: true
            ),
            toolDefinition(
                name: "fulltext_cache_stats",
                description: "Inspect Litrix's in-memory PDF full-text cache statistics.",
                schema: [
                    "type": "object",
                    "properties": [:]
                ],
                readOnly: true
            ),
            toolDefinition(
                name: "semantic_index_status",
                description: "Inspect the current Litrix semantic search backend and readiness state.",
                schema: [
                    "type": "object",
                    "properties": [:]
                ],
                readOnly: true
            ),
            toolDefinition(
                name: "manage_collections",
                description: "List, create, rename, delete, assign, or unassign Litrix collections.",
                schema: managementSchema(entityDescription: "collection", supportsColor: false),
                readOnly: false
            ),
            toolDefinition(
                name: "manage_tags",
                description: "List, create, rename, delete, assign, unassign, or recolor Litrix tags.",
                schema: managementSchema(entityDescription: "tag", supportsColor: true),
                readOnly: false
            ),
            toolDefinition(
                name: "create_or_update_items",
                description: "Create, update, or upsert Litrix items with structured metadata.",
                schema: itemSelectorSchema(
                    extraProperties: [
                        "mode": [
                            "type": "string",
                            "description": "One of create, update, or upsert."
                        ],
                        "item": [
                            "type": "object",
                            "description": "Dictionary of item metadata fields. Field names and types are discoverable via describe_metadata_fields.",
                            "properties": metadataUpdateSchemaProperties(),
                            "additionalProperties": false
                        ]
                    ],
                    required: ["item"],
                    requiredAnySelector: false
                ),
                readOnly: false
            ),
            toolDefinition(
                name: "create_or_append_notes",
                description: "Replace or append Litrix note text for a single item.",
                schema: itemSelectorSchema(
                    extraProperties: [
                        "mode": [
                            "type": "string",
                            "description": "Either append or replace."
                        ],
                        "text": [
                            "type": "string",
                            "description": "Note text to append or replace."
                        ],
                        "separator": [
                            "type": "string",
                            "description": "Optional separator used in append mode."
                        ]
                    ],
                    required: ["text"],
                    requiredAnySelector: true
                ),
                readOnly: false
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) -> ToolCallPayload {
        do {
            let content: [String: Any]
            switch name {
            case "browse_library_structure":
                content = try browseLibraryStructure(arguments: arguments)
            case "search_library":
                content = try searchLibrary(arguments: arguments)
            case "semantic_search":
                content = try semanticSearch(arguments: arguments)
            case "read_item_metadata":
                content = try readItemMetadata(arguments: arguments)
            case "describe_metadata_fields":
                content = describeMetadataFields(arguments: arguments)
            case "update_item_metadata":
                content = try updateItemMetadata(arguments: arguments)
            case "read_abstract":
                content = try readAbstract(arguments: arguments)
            case "read_fulltext":
                content = try readFullText(arguments: arguments)
            case "search_annotations":
                content = try searchAnnotations(arguments: arguments)
            case "find_similar":
                content = try findSimilar(arguments: arguments)
            case "item_details":
                content = try itemDetails(arguments: arguments)
            case "fulltext_cache_stats":
                content = fullTextCacheStats()
            case "semantic_index_status":
                content = semanticIndexStatus()
            case "manage_collections":
                content = try manageCollections(arguments: arguments)
            case "manage_tags":
                content = try manageTags(arguments: arguments)
            case "create_or_update_items":
                content = try createOrUpdateItems(arguments: arguments)
            case "create_or_append_notes":
                content = try createOrAppendNotes(arguments: arguments)
            default:
                throw ToolServiceError.invalidArguments("Unknown tool: \(name)")
            }
            return ToolCallPayload(structuredContent: content, isError: false)
        } catch let error as ToolServiceError {
            return errorPayload(for: error)
        } catch {
            return ToolCallPayload(
                structuredContent: [
                    "error": "Unexpected MCP tool error",
                    "details": error.localizedDescription
                ],
                isError: true
            )
        }
    }

    func renderPayloadText(_ payload: ToolCallPayload) -> String {
        prettyJSONString(payload.structuredContent)
    }

    private func toolDefinition(
        name: String,
        description: String,
        schema: [String: Any],
        readOnly: Bool
    ) -> [String: Any] {
        var tool: [String: Any] = [
            "name": name,
            "description": description,
            "inputSchema": schema
        ]
        tool["annotations"] = [
            "readOnlyHint": readOnly
        ]
        return tool
    }

    private func itemSelectorSchema(
        extraProperties: [String: Any],
        required: [String] = [],
        requiredAnySelector: Bool
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "item_id": [
                "type": "string",
                "description": "The Litrix item UUID."
            ],
            "doi": [
                "type": "string",
                "description": "The DOI of the item."
            ],
            "title": [
                "type": "string",
                "description": "The exact item title."
            ]
        ]
        for (key, value) in extraProperties {
            properties[key] = value
        }

        var schema: [String: Any] = [
            "type": "object",
            "properties": properties
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        if requiredAnySelector {
            schema["description"] = "Provide exactly one item selector: item_id, doi, or title. Litrix validates the selector at runtime."
        }
        return schema
    }

    private func managementSchema(entityDescription: String, supportsColor: Bool) -> [String: Any] {
        var properties: [String: Any] = [
            "action": [
                "type": "string",
                "description": supportsColor
                    ? "One of list, create, rename, delete, assign, unassign, set_color, clear_color."
                    : "One of list, create, rename, delete, assign, or unassign."
            ],
            "name": [
                "type": "string",
                "description": "The \(entityDescription) name to act on."
            ],
            "new_name": [
                "type": "string",
                "description": "New name for rename actions."
            ],
            "item_id": [
                "type": "string",
                "description": "Single Litrix item UUID."
            ],
            "item_ids": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Multiple Litrix item UUIDs."
            ]
        ]
        if supportsColor {
            properties["color_hex"] = [
                "type": "string",
                "description": "Hex color to assign to the tag."
            ]
        }

        return [
            "type": "object",
            "properties": properties,
            "required": ["action"]
        ]
    }

    private func metadataUpdateSchemaProperties() -> [String: Any] {
        metadataFieldDescriptors()
            .filter(\.editable)
            .reduce(into: [String: Any]()) { partial, field in
                partial[field.name] = field.jsonSchema
            }
    }

    private func metadataFieldDescriptors() -> [MetadataFieldDescriptor] {
        [
            MetadataFieldDescriptor(
                name: "id",
                displayName: "Item ID",
                description: "Stable Litrix UUID for the item.",
                valueType: "uuid",
                editable: false,
                hidden: true,
                group: "identity",
                jsonSchema: [
                    "type": "string",
                    "format": "uuid",
                    "description": "Stable Litrix UUID for the item."
                ]
            ),
            MetadataFieldDescriptor(
                name: "title",
                displayName: "Title",
                description: "Primary item title.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "core",
                jsonSchema: [
                    "type": "string",
                    "description": "Primary item title."
                ]
            ),
            MetadataFieldDescriptor(
                name: "englishTitle",
                displayName: "English Title",
                description: "Alternate English title.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "core",
                jsonSchema: [
                    "type": "string",
                    "description": "Alternate English title."
                ]
            ),
            MetadataFieldDescriptor(
                name: "authors",
                displayName: "Authors",
                description: "Primary author string.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "core",
                jsonSchema: [
                    "type": "string",
                    "description": "Primary author string."
                ]
            ),
            MetadataFieldDescriptor(
                name: "authorsEnglish",
                displayName: "Authors (English)",
                description: "English author string.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "core",
                jsonSchema: [
                    "type": "string",
                    "description": "English author string."
                ]
            ),
            MetadataFieldDescriptor(
                name: "searchMetadata",
                displayName: "Search Metadata",
                description: "Derived search index metadata computed from authors and used internally for search.",
                valueType: "object",
                editable: false,
                hidden: true,
                group: "internal",
                jsonSchema: [
                    "type": "object",
                    "description": "Derived search index metadata computed from authors.",
                    "properties": [
                        "authorNames": ["type": "array", "items": ["type": "string"]],
                        "normalizedAuthorTerms": ["type": "array", "items": ["type": "string"]],
                        "normalizedAuthorsBlob": ["type": "string"],
                        "authorCount": ["type": "integer"]
                    ]
                ]
            ),
            MetadataFieldDescriptor(
                name: "year",
                displayName: "Year",
                description: "Publication year.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "bibliographic",
                jsonSchema: [
                    "type": "string",
                    "description": "Publication year."
                ]
            ),
            MetadataFieldDescriptor(
                name: "source",
                displayName: "Source",
                description: "Journal, conference, book, or venue.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "bibliographic",
                jsonSchema: [
                    "type": "string",
                    "description": "Journal, conference, book, or venue."
                ]
            ),
            MetadataFieldDescriptor(
                name: "rating",
                displayName: "Rating",
                description: "Numeric rating clamped to the Litrix rating scale.",
                valueType: "integer",
                editable: true,
                hidden: false,
                group: "core",
                jsonSchema: [
                    "type": "integer",
                    "description": "Numeric rating clamped to the Litrix rating scale."
                ]
            ),
            MetadataFieldDescriptor(
                name: "doi",
                displayName: "DOI",
                description: "Digital Object Identifier.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "bibliographic",
                jsonSchema: [
                    "type": "string",
                    "description": "Digital Object Identifier."
                ]
            ),
            MetadataFieldDescriptor(
                name: "abstractText",
                displayName: "Abstract",
                description: "Abstract text in the source language.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "content",
                jsonSchema: [
                    "type": "string",
                    "description": "Abstract text in the source language."
                ]
            ),
            MetadataFieldDescriptor(
                name: "chineseAbstract",
                displayName: "Chinese Abstract",
                description: "Chinese-language abstract, translated or summarized from the source when needed.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "content",
                jsonSchema: [
                    "type": "string",
                    "description": "Chinese-language abstract."
                ]
            ),
            MetadataFieldDescriptor(
                name: "notes",
                displayName: "Notes",
                description: "Litrix note content stored with the item.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "content",
                jsonSchema: [
                    "type": "string",
                    "description": "Litrix note content stored with the item."
                ]
            ),
            MetadataFieldDescriptor(
                name: "collections",
                displayName: "Collections",
                description: "Collections assigned to the item.",
                valueType: "string[]",
                editable: true,
                hidden: false,
                group: "taxonomy",
                jsonSchema: [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Collections assigned to the item."
                ]
            ),
            MetadataFieldDescriptor(
                name: "tags",
                displayName: "Tags",
                description: "Tags assigned to the item.",
                valueType: "string[]",
                editable: true,
                hidden: false,
                group: "taxonomy",
                jsonSchema: [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Tags assigned to the item."
                ]
            ),
            MetadataFieldDescriptor(
                name: "paperType",
                displayName: "Paper Type",
                description: "Litrix paper type label.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "bibliographic",
                jsonSchema: [
                    "type": "string",
                    "description": "Litrix paper type label."
                ]
            ),
            MetadataFieldDescriptor(
                name: "volume",
                displayName: "Volume",
                description: "Volume metadata.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "bibliographic",
                jsonSchema: [
                    "type": "string",
                    "description": "Volume metadata."
                ]
            ),
            MetadataFieldDescriptor(
                name: "issue",
                displayName: "Issue",
                description: "Issue metadata.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "bibliographic",
                jsonSchema: [
                    "type": "string",
                    "description": "Issue metadata."
                ]
            ),
            MetadataFieldDescriptor(
                name: "pages",
                displayName: "Pages",
                description: "Page range metadata.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "bibliographic",
                jsonSchema: [
                    "type": "string",
                    "description": "Page range metadata."
                ]
            ),
            MetadataFieldDescriptor(
                name: "rqs",
                displayName: "Research Questions",
                description: "Research question notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Research question notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "conclusion",
                displayName: "Conclusion",
                description: "Conclusion notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Conclusion notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "results",
                displayName: "Results",
                description: "Results notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Results notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "category",
                displayName: "Category",
                description: "Category label.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Category label."
                ]
            ),
            MetadataFieldDescriptor(
                name: "impactFactor",
                displayName: "Impact Factor",
                description: "Impact factor or ranking notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Impact factor or ranking notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "samples",
                displayName: "Samples",
                description: "Sample description.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Sample description."
                ]
            ),
            MetadataFieldDescriptor(
                name: "participantType",
                displayName: "Participant Type",
                description: "Participant type description.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Participant type description."
                ]
            ),
            MetadataFieldDescriptor(
                name: "variables",
                displayName: "Variables",
                description: "Variables or constructs.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Variables or constructs."
                ]
            ),
            MetadataFieldDescriptor(
                name: "dataCollection",
                displayName: "Data Collection",
                description: "Data collection notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Data collection notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "dataAnalysis",
                displayName: "Data Analysis",
                description: "Data analysis notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Data analysis notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "methodology",
                displayName: "Methodology",
                description: "Methodology notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Methodology notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "theoreticalFoundation",
                displayName: "Theoretical Foundation",
                description: "Theoretical foundation notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Theoretical foundation notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "educationalLevel",
                displayName: "Educational Level",
                description: "Educational level label.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Educational level label."
                ]
            ),
            MetadataFieldDescriptor(
                name: "country",
                displayName: "Country",
                description: "Country or region label.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Country or region label."
                ]
            ),
            MetadataFieldDescriptor(
                name: "keywords",
                displayName: "Keywords",
                description: "Keyword string.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Keyword string."
                ]
            ),
            MetadataFieldDescriptor(
                name: "limitations",
                displayName: "Limitations",
                description: "Limitations notes.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "analysis",
                jsonSchema: [
                    "type": "string",
                    "description": "Limitations notes."
                ]
            ),
            MetadataFieldDescriptor(
                name: "webPageURL",
                displayName: "Web Page URL",
                description: "Original web page link used for browser import and web metadata refresh.",
                valueType: "string",
                editable: true,
                hidden: false,
                group: "bibliographic",
                jsonSchema: [
                    "type": "string",
                    "description": "Original web page link used for browser import and web metadata refresh."
                ]
            ),
            MetadataFieldDescriptor(
                name: "storageFolderName",
                displayName: "Storage Folder Name",
                description: "Internal paper folder name under the Litrix papers directory.",
                valueType: "string?",
                editable: true,
                hidden: true,
                group: "internal",
                jsonSchema: [
                    "type": ["string", "null"],
                    "description": "Internal paper folder name under the Litrix papers directory."
                ]
            ),
            MetadataFieldDescriptor(
                name: "storedPDFFileName",
                displayName: "Stored PDF File Name",
                description: "Internal PDF attachment file name.",
                valueType: "string?",
                editable: true,
                hidden: true,
                group: "internal",
                jsonSchema: [
                    "type": ["string", "null"],
                    "description": "Internal PDF attachment file name."
                ]
            ),
            MetadataFieldDescriptor(
                name: "originalPDFFileName",
                displayName: "Original PDF File Name",
                description: "Original imported PDF file name.",
                valueType: "string?",
                editable: true,
                hidden: true,
                group: "internal",
                jsonSchema: [
                    "type": ["string", "null"],
                    "description": "Original imported PDF file name."
                ]
            ),
            MetadataFieldDescriptor(
                name: "imageFileNames",
                displayName: "Image File Names",
                description: "Internal image attachment file names stored with the item.",
                valueType: "string[]",
                editable: true,
                hidden: true,
                group: "internal",
                jsonSchema: [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Internal image attachment file names stored with the item."
                ]
            ),
            MetadataFieldDescriptor(
                name: "addedAtMilliseconds",
                displayName: "Added At (ms)",
                description: "Item creation timestamp in Unix milliseconds.",
                valueType: "integer",
                editable: true,
                hidden: true,
                group: "timestamps",
                aliases: ["addedAt"],
                jsonSchema: [
                    "type": "integer",
                    "description": "Item creation timestamp in Unix milliseconds."
                ]
            ),
            MetadataFieldDescriptor(
                name: "importedAt",
                displayName: "Imported At",
                description: "Import timestamp as ISO-8601 text.",
                valueType: "datetime",
                editable: true,
                hidden: true,
                group: "timestamps",
                jsonSchema: [
                    "type": "string",
                    "format": "date-time",
                    "description": "Import timestamp as ISO-8601 text."
                ]
            ),
            MetadataFieldDescriptor(
                name: "lastOpenedAt",
                displayName: "Last Opened At",
                description: "Last-opened timestamp as ISO-8601 text or null.",
                valueType: "datetime?",
                editable: true,
                hidden: true,
                group: "timestamps",
                jsonSchema: [
                    "type": ["string", "null"],
                    "format": "date-time",
                    "description": "Last-opened timestamp as ISO-8601 text or null."
                ]
            ),
            MetadataFieldDescriptor(
                name: "lastEditedAtMilliseconds",
                displayName: "Last Edited At (ms)",
                description: "Last-edited timestamp in Unix milliseconds or null.",
                valueType: "integer?",
                editable: true,
                hidden: true,
                group: "timestamps",
                aliases: ["lastEditedAt"],
                jsonSchema: [
                    "type": ["integer", "null"],
                    "description": "Last-edited timestamp in Unix milliseconds or null."
                ]
            )
        ]
    }

    private func browseLibraryStructure(arguments: [String: Any]) throws -> [String: Any] {
        let includeCounts = boolValue(arguments["include_counts"]) ?? true
        let snapshot = store.currentLibrarySnapshot()
        let systemLibraries = SystemLibrary.allCases.map { library -> [String: Any] in
            var item: [String: Any] = [
                "id": library.rawValue,
                "title": library.title
            ]
            if includeCounts {
                item["count"] = store.count(for: .library(library))
            }
            return item
        }
        let collections = snapshot.collections.map { collection -> [String: Any] in
            var item: [String: Any] = ["name": collection]
            if includeCounts {
                item["count"] = store.count(for: .collection(collection))
            }
            return item
        }
        let tags = snapshot.tags.map { tag -> [String: Any] in
            var item: [String: Any] = ["name": tag]
            if includeCounts {
                item["count"] = store.count(for: .tag(tag))
            }
            if let color = snapshot.tagColorHexes[tag] {
                item["colorHex"] = color
            }
            return item
        }

        return [
            "library": [
                "paperCount": snapshot.papers.count,
                "systemLibraries": systemLibraries,
                "collections": collections,
                "tags": tags
            ]
        ]
    }

    private func describeMetadataFields(arguments: [String: Any]) -> [String: Any] {
        let includeHidden = boolValue(arguments["include_hidden"]) ?? true
        let editableOnly = boolValue(arguments["editable_only"]) ?? false
        let fields = metadataFieldDescriptors().filter { descriptor in
            (includeHidden || !descriptor.hidden) && (!editableOnly || descriptor.editable)
        }

        let payloadFields = fields.map { descriptor -> [String: Any] in
            [
                "name": descriptor.name,
                "displayName": descriptor.displayName,
                "description": descriptor.description,
                "valueType": descriptor.valueType,
                "editable": descriptor.editable,
                "hidden": descriptor.hidden,
                "group": descriptor.group,
                "aliases": descriptor.aliases,
                "jsonSchema": descriptor.jsonSchema
            ]
        }

        return [
            "fieldCount": payloadFields.count,
            "editableFieldCount": fields.filter(\.editable).count,
            "readOnlyFieldCount": fields.filter { !$0.editable }.count,
            "supportsPartialUpdate": true,
            "supportsFullUpdate": true,
            "fullUpdateInstructions": "To rewrite all editable metadata, pass every editable field to update_item_metadata.updates. To update only selected metadata, pass only those fields. Hidden/internal fields are included here when include_hidden=true.",
            "fields": payloadFields
        ]
    }

    private func searchLibrary(arguments: [String: Any]) throws -> [String: Any] {
        let query = try requiredNonEmptyString(arguments["query"], label: "query")
        let field = try optionalSearchField(arguments["field"])
        let scope = try parseSidebarSelection(arguments["scope"])
        let limit = resolvedLimit(arguments["limit"])
        let papers = store.filteredPapers(
            for: scope,
            searchText: query,
            searchField: field
        )
        let results = Array(papers.prefix(limit)).map { paperSummary($0) }
        return [
            "query": query,
            "scope": sidebarSelectionLabel(scope),
            "field": field?.rawValue as Any,
            "resultCount": papers.count,
            "returnedCount": results.count,
            "items": results
        ]
    }

    private func semanticSearch(arguments: [String: Any]) throws -> [String: Any] {
        let query = try requiredNonEmptyString(arguments["query"], label: "query")
        let scope = try parseSidebarSelection(arguments["scope"])
        let limit = resolvedLimit(arguments["limit"])
        let candidatePapers = store.filteredPapers(for: scope, searchText: "")
        let scored = scorePapers(query: query, papers: candidatePapers)
        let items = Array(scored.prefix(limit)).map { scoredPaper in
            paperSummary(scoredPaper.paper, score: scoredPaper.score, matchedTerms: scoredPaper.matchedTerms)
        }
        return [
            "query": query,
            "scope": sidebarSelectionLabel(scope),
            "backend": "weighted_metadata_similarity",
            "resultCount": scored.count,
            "returnedCount": items.count,
            "items": items
        ]
    }

    private func readItemMetadata(arguments: [String: Any]) throws -> [String: Any] {
        let paper = try resolvePaper(arguments: arguments)
        return [
            "item": paperMetadata(paper, includePaths: false)
        ]
    }

    private func updateItemMetadata(arguments: [String: Any]) throws -> [String: Any] {
        let mode = try metadataUpdateMode(arguments["mode"])
        let updates = try normalizedMetadataUpdates(
            try requiredDictionary(arguments["updates"], label: "updates")
        )
        let existingPaper = try resolvePaper(arguments: arguments)
        var paper = mode == .replace ? replacementBaseline(for: existingPaper) : existingPaper
        try applyMetadataUpdates(updates, to: &paper)
        let refreshed = try persistPaperUpdate(
            from: existingPaper,
            updated: paper,
            preserveExplicitLastEditedTimestamp: updates.keys.contains("lastEditedAtMilliseconds")
        )
        return [
            "updated": true,
            "mode": mode.rawValue,
            "updatedFields": updates.keys.sorted(),
            "item": paperMetadata(refreshed, includePaths: false)
        ]
    }

    private func readAbstract(arguments: [String: Any]) throws -> [String: Any] {
        let paper = try resolvePaper(arguments: arguments)
        let maxChars = resolvedOptionalCharLimit(arguments["max_chars"])
        let abstractText = limitedText(paper.abstractText, maxChars: maxChars)
        let chineseAbstract = limitedText(paper.chineseAbstract, maxChars: maxChars)
        return [
            "item": minimalItemIdentity(paper),
            "abstract": abstractText,
            "abstractLength": paper.abstractText.count,
            "chineseAbstract": chineseAbstract,
            "chineseAbstractLength": paper.chineseAbstract.count
        ]
    }

    private func readFullText(arguments: [String: Any]) throws -> [String: Any] {
        let paper = try resolvePaper(arguments: arguments)
        let startChar = max(0, intValue(arguments["start_char"]) ?? 0)
        let maxChars = resolvedOptionalCharLimit(arguments["max_chars"]) ?? settings.mcpMaxContentLength
        let extraction = try fullText(for: paper)
        let text = extraction.text
        let safeStart = min(startChar, text.count)
        let startIndex = text.index(text.startIndex, offsetBy: safeStart)
        let endIndex = text.index(startIndex, offsetBy: min(maxChars, text.distance(from: startIndex, to: text.endIndex)))
        let slice = String(text[startIndex..<endIndex])

        return [
            "item": minimalItemIdentity(paper),
            "pageCount": extraction.pageCount,
            "charCount": text.count,
            "returnedStart": safeStart,
            "returnedLength": slice.count,
            "cached": extraction.cached,
            "cacheTruncated": extraction.isTruncatedInCache,
            "text": slice
        ]
    }

    private func searchAnnotations(arguments: [String: Any]) throws -> [String: Any] {
        let query = try requiredNonEmptyString(arguments["query"], label: "query")
        let scope = try parseSidebarSelection(arguments["scope"])
        let limit = resolvedLimit(arguments["limit"])
        let normalizedQuery = normalizedTextToken(query)
        let matches = store.filteredPapers(for: scope, searchText: "")
            .compactMap { paper -> [String: Any]? in
                guard paper.notes.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || normalizedTextToken(paper.notes).contains(normalizedQuery) else {
                    return nil
                }
                let excerpt = excerptAroundMatch(in: paper.notes, query: query, maximumLength: 260)
                var item = paperSummary(paper)
                item["noteExcerpt"] = excerpt
                return item
            }

        return [
            "query": query,
            "scope": sidebarSelectionLabel(scope),
            "resultCount": matches.count,
            "returnedCount": min(limit, matches.count),
            "items": Array(matches.prefix(limit))
        ]
    }

    private func findSimilar(arguments: [String: Any]) throws -> [String: Any] {
        let seedPaper = try resolvePaper(arguments: arguments)
        let limit = resolvedLimit(arguments["limit"])
        let query = similaritySeedText(for: seedPaper)
        let candidates = store.currentLibrarySnapshot().papers.filter { $0.id != seedPaper.id }
        let scored = scorePapers(query: query, papers: candidates)
        let items = Array(scored.prefix(limit)).map { scoredPaper in
            paperSummary(scoredPaper.paper, score: scoredPaper.score, matchedTerms: scoredPaper.matchedTerms)
        }

        return [
            "seedItem": minimalItemIdentity(seedPaper),
            "backend": "weighted_metadata_similarity",
            "resultCount": scored.count,
            "returnedCount": items.count,
            "items": items
        ]
    }

    private func itemDetails(arguments: [String: Any]) throws -> [String: Any] {
        let paper = try resolvePaper(arguments: arguments)
        let includePreview = boolValue(arguments["include_fulltext_preview"]) ?? false
        var item = paperMetadata(paper, includePaths: true)
        if includePreview {
            let maxChars = resolvedOptionalCharLimit(arguments["max_chars"]) ?? settings.mcpMaxContentLength
            if let extraction = try? fullText(for: paper) {
                item["fulltextPreview"] = limitedText(extraction.text, maxChars: maxChars)
                item["fulltextPageCount"] = extraction.pageCount
                item["fulltextCached"] = extraction.cached
            }
        }
        return [
            "item": item
        ]
    }

    private func fullTextCacheStats() -> [String: Any] {
        let cachedCharacters = fullTextCache.values.reduce(0) { $0 + $1.text.count }
        return [
            "backend": "in_memory_pdf_text_cache",
            "cachedItems": fullTextCache.count,
            "cacheHits": fullTextCacheHits,
            "cacheMisses": fullTextCacheMisses,
            "cachedCharacters": cachedCharacters,
            "maximumCachedFullTextLength": maximumCachedFullTextLength
        ]
    }

    private func semanticIndexStatus() -> [String: Any] {
        [
            "semanticSearchAvailable": true,
            "backend": "weighted_metadata_similarity",
            "embeddingIndexAvailable": false,
            "notes": "Current semantic search is implemented with weighted metadata and note-text overlap. No embedding index is built yet.",
            "fulltextCache": fullTextCacheStats()
        ]
    }

    private func manageCollections(arguments: [String: Any]) throws -> [String: Any] {
        let action = try requiredNonEmptyString(arguments["action"], label: "action").lowercased()
        switch action {
        case "list":
            let snapshot = store.currentLibrarySnapshot()
            let items = snapshot.collections.map { name in
                [
                    "name": name,
                    "count": store.count(for: .collection(name))
                ]
            }
            return [
                "action": action,
                "collections": items
            ]
        case "create":
            let name = try requiredNonEmptyString(arguments["name"], label: "name")
            store.createCollection(named: name)
            return [
                "action": action,
                "collection": name
            ]
        case "rename":
            let oldName = try requiredNonEmptyString(arguments["name"], label: "name")
            let newName = try requiredNonEmptyString(arguments["new_name"], label: "new_name")
            store.renameCollection(oldName: oldName, newName: newName)
            return [
                "action": action,
                "from": oldName,
                "to": newName
            ]
        case "delete":
            let name = try requiredNonEmptyString(arguments["name"], label: "name")
            store.deleteCollection(named: name)
            return [
                "action": action,
                "collection": name
            ]
        case "assign", "unassign":
            let name = try requiredNonEmptyString(arguments["name"], label: "name")
            let paperIDs = try resolvePaperIDs(arguments: arguments)
            store.setCollection(name, assigned: action == "assign", forPaperIDs: paperIDs)
            return [
                "action": action,
                "collection": name,
                "itemIDs": paperIDs.map(\.uuidString)
            ]
        default:
            throw ToolServiceError.invalidArguments("Unsupported collection action: \(action)")
        }
    }

    private func manageTags(arguments: [String: Any]) throws -> [String: Any] {
        let action = try requiredNonEmptyString(arguments["action"], label: "action").lowercased()
        switch action {
        case "list":
            let snapshot = store.currentLibrarySnapshot()
            let items = snapshot.tags.map { name -> [String: Any] in
                var item: [String: Any] = [
                    "name": name,
                    "count": store.count(for: .tag(name))
                ]
                if let color = snapshot.tagColorHexes[name] {
                    item["colorHex"] = color
                }
                return item
            }
            return [
                "action": action,
                "tags": items
            ]
        case "create":
            let name = try requiredNonEmptyString(arguments["name"], label: "name")
            store.createTag(named: name)
            return [
                "action": action,
                "tag": name
            ]
        case "rename":
            let oldName = try requiredNonEmptyString(arguments["name"], label: "name")
            let newName = try requiredNonEmptyString(arguments["new_name"], label: "new_name")
            store.renameTag(oldName: oldName, newName: newName)
            return [
                "action": action,
                "from": oldName,
                "to": newName
            ]
        case "delete":
            let name = try requiredNonEmptyString(arguments["name"], label: "name")
            store.deleteTag(named: name)
            return [
                "action": action,
                "tag": name
            ]
        case "assign", "unassign":
            let name = try requiredNonEmptyString(arguments["name"], label: "name")
            let paperIDs = try resolvePaperIDs(arguments: arguments)
            store.setTag(name, assigned: action == "assign", forPaperIDs: paperIDs)
            return [
                "action": action,
                "tag": name,
                "itemIDs": paperIDs.map(\.uuidString)
            ]
        case "set_color":
            let name = try requiredNonEmptyString(arguments["name"], label: "name")
            let color = try requiredNonEmptyString(arguments["color_hex"], label: "color_hex")
            store.setTagColor(hex: color, forTag: name)
            return [
                "action": action,
                "tag": name,
                "colorHex": color
            ]
        case "clear_color":
            let name = try requiredNonEmptyString(arguments["name"], label: "name")
            store.setTagColor(hex: nil, forTag: name)
            return [
                "action": action,
                "tag": name,
                "colorHex": NSNull()
            ]
        default:
            throw ToolServiceError.invalidArguments("Unsupported tag action: \(action)")
        }
    }

    private func createOrUpdateItems(arguments: [String: Any]) throws -> [String: Any] {
        let mode = (stringValue(arguments["mode"]) ?? "upsert").lowercased()
        let itemValues = try normalizedMetadataUpdates(
            try requiredDictionary(arguments["item"], label: "item")
        )
        let existingPaper = try resolvePaperIfPresent(arguments: arguments)

        switch mode {
        case "create":
            guard existingPaper == nil else {
                throw ToolServiceError.conflict("Create mode matched an existing item. Use update or upsert instead.")
            }
            let created = try createPaper(from: itemValues)
            return [
                "mode": mode,
                "created": true,
                "item": paperMetadata(created, includePaths: false)
            ]
        case "update":
            guard let originalPaper = existingPaper else {
                throw ToolServiceError.notFound("Update mode did not match any existing item.")
            }
            var updatedPaper = originalPaper
            try applyMetadataUpdates(itemValues, to: &updatedPaper)
            let refreshed = try persistPaperUpdate(
                from: originalPaper,
                updated: updatedPaper,
                preserveExplicitLastEditedTimestamp: itemValues.keys.contains("lastEditedAtMilliseconds")
            )
            return [
                "mode": mode,
                "updated": true,
                "item": paperMetadata(refreshed, includePaths: false)
            ]
        case "upsert":
            if let originalPaper = existingPaper {
                var updatedPaper = originalPaper
                try applyMetadataUpdates(itemValues, to: &updatedPaper)
                let refreshed = try persistPaperUpdate(
                    from: originalPaper,
                    updated: updatedPaper,
                    preserveExplicitLastEditedTimestamp: itemValues.keys.contains("lastEditedAtMilliseconds")
                )
                return [
                    "mode": mode,
                    "created": false,
                    "updated": true,
                    "item": paperMetadata(refreshed, includePaths: false)
                ]
            }
            let created = try createPaper(from: itemValues)
            return [
                "mode": mode,
                "created": true,
                "updated": false,
                "item": paperMetadata(created, includePaths: false)
            ]
        default:
            throw ToolServiceError.invalidArguments("Unsupported mode: \(mode)")
        }
    }

    private func createOrAppendNotes(arguments: [String: Any]) throws -> [String: Any] {
        let mode = (stringValue(arguments["mode"]) ?? "append").lowercased()
        let text = try requiredString(arguments["text"], label: "text")
        var paper = try resolvePaper(arguments: arguments)

        switch mode {
        case "replace":
            paper.notes = text
        case "append":
            if paper.notes.isEmpty {
                paper.notes = text
            } else {
                let separator = stringValue(arguments["separator"]) ?? "\n\n"
                paper.notes += "\(separator)\(text)"
            }
        default:
            throw ToolServiceError.invalidArguments("Unsupported note mode: \(mode)")
        }

        store.updatePaper(paper)
        guard let refreshed = store.paper(id: paper.id) else {
            throw ToolServiceError.execution("Updated note could not be reloaded.")
        }

        return [
            "mode": mode,
            "item": minimalItemIdentity(refreshed),
            "noteLength": refreshed.notes.count,
            "notePreview": limitedText(refreshed.notes, maxChars: 320)
        ]
    }

    private func createPaper(from itemValues: [String: Any]) throws -> Paper {
        var paper = Paper()
        try applyMetadataUpdates(itemValues, to: &paper)
        try ensureStorageFolderExistsIfNeeded(for: paper)

        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let doi = normalizedDOI(paper.doi)
        if title.isEmpty, doi.isEmpty {
            throw ToolServiceError.invalidArguments("New items must include at least a title or DOI.")
        }

        if duplicatePaperExists(title: title, doi: doi) {
            throw ToolServiceError.conflict("A Litrix item with the same DOI or normalized title already exists.")
        }

        var snapshot = store.currentLibrarySnapshot()
        snapshot.papers.insert(paper, at: 0)
        store.restoreLibrarySnapshot(snapshot)

        guard let created = store.paper(id: paper.id) else {
            throw ToolServiceError.execution("Created item could not be reloaded.")
        }
        return created
    }

    private func duplicatePaperExists(title: String, doi: String) -> Bool {
        let normalizedTitleValue = normalizedTitle(title)
        return store.currentLibrarySnapshot().papers.contains { paper in
            if !doi.isEmpty && normalizedDOI(paper.doi) == doi {
                return true
            }
            if !normalizedTitleValue.isEmpty && normalizedTitle(paper.title) == normalizedTitleValue {
                return true
            }
            return false
        }
    }

    private func metadataUpdateMode(_ rawValue: Any?) throws -> MetadataUpdateMode {
        guard let rawMode = nonEmptyTrimmedString(rawValue) else {
            return .merge
        }
        guard let mode = MetadataUpdateMode(rawValue: rawMode.lowercased()) else {
            throw ToolServiceError.invalidArguments("mode must be merge or replace.")
        }
        return mode
    }

    private func replacementBaseline(for paper: Paper) -> Paper {
        Paper(id: paper.id)
    }

    private func normalizedMetadataUpdates(_ updates: [String: Any]) throws -> [String: Any] {
        guard !updates.isEmpty else {
            throw ToolServiceError.invalidArguments("updates/item cannot be empty.")
        }

        let descriptors = metadataFieldDescriptors()
        let editableFields = Set(descriptors.filter(\.editable).map(\.name))
        let readOnlyFields = Set(descriptors.filter { !$0.editable }.map(\.name))
        let aliasMap = descriptors.reduce(into: [String: String]()) { partial, descriptor in
            for alias in descriptor.aliases {
                partial[alias] = descriptor.name
            }
        }

        var normalized: [String: Any] = [:]
        for (rawKey, value) in updates {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw ToolServiceError.invalidArguments("Metadata field names cannot be empty.")
            }

            let canonicalKey: String
            if editableFields.contains(key) {
                canonicalKey = key
            } else if let aliased = aliasMap[key] {
                canonicalKey = aliased
            } else if readOnlyFields.contains(key) {
                throw ToolServiceError.invalidArguments("Field \(key) is read-only and cannot be updated.")
            } else {
                throw ToolServiceError.invalidArguments("Unsupported editable field: \(key)")
            }

            if normalized[canonicalKey] != nil {
                throw ToolServiceError.conflict("Metadata field \(canonicalKey) was provided more than once.")
            }
            normalized[canonicalKey] = value
        }

        return normalized
    }

    private func persistPaperUpdate(
        from existing: Paper,
        updated: Paper,
        preserveExplicitLastEditedTimestamp: Bool
    ) throws -> Paper {
        var updated = updated
        try synchronizeAssetBackedMetadata(from: existing, to: &updated)
        store.updatePaper(
            updated,
            preserveExplicitLastEditedTimestamp: preserveExplicitLastEditedTimestamp
        )
        guard let refreshed = store.paper(id: updated.id) else {
            throw ToolServiceError.execution("Updated item could not be reloaded.")
        }
        return refreshed
    }

    private func synchronizeAssetBackedMetadata(from existing: Paper, to updated: inout Paper) throws {
        try synchronizeStoredPDFFileIfNeeded(from: existing, to: &updated)
        try synchronizeImageFilesIfNeeded(from: existing, to: &updated)
        try synchronizeStorageFolderIfNeeded(from: existing, to: &updated)
    }

    private func synchronizeStoredPDFFileIfNeeded(from existing: Paper, to updated: inout Paper) throws {
        guard existing.storedPDFFileName != updated.storedPDFFileName else { return }
        guard let currentURL = store.pdfURL(for: existing),
              fileManager.fileExists(atPath: currentURL.path) else {
            return
        }

        guard let targetFileName = updated.storedPDFFileName else {
            throw ToolServiceError.invalidArguments("storedPDFFileName cannot be cleared while the item still has a stored PDF attachment.")
        }

        let destinationURL = currentURL.deletingLastPathComponent()
            .appendingPathComponent(targetFileName, isDirectory: false)
        guard destinationURL.standardizedFileURL != currentURL.standardizedFileURL else { return }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ToolServiceError.conflict("A file named \(targetFileName) already exists in the paper folder.")
        }

        do {
            try fileManager.moveItem(at: currentURL, to: destinationURL)
            updated.storedPDFFileName = destinationURL.lastPathComponent
        } catch {
            throw ToolServiceError.execution("Failed to rename the stored PDF attachment: \(error.localizedDescription)")
        }
    }

    private func synchronizeImageFilesIfNeeded(from existing: Paper, to updated: inout Paper) throws {
        guard existing.imageFileNames != updated.imageFileNames else { return }

        let existingNames = existing.imageFileNames
        let updatedNames = updated.imageFileNames

        if existingNames.isEmpty {
            if !updatedNames.isEmpty {
                throw ToolServiceError.invalidArguments("imageFileNames cannot create new image attachments. Use image import workflows instead.")
            }
            return
        }

        guard existingNames.count == updatedNames.count else {
            throw ToolServiceError.invalidArguments("imageFileNames can rename existing image attachments, but cannot change the number of image attachments.")
        }

        guard let directoryURL = store.imageDirectoryURL(for: existing) else {
            throw ToolServiceError.execution("The item has image metadata but no storage folder.")
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let renamePairs = Array(zip(existingNames, updatedNames)).filter { $0.0 != $0.1 }
        guard !renamePairs.isEmpty else { return }

        let renamedSourceNames = Set(renamePairs.map { $0.0 })
        for (_, targetName) in renamePairs {
            let destinationURL = directoryURL.appendingPathComponent(targetName, isDirectory: false)
            if fileManager.fileExists(atPath: destinationURL.path),
               !renamedSourceNames.contains(targetName) {
                throw ToolServiceError.conflict("A file named \(targetName) already exists in the paper folder.")
            }
        }

        var stagedMoves: [(temporaryURL: URL, destinationURL: URL)] = []
        do {
            for (sourceName, targetName) in renamePairs {
                let sourceURL = store.imageURL(for: existing, fileName: sourceName)
                    ?? directoryURL.appendingPathComponent(sourceName, isDirectory: false)
                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

                let temporaryURL = directoryURL.appendingPathComponent(
                    ".litrix-mcp-image-temp-\(UUID().uuidString)",
                    isDirectory: false
                )
                try fileManager.moveItem(at: sourceURL, to: temporaryURL)
                let destinationURL = directoryURL.appendingPathComponent(targetName, isDirectory: false)
                stagedMoves.append((temporaryURL: temporaryURL, destinationURL: destinationURL))
            }

            for move in stagedMoves {
                try fileManager.moveItem(at: move.temporaryURL, to: move.destinationURL)
            }
        } catch {
            for move in stagedMoves {
                if fileManager.fileExists(atPath: move.temporaryURL.path),
                   !fileManager.fileExists(atPath: move.destinationURL.path) {
                    try? fileManager.moveItem(at: move.temporaryURL, to: move.destinationURL)
                }
            }
            throw ToolServiceError.execution("Failed to rename image attachments: \(error.localizedDescription)")
        }
    }

    private func synchronizeStorageFolderIfNeeded(from existing: Paper, to updated: inout Paper) throws {
        guard existing.storageFolderName != updated.storageFolderName else { return }

        if let currentDirectoryURL = store.paperDirectoryURL(for: existing),
           fileManager.fileExists(atPath: currentDirectoryURL.path) {
            guard let destinationDirectoryURL = store.paperDirectoryURL(for: updated) else {
                throw ToolServiceError.invalidArguments("storageFolderName cannot be cleared while the item still has stored assets.")
            }
            guard destinationDirectoryURL.standardizedFileURL != currentDirectoryURL.standardizedFileURL else { return }
            guard !fileManager.fileExists(atPath: destinationDirectoryURL.path) else {
                throw ToolServiceError.conflict("A paper folder named \(destinationDirectoryURL.lastPathComponent) already exists.")
            }

            do {
                try fileManager.moveItem(at: currentDirectoryURL, to: destinationDirectoryURL)
                try ensureStorageFolderExistsIfNeeded(for: updated)
            } catch {
                throw ToolServiceError.execution("Failed to rename the paper storage folder: \(error.localizedDescription)")
            }
            return
        }

        guard let destinationDirectoryURL = store.paperDirectoryURL(for: updated) else { return }
        try ensureStorageFolderExistsIfNeeded(for: updated)

        if let legacyPDFURL = store.pdfURL(for: existing),
           fileManager.fileExists(atPath: legacyPDFURL.path) {
            let targetFileName = updated.storedPDFFileName ?? legacyPDFURL.lastPathComponent
            let destinationPDFURL = destinationDirectoryURL.appendingPathComponent(targetFileName, isDirectory: false)
            if destinationPDFURL.standardizedFileURL != legacyPDFURL.standardizedFileURL {
                guard !fileManager.fileExists(atPath: destinationPDFURL.path) else {
                    throw ToolServiceError.conflict("A file named \(targetFileName) already exists in the destination paper folder.")
                }
                do {
                    try fileManager.moveItem(at: legacyPDFURL, to: destinationPDFURL)
                } catch {
                    throw ToolServiceError.execution("Failed to move the legacy PDF into the paper folder: \(error.localizedDescription)")
                }
            }
            updated.storedPDFFileName = destinationPDFURL.lastPathComponent
            if updated.originalPDFFileName == nil {
                updated.originalPDFFileName = existing.originalPDFFileName ?? legacyPDFURL.lastPathComponent
            }
        }
    }

    private func ensureStorageFolderExistsIfNeeded(for paper: Paper) throws {
        guard let folderURL = store.paperDirectoryURL(for: paper) else { return }
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            throw ToolServiceError.execution("Failed to create the paper storage folder: \(error.localizedDescription)")
        }
    }

    private func searchMetadataPayload(_ metadata: PaperSearchMetadata) -> [String: Any] {
        [
            "authorNames": metadata.authorNames,
            "normalizedAuthorTerms": metadata.normalizedAuthorTerms,
            "normalizedAuthorsBlob": metadata.normalizedAuthorsBlob,
            "authorCount": metadata.authorCount
        ]
    }

    private func applyMetadataUpdates(_ updates: [String: Any], to paper: inout Paper) throws {
        guard !updates.isEmpty else {
            throw ToolServiceError.invalidArguments("updates/item cannot be empty.")
        }

        for key in updates.keys.sorted() {
            let value = updates[key]
            switch key {
            case "title":
                paper.title = try requiredString(value, label: key)
            case "englishTitle":
                paper.englishTitle = try requiredString(value, label: key)
            case "authors":
                paper.authors = try requiredString(value, label: key)
            case "authorsEnglish":
                paper.authorsEnglish = try requiredString(value, label: key)
            case "year":
                paper.year = try requiredString(value, label: key)
            case "source":
                paper.source = try requiredString(value, label: key)
            case "rating":
                guard let rating = intValue(value) else {
                    throw ToolServiceError.invalidArguments("rating must be an integer.")
                }
                paper.rating = PaperRatingScale.clamped(rating)
            case "doi":
                paper.doi = try requiredString(value, label: key)
            case "abstractText":
                paper.abstractText = try requiredString(value, label: key)
            case "chineseAbstract":
                paper.chineseAbstract = try requiredString(value, label: key)
            case "notes":
                paper.notes = try requiredString(value, label: key)
            case "collections":
                paper.collections = try normalizedStringArray(value, label: key)
            case "tags":
                paper.tags = try normalizedStringArray(value, label: key)
            case "paperType":
                paper.paperType = try requiredString(value, label: key)
            case "volume":
                paper.volume = try requiredString(value, label: key)
            case "issue":
                paper.issue = try requiredString(value, label: key)
            case "pages":
                paper.pages = try requiredString(value, label: key)
            case "rqs":
                paper.rqs = try requiredString(value, label: key)
            case "conclusion":
                paper.conclusion = try requiredString(value, label: key)
            case "results":
                paper.results = try requiredString(value, label: key)
            case "category":
                paper.category = try requiredString(value, label: key)
            case "impactFactor":
                paper.impactFactor = try requiredString(value, label: key)
            case "samples":
                paper.samples = try requiredString(value, label: key)
            case "participantType":
                paper.participantType = try requiredString(value, label: key)
            case "variables":
                paper.variables = try requiredString(value, label: key)
            case "dataCollection":
                paper.dataCollection = try requiredString(value, label: key)
            case "dataAnalysis":
                paper.dataAnalysis = try requiredString(value, label: key)
            case "methodology":
                paper.methodology = try requiredString(value, label: key)
            case "theoreticalFoundation":
                paper.theoreticalFoundation = try requiredString(value, label: key)
            case "educationalLevel":
                paper.educationalLevel = try requiredString(value, label: key)
            case "country":
                paper.country = try requiredString(value, label: key)
            case "keywords":
                paper.keywords = try requiredString(value, label: key)
            case "limitations":
                paper.limitations = try requiredString(value, label: key)
            case "webPageURL":
                paper.webPageURL = try requiredString(value, label: key)
            case "storageFolderName":
                paper.storageFolderName = try optionalPathComponent(value, label: key)
            case "storedPDFFileName":
                paper.storedPDFFileName = try optionalFileName(value, label: key)
            case "originalPDFFileName":
                paper.originalPDFFileName = try optionalFileName(value, label: key)
            case "imageFileNames":
                paper.imageFileNames = try normalizedFileNameArray(value, label: key)
            case "addedAtMilliseconds":
                guard let timestamp = try int64OrNilValue(value, label: key) else {
                    throw ToolServiceError.invalidArguments("\(key) cannot be null.")
                }
                paper.addedAtMilliseconds = timestamp
            case "importedAt":
                guard let importedAt = try dateValue(value, label: key) else {
                    throw ToolServiceError.invalidArguments("\(key) must be a valid ISO-8601 datetime.")
                }
                paper.importedAt = importedAt
            case "lastOpenedAt":
                paper.lastOpenedAt = try dateValue(value, label: key)
            case "lastEditedAtMilliseconds":
                paper.lastEditedAtMilliseconds = try int64OrNilValue(value, label: key)
            default:
                throw ToolServiceError.invalidArguments("Unsupported editable field: \(key)")
            }
        }
    }

    private func resolvePaper(arguments: [String: Any]) throws -> Paper {
        if let paper = try resolvePaperIfPresent(arguments: arguments) {
            return paper
        }
        throw ToolServiceError.notFound("No Litrix item matched the provided selector.")
    }

    private func resolvePaperIfPresent(arguments: [String: Any]) throws -> Paper? {
        let papers = store.currentLibrarySnapshot().papers

        if let idString = nonEmptyTrimmedString(arguments["item_id"]) {
            guard let id = UUID(uuidString: idString) else {
                throw ToolServiceError.invalidArguments("item_id must be a valid UUID.")
            }
            return papers.first(where: { $0.id == id })
        }

        if let doi = nonEmptyTrimmedString(arguments["doi"]) {
            let normalized = normalizedDOI(doi)
            return papers.first(where: { normalizedDOI($0.doi) == normalized })
        }

        if let title = nonEmptyTrimmedString(arguments["title"]) {
            let normalized = normalizedTitle(title)
            let matches = papers.filter { normalizedTitle($0.title) == normalized }
            if matches.count > 1 {
                let candidates = matches.prefix(5).map { "\($0.id.uuidString) | \($0.title)" }.joined(separator: "\n")
                throw ToolServiceError.conflict("Title selector matched multiple items. Use item_id instead.\n\(candidates)")
            }
            return matches.first
        }

        return nil
    }

    private func resolvePaperIDs(arguments: [String: Any]) throws -> [UUID] {
        if let rawIDs = arguments["item_ids"] as? [Any] {
            let ids = try rawIDs.map { raw -> UUID in
                guard let string = raw as? String, let id = UUID(uuidString: string) else {
                    throw ToolServiceError.invalidArguments("item_ids must contain only UUID strings.")
                }
                return id
            }
            return Array(Set(ids))
        }

        let paper = try resolvePaper(arguments: arguments)
        return [paper.id]
    }

    private func parseSidebarSelection(_ rawValue: Any?) throws -> SidebarSelection {
        guard let rawScope = nonEmptyTrimmedString(rawValue) else {
            return .library(.all)
        }

        if let system = SystemLibrary(rawValue: rawScope) {
            return .library(system)
        }
        if rawScope.hasPrefix("collection:") {
            let name = String(rawScope.dropFirst("collection:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw ToolServiceError.invalidArguments("collection scope requires a name.")
            }
            return .collection(name)
        }
        if rawScope.hasPrefix("tag:") {
            let name = String(rawScope.dropFirst("tag:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw ToolServiceError.invalidArguments("tag scope requires a name.")
            }
            return .tag(name)
        }

        throw ToolServiceError.invalidArguments("Unsupported scope: \(rawScope)")
    }

    private func optionalSearchField(_ rawValue: Any?) throws -> AdvancedSearchField? {
        guard let rawField = nonEmptyTrimmedString(rawValue) else { return nil }
        guard let field = AdvancedSearchField(rawValue: rawField) else {
            throw ToolServiceError.invalidArguments("Unsupported search field: \(rawField)")
        }
        return field
    }

    private func resolvedLimit(_ rawValue: Any?) -> Int {
        let requested = intValue(rawValue) ?? settings.mcpSearchResultLimit
        return max(1, min(settings.mcpSearchResultLimit, requested))
    }

    private func resolvedOptionalCharLimit(_ rawValue: Any?) -> Int? {
        guard let requested = intValue(rawValue) else { return nil }
        return max(1, min(settings.mcpMaxContentLength, requested))
    }

    private func paperSummary(
        _ paper: Paper,
        score: Double? = nil,
        matchedTerms: [String] = []
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": paper.id.uuidString,
            "title": paper.title,
            "authors": paper.authors,
            "year": paper.year,
            "source": paper.source,
            "doi": paper.doi,
            "webPageURL": paper.webPageURL,
            "collections": paper.collections,
            "tags": paper.tags,
            "hasPDF": store.hasExistingPDFAttachment(for: paper)
        ]
        if let score {
            result["score"] = round(score * 1000) / 1000
        }
        if !matchedTerms.isEmpty {
            result["matchedTerms"] = matchedTerms
        }
        return result
    }

    private func minimalItemIdentity(_ paper: Paper) -> [String: Any] {
        [
            "id": paper.id.uuidString,
            "title": paper.title,
            "doi": paper.doi
        ]
    }

    private func paperMetadata(_ paper: Paper, includePaths: Bool) -> [String: Any] {
        var result: [String: Any] = [
            "id": paper.id.uuidString,
            "title": paper.title,
            "englishTitle": paper.englishTitle,
            "authors": paper.authors,
            "authorsEnglish": paper.authorsEnglish,
            "searchMetadata": searchMetadataPayload(paper.searchMetadata),
            "year": paper.year,
            "source": paper.source,
            "rating": paper.rating,
            "doi": paper.doi,
            "abstractText": paper.abstractText,
            "chineseAbstract": paper.chineseAbstract,
            "notes": paper.notes,
            "collections": paper.collections,
            "tags": paper.tags,
            "paperType": paper.paperType,
            "volume": paper.volume,
            "issue": paper.issue,
            "pages": paper.pages,
            "rqs": paper.rqs,
            "conclusion": paper.conclusion,
            "results": paper.results,
            "category": paper.category,
            "impactFactor": paper.impactFactor,
            "samples": paper.samples,
            "participantType": paper.participantType,
            "variables": paper.variables,
            "dataCollection": paper.dataCollection,
            "dataAnalysis": paper.dataAnalysis,
            "methodology": paper.methodology,
            "theoreticalFoundation": paper.theoreticalFoundation,
            "educationalLevel": paper.educationalLevel,
            "country": paper.country,
            "keywords": paper.keywords,
            "limitations": paper.limitations,
            "webPageURL": paper.webPageURL,
            "storageFolderName": paper.storageFolderName as Any,
            "storedPDFFileName": paper.storedPDFFileName as Any,
            "originalPDFFileName": paper.originalPDFFileName as Any,
            "imageFileNames": paper.imageFileNames,
            "addedAtMilliseconds": paper.addedAtMilliseconds,
            "addedAt": isoFormatter.string(from: paper.addedAtDate),
            "importedAt": isoFormatter.string(from: paper.importedAt),
            "lastOpenedAt": paper.lastOpenedAt.map(isoFormatter.string(from:)) as Any,
            "lastEditedAtMilliseconds": paper.lastEditedAtMilliseconds as Any,
            "lastEditedAt": paper.editedAtDate.map(isoFormatter.string(from:)) as Any,
            "hasPDF": store.hasExistingPDFAttachment(for: paper)
        ]

        if includePaths {
            result["pdfPath"] = store.pdfURL(for: paper)?.path as Any
            result["notePath"] = store.noteURL(for: paper)?.path as Any
            result["paperDirectoryPath"] = store.paperDirectoryURL(for: paper)?.path as Any
            result["imagePaths"] = store.imageURLs(for: paper).map(\.path)
        }

        return result
    }

    private func scorePapers(query: String, papers: [Paper]) -> [SimilarityScoredPaper] {
        let tokens = queryTokens(from: query)
        guard !tokens.isEmpty else { return [] }
        let normalizedQuery = normalizedTextToken(query)

        let fieldWeights: [(String, (Paper) -> String, Double)] = [
            ("title", \.title, 8),
            ("englishTitle", \.englishTitle, 7),
            ("keywords", \.keywords, 6),
            ("abstractText", \.abstractText, 6),
            ("chineseAbstract", \.chineseAbstract, 6),
            ("results", \.results, 5),
            ("conclusion", \.conclusion, 5),
            ("rqs", \.rqs, 4),
            ("notes", \.notes, 4),
            ("variables", \.variables, 4),
            ("methodology", \.methodology, 3),
            ("theoreticalFoundation", \.theoreticalFoundation, 3),
            ("country", \.country, 2),
            ("category", \.category, 2),
            ("source", \.source, 2),
            ("authors", \.authors, 2),
            ("authorsEnglish", \.authorsEnglish, 2),
            ("paperType", \.paperType, 1.5),
            ("collections", { $0.collections.joined(separator: " ") }, 3),
            ("tags", { $0.tags.joined(separator: " ") }, 3)
        ]

        let scored = papers.compactMap { paper -> SimilarityScoredPaper? in
            var score = 0.0
            var matchedTerms: Set<String> = []
            for (_, extractor, weight) in fieldWeights {
                let normalizedField = normalizedTextToken(extractor(paper))
                guard !normalizedField.isEmpty else { continue }
                for token in tokens where normalizedField.contains(token) {
                    score += weight
                    matchedTerms.insert(token)
                }
                if !normalizedQuery.isEmpty, normalizedField.contains(normalizedQuery) {
                    score += weight * 1.6
                }
            }
            guard score > 0 else { return nil }
            let normalizedScore = score / Double(max(tokens.count, 1))
            return SimilarityScoredPaper(
                paper: paper,
                score: normalizedScore,
                matchedTerms: Array(matchedTerms).sorted()
            )
        }

        return scored.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.paper.addedAtMilliseconds > rhs.paper.addedAtMilliseconds
            }
            return lhs.score > rhs.score
        }
    }

    private func queryTokens(from value: String) -> [String] {
        normalizedTextToken(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private func similaritySeedText(for paper: Paper) -> String {
        [
            paper.title,
            paper.englishTitle,
            paper.keywords,
            paper.abstractText,
            paper.chineseAbstract,
            paper.results,
            paper.conclusion,
            paper.rqs,
            paper.notes,
            paper.variables,
            paper.methodology,
            paper.theoreticalFoundation,
            paper.category,
            paper.country,
            paper.collections.joined(separator: " "),
            paper.tags.joined(separator: " ")
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    private func fullText(for paper: Paper) throws -> (text: String, pageCount: Int, cached: Bool, isTruncatedInCache: Bool) {
        guard let pdfURL = store.pdfURL(for: paper),
              fileManager.fileExists(atPath: pdfURL.path) else {
            throw ToolServiceError.notFound("This item does not have an accessible PDF attachment.")
        }

        let modifiedAt = try? pdfURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = fullTextCache[paper.id],
           cached.pdfPath == pdfURL.path,
           cached.modifiedAt == modifiedAt {
            fullTextCacheHits += 1
            return (cached.text, cached.pageCount, true, cached.isTruncatedInCache)
        }

        guard let document = PDFDocument(url: pdfURL) else {
            throw ToolServiceError.execution("PDFKit could not open the attached PDF.")
        }

        fullTextCacheMisses += 1
        var text = ""
        var wasTruncated = false
        for pageIndex in 0..<document.pageCount {
            guard let pageText = document.page(at: pageIndex)?.string else { continue }
            if !text.isEmpty {
                text.append("\n\n")
            }
            text.append(pageText)
            if text.count >= maximumCachedFullTextLength {
                text = String(text.prefix(maximumCachedFullTextLength))
                wasTruncated = true
                break
            }
        }

        let entry = FullTextCacheEntry(
            pdfPath: pdfURL.path,
            modifiedAt: modifiedAt ?? nil,
            pageCount: document.pageCount,
            text: text,
            extractedAt: .now,
            isTruncatedInCache: wasTruncated
        )
        fullTextCache[paper.id] = entry
        return (entry.text, entry.pageCount, false, entry.isTruncatedInCache)
    }

    private func errorPayload(for error: ToolServiceError) -> ToolCallPayload {
        let message: String
        switch error {
        case .invalidArguments(let details),
             .notFound(let details),
             .conflict(let details),
             .execution(let details):
            message = details
        }

        return ToolCallPayload(
            structuredContent: [
                "error": message
            ],
            isError: true
        )
    }

    private func sidebarSelectionLabel(_ selection: SidebarSelection) -> String {
        switch selection {
        case .library(let system):
            return system.rawValue
        case .collection(let name):
            return "collection:\(name)"
        case .tag(let name):
            return "tag:\(name)"
        }
    }

    private func excerptAroundMatch(in text: String, query: String, maximumLength: Int) -> String {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return limitedText(text, maxChars: maximumLength)
        }
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let lowerOffset = max(0, matchStart - maximumLength / 3)
        let upperOffset = min(text.count, matchStart + maximumLength * 2 / 3)
        let lowerIndex = text.index(text.startIndex, offsetBy: lowerOffset)
        let upperIndex = text.index(text.startIndex, offsetBy: upperOffset)
        let excerpt = String(text[lowerIndex..<upperIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return excerpt.isEmpty ? limitedText(text, maxChars: maximumLength) : excerpt
    }

    private func limitedText(_ text: String, maxChars: Int?) -> String {
        guard let maxChars, maxChars > 0, text.count > maxChars else {
            return text
        }
        return String(text.prefix(maxChars))
    }

    private func prettyJSONString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return string
    }

    private func normalizedTextToken(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizedTitle(_ value: String) -> String {
        normalizedTextToken(value)
    }

    private func normalizedDOI(_ value: String) -> String {
        normalizeDOIIdentifier(value)
    }

    private func requiredDictionary(_ value: Any?, label: String) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw ToolServiceError.invalidArguments("\(label) must be an object.")
        }
        return dictionary
    }

    private func requiredNonEmptyString(_ value: Any?, label: String) throws -> String {
        let string = try requiredString(value, label: label)
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolServiceError.invalidArguments("\(label) cannot be empty.")
        }
        return trimmed
    }

    private func optionalNonEmptyString(_ value: Any?, label: String) throws -> String? {
        guard !(value is NSNull) else { return nil }
        guard let string = stringValue(value) else {
            throw ToolServiceError.invalidArguments("\(label) must be a string or null.")
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func optionalPathComponent(_ value: Any?, label: String) throws -> String? {
        guard let component = try optionalNonEmptyString(value, label: label) else {
            return nil
        }
        let lastPathComponent = (component as NSString).lastPathComponent
        guard lastPathComponent == component, component != ".", component != ".." else {
            throw ToolServiceError.invalidArguments("\(label) must be a single file or folder name, not a path.")
        }
        return component
    }

    private func optionalFileName(_ value: Any?, label: String) throws -> String? {
        try optionalPathComponent(value, label: label)
    }

    private func requiredString(_ value: Any?, label: String) throws -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        throw ToolServiceError.invalidArguments("\(label) must be a string.")
    }

    private func normalizedStringArray(_ value: Any?, label: String) throws -> [String] {
        guard let items = value as? [Any] else {
            throw ToolServiceError.invalidArguments("\(label) must be an array of strings.")
        }
        let strings = try items.map { raw -> String in
            let string = try requiredString(raw, label: label).trimmingCharacters(in: .whitespacesAndNewlines)
            return string
        }
        return Array(Set(strings.filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func normalizedFileNameArray(_ value: Any?, label: String) throws -> [String] {
        guard let items = value as? [Any] else {
            throw ToolServiceError.invalidArguments("\(label) must be an array of file names.")
        }

        var normalized: [String] = []
        var seen = Set<String>()
        for raw in items {
            guard let fileName = try optionalFileName(raw, label: label) else {
                throw ToolServiceError.invalidArguments("\(label) cannot contain empty file names.")
            }
            if seen.contains(fileName) {
                throw ToolServiceError.invalidArguments("\(label) cannot contain duplicate file names.")
            }
            normalized.append(fileName)
            seen.insert(fileName)
        }
        return normalized
    }

    private func nonEmptyTrimmedString(_ value: Any?) -> String? {
        guard let string = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            return nil
        }
        return string
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func int64Value(_ value: Any?) -> Int64? {
        if let int = value as? Int64 {
            return int
        }
        if let int = value as? Int {
            return Int64(int)
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String {
            return Int64(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func int64OrNilValue(_ value: Any?, label: String) throws -> Int64? {
        if value is NSNull {
            return nil
        }
        if let int = int64Value(value) {
            return int
        }
        if let date = try dateValue(value, label: label) {
            return Int64((date.timeIntervalSince1970 * 1_000).rounded())
        }
        throw ToolServiceError.invalidArguments("\(label) must be an integer timestamp in milliseconds, an ISO-8601 datetime, or null.")
    }

    private func dateValue(_ value: Any?, label: String) throws -> Date? {
        if value is NSNull {
            return nil
        }
        if let date = value as? Date {
            return date
        }
        if let timestamp = int64Value(value) {
            let seconds: TimeInterval
            if abs(timestamp) >= 100_000_000_000 {
                seconds = TimeInterval(timestamp) / 1_000
            } else {
                seconds = TimeInterval(timestamp)
            }
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            throw ToolServiceError.invalidArguments("\(label) must be a valid ISO-8601 datetime.")
        }
        if let parsed = isoFormatter.date(from: string) ?? isoFormatterWithFractionalSeconds.date(from: string) {
            return parsed
        }
        throw ToolServiceError.invalidArguments("\(label) must be a valid ISO-8601 datetime.")
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

private extension KeyPath where Root == Paper, Value == String {
    static func title(_ paper: Paper) -> String { paper[keyPath: \.title] }
    static func englishTitle(_ paper: Paper) -> String { paper[keyPath: \.englishTitle] }
    static func keywords(_ paper: Paper) -> String { paper[keyPath: \.keywords] }
    static func abstractText(_ paper: Paper) -> String { paper[keyPath: \.abstractText] }
    static func chineseAbstract(_ paper: Paper) -> String { paper[keyPath: \.chineseAbstract] }
    static func results(_ paper: Paper) -> String { paper[keyPath: \.results] }
    static func conclusion(_ paper: Paper) -> String { paper[keyPath: \.conclusion] }
    static func rqs(_ paper: Paper) -> String { paper[keyPath: \.rqs] }
    static func notes(_ paper: Paper) -> String { paper[keyPath: \.notes] }
    static func variables(_ paper: Paper) -> String { paper[keyPath: \.variables] }
    static func methodology(_ paper: Paper) -> String { paper[keyPath: \.methodology] }
    static func theoreticalFoundation(_ paper: Paper) -> String { paper[keyPath: \.theoreticalFoundation] }
    static func country(_ paper: Paper) -> String { paper[keyPath: \.country] }
    static func category(_ paper: Paper) -> String { paper[keyPath: \.category] }
    static func source(_ paper: Paper) -> String { paper[keyPath: \.source] }
    static func authors(_ paper: Paper) -> String { paper[keyPath: \.authors] }
    static func authorsEnglish(_ paper: Paper) -> String { paper[keyPath: \.authorsEnglish] }
    static func paperType(_ paper: Paper) -> String { paper[keyPath: \.paperType] }
}
