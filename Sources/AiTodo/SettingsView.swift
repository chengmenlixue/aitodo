import SwiftUI

struct SettingsView: View {
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue
    @AppStorage("autoArchiveEnabled") private var autoArchiveEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("皮肤")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                Picker("", selection: $skinRaw) {
                    ForEach(AppSkin.allCases) { skin in
                        Text(skin.label).tag(skin.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(skin == .glass
                     ? "毛玻璃：透过窗口实时模糊显示桌面背景"
                     : "经典深色：纯深色背景，与设计稿一致")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $autoArchiveEnabled) {
                    Text("完成后自动归档")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                }
                .toggleStyle(.switch)
                Text("已完成的任务将在当天结束后（次日）自动移入归档")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(18)
        .frame(width: 300)
    }

    private var skin: AppSkin { AppSkin.from(skinRaw) }
}
