import Foundation
import AVFoundation
import UIKit

/// 锁屏/后台保活：用静音音频维持后台运行，配合 beginBackgroundTask 兜底。
final class BackgroundKeeper {
    private var player: AVAudioPlayer?
    private var task: UIBackgroundTaskIdentifier = .invalid
    private(set) var isActive = false

    func start() {
        guard !isActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            NSLog("[PhotoNAS] 音频会话激活失败：\(error)")
        }

        let url = silentFileURL()
        if let url, let audioPlayer = try? AVAudioPlayer(contentsOf: url) {
            audioPlayer.numberOfLoops = -1
            audioPlayer.volume = 0
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            player = audioPlayer
            isActive = true
        }

        task = UIApplication.shared.beginBackgroundTask(withName: "PhotoNAS Server") { [weak self] in
            self?.endTask()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isActive = false
        endTask()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func endTask() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }

    private func silentFileURL() -> URL? {
        let url = AppDirs.caches.appendingPathComponent("photonas-silence.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let data = Self.silentWav(duration: 4.0)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func silentWav(duration: Double) -> Data {
        let sampleRate: UInt32 = 8000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 8
        let frames = UInt32(duration * Double(sampleRate))
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = frames * UInt32(blockAlign)

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(36 + dataSize, to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(channels, to: &data)
        appendUInt32(sampleRate, to: &data)
        appendUInt32(byteRate, to: &data)
        appendUInt16(blockAlign, to: &data)
        appendUInt16(bitsPerSample, to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(dataSize, to: &data)
        data.append(contentsOf: [UInt8](repeating: 128, count: Int(dataSize)))
        return data
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { raw in
            data.append(contentsOf: raw)
        }
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { raw in
            data.append(contentsOf: raw)
        }
    }
}
