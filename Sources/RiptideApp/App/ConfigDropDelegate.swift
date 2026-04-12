import SwiftUI
import UniformTypeIdentifiers

/// Drop delegate for importing config files (.yaml, .yml) by drag-and-drop.
@MainActor
public final class ConfigDropDelegate: DropDelegate {
    let onDrop: ([URL]) -> Void

    public init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
    }

    public func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] item, error in
                guard let self, let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                Task { @MainActor in
                    self.onDrop([url])
                }
            }
        }
        return true
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.yaml, .init(filenameExtension: "yml")!])
    }
}

/// View modifier that adds config file drop import support.
public struct ConfigDropImportModifier: ViewModifier {
    let onDrop: ([URL]) -> Void

    public func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                let urls = providers.compactMap { provider -> URL? in
                    guard let data = try? provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return nil
                    }
                    return url
                }
                guard !urls.isEmpty else { return false }
                onDrop(urls)
                return true
            }
    }
}

extension View {
    /// Adds config file (.yaml/.yml) drop import support to this view.
    public func onConfigDrop(perform action: @escaping ([URL]) -> Void) -> some View {
        modifier(ConfigDropImportModifier(onDrop: action))
    }
}
