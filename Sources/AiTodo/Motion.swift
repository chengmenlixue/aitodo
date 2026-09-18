import SwiftUI

/// 动效参数：时长与曲线对照 GSAP 最佳实践（gsap.defaults + 常用 ease 映射）
enum Motion {
    /// 微交互（悬停按钮、文字变色）：power2.out @ 0.18s
    static let micro = Animation.easeOut(duration: 0.18)
    /// 软入软出（墨晕淡入、卡片辉光）：power3.out @ 0.28s
    static let softIn = Animation.easeOut(duration: 0.28)
    /// 强调弹跳（勾选打勾、颜色选中环）：back.out(1.7) 的弹簧等价
    static let pop = Animation.spring(response: 0.36, dampingFraction: 0.68)
    /// 拖拽实时腾位：Things 式干净利落、微过冲（跟手且行位移动画不晃动）
    static let reorder = Animation.spring(response: 0.28, dampingFraction: 0.88)
    /// 列表入场 stagger 间隔（每行错峰 45ms）
    static let stagger: Double = 0.045
}
