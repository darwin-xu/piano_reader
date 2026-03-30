import AVFoundation
import Foundation

public enum AudioFileLoaderError: Error, LocalizedError {
    case unsupportedSampleFormat(URL)
    case emptyFile(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSampleFormat(let url):
            return "Unsupported sample format for \(url.lastPathComponent)."
        case .emptyFile(let url):
            return "Audio file \(url.lastPathComponent) does not contain samples."
        }
    }
}

public enum AudioFileLoader {
    public static func load(from url: URL) throws -> AudioClip {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else {
            throw AudioFileLoaderError.emptyFile(url)
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioFileLoaderError.unsupportedSampleFormat(url)
        }

        try file.read(into: buffer)
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let frameLength = Int(buffer.frameLength)

        var mono = [Float](repeating: 0, count: frameLength)

        if let floatChannels = buffer.floatChannelData {
            for channelIndex in 0..<channelCount {
                let samples = floatChannels[channelIndex]
                for frameIndex in 0..<frameLength {
                    mono[frameIndex] += samples[frameIndex] / Float(channelCount)
                }
            }
        } else if let int16Channels = buffer.int16ChannelData {
            let scale = 1.0 / Float(Int16.max)
            for channelIndex in 0..<channelCount {
                let samples = int16Channels[channelIndex]
                for frameIndex in 0..<frameLength {
                    mono[frameIndex] += Float(samples[frameIndex]) * scale / Float(channelCount)
                }
            }
        } else {
            throw AudioFileLoaderError.unsupportedSampleFormat(url)
        }

        return AudioClip(fileURL: url, samples: mono, sampleRate: sampleRate)
    }
}
