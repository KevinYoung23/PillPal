import SwiftUI

struct SettingsView: View {
    @AppStorage("pile_by_default") private var pileByDefault = true
    @AppStorage("home_card_style") private var homeCardStyle = "concise"

    var body: some View {
        Form {
            Section("Schedule Layout") {
                Toggle("Default pile sections", isOn: $pileByDefault)
                Text(
                    pileByDefault
                    ? "Sections with multiple items start as stacked piles."
                    : "Sections with multiple items start expanded."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Main Page Cards") {
                Picker("Card style", selection: $homeCardStyle) {
                    Text("Detailed").tag("detailed")
                    Text("Concise").tag("concise")
                }
                .pickerStyle(.segmented)

                Text(
                    homeCardStyle == "concise"
                    ? "Concise shows only time and medication name on the main page."
                    : "Detailed shows dose and instruction information on the main page."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .dockSafeContentInset()
        .navigationTitle("Settings")
    }
}
