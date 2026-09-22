import SwiftUI

/// 拖拽悬停时的墨晕：以落点为中心的柔和径向辉光，缓慢呼吸
struct InkOverlay: View {
    let point: CGPoint
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        RadialGradient(colors: [color.opacity(0.20), color.opacity(0.0)],
                       center: .center, startRadius: 4, endRadius: 240)
            .frame(width: 480, height: 480)
            .position(point)
            .scaleEffect(phase ? 1.06 : 0.94)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: phase)
            .allowsHitTesting(false)
            .onAppear {
                if !reduceMotion { phase = true }
            }
    }
}

/// 松手落点的一次性“墨滴迸溅”
/// GSAP timeline 思路：光斑 easeOut 0.55s 先行，冲击环 spring 0.4s 延迟 0.05s 略过冲
struct InkBurst: View {
    let point: CGPoint
    let color: Color
    @State private var glowScale: CGFloat = 0.15
    @State private var glowOpacity: Double = 0.95
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0.6

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.38), color.opacity(0.0)],
                                     center: .center, startRadius: 2, endRadius: 150))
                .frame(width: 300, height: 300)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)

            Circle()
                .stroke(color.opacity(ringOpacity), lineWidth: 2)
                .frame(width: 110, height: 110)
                .scaleEffect(ringScale)
        }
        .position(point)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                glowScale = 1.3
                glowOpacity = 0
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72).delay(0.05)) {
                ringScale = 2.6
                ringOpacity = 0
            }
        }
    }
}

/// 提醒时间胶囊（任务行共用）
struct DueChip: View {
    let text: String
    let isOverdue: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(isOverdue ? Theme.overdue : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isOverdue ? Theme.overdue.opacity(0.13) : Theme.chipBackground)
            )
    }
}

/// 落位高亮脉冲：松手后目标行闪一下象限色光边
struct HighlightPulse: View {
    let pulse: LandedPulse
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var faded = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(pulse.accent.opacity(faded ? 0.0 : 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(pulse.accent.opacity(faded ? 0.0 : 0.6), lineWidth: 1.5)
            )
            .frame(width: pulse.rect.width, height: pulse.rect.height)
            .position(x: pulse.rect.midX, y: pulse.rect.midY)
            .allowsHitTesting(false)
            .onAppear {
                if reduceMotion {
                    faded = true
                } else {
                    withAnimation(.easeOut(duration: 0.55).delay(0.12)) { faded = true }
                }
            }
    }
}
