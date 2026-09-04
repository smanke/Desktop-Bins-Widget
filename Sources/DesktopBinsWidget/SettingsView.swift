import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Open Desktop Bins Widget at login", isOn: $settings.launchAtLogin)
                .font(.system(size: 13, weight: .semibold))

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                slider(label: "Icon size", value: $settings.iconSize, range: 24...96, step: 8, suffix: "pt")
                slider(label: "Panel opacity", value: $settings.panelOpacity, range: 0.3...1.0, step: 0.05, suffix: "")
                Toggle("Show file names under icons", isOn: $settings.showLabels)
                Text("Items flow in the order you arrange them, so panels never leave gaps. Drag an item within a bin to reorder it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Reset to Defaults") { settings.resetToDefaults() }
                Spacer()
                Text("Desktop Bins Widget \(AppInfo.displayVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 430, height: 340)
    }

    private func slider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(suffix.isEmpty
                     ? String(format: "%.0f%%", value.wrappedValue * 100)
                     : "\(Int(value.wrappedValue)) \(suffix)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
