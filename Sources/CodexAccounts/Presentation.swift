import SwiftUI
import AccountsCore

enum PreviewConfiguration {
    static var variant: String? {
        guard Bundle.main.bundleIdentifier?.hasPrefix("org.codexaccounts.preview.") == true else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "CodexAccountsPreviewMode") as? String
    }
    static var enabled: Bool { CommandLine.arguments.contains("--demo") || variant != nil }
}

/// UI-only projections. Never change stored accounts when filtering, hiding or ordering them.
enum AccountPresentation {
    static func title(_ account: Account, hideEmails: Bool) -> String {
        if !account.nickname.isEmpty { return account.nickname }
        return hideEmails ? "账号 · \(account.id.prefix(4).uppercased())" : account.email
    }
    static func email(_ account: Account, hideEmails: Bool) -> String {
        hideEmails ? "邮箱已隐藏" : account.email
    }
    static func initials(_ account: Account, hideEmails: Bool) -> String {
        if !account.nickname.isEmpty { return String(account.nickname.prefix(2)).uppercased() }
        return hideEmails ? String(account.id.prefix(2)).uppercased() : String(account.email.prefix(1)).uppercased()
    }
    static func ordered(_ accounts: [Account], current: String?, query: String) -> [Account] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return accounts.enumerated().filter { _, account in
            query.isEmpty || account.title.localizedCaseInsensitiveContains(query) || account.email.localizedCaseInsensitiveContains(query)
        }.sorted { lhs, rhs in
            let leftCurrent = lhs.element.id == current, rightCurrent = rhs.element.id == current
            return leftCurrent != rightCurrent ? leftCurrent : lhs.offset < rhs.offset
        }.map(\.element)
    }
    static func needsRefresh(_ account: Account, now: Date = Date()) -> Bool {
        guard account.issue == nil, !account.quotas.isEmpty, let updated = account.updatedAt else { return true }
        return now.timeIntervalSince(updated) >= 900 || account.quotas.contains {
            guard let reset = $0.resetsAt else { return false }
            return reset <= now && updated < reset
        }
    }
    static func updatedLabel(_ account: Account, now: Date = Date()) -> String {
        guard let date = account.updatedAt else { return "尚未刷新" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "刚刚更新" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前更新" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前更新" }
        return "\(Int(seconds / 86400)) 天前更新"
    }
}

enum Palette {
    static let cobalt = Color(red: 0.24, green: 0.36, blue: 0.83)
    static let accents: [Color] = [cobalt, .teal, .purple, .indigo, .brown]
    static func account(_ id: String) -> Color {
        let index = id.utf8.reduce(0) { ($0 + Int($1)) % accents.count }
        return accents[index]
    }
}

/// Original pair of rounded exchange rails, shared by the UI and menu-bar label.
struct SwitchGlyph: Shape {
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(SwitchGlyph().path(in: rect).cgPath)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.7)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }()
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rect.width*x, y: rect.minY + rect.height*y) }
        var path = Path()
        path.move(to: p(0.22, 0.48)); path.addLine(to: p(0.22, 0.33))
        path.addQuadCurve(to: p(0.32, 0.23), control: p(0.22, 0.23))
        path.addLine(to: p(0.76, 0.23))
        path.move(to: p(0.63, 0.10)); path.addLine(to: p(0.76, 0.23)); path.addLine(to: p(0.63, 0.36))
        path.move(to: p(0.78, 0.52)); path.addLine(to: p(0.78, 0.67))
        path.addQuadCurve(to: p(0.68, 0.77), control: p(0.78, 0.77))
        path.addLine(to: p(0.24, 0.77))
        path.move(to: p(0.37, 0.64)); path.addLine(to: p(0.24, 0.77)); path.addLine(to: p(0.37, 0.90))
        return path
    }
}

struct BrandMark: View {
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24).fill(LinearGradient(colors: [Color(red: 0.36, green: 0.48, blue: 0.92), Palette.cobalt], startPoint: .topLeading, endPoint: .bottomTrailing))
            SwitchGlyph().stroke(.white, style: StrokeStyle(lineWidth: size*0.075, lineCap: .round, lineJoin: .round)).padding(size*0.06)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct AccountAvatar: View {
    let account: Account
    let hideEmails: Bool
    var size: CGFloat = 38
    var highlighted = false
    var body: some View {
        Text(AccountPresentation.initials(account, hideEmails: hideEmails))
            .font(.system(size: size * 0.30, weight: .semibold, design: .rounded))
            .foregroundStyle(highlighted ? .white : Palette.account(account.id))
            .frame(width: size, height: size)
            .background(highlighted ? Color.white.opacity(0.16) : Palette.account(account.id).opacity(0.12), in: RoundedRectangle(cornerRadius: size*0.29))
            .accessibilityHidden(true)
    }
}

struct PlanBadge: View {
    let plan: String
    var body: some View {
        Text(plan.uppercased()).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct QuotaMeter: View {
    let window: QuotaWindow
    var height: CGFloat = 5
    var highlighted = false
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(highlighted ? Color.white.opacity(0.25) : Color.primary.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule().fill(highlighted ? Color.white : window.remaining < 20 ? Color.orange : Color.accentColor)
                        .frame(width: geometry.size.width * min(1, max(0, window.remaining / 100)))
                }
        }.frame(height: height).accessibilityHidden(true)
    }
}
