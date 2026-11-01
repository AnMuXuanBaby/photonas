import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var portDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                thumbnailSection
                paginationSection
                cacheSection
                powerSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                portDraft = String(model.settings.serverPort)
            }
        }
    }

    // MARK: - 分区

    private var serverSection: some View {
        Section {
            HStack {
                Text("端口")
                Spacer()
                TextField("8080", text: $portDraft)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 86)
                Button("应用") {
                    if let value = Int(portDraft) {
                        var next = model.settings
                        next.serverPort = value
                        model.settings = next
                        portDraft = String(model.settings.serverPort)
                    } else {
                        portDraft = String(model.settings.serverPort)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .disabled(Int(portDraft) == model.settings.serverPort)
            }
            TextField("设备名称（留空则用本机名称）", text: $model.settings.serverNickname)
            Toggle("启动 App 时自动开启服务", isOn: $model.settings.autoStartServer)
        } header: {
            Text("服务")
        } footer: {
            Text("端口修改后服务会自动重启。建议使用 1024 以上的端口。")
        }
    }

    private var thumbnailSection: some View {
        Section {
            Picker("缩略图格式", selection: $model.settings.thumbnailFormat) {
                Text("WEBP").tag(ThumbnailFormat.webp)
                Text("JPEG").tag(ThumbnailFormat.jpeg)
            }
            .pickerStyle(.segmented)

            if ImageEncoding.isWebPAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("压缩质量")
                        Spacer()
                        Text("\(Int(currentQuality * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: qualityBinding, in: 0.4...1.0, step: 0.02)
                }
            } else {
                Text("当前构建没有可用的 WEBP 编码器，将自动回退为 JPEG。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("网格缩略图", selection: $model.settings.gridThumbnailPixels) {
                Text("300 px").tag(300)
                Text("400 px").tag(400)
                Text("500 px").tag(500)
            }

            Picker("大图预览", selection: $model.settings.viewerThumbnailPixels) {
                Text("1080 px").tag(1080)
                Text("1440 px").tag(1440)
                Text("2048 px").tag(2048)
            }
        } header: {
            Text("缩略图")
        } footer: {
            Text("缩略图由 PHImageManager 异步生成后缓存在 App 沙盒。WEBP 通常比 JPEG 小 25%–35%，局域网加载更快。")
        }
    }

    private var paginationSection: some View {
        Section {
            Picker("每页数量", selection: $model.settings.pageSize) {
                Text("20 张").tag(20)
                Text("40 张").tag(40)
                Text("60 张").tag(60)
                Text("100 张").tag(100)
            }
        } header: {
            Text("加载策略")
        } footer: {
            Text("网页端滚动到底部自动加载下一页，只按需读取当前页，不会一次性遍历上万张照片。")
        }
    }

    private var cacheSection: some View {
        Section {
            Picker("缩略图缓存上限", selection: $model.settings.thumbnailCacheLimitMB) {
                Text("200 MB").tag(200)
                Text("400 MB").tag(400)
                Text("600 MB").tag(600)
                Text("1000 MB").tag(1000)
            }
            Picker("原图缓存上限", selection: $model.settings.originalCacheLimitMB) {
                Text("500 MB").tag(500)
                Text("1 GB").tag(1000)
                Text("2 GB").tag(2000)
                Text("4 GB").tag(4000)
            }
            LabeledContent("缩略图占用", value: model.thumbnailCacheText)
            LabeledContent("原图占用", value: model.originalCacheText)
            Button("清空缩略图缓存") {
                model.clearThumbnailCache()
            }
            Button("清空原图缓存") {
                model.clearOriginalCache()
            }
        } header: {
            Text("缓存")
        } footer: {
            Text("采用 LRU 淘汰：容量超限时自动删除最久未使用的文件。")
        }
    }

    private var powerSection: some View {
        Section {
            Picker("锁屏 / 后台行为", selection: $model.settings.lockPolicy) {
                ForEach(LockPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            Toggle("允许从 iCloud 下载原图", isOn: $model.settings.allowICloudDownload)
        } header: {
            Text("省电")
        } footer: {
            Text("\(model.settings.lockPolicy.detail)\n选择「继续运行」时会用静音音频保活，耗电会增加；选择「自动暂停」最省电。")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: "1.0.0")
            LabeledContent("安装方式", value: "TrollStore / 未签名 IPA")
            Button("重新扫描相册") {
                model.rescanLibrary()
            }
            Text("TrollStore 直接安装本 IPA 即可，无需证书。首次启动请允许「相册」与「本地网络」权限。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("关于")
        }
    }

    // MARK: - 绑定

    private var currentQuality: Double {
        model.settings.thumbnailFormat == .webp ? model.settings.webpQuality : model.settings.jpegQuality
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { currentQuality },
            set: { newValue in
                var next = model.settings
                if next.thumbnailFormat == .webp {
                    next.webpQuality = newValue
                } else {
                    next.jpegQuality = newValue
                }
                model.settings = next
            }
        )
    }
}
