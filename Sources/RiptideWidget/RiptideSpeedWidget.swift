import SwiftUI
import WidgetKit

/// The Riptide speed widget declaration. Renders a small or medium
/// system widget showing the current upload/download throughput and the
/// name of the active proxy node.
public struct RiptideSpeedWidget: Widget {
    public let kind: String = "RiptideSpeedWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpeedProvider()) { entry in
            SpeedWidgetView(entry: entry)
        }
        .configurationDisplayName("Riptide 实时速度")
        .description("显示当前代理节点和上下行速率")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
