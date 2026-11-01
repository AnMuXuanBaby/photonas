import SwiftUI

struct LogsView: View {
    @ObservedObject var store: LogStore
    @State private var selected: AccessLogEntry?

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("还没有访问记录")
                            .font(.subheadline.weight(.medium))
                        Text("其他设备通过浏览器访问时，这里会记录访问设备、IP、时间和请求内容。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        ForEach(store.entries) { entry in
                            Button {
                                selected = entry
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("访问日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        store.clear()
                    }
                    .disabled(store.entries.isEmpty)
                }
            }
            .sheet(item: $selected) { entry in
                LogDetailView(entry: entry)
            }
        }
    }

    private func row(_ entry: AccessLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: entry.device))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.device)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.ip)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(entry.fullPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(entry.status)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusColor(entry.status))
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func icon(for device: String) -> String {
        if device.contains("iPad") { return "ipad" }
        if device.contains("iPhone") { return "iphone" }
        if device.contains("Mac") { return "laptopcomputer" }
        if device.contains("Android") { return "phone" }
        if device.contains("Windows") { return "desktopcomputer" }
        if device.contains("命令行") { return "terminal" }
        return "questionmark.circle"
    }

    private func statusColor(_ status: Int) -> Color {
        if status >= 500 { return .red }
        if status >= 400 { return .orange }
        return .green
    }
}

struct LogDetailView: View {
    let entry: AccessLogEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("时间") {
                    Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        .font(.subheadline)
                }
                Section("访问设备") {
                    LabeledContent("设备", value: entry.device)
                    LabeledContent("IP", value: entry.ip)
                }
                Section("请求") {
                    LabeledContent("方法", value: entry.method)
                    LabeledContent("路径", value: entry.path)
                    if !entry.query.isEmpty {
                        LabeledContent("参数", value: entry.query)
                    }
                    LabeledContent("状态码", value: "\(entry.status)")
                    LabeledContent("响应大小", value: AppModel.bytes(entry.bytes))
                    LabeledContent("耗时", value: String(format: "%.0f ms", entry.durationMs))
                }
                Section("User-Agent") {
                    Text(entry.userAgent.isEmpty ? "（空）" : entry.userAgent)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("访问详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
