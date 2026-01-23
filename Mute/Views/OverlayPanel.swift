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
        self.init(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64), styleMask: [], backing: .buffered, defer: false)
    }

    private func setupPanel() {
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none

        let contentView = OverlayContentView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)

        let panelSize = NSSize(width: 64, height: 64)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]

        self.contentView = hostingView
        self.overlayView = hostingView

        positionPanel()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let margin: CGFloat = 14
        let panelSize: CGFloat = 64

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
        .frame(width: 64, height: 64)
    }
}

// MARK: - State Colors
private struct StateColors {
    static let recording = Color(red: 0.95, green: 0.25, blue: 0.25)
    static let processing = Color(red: 0.95, green: 0.65, blue: 0.15)
    static let done = Color(red: 0.25, green: 0.85, blue: 0.55)
    static let error = Color(red: 0.95, green: 0.3, blue: 0.3)
}

// MARK: - Indicator Base
struct IndicatorBase: View {
    let stateColor: Color
    let glowIntensity: Double

    var body: some View {
        ZStack {
            // Outer diffused glow
            Circle()
                .fill(stateColor.opacity(glowIntensity * 0.3))
                .frame(width: 48, height: 48)
                .blur(radius: 10)

            // Inner tight glow
            Circle()
                .fill(stateColor.opacity(glowIntensity * 0.5))
                .frame(width: 38, height: 38)
                .blur(radius: 5)

            // Dark base with depth gradient
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.18),
                            Color(white: 0.08)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 18
                    )
                )
                .frame(width: 36, height: 36)

            // Subtle highlight edge (top-left light source)
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.03)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
                .frame(width: 36, height: 36)
        }
    }
}

// MARK: - Recording Indicator
struct RecordingIndicator: View {
    @State private var ringRotation: Double = 0
    @State private var dotScale: CGFloat = 1.0
    @State private var glowPulse: Double = 0.6
    @State private var appeared = false

    var body: some View {
        ZStack {
            IndicatorBase(stateColor: StateColors.recording, glowIntensity: glowPulse)

            // Rotating gradient ring
            Circle()
                .trim(from: 0, to: 0.65)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: StateColors.recording.opacity(0.0), location: 0.0),
                            .init(color: StateColors.recording.opacity(0.5), location: 0.3),
                            .init(color: StateColors.recording, location: 0.6),
                            .init(color: StateColors.recording.opacity(0.8), location: 0.65)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(ringRotation))

            // Center dot (rounded square = stop icon vibe)
            RoundedRectangle(cornerRadius: 3.5)
                .fill(StateColors.recording)
                .frame(width: 11, height: 11)
                .scaleEffect(dotScale)
                .shadow(color: StateColors.recording.opacity(0.6), radius: 3, x: 0, y: 0)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.5)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                appeared = true
            }
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                dotScale = 0.82
                glowPulse = 1.0
            }
        }
    }
}

// MARK: - Processing Indicator
struct ProcessingIndicator: View {
    @State private var ringRotation: Double = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            IndicatorBase(stateColor: StateColors.processing, glowIntensity: 0.6)

            // Fast spinning ring
            Circle()
                .trim(from: 0, to: 0.55)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: StateColors.processing.opacity(0.0), location: 0.0),
                            .init(color: StateColors.processing.opacity(0.4), location: 0.2),
                            .init(color: StateColors.processing, location: 0.5),
                            .init(color: StateColors.processing.opacity(0.7), location: 0.55)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(ringRotation))

            // Waveform icon
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(StateColors.processing)
                .shadow(color: StateColors.processing.opacity(0.5), radius: 2, x: 0, y: 0)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.5)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                appeared = true
            }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }
}

// MARK: - Done Indicator
struct DoneIndicator: View {
    @State private var appeared = false
    @State private var ringProgress: CGFloat = 0.0
    @State private var checkScale: CGFloat = 0.0
    @State private var glowPulse: Double = 0.0

    var body: some View {
        ZStack {
            IndicatorBase(stateColor: StateColors.done, glowIntensity: glowPulse)

            // Ring draws in
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    StateColors.done.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(-90))

            // Checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(StateColors.done)
                .scaleEffect(checkScale)
                .shadow(color: StateColors.done.opacity(0.5), radius: 2, x: 0, y: 0)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.5)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                appeared = true
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) {
                ringProgress = 1.0
                glowPulse = 0.8
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45).delay(0.3)) {
                checkScale = 1.0
            }
        }
    }
}

// MARK: - Error Indicator
struct ErrorIndicator: View {
    @State private var appeared = false
    @State private var shakeOffset: CGFloat = 0
    @State private var xScale: CGFloat = 0.0

    var body: some View {
        ZStack {
            IndicatorBase(stateColor: StateColors.error, glowIntensity: 0.7)

            // Static ring
            Circle()
                .stroke(StateColors.error.opacity(0.5), lineWidth: 2)
                .frame(width: 42, height: 42)

            // X mark
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(StateColors.error)
                .scaleEffect(xScale)
                .shadow(color: StateColors.error.opacity(0.5), radius: 2, x: 0, y: 0)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.5)
        .offset(x: shakeOffset)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4).delay(0.15)) {
                xScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(
                    Animation.easeInOut(duration: 0.055)
                        .repeatCount(5, autoreverses: true)
                ) {
                    shakeOffset = 3
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.05)) {
                        shakeOffset = 0
                    }
                }
            }
        }
    }
}
