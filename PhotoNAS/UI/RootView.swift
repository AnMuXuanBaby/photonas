import SwiftUI
import UIKit
import CoreImage
import Photos

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var logStore = LogStore.shared

    var body: some View {
        TabView {
            DashboardView(model: model)
                .tabItem { Label("服务", systemImage: "antenna.radiowaves.left.and.right") }
            LogsView(store: logStore)
                .tabItem { Label("日志", systemImage: "list.bullet.rectangle") }
            SettingsView(model: model)
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .onAppear {
            model.bootstrap()
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    addressCard
                    metricsCard
                    if !model.peers.isEmpty {
                        peersCard
                    }
                    cacheCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PhotoNAS")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 卡片

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.running ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: 9, height: 9)
                Text(model.running ? "服务运行中" : "服务已停止")
                    .font(.headline)
                Spacer()
                Text("1.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(model.running
                 ? "同一 Wi-Fi 下的设备用浏览器打开下方地址即可直接浏览、播放与下载。"
                 : "启动后会开启局域网 HTTP 服务，并通过 UDP 广播让同网络设备自动发现。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if model.authorization != .authorized && model.authorization != .limited {
                Button {
                    model.requestAuthorization()
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("授予相册访问权限")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                if model.running {
                    model.stopServer()
                } else {
                    model.startServer()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.running ? "stop.fill" : "play.fill")
                    Text(model.running ? "停止服务" : "启动服务")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(model.running ? Color.red.opacity(0.12) : Color.accentColor)
                .foregroundStyle(model.running ? Color.red : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var addressCard: some View {
        HStack(alignment: .center, spacing: 16) {
            QRCodeView(text: model.localURL)
                .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 8) {
                Text("访问地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.localURL)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = model.localURL
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.14))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if let link = URL(string: model.localURL) {
                        Link(destination: link) {
                            Label("打开", systemImage: "safari")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill))
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("运行统计")
                    .font(.headline)
                Spacer()
                Text("相册共 \(model.totalPhotos) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                metric("请求数", "\(model.stats.requests)")
                metric("已发送", AppModel.bytes(model.stats.bytes))
                metric("生成缩略图", "\(model.stats.thumbnailsGenerated)")
                metric("缓存命中", "\(model.stats.thumbnailCacheHits)")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var cacheCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("缓存占用")
                .font(.headline)
            HStack {
                Text("缩略图（\(model.settings.thumbnailFormat.title)）")
                    .font(.subheadline)
                Spacer()
                Text(model.thumbnailCacheText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("原图 / 视频")
                    .font(.subheadline)
                Spacer()
                Text(model.originalCacheText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var peersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("同网络发现的设备")
                .font(.headline)
            ForEach(model.peers) { peer in
                HStack(spacing: 10) {
                    Image(systemName: "iphone.gen3")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.name)
                            .font(.subheadline.weight(.medium))
                        Text("http://\(peer.address):\(peer.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 二维码

struct QRCodeView: View {
    let text: String

    var body: some View {
        Group {
            if let image = QRCodeView.makeImage(text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .overlay(
                        Image(systemName: "qrcode")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    static func makeImage(_ string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
