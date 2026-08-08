import WidgetKit
import SwiftUI

/// TimelineEntry model for SentinelVault WidgetKit home-screen extension.
struct WidgetEntry: TimelineEntry {
    let date: Date
    let lockState: String
    let title: String
    let issuer: String
    let account: String
    let code: String
}

/// TimelineProvider reading App Group `UserDefaults` written by Flutter `home_widget`.
struct SentinelVaultWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), lockState: "locked", title: "SentinelVault", issuer: "TOTP", account: "", code: "------")
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchEntry() -> WidgetEntry {
        let userDefaults = UserDefaults(suiteName: "group.com.sentinelvault.app")
        guard let rawData = userDefaults?.string(forKey: "sentinelvault_widget_data"),
              let data = rawData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return WidgetEntry(date: Date(), lockState: "locked", title: "SentinelVault", issuer: "TOTP", account: "", code: "------")
        }

        let lockState = json["lockState"] as? String ?? "locked"
        let items = json["items"] as? [[String: Any]] ?? []

        if lockState == "unlocked", let first = items.first {
            let title = first["title"] as? String ?? "TOTP"
            let issuer = first["issuer"] as? String ?? title
            let account = first["account"] as? String ?? ""
            let code = first["code"] as? String ?? "------"
            return WidgetEntry(date: Date(), lockState: "unlocked", title: title, issuer: issuer, account: account, code: code)
        }

        return WidgetEntry(date: Date(), lockState: "locked", title: "SentinelVault", issuer: "TOTP", account: "", code: "------")
    }
}

/// SwiftUI View rendering active TOTP card or locked privacy card.
struct SentinelVaultWidgetView : View {
    var entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.lockState == "unlocked" {
                Text(entry.issuer.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.cyan)
                if !entry.account.isEmpty {
                    Text(entry.account)
                        .font(.caption2)
                        .foregroundColor(Color.gray)
                        .lineLimit(1)
                }
                Spacer()
                Text(formatCode(entry.code))
                    .font(.title2)
                    .fontDesign(.monospaced)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            } else {
                VStack(alignment: .center, spacing: 4) {
                    Spacer()
                    Text("🔒 Vault Locked")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("Tap to unlock")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))
        .widgetURL(URL(string: "sentinelvault://unlock"))
    }

    private func formatCode(_ code: String) -> String {
        if code.count == 6 {
            let index = code.index(code.startIndex, offsetBy: 3)
            return "\(code[..<index]) \(code[index...])"
        }
        return code
    }
}

@main
struct SentinelVaultWidget: Widget {
    let kind: String = "SentinelVaultWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SentinelVaultWidgetProvider()) { entry in
            SentinelVaultWidgetView(entry: entry)
        }
        .configurationDisplayName("SentinelVault TOTP")
        .description("Quick access to opt-in 2FA codes when unlocked.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
