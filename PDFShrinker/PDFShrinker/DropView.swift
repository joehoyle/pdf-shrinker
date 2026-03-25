import SwiftUI
import AppKit

/// Wraps SwiftUI content inside an NSView that handles file drops.
/// The NSView is the root, so it always receives drag events.
struct DropTargetWindow<Content: View>: NSViewRepresentable {
    var isTargeted: Binding<Bool>
    var onFileDrop: (URL) -> Void
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> DropHostView {
        let view = DropHostView()
        view.onFileDrop = onFileDrop
        view.onTargetChanged = { val in
            DispatchQueue.main.async { isTargeted.wrappedValue = val }
        }
        view.registerForDraggedTypes([.fileURL])

        let hostingView = NSHostingView(rootView: content())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        context.coordinator.hostingView = hostingView

        return view
    }

    func updateNSView(_ nsView: DropHostView, context: Context) {
        nsView.onFileDrop = onFileDrop
        nsView.onTargetChanged = { val in
            DispatchQueue.main.async { isTargeted.wrappedValue = val }
        }
        context.coordinator.hostingView?.rootView = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}

class DropHostView: NSView {
    var onFileDrop: ((URL) -> Void)?
    var onTargetChanged: ((Bool) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NSLog("[DropView] draggingEntered")
        guard hasPDF(sender) else {
            NSLog("[DropView] not a PDF, rejecting")
            return []
        }
        onTargetChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasPDF(sender) else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        NSLog("[DropView] draggingExited")
        onTargetChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        NSLog("[DropView] draggingEnded")
        onTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        NSLog("[DropView] prepareForDragOperation")
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        NSLog("[DropView] performDragOperation")
        onTargetChanged?(false)

        if let url = getPDFURL(sender) {
            NSLog("[DropView] dropping PDF: %@", url.path)
            onFileDrop?(url)
            return true
        }

        NSLog("[DropView] no valid PDF found")
        return false
    }

    private func hasPDF(_ info: NSDraggingInfo) -> Bool {
        return getPDFURL(info) != nil
    }

    private func getPDFURL(_ info: NSDraggingInfo) -> URL? {
        // Try pasteboardItems (most reliable)
        if let items = info.draggingPasteboard.pasteboardItems {
            for item in items {
                if let urlString = item.string(forType: .fileURL),
                   let url = URL(string: urlString),
                   url.pathExtension.lowercased() == "pdf" {
                    return url
                }
            }
        }
        return nil
    }
}
