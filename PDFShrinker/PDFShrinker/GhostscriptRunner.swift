import Foundation

enum CompressionLevel: String, CaseIterable, Identifiable {
    case screen = "/screen"
    case ebook = "/ebook"
    case printer = "/printer"
    case prepress = "/prepress"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screen: return "Low (72 dpi)"
        case .ebook: return "Medium (150 dpi)"
        case .printer: return "High (300 dpi)"
        case .prepress: return "Maximum (300 dpi, color preserving)"
        }
    }
}

enum ShrinkError: LocalizedError {
    case gsNotFound
    case processError(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .gsNotFound:
            return "Ghostscript binary not found in app bundle."
        case .processError(let msg):
            return msg
        case .outputMissing:
            return "Output file was not created."
        }
    }
}

struct ShrinkResult {
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64

    var savings: Double {
        guard originalSize > 0 else { return 0 }
        return Double(originalSize - compressedSize) / Double(originalSize) * 100
    }
}

class GhostscriptRunner {
    private let gsURL: URL
    private let resourceDir: URL
    private let libDir: URL

    init() {
        let bundle = Bundle.main
        let binDir = bundle.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")

        self.gsURL = binDir.appendingPathComponent("gs")

        self.resourceDir = bundle.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("ghostscript")

        self.libDir = bundle.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Frameworks")
    }

    func shrink(input: URL, level: CompressionLevel) async throws -> ShrinkResult {
        guard FileManager.default.fileExists(atPath: gsURL.path) else {
            throw ShrinkError.gsNotFound
        }

        let originalSize = try FileManager.default
            .attributesOfItem(atPath: input.path)[.size] as? Int64 ?? 0

        // Build output filename: "Original-compressed.pdf"
        let stem = input.deletingPathExtension().lastPathComponent
        let outputURL = input.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-compressed.pdf")

        let process = Process()
        process.executableURL = gsURL
        process.arguments = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-dPDFSETTINGS=\(level.rawValue)",
            "-dNOPAUSE",
            "-dQUIET",
            "-dBATCH",
            "-sOutputFile=\(outputURL.path)",
            input.path
        ]

        // Set up environment so gs finds its resources and dylibs
        var env = ProcessInfo.processInfo.environment
        env["GS_LIB"] = resourceDir.appendingPathComponent("lib").path
            + ":" + resourceDir.appendingPathComponent("Resource/Init").path
            + ":" + resourceDir.appendingPathComponent("iccprofiles").path
        env["GS_FONTPATH"] = resourceDir.appendingPathComponent("fonts").path
        env["DYLD_LIBRARY_PATH"] = libDir.path
        process.environment = env

        // Pass resource dir explicitly to suppress warning
        process.arguments?.insert(
            "-sGenericResourceDir=\(resourceDir.appendingPathComponent("Resource").path)/",
            at: 0
        )

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ShrinkError.processError("Ghostscript failed (exit \(process.terminationStatus)): \(errorMsg)")
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ShrinkError.outputMissing
        }

        let compressedSize = try FileManager.default
            .attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0

        return ShrinkResult(
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: compressedSize
        )
    }
}
