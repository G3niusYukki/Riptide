import SwiftUI
import Riptide

/// First-run onboarding flow that guides users through initial setup.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var step: OnboardingStep = .welcome
    @State private var helperInstalled = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case helperInstall = 1
        case importConfig = 2
        case complete = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Theme.accent : Theme.subtext.opacity(0.3))
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
                case .helperInstall:
                    helperInstallStep
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
        .frame(width: 520, height: 400)
        .background(Theme.backgroundGradient)
    }

    private var nextButtonTitle: String {
        switch step {
        case .welcome: return "开始设置"
        case .helperInstall: return "跳过"
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
            Text("原生 macOS 代理客户端，由 mihomo 驱动")
                .font(.body)
                .foregroundStyle(Theme.subtext)
            Text("接下来将引导你完成基本设置")
                .font(.callout)
                .foregroundStyle(Theme.subtext.opacity(0.7))
        }
        .padding(.horizontal, 40)
    }

    private var helperInstallStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("安装辅助工具")
                .font(.title.bold())
                .foregroundStyle(Theme.text)
            Text("Riptide 需要一个特权辅助工具来配置系统代理和 TUN 模式")
                .font(.body)
                .foregroundStyle(Theme.subtext)
                .multilineTextAlignment(.center)
            Text("辅助工具通过 SMJobBless 安装，需要管理员密码")
                .font(.callout)
                .foregroundStyle(Theme.subtext.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("安装辅助工具") {
                // TODO: Trigger SMJobBless install
                helperInstalled = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 8)
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
            Text("设置完成！")
                .font(.title.bold())
                .foregroundStyle(Theme.text)
            Text("现在你可以开始使用 Riptide 了")
                .font(.body)
                .foregroundStyle(Theme.subtext)
            Text("点击右上角的\"开始使用 Riptide\"进入主界面")
                .font(.callout)
                .foregroundStyle(Theme.subtext.opacity(0.7))
        }
        .padding(.horizontal, 40)
    }
}
