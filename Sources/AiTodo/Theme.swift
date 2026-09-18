import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// 皮肤主题
enum AppSkin: String, CaseIterable, Identifiable {
    case classic
    case plain
    case glass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "经典深色"
        case .plain: return "纯白"
        case .glass: return "毛玻璃"
        }
    }

    /// 设置面板里的一句话说明
    var caption: String {
        switch self {
        case .classic: return "经典深色：纯深色背景，与设计稿一致"
        case .plain: return "纯白：白纸黑字，与 App 图标同源的配色"
        case .glass: return "毛玻璃：透过窗口实时模糊显示桌面背景"
        }
    }

    static func from(_ raw: String?) -> AppSkin {
        AppSkin(rawValue: raw ?? "") ?? .classic
    }
}

/// 色板：全部跟随当前皮肤计算（视图通过 @AppStorage("skin") 获得刷新时机）
enum Theme {
    static var skin: AppSkin { AppSkin.from(UserDefaults.standard.string(forKey: "skin")) }
    static var isLight: Bool { skin == .plain }

    // MARK: 背景

    static var appBackground: Color { isLight ? Color(hex: 0xF7F7F5) : Color(hex: 0x0B0B0C) }
    static var cardBase: Color { isLight ? Color(hex: 0xFFFFFF) : Color(hex: 0x141414) }
    static var rowBackground: Color { isLight ? Color(hex: 0xFCFCFA) : Color(hex: 0x181818) }
    static var controlBackground: Color { isLight ? Color(hex: 0xEFEFEC) : Color(hex: 0x1A1A1B) }
    /// 强调按钮/选中填充：深色皮肤为浅色，纯白皮肤为墨色（呼应图标黑字）
    static var actionButton: Color { isLight ? Color(hex: 0x1B1B1C) : Color(hex: 0xE9E9E9) }
    /// 强调控件上的前景（+ 号、选中态图标）
    static var actionForeground: Color { isLight ? .white : .black }

    // MARK: 文本

    static var textPrimary: Color { isLight ? Color(hex: 0x1A1A1B) : Color(hex: 0xF2F2F3) }
    static var textSecondary: Color { isLight ? Color(hex: 0x6E6E73) : Color(hex: 0x949499) }
    static var textTertiary: Color { isLight ? Color(hex: 0xA6A6AB) : Color(hex: 0x66666B) }
    static var overdue: Color { isLight ? Color(hex: 0xD9503F) : Color(hex: 0xF2796B) }

    // MARK: 半透明覆盖层

    static var chipBackground: Color { isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08) }
    static var controlCircle: Color { isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.07) }
    static var checkBoxRing: Color { isLight ? Color.black.opacity(0.28) : Color.white.opacity(0.3) }
    static var cardBorder: Color { isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.04) }
    static var chromeBorder: Color { isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.06) }
}

/// 控件胶囊底（输入框、头部按钮组等）
struct ChromeBackground: View {
    var cornerRadius: CGFloat = 14
    @AppStorage("skin") private var skinRaw = AppSkin.classic.rawValue

    var body: some View {
        let glass = AppSkin.from(skinRaw) == .glass
        Group {
            if glass {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.controlBackground)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.chromeBorder)
        )
    }
}

/// 毛玻璃模式下的窗口底衬：透过窗口实时模糊桌面
struct VisualEffectBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
