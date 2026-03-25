import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var state: AppState = .idle
    @State private var compressionLevel: CompressionLevel = .ebook
    @State private var isTargeted = false
    @State private var appearAnimation = false

    private let runner = GhostscriptRunner()

    enum AppState: Equatable {
        case idle
        case processing(String)
        case done(ShrinkResult)
        case error(String)

        static func == (lhs: AppState, rhs: AppState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.processing(let a), .processing(let b)): return a == b
            case (.done(let a), .done(let b)): return a.outputURL == b.outputURL
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    var body: some View {
        DropTargetWindow(isTargeted: $isTargeted, onFileDrop: { url in
            processFile(url)
        }) {
            VStack(spacing: 0) {
                // Quality picker bar
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Quality:")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $compressionLevel) {
                            ForEach(CompressionLevel.allCases) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 240)
                        .disabled(isProcessing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Main content
                dropZone
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .frame(width: 500, height: 380)
        }
        .frame(width: 500, height: 380)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appearAnimation = true } }
    }

    private var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    // MARK: - Drop Zone

    @ViewBuilder
    private var dropZone: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)

            // Border
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isTargeted
                        ? Color.accentColor
                        : Color.primary.opacity(0.08),
                    lineWidth: isTargeted ? 2.5 : 1
                )

            // Highlight overlay when targeted
            if isTargeted {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.06))
            }

            contentForState
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if case .idle = state { pickFile() }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTargeted)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state)
    }

    // MARK: - State Views

    @ViewBuilder
    private var contentForState: some View {
        switch state {
        case .idle:
            idleView
        case .processing(let filename):
            processingView(filename: filename)
        case .done(let result):
            doneView(result: result)
        case .error(let msg):
            errorView(message: msg)
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tint)
                    .offset(y: appearAnimation ? 0 : -8)
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: appearAnimation
                    )
            }

            VStack(spacing: 6) {
                Text("Drop a PDF here")
                    .font(.system(size: 18, weight: .semibold))

                Text("or click to choose a file")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func processingView(filename: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                ProgressView()
                    .scaleEffect(1.6)
                    .tint(.accentColor)
            }

            VStack(spacing: 6) {
                Text("Compressing...")
                    .font(.system(size: 18, weight: .semibold))

                Text(filename)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 300)
            }
        }
    }

    private func doneView(result: ShrinkResult) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 8) {
                Text("Compressed!")
                    .font(.system(size: 18, weight: .semibold))

                // Size comparison
                HStack(spacing: 8) {
                    sizeLabel(formatSize(result.originalSize), color: .secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                    sizeLabel(formatSize(result.compressedSize), color: .primary)
                }

                Text(String(format: "%.0f%% smaller", result.savings))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1), in: Capsule())
            }

            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    withAnimation { state = .idle }
                } label: {
                    Label("Shrink Another", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 6) {
                Text("Something went wrong")
                    .font(.system(size: 18, weight: .semibold))

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 340)
            }

            Button {
                withAnimation { state = .idle }
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    // MARK: - Helpers

    private func sizeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a PDF to compress"

        if panel.runModal() == .OK, let url = panel.url {
            processFile(url)
        }
    }

    private func processFile(_ url: URL) {
        withAnimation { state = .processing(url.lastPathComponent) }
        let level = compressionLevel

        Task {
            do {
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }

                let result = try await runner.shrink(input: url, level: level)
                await MainActor.run {
                    withAnimation { state = .done(result) }
                }
            } catch {
                await MainActor.run {
                    withAnimation { state = .error(error.localizedDescription) }
                }
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
