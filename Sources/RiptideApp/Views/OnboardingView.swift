import SwiftUI
import Riptide

/// First-run onboarding flow that guides users through initial setup.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var step: OnboardingStep = .welcome
    @State private var selectedMode: RuntimeMode = .tun

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case modeSelect = 1
        case importConfig = 2
        case complete = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { stepCase in
                    Circle()
                        .fill(stepCase.rawValue <= step.rawValue ? Theme.accent : Theme.subtext.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)

            Spacer()

            // Step content
            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .modeSelect:
                    modeSelectionStep
                case .importConfig:
                    importConfigStep
                case .complete:
                    completeStep
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            Spacer()

            // Navigation buttons
            HStack {
                if step.rawValue > 0 {
                    Button("上一步") {
                        withAnimation {
                            step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button(nextButtonTitle) {
                    withAnimation {
                        if step == .complete {
                            // Save mode choice before completing
                            UserDefaults.standard.set(selectedMode.rawValue, forKey: "selectedRuntimeMode")
                            isPresented = false
                        } else {
                            step = OnboardingStep(rawValue: step.rawValue + 1) ?? .complete
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(24)
        }
        .frame(width: 520, height: 440)
        .background(Theme.backgroundGradient)
    }

    private var nextButtonTitle: String {
        switch step {
        case .welcome: return "开始设置"
        case .modeSelect: return "继续"
        case .importConfig: return "跳过"
        case .complete: return "开始使用 Riptide"
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("欢迎使用 Riptide")
                .font(.title.bold())
                .foregroundStyle(Theme.text)
            Text("原生 macOS 代理客户端，内置 sing-box 核心")
                .font(.body)
                .foregroundStyle(Theme.subtext)
            Text("接下来将引导你完成基本设置")
                .font(.callout)
                .foregroundStyle(Theme.subtext.opacity(0.7))
        }
        .padding(.horizontal, 40)
    }

    private var modeSelectionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            Text("选择运行模式")
                .font(.title2.bold())
                .foregroundStyle(Theme.text)

            Text("系统代理无需任何权限；TUN 首次启动会请求一次管理员密码安装后台服务")
                .font(.callout)
                .foregroundStyle(Theme.subtext)
                .multilineTextAlignment(.center)

            // TUN mode option
            ModeOptionView(
                title: "TUN 模式",
                subtitle: "全流量拦截 · 首次启动需一次管理员密码 · 推荐",
                isRecommended: true,
                isSelected: selectedMode == .tun,
                action: { selectedMode = .tun }
            )

            // System Proxy option
            ModeOptionView(
                title: "系统代理模式",
                subtitle: "轻量级 · 无需密码 · 适合日常浏览",
                isRecommended: false,
                isSelected: selectedMode == .systemProxy,
                action: { selectedMode = .systemProxy }
            )
        }
        .padding(.horizontal, 40)
    }

    private var importConfigStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(Theme.success)
            Text("导入配置")
                .font(.title.bold())
                .foregroundStyle(Theme.text)
            Text("导入一个 .yaml 配置文件，或者添加订阅链接")
                .font(.body)
                .foregroundStyle(Theme.subtext)
                .multilineTextAlignment(.center)
            Text("你也可以稍后在设置中完成此步骤")
                .font(.callout)
                .foregroundStyle(Theme.subtext.opacity(0.7))
        }
        .padding(.horizontal, 40)
    }

    private var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.success)
                .symbolEffect(.bounce, value: true)
            Text("设置完成！")
                .font(.title.bold())
                .foregroundStyle(Theme.text)
            Text("运行模式：\(selectedMode == .tun ? "TUN 模式" : "系统代理模式")")
                .font(.body)
                .foregroundStyle(Theme.subtext)
            Text("点击\"开始使用 Riptide\"进入主界面")
                .font(.callout)
                .foregroundStyle(Theme.subtext.opacity(0.7))
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Mode Option View

private struct ModeOptionView: View {
    let title: String
    let subtitle: String
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.body.bold())
                            .foregroundStyle(Theme.text)
                        if isRecommended {
                            Text("推荐")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.2))
                                .foregroundStyle(Theme.accent)
                                .cornerRadius(4)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(Theme.subtext.opacity(0.4))
                        .font(.title3)
                }
            }
            .padding(10)
            .background(isSelected ? Theme.accent.opacity(0.08) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.accent : Theme.subtext.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
