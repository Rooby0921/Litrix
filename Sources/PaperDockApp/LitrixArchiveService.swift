import Foundation

enum LitrixArchiveService {
    static let manifestFileName = "manifest.json"
    static let papersDirectoryName = "papers"

    static func exportArchive(
        to destinationURL: URL,
        manifest: LitrixArchiveManifest,
        papersRootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("litrix-export-\(UUID().uuidString)", isDirectory: true)
        let payloadRoot = tempRoot.appendingPathComponent("payload", isDirectory: true)
        let payloadPapersRoot = payloadRoot.appendingPathComponent(papersDirectoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: payloadPapersRoot, withIntermediateDirectories: true)
            try writeManifest(manifest, to: payloadRoot)
            try copyPaperAssets(
                for: manifest.library.papers,
                from: papersRootURL,
                to: payloadPapersRoot,
                fileManager: fileManager
            )
            try createZipArchive(from: payloadRoot, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: tempRoot)
            throw error
        }

        try? fileManager.removeItem(at: tempRoot)
    }

    static func unpackArchive(
        from archiveURL: URL,
        fileManager: FileManager = .default
    ) throws -> (manifest: LitrixArchiveManifest, unpackedRoot: URL) {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("litrix-import-\(UUID().uuidString)", isDirectory: true)
        let payloadRoot = tempRoot.appendingPathComponent("payload", isDirectory: true)

        do {
            try fileManager.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
            try extractZipArchive(from: archiveURL, to: payloadRoot)
            let manifest = try readManifest(from: payloadRoot)
            guard manifest.formatIdentifier == "litrix-archive" else {
                throw LitrixArchiveError.unsupportedFormat
            }
            guard manifest.formatVersion == 1 else {
                throw LitrixArchiveError.unsupportedVersion(manifest.formatVersion)
            }
            return (manifest, payloadRoot)
        } catch {
            try? fileManager.removeItem(at: tempRoot)
            throw error
        }
    }

    static func cleanupUnpackedRoot(_ unpackedRoot: URL, fileManager: FileManager = .default) {
        let tempRoot = unpackedRoot.deletingLastPathComponent()
        try? fileManager.removeItem(at: tempRoot)
    }

    static func papersDirectory(in unpackedRoot: URL) -> URL {
        unpackedRoot.appendingPathComponent(papersDirectoryName, isDirectory: true)
    }

    private static func writeManifest(_ manifest: LitrixArchiveManifest, to root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(
            to: root.appendingPathComponent(manifestFileName, isDirectory: false),
            options: .atomic
        )
    }

    private static func readManifest(from root: URL) throws -> LitrixArchiveManifest {
        let url = root.appendingPathComponent(manifestFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LitrixArchiveError.invalidManifest
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LitrixArchiveManifest.self, from: data)
    }

    private static func copyPaperAssets(
        for papers: [Paper],
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager
    ) throws {
        var copiedFolders: Set<String> = []
        for paper in papers {
            guard let folderName = paper.storageFolderName,
                  !folderName.isEmpty,
                  !copiedFolders.contains(folderName) else {
                continue
            }

            let source = sourceRoot.appendingPathComponent(folderName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let destination = destinationRoot.appendingPathComponent(folderName, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            copiedFolders.insert(folderName)
        }
    }

    private static func createZipArchive(from sourceDirectory: URL, to destinationArchive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto", isDirectory: false)
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            sourceDirectory.path,
            destinationArchive.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            throw LitrixArchiveError.packFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown"
            throw LitrixArchiveError.packFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func extractZipArchive(from archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto", isDirectory: false)
        process.arguments = [
            "-x",
            "-k",
            archive.path,
            destination.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            throw LitrixArchiveError.unpackFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown"
            throw LitrixArchiveError.unpackFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
