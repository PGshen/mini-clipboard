import SwiftUI

public struct SettingsView: View {
    @State private var settings = AppSettings()
    @AppStorage("historyLayoutStyle") private var layoutStyleRaw: String = "horizontal"
    @AppStorage("appLanguage") private var appLanguage: String = "zh-Hans"
    private let settingsStore = SettingsStore()
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("settings.title"))
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(L("settings.section.general"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("settings.retentionDays"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Stepper(value: $settings.historyRetentionDays, in: 7...365) {
                            Text("\(settings.historyRetentionDays)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.maxItems"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Stepper(value: $settings.historyMaxItems, in: 50...5000, step: 50) {
                            Text("\(settings.historyMaxItems)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.appLanguage"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: $appLanguage) {
                            Text(L("language.zh")).tag("zh-Hans")
                            Text(L("language.en")).tag("en")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.historyLayout"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: Binding(get: { HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal }, set: { layoutStyleRaw = $0.rawValue })) {
                            Text(L("settings.historyLayout.horizontal")).tag(HistoryLayoutStyle.horizontal)
                            Text(L("settings.historyLayout.grid")).tag(HistoryLayoutStyle.grid)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L("shortcuts.title"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("shortcuts.panel"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        ShortcutRecorder(shortcut: Binding(get: { settings.shortcuts.showPanel }, set: { settings.shortcuts.showPanel = $0 }))
                            .frame(width: 160, height: 22)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L("about.title"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("about.text"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .padding(10)
        .background(AppTheme.panelBackground)

        .frame(maxWidth: 360)
        .controlSize(.small)
        .onAppear { settings = settingsStore.load() }
        .onChange(of: appLanguage) { _ in }
        .onChange(of: settings) { s in
            try? settingsStore.save(s)
            HotkeyService.shared?.unregisterAll()
            HotkeyService.shared?.registerShowPanel()
            HotkeyService.shared?.registerQuickPasteSlots()
            HotkeyService.shared?.registerStackToggle()
        }
    }
    
}
