// OverlayPanel.swift
// Mute

import AppKit
import SwiftUI

// MARK: - Overlay State
enum OverlayState {
    case hidden
    case recording
    case processing
    case done
    case error
}

// MARK: - Overlay Panel
class OverlayPanel: NSPanel {
    private var overlayView: NSHostingView<OverlayContentView>?
    private var viewModel = OverlayViewModel()

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setupPanel()
    }

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 44, height: 44), styleMask: [], backing: .buffered, defer: false)
    }

    private func setupPanel() {
        // Panel configuration
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none

        // Setup SwiftUI content
        let contentView = OverlayContentView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)

        let panelSize = NSSize(width: 44, height: 44)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]

        self.contentView = hostingView
        self.overlayView = hostingView

        positionPanel()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let margin: CGFloat = 20
        let panelSize: CGFloat = 44

        let x = screen.visibleFrame.origin.x + margin
        let y = screen.visibleFrame.origin.y + screen.visibleFrame.height - panelSize - margin

        self.setFrame(NSRect(x: x, y: y, width: panelSize, height: panelSize), display: false)
    }

    // MARK: - Public API
    func show(state: OverlayState, text: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.viewModel.state = state
            self.viewModel.text = text

            if state == .hidden {
                self.orderOut(nil)
            } else {
                self.positionPanel()
                self.orderFront(nil)
            }
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.state = .hidden
            self?.orderOut(nil)
        }
    }

    func updatePartialText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.partialText = text
        }
    }
}

// MARK: - Overlay View Model
class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .hidden
    @Published var text: String?
    @Published var partialText: String = ""
}

// MARK: - Overlay Content View
struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .hidden:
                EmptyView()
            case .recording:
                RecordingIndicator()
            case .processing:
                ProcessingIndicator()
            case .done:
                DoneIndicator()
            case .error:
                ErrorIndicator()
            }
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - Recording Indicator
struct RecordingIndicator: View {
    @State private var isAnimating = false
    @State private var ringScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .stroke(Color.red.opacity(0.3), lineWidth: 2)
                .frame(width: 36, height: 36)
                .scaleEffect(ringScale)
                .opacity(2 - ringScale)

            // Middle ring
            Circle()
                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                .frame(width: 28, height: 28)

            // Inner glowing circle
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.red,
                            Color.red.opacity(0.8)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 10
                    )
                )
                .frame(width: 16, height: 16)
                .shadow(color: Color.red.opacity(0.6), radius: 8, x: 0, y: 0)
                .scaleEffect(isAnimating ? 1.1 : 0.95)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
            withAnimation(
                Animation.easeOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                ringScale = 1.8
            }
        }
    }
}

// MARK: - Processing Indicator
struct ProcessingIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: 36, height: 36)

            // Spinning arc
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Color.orange.opacity(0.2), Color.orange]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(rotation))

            // Center dots
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(
                Animation.linear(duration: 1)
                    .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}

// MARK: - Done Indicator
struct DoneIndicator: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 36, height: 36)

            Circle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: 28, height: 28)

            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.green)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

// MARK: - Error Indicator
struct ErrorIndicator: View {
    @State private var isShaking = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.2))
                .frame(width: 36, height: 36)

            Circle()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: 28, height: 28)

            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.red)
        }
        .offset(x: isShaking ? -3 : 0)
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 0.08)
                    .repeatCount(4, autoreverses: true)
            ) {
                isShaking = true
            }
        }
    }
}
