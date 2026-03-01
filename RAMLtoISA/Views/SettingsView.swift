import SwiftUI

/// Settings panel for ISA document generation options
struct SettingsView: View {
    @AppStorage("architectName") var architectName: String = "<architect.email@company.com>"
    @AppStorage("includeEndpoints") var includeEndpoints: Bool = true
    @AppStorage("includeDiagrams") var includeDiagrams: Bool = true
    @AppStorage("includeRequirements") var includeRequirements: Bool = true

    var body: some View {
        Form {
            Section {
                TextField("Architect Name / Email", text: $architectName)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Document Header")
            }

            Section {
                Toggle("Include endpoint specifications", isOn: $includeEndpoints)
                Toggle("Include Mermaid diagrams", isOn: $includeDiagrams)
                Toggle("Include requirements traceability", isOn: $includeRequirements)
            } header: {
                Text("Content Sections")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
    }

    /// Build an ISASettings value from the current stored preferences
    static var current: ISASettings {
        let defaults = UserDefaults.standard
        return ISASettings(
            architectName: defaults.string(forKey: "architectName") ?? "<architect.email@company.com>",
            includeEndpoints: defaults.object(forKey: "includeEndpoints") as? Bool ?? true,
            includeDiagrams: defaults.object(forKey: "includeDiagrams") as? Bool ?? true,
            includeRequirements: defaults.object(forKey: "includeRequirements") as? Bool ?? true
        )
    }
}

#Preview {
    SettingsView()
}
