import Foundation

public struct DetectionFrame: Codable, Sendable {
    public let frameIndex: Int
    public let timestampSeconds: Double
    public let frequencyHz: Double?
    public let confidence: Double
    public let rms: Double
    public let noteName: String?
    public let centsOffset: Double?
    public let isVoiced: Bool

    public init(
        frameIndex: Int,
        timestampSeconds: Double,
        frequencyHz: Double?,
        confidence: Double,
        rms: Double,
        noteName: String?,
        centsOffset: Double?,
        isVoiced: Bool
    ) {
        self.frameIndex = frameIndex
        self.timestampSeconds = timestampSeconds
        self.frequencyHz = frequencyHz
        self.confidence = confidence
        self.rms = rms
        self.noteName = noteName
        self.centsOffset = centsOffset
        self.isVoiced = isVoiced
    }
}

public struct ClipDetection: Codable, Sendable {
    public let dominantPitch: DetectionFrame?
    public let voicedFrameCount: Int
    public let totalFrameCount: Int
    public let analysisSampleRate: Double
    public let frameSize: Int
    public let hopSize: Int
    public let frames: [DetectionFrame]

    public init(
        dominantPitch: DetectionFrame?,
        voicedFrameCount: Int,
        totalFrameCount: Int,
        analysisSampleRate: Double,
        frameSize: Int,
        hopSize: Int,
        frames: [DetectionFrame]
    ) {
        self.dominantPitch = dominantPitch
        self.voicedFrameCount = voicedFrameCount
        self.totalFrameCount = totalFrameCount
        self.analysisSampleRate = analysisSampleRate
        self.frameSize = frameSize
        self.hopSize = hopSize
        self.frames = frames
    }
}

public struct AudioClip: Sendable {
    public let fileURL: URL
    public let samples: [Float]
    public let sampleRate: Double

    public init(fileURL: URL, samples: [Float], sampleRate: Double) {
        self.fileURL = fileURL
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

public protocol PitchDetector: Sendable {
    func analyze(audioClip: AudioClip) throws -> ClipDetection
}

// MARK: - Multi-pitch detection

public struct DetectedNote: Codable, Sendable {
    public let midi: Int
    public let name: String
    public let pitchClass: String
    public let frequencyHz: Double
    public let salience: Double

    public init(midi: Int, name: String, pitchClass: String, frequencyHz: Double, salience: Double) {
        self.midi = midi
        self.name = name
        self.pitchClass = pitchClass
        self.frequencyHz = frequencyHz
        self.salience = salience
    }
}

public struct MultiPitchClipDetection: Codable, Sendable {
    public let detectedNotes: [DetectedNote]
    public let frameCount: Int
    public let sampleRate: Double

    public init(detectedNotes: [DetectedNote], frameCount: Int, sampleRate: Double) {
        self.detectedNotes = detectedNotes
        self.frameCount = frameCount
        self.sampleRate = sampleRate
    }
}

public protocol MultiPitchDetector: Sendable {
    func analyzeMulti(audioClip: AudioClip) throws -> MultiPitchClipDetection
}
