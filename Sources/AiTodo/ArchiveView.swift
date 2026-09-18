import SwiftUI

/// 归档页：按归档日期分组，支持恢复、删除、清空
struct ArchiveView: View {
    @EnvironmentObject private var store: TaskStore
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue
    @Binding var page: Page

    private var skin: AppSkin { AppSkin.from(skinRaw) }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private struct DayGroup: Identifiable {
        let id: Date
        let title: String
        let items: [TaskItem]
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let dictionary = Dictionary(grouping: store.archivedTasks) {
            calendar.startOfDay(for: $0.archivedAt ?? $0.createdAt)
        }
        return dictionary
            .sorted { $0.key > $1.key }
            .map { key, items in
                DayGroup(id: key,
                         title: Self.dayFormatter.string(from: key),
                         items: items.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) })
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if groups.isEmpty {
                ZStack {
                    Text("暂无归档")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(groups) { group in
                            groupCard(group)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 子视图

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { page = .main }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 13))
                }
                .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("返回主界面")

            Text("归档")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text("\(store.archivedCount) 项")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.chipBackground))
            Button {
                store.clearArchive()
            } label: {
                Text("清空归档")
                    .font(.system(size: 13))
                    .foregroundColor(store.archivedCount > 0 ? Theme.textSecondary : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(store.archivedCount == 0)
        }
        .padding(.top, 6)
    }

    private func groupCard(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("\(group.items.count) 项")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.chipBackground))
            }
            ForEach(group.items) { task in
                ArchiveRow(task: task)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var cardBackground: some View {
        let glass = skin == .glass
        return Group {
            if glass {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.cardBase)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.cardBorder)
        )
    }
}

/// 归档条目：左侧色条标识来源象限，可恢复或删除
struct ArchiveRow: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue
    let task: TaskItem

    @State private var expanded = false

    private var skin: AppSkin { AppSkin.from(skinRaw) }
    private var hasSubtasks: Bool { !task.subtasks.isEmpty }
    private var doneCount: Int { task.subtasks.filter(\.isDone).count }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var subtitle: String {
        var parts = [task.quadrant.title]
        if let archivedAt = task.archivedAt {
            parts.append(Self.timeFormatter.string(from: archivedAt) + " 归档")
        }
        if hasSubtasks {
            parts.append("子任务 \(doneCount)/\(task.subtasks.count)")
        }
        if task.isDone {
            parts.append("已完成")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if expanded && hasSubtasks {
                subtaskList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : Motion.softIn, value: expanded)
        .onTapGesture {
            if hasSubtasks {
                withAnimation(Motion.softIn) { expanded.toggle() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if hasSubtasks {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 12)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundColor(task.isDone ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(task.isDone, color: Theme.textTertiary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            if task.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(task.quadrant.accent.opacity(0.8))
            }

            if hasSubtasks {
                Button {
                    withAnimation(Motion.softIn) { expanded.toggle() }
                } label: {
                    Text("\(doneCount)/\(task.subtasks.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(task.quadrant.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(task.quadrant.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("展开子任务")
            }

            Button {
                store.unarchive(id: task.id)
            } label: {
                Image(systemName: "tray.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.controlCircle))
            }
            .buttonStyle(.plain)
            .help("恢复到原象限")

            Button {
                store.delete(id: task.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("永久删除")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(minHeight: 48)
    }

    /// 归档中的子任务（只读展示完成状态）
    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(task.subtasks) { sub in
                HStack(spacing: 6) {
                    Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9))
                        .foregroundColor(sub.isDone ? task.quadrant.accent : Theme.textTertiary)
                    Text(sub.title)
                        .font(.system(size: 11))
                        .foregroundColor(sub.isDone ? Theme.textTertiary : Theme.textSecondary)
                        .strikethrough(sub.isDone, color: Theme.textTertiary)
                }
            }
        }
        .padding(.leading, 28)
        .padding(.bottom, 10)
    }

    private var rowBackground: some View {
        let glass = skin == .glass
        return Group {
            if glass {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thinMaterial)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.rowBackground)
            }
        }
    }
}
