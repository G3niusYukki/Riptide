import SwiftUI
import Riptide

struct DiagnosticsTabView: View {
    @Bindable var vm: AppViewModel
    @State private var section: Section = .events

    enum Section: String, CaseIterable, Identifiable {
        case events = "事件"
        case connectionHistory = "连接历史"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("section", selection: $section) {
                ForEach(Section.allCases) { currentSection in
                    Text(currentSection.rawValue).tag(currentSection)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch section {
            case .events:
                EventLogSection(vm: vm)
            case .connectionHistory:
                ConnectionHistorySection(vm: vm)
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
