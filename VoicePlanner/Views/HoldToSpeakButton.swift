//
//  HoldToSpeakButton.swift
//  VoicePlanner
//
//  Press and hold to record, release to save, drag up to cancel.
//  With VoiceOver, a double-tap starts recording and a second double-tap stops it.
//

import SwiftUI

struct HoldToSpeakButton: View {
    let isRecording: Bool
    let onPress: () -> Void
    let onRelease: (_ cancelled: Bool) -> Void

    @State private var isPressed = false
    @State private var willCancel = false

    private let size: CGFloat = 76
    private let cancelDistance: CGFloat = 80

    var body: some View {
        ZStack {
            if isRecording && !willCancel {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: size, height: size)
                    .phaseAnimator([1.0, 1.6]) { content, scale in
                        content.scaleEffect(scale).opacity(1.6 - scale)
                    } animation: { _ in
                        .easeOut(duration: 1)
                    }
            }

            Circle()
                .fill(fillColor.gradient)
                .frame(width: size, height: size)
                .shadow(color: fillColor.opacity(0.4), radius: isPressed ? 16 : 8, y: 4)

            Image(systemName: willCancel ? "xmark" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: isRecording && !willCancel)
        }
        .scaleEffect(isPressed ? 1.15 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.easeInOut(duration: 0.15), value: willCancel)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPressed {
                        isPressed = true
                        onPress()
                    }
                    willCancel = value.translation.height < -cancelDistance
                }
                .onEnded { _ in
                    let cancelled = willCancel
                    isPressed = false
                    willCancel = false
                    onRelease(cancelled)
                }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: isPressed)
        .sensoryFeedback(.warning, trigger: willCancel) { _, new in new }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRecording ? "إيقاف التسجيل وحفظ الفكرة" : "تسجيل فكرة صوتية")
        .accessibilityAction {
            if isRecording { onRelease(false) } else { onPress() }
        }
    }

    private var fillColor: Color {
        if willCancel { return .gray }
        return isRecording ? .red : .accentColor
    }
}
