import SwiftUI

struct ProfileTabView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppBrand.displayName)
                                .font(.title3.weight(.semibold))
                            Text("v\(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("数据") {
                    NavigationLink { BackupView() } label: {
                        Label("数据备份", systemImage: "externaldrive")
                    }
                }

                Section("系统") {
                    NavigationLink { SettingsView() } label: {
                        Label("设置", systemImage: "gear")
                    }
                }

                Section("关于") {
                    HStack {
                        Label("当前版本", systemImage: "info.circle")
                        Spacer()
                        Text("v\(appVersion)")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink { PrivacyPolicyView() } label: {
                        Label("隐私政策", systemImage: "hand.raised.fill")
                    }
                    NavigationLink { FeedbackView() } label: {
                        Label("意见反馈", systemImage: "envelope.fill")
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}
