import SwiftUI
import Riptide

struct ConnectionHistorySection: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(Theme.subtext)
            Text("连接历史 (W3-2b)")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("已关闭连接的可追溯记录将在 W3-2b 启用。\n当前 W3-2a 写入的 ClosedConnectionRecord 已经在 Logbook 里持久化,UI 读取将在 W3-2b 引入 ClosedConnectionWatcher 运行时循环时补齐。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
