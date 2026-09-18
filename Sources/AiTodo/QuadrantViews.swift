import SwiftUI
import UniformTypeIdentifiers

struct QuadrantGrid: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                QuadrantCard(quadrant: .urgentImportant)
                QuadrantCard(quadrant: .importantNotUrgent)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 18) {
                QuadrantCard(quadrant: .urgentNotImportant)
                QuadrantCard(quadrant: .neither)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct ListView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(Quadrant.allCases) { quadrant in
                    QuadrantCard(quadrant: quadrant)
                        .frame(minHeight: 150)
                }
            }
        }
    }
}

struct QuadrantCard: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue
    let quadrant: Quadrant

    @State private var targeted = false
    @State private var inkPoint: CGPoint = CGPoint(x: 120, y: 90)
    @State private var burstPoint: CGPoint?
    @State private var burstID = UUID()
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var appeared = false
    @State private var landedPulse: LandedPulse?

    private var skin: AppSkin { AppSkin.from(skinRaw) }
    private var items: [TaskItem] { store.tasks(in: quadrant) }
    private static let cardSpace = "quadrantCard"

    var body: some View {
        ZStack {
            cardContent
            overlays
        }
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: targeted ? quadrant.accent.opacity(0.30) : .clear, radius: 24)
        .onDrop(of: [UTType.plainText], isTargeted: Binding(
            get: { targeted },
            set: { hovering in withAnimation(Motion.softIn) { targeted = hovering } }
        )) { _ in
            // 空白处松手：追加到本象限末尾
            appendDropped(at: inkPoint)
            return store.draggingID != nil
        }
        .onAppear {
            withAnimation(Motion.softIn) { appeared = true }
            // 调试：AITODO_DEMO_INK=1 时常驻展示墨晕
            if ProcessInfo.processInfo.environment["AITODO_DEMO_INK"] != nil {
                targeted = true
                inkPoint = CGPoint(x: 230, y: 130)
            }
        }
    }

    // MARK: - 内容

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            taskArea
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var taskArea: some View {
        if items.isEmpty {
            ZStack {
                Text("暂无")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                        taskRow(task, index: index)
                    }
                }
            }
            .animation(reduceMotion ? nil : Motion.reorder, value: items)
        }
    }

    private func taskRow(_ task: TaskItem, index: Int) -> some View {
        TaskRow(task: task,
                isDragSource: store.draggingID == task.id,
                onDragStarted: { store.beginDrag(id: task.id) },
                dropHandlers: RowDropHandlers(
                    onEnter: { rowEnter(task) },
                    onExit: {},
                    onDrop: { rowDrop(task) }))
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .opacity))
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            // GSAP stagger：入场按序错峰滑入
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(min(index, 8)) * Motion.stagger), value: appeared)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { rowFrames[task.id] = geo.frame(in: .named(Self.cardSpace)) }
                        .onChange(of: geo.frame(in: .named(Self.cardSpace))) { frame in
                            rowFrames[task.id] = frame
                        }
                }
            )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(quadrant.accent)
                .frame(width: 9, height: 9)
            Text(quadrant.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(quadrant.actionHint)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text("\(items.count) 项")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.chipBackground))
        }
        .padding(.top, 2)
    }

    // MARK: - 覆盖层

    @ViewBuilder private var overlays: some View {
        // 拖拽悬停的墨晕（裁切在卡片内）
        if targeted {
            InkOverlay(point: inkPoint, color: quadrant.accent)
                .transition(.opacity)
        }

        // 落位高亮脉冲
        if let pulse = landedPulse {
            HighlightPulse(pulse: pulse)
                .id(pulse.id)
        }

        // 跨象限落位的墨滴迸溅
        if let burst = burstPoint {
            InkBurst(point: burst, color: quadrant.accent)
                .id(burstID)
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                targeted ? quadrant.accent.opacity(0.85) : Theme.cardBorder,
                lineWidth: targeted ? 2 : 1
            )
    }

    private var cardBackground: some View {
        let glass = skin == .glass
        let base = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Group {
            if glass {
                base.fill(.ultraThinMaterial)
                    .overlay(
                        base.fill(
                            LinearGradient(
                                colors: [quadrant.accent.opacity(0.13), quadrant.accent.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
                    .overlay(base.strokeBorder(Color.white.opacity(0.10)))
            } else {
                base.fill(Theme.cardBase)
                    .overlay(
                        base.fill(
                            LinearGradient(
                                colors: [quadrant.accent.opacity(0.17), quadrant.accent.opacity(0.07)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
            }
        }
    }

    // MARK: - 拖拽：行级腾位 + 落位

    /// 光标进入某行 → 把拖拽中的任务实时移动到该行之前（同象限排序 / 跨象限飞入）
    private func rowEnter(_ target: TaskItem) {
        DebugLog.write("rowEnter target=\(target.title.prefix(6)) draggingID=\(String(describing: store.draggingID))")
        guard let dragID = store.draggingID, dragID != target.id else { return }
        let targetIndex = items.firstIndex(where: { $0.id == target.id }) ?? items.count
        store.move(id: dragID, to: quadrant, insertionIndex: targetIndex)
        withAnimation(Motion.softIn) {
            targeted = true
            if let rect = rowRect(target.id) {
                inkPoint = CGPoint(x: rect.midX, y: rect.midY)
            }
        }
    }

    /// 在某行上松手：确保落进本象限并触发落位高亮
    private func rowDrop(_ target: TaskItem) {
        DebugLog.write("rowDrop target=\(target.title.prefix(6)) draggingID=\(String(describing: store.draggingID))")
        guard let dragID = store.draggingID else { return }
        var crossed = false
        if let index = store.tasks.firstIndex(where: { $0.id == dragID }),
           store.tasks[index].quadrant != quadrant {
            let targetIndex = items.firstIndex(where: { $0.id == target.id }) ?? items.count
            store.move(id: dragID, to: quadrant, insertionIndex: targetIndex)
            crossed = true
        }
        let near = rowRect(target.id).map { CGPoint(x: $0.midX, y: $0.midY) } ?? inkPoint
        finishDrop(crossed: crossed, near: near, landedRect: rowRect(target.id))
    }

    /// 空白处松手：追加到本象限末尾
    private func appendDropped(at point: CGPoint) {
        guard let dragID = store.draggingID else { return }
        var crossed = false
        if let index = store.tasks.firstIndex(where: { $0.id == dragID }),
           store.tasks[index].quadrant != quadrant {
            store.move(id: dragID, to: quadrant)
            crossed = true
        }
        var near = point
        if let last = items.last, let rect = rowRect(last.id) {
            near = CGPoint(x: rect.midX, y: rect.maxY + 10)
        }
        let landed = items.last.flatMap { rowRect($0.id) }
        finishDrop(crossed: crossed, near: near, landedRect: landed)
    }

    private func finishDrop(crossed: Bool, near point: CGPoint, landedRect: CGRect?) {
        guard let dragID = store.draggingID else { return }
        if crossed {
            burstID = UUID()
            burstPoint = point
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { burstPoint = nil }
        }
        if let rect = rowRect(dragID) ?? landedRect {
            landedPulse = LandedPulse(rect: rect, accent: quadrant.accent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { landedPulse = nil }
        }
        store.endDrag()
    }

    private func rowRect(_ id: UUID) -> CGRect? {
        rowFrames[id]
    }
}

/// 行级落点代理：光标进入行即回调（比卡片级 dropUpdated 可靠）
struct RowDropDelegate: DropDelegate {
    let onEnter: () -> Void
    let onExit: () -> Void
    let onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        DebugLog.write("row dropEntered")
        onEnter()
    }

    func dropUpdated(info: DropInfo) -> DropOperation? {
        .move
    }

    func dropExited(info: DropInfo) {
        DebugLog.write("row dropExited")
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        DebugLog.write("row performDrop")
        guard !info.itemProviders(for: [.plainText]).isEmpty else { return false }
        onDrop()
        return true
    }
}

struct RowDropHandlers {
    let onEnter: () -> Void
    let onExit: () -> Void
    let onDrop: () -> Void
}

struct LandedPulse: Identifiable {
    let id = UUID()
    let rect: CGRect
    let accent: Color
}
