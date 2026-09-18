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

/// 松手变形：拖拽预览从落点形变飞入目标行位（FLIP morph）
struct SettleMorph: Identifiable {
    let id = UUID()
    let from: CGPoint
    let to: CGRect
    let title: String
    let accent: Color
    let isDone: Bool
    let dueDate: Date?
}

struct MorphSettleView: View {
    let morph: SettleMorph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue
    @State private var settled = false

    private var glass: Bool { AppSkin.from(skinRaw) == .glass }
    private var isOverdue: Bool {
        guard let due = morph.dueDate, !morph.isDone else { return false }
        return due < Date()
    }

    var body: some View {
        let radius = settled ? CGFloat(14) : CGFloat(12)
        let base = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // 与目标行一致：象限色从前往后渐变淡出（无高亮条）
        let wash = LinearGradient(
            stops: [
                .init(color: morph.accent.opacity(settled ? 0.48 : 0.55), location: 0),
                .init(color: morph.accent.opacity(settled ? 0.16 : 0.20), location: 0.55),
                .init(color: morph.accent.opacity(0), location: 1.0),
            ],
            startPoint: .leading, endPoint: .trailing)

        HStack(spacing: 12) {
            // 勾选圆圈：飞行全程展示，落位无缝
            ZStack {
                if morph.isDone {
                    Circle().fill(morph.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle().strokeBorder(Theme.checkBoxRing, lineWidth: 1.6)
                }
            }
            .frame(width: 20, height: 20)

            Text(morph.title)
                .font(.system(size: 14))
                .foregroundColor(morph.isDone ? Theme.textTertiary : Theme.textPrimary)
                .strikethrough(morph.isDone, color: Theme.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let due = morph.dueDate {
                DueChip(text: DueChipText.text(for: due), isOverdue: isOverdue)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(width: settled ? morph.to.width : 260,
               height: settled ? morph.to.height : 42,
               alignment: .leading)
            .background(
                base.fill(glass ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Theme.rowBackground))
                    .overlay(base.fill(wash))
            )
            // 起飞时带一点象限色描边方便追踪，落位时融入行（行本身无描边）
            .overlay(
                base.strokeBorder(morph.accent.opacity(settled ? 0 : 0.8), lineWidth: 1.2)
            )
            .shadow(color: morph.accent.opacity(settled ? 0 : 0.35), radius: settled ? 4 : 16)
            .position(x: settled ? morph.to.midX : morph.from.x,
                      y: settled ? morph.to.midY : morph.from.y)
            .allowsHitTesting(false)
            .onAppear {
                if reduceMotion {
                    settled = true
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { settled = true }
                }
            }
    }
}

/// 提醒时间胶囊（任务行与形变卡共用，保证外观一致）
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
