import SwiftUI
import UniformTypeIdentifiers

/// 行内落区分区：上带=排到前面，中带=成为子任务，下带=排到后面；out=离开行
enum DropZone {
    case above
    case middle
    case below
    case out

    init(y: CGFloat, rowHeight: CGFloat) {
        if y < rowHeight * 0.25 {
            self = .above
        } else if y > rowHeight * 0.75 {
            self = .below
        } else {
            self = .middle
        }
    }
}

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
    private static let rowHeight: CGFloat = 48

    var body: some View {
        ZStack {
            cardContent
            overlays
        }
        // 命名坐标空间：行内 rowFrames 按此测量，墨晕/落位脉冲按卡片本地坐标定位
        // （未声明命名空间时 .named 回退为全局坐标，高亮会整体偏移）
        .coordinateSpace(name: Self.cardSpace)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: targeted ? quadrant.accent.opacity(0.30) : .clear, radius: 24)
        .onDrop(of: [UTType.plainText], isTargeted: Binding(
            get: { targeted },
            set: { hovering in withAnimation(Motion.softIn) { targeted = hovering } }
        )) { _ in
            // 空白处松手：追加到本象限末尾
            appendDropped()
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
                    onZone: { zone in rowZone(task, zone) },
                    onDrop: { zone in rowDrop(task, zone) }))
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

    // MARK: - 拖拽落区

    /// 光标进入行的不同落区 → 实时排序（上/下带）或嵌套为子任务（中带）
    private func idx(_ task: TaskItem) -> Int {
        items.firstIndex(where: { $0.id == task.id }) ?? items.count
    }

    private func rowZone(_ target: TaskItem, _ zone: DropZone) {
        guard let dragID = store.draggingID, dragID != target.id, !target.isDone else {
            return
        }
        // 带子任务的任务不能成为别人的子任务：中带落区退化为排序
        let canNest = store.tasks.first(where: { $0.id == dragID })?.subtasks.isEmpty ?? false

        switch zone {
        case .above:
            let index = idx(target)
            store.applyDropPlacement(id: dragID, placement: .reorderTo(quadrant: quadrant, index: index))
        case .middle:
            if canNest {
                store.applyDropPlacement(id: dragID, placement: .nestInto(parentID: target.id))
            } else {
                let index = idx(target) + 1
                store.applyDropPlacement(id: dragID, placement: .reorderTo(quadrant: quadrant, index: index))
            }
        case .below:
            let index = idx(target) + 1
            store.applyDropPlacement(id: dragID, placement: .reorderTo(quadrant: quadrant, index: index))
        case .out:
            return
        }
        withAnimation(Motion.softIn) {
            targeted = true
            if let rect = rowRect(target.id) {
                inkPoint = CGPoint(x: rect.midX, y: rect.midY)
            }
        }
    }

    /// 在某行落区上松手：按当前落区最终放置一次，并触发落位高亮
    private func rowDrop(_ target: TaskItem, _ zone: DropZone) {
        rowZone(target, zone)
        var crossed = false
        if let dragID = store.draggingID,
           let index = store.tasks.firstIndex(where: { $0.id == dragID }),
           store.tasks[index].quadrant != quadrant {
            crossed = true
        }
        let rect = rowRect(store.draggingID ?? target.id) ?? rowRect(target.id)
        finishDrop(crossed: crossed, near: rect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? inkPoint,
                   landedRect: rect)
    }

    /// 空白处松手：追加到本象限末尾
    private func appendDropped() {
        guard let dragID = store.draggingID else { return }
        var crossed = false
        if let index = store.tasks.firstIndex(where: { $0.id == dragID }),
           store.tasks[index].quadrant != quadrant {
            store.applyDropPlacement(id: dragID, placement: .reorderTo(quadrant: quadrant, index: .max))
            crossed = true
        }
        var near = inkPoint
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

/// 行级落点代理：进入/移动/离开/落下时回报落区
struct RowDropDelegate: DropDelegate {
    let onZone: (DropZone) -> Void
    let onDrop: (DropZone) -> Void
    private let rowHeight: CGFloat

    init(rowHeight: CGFloat, onZone: @escaping (DropZone) -> Void, onDrop: @escaping (DropZone) -> Void) {
        self.rowHeight = rowHeight
        self.onZone = onZone
        self.onDrop = onDrop
    }

    func dropEntered(info: DropInfo) {
        DebugLog.write("row dropEntered y=\\(info.location.y)")
        onZone(DropZone(y: info.location.y, rowHeight: rowHeight))
    }

    func dropUpdated(info: DropInfo) -> DropOperation? {
        onZone(DropZone(y: info.location.y, rowHeight: rowHeight))
        return .move
    }

    func dropExited(info: DropInfo) {
        DebugLog.write("row dropExited")
        onZone(.out)
    }

    func performDrop(info: DropInfo) -> Bool {
        DebugLog.write("row performDrop y=\\(info.location.y)")
        guard !info.itemProviders(for: [.plainText]).isEmpty else { return false }
        onDrop(DropZone(y: info.location.y, rowHeight: rowHeight))
        return true
    }
}

struct RowDropHandlers {
    let onZone: (DropZone) -> Void
    let onDrop: (DropZone) -> Void
}

struct LandedPulse: Identifiable {
    let id = UUID()
    let rect: CGRect
    let accent: Color
}
