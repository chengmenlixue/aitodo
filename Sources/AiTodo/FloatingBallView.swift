import SwiftUI

/// 桌面悬浮球「田字格」：圆角方形底 + 2×2 四格，每格显示对应象限未完成数
struct FloatingBallView: View {
    @ObservedObject var manager: FloatingBallManager
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue

    /// 象限与位置固定：左上=重要·紧急(红)、右上=重要·不紧急(绿)、左下=紧急·不重要(黄)、右下=不重要·不紧急(蓝)
    private static let grid: [[Quadrant]] = [
        [.urgentImportant, .importantNotUrgent],
        [.urgentNotImportant, .neither],
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
            cells
                .padding(3)
        }
        .frame(width: 62, height: 62)
        .scaleEffect(manager.ballHovered ? 1.05 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: manager.ballHovered)
        .frame(width: 72, height: 72)
    }

    private var cells: some View {
        VStack(spacing: 2) {
            ForEach(Self.grid, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(row) { quadrant in
                        Cell(quadrant: quadrant,
                             count: count(of: quadrant),
                             isHovered: manager.ballHoveredCell == quadrant)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: manager.ballHoveredCell)
    }

    private func count(of quadrant: Quadrant) -> Int {
        manager.quadrantCounts.indices.contains(quadrant.rawValue)
            ? manager.quadrantCounts[quadrant.rawValue] : 0
    }

    private struct Cell: View {
        let quadrant: Quadrant
        let count: Int
        let isHovered: Bool

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: quadrant.accentHex).opacity(count == 0 ? 0.45 : 1))
                if isHovered {
                    // 点击色格可弹出该象限待办，悬停给一层墨润提示
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                }
                Text(count > 99 ? "99" : "\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: 27, height: 27)
        }
    }
}
