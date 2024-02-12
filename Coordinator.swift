import AVFoundation
import Foundation

class Coordinator: NSObject, AVSpeechSynthesizerDelegate {
    
    let synthesizer: AVSpeechSynthesizer
    var audioEngine: AVAudioEngine
    var audioPlayerNode: AVAudioPlayerNode?
    var audioFilesQueue: [URL] = []
    var speakPhrasesQueue: [String] = []
    var anotherappPlaying = false
    let audsession = AVAudioSession.sharedInstance()
    
    override init() {
        self.synthesizer = AVSpeechSynthesizer()
        self.audioEngine = AVAudioEngine()
        super.init()
        self.synthesizer.delegate = self
        configureAudioSession()
        observeAudioSessionNotifications()
        
    }
    func observeAudioSessionNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .duckOthers)
            try session.setActive(true)
        } catch let error as NSError {
            print("Error configuring audio session: \(error.localizedDescription)")
            print("Error code: \(error.code)")
        }
    }
    func duckVolume() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Error ducking volume: \(error.localizedDescription)")
        }
    }
    
    func restoreAudioSession() {
        do {
            // Stop or pause all audio playback and recording
            audioEngine.stop()
            audioEngine.disconnectNodeOutput(audioEngine.mainMixerNode)
            
            // Wait for the audio engine to fully stop before deactivating the audio session
            while audioEngine.isRunning {
                // Wait for the audio engine to stop
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            // Introduce a delay before deactivating the audio session
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                do {
                    // Deactivate the audio session
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    
                    // Notify other apps, like Spotify, to resume playback
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Error deactivating or reactivating audio session: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error stopping audio engine: \(error.localizedDescription)")
        }
    }
    
    func speakPhrase(phrase: String) {
        if !phrase.isEmpty {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoiceIdentifierAlex)
            synthesizer.speak(utterance)
        } else {
            print("Empty phrase. Cannot speak.")
        }
    }
    
    
    func playFile(filePath: URL, thenSpeakPhrase phrase: String) {
        print("Trying to play the file")
        
        do {
            let audioFile = try AVAudioFile(forReading: filePath)
            audioPlayerNode = AVAudioPlayerNode()
            audioEngine.attach(audioPlayerNode!)
            
            audioEngine.connect(audioPlayerNode!, to: audioEngine.mainMixerNode, format: audioFile.processingFormat)
            audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: audioFile.processingFormat)
            
            audioPlayerNode?.scheduleFile(audioFile, at: nil) {
                // Play the next file in the queue recursively
                self.playQueue()
            }
            audioEngine.prepare()
            try audioEngine.start()
            audioPlayerNode?.play()
            
        } catch let error {
            print("Error playing file: \(error.localizedDescription)")
            // Restore audio session in case of error
            restoreAudioSession()
        }
    }
    
    func playAudio(soundFile: String, alertTextmessage: String) {
        
        //   configureAudioSession()
        if let waveFileURL = Bundle.main.url(forResource: soundFile, withExtension: "wav") {
            do {
                // Create an AVAudioFile from the wave file URL
                let audioFile = try AVAudioFile(forReading: waveFileURL)
                
                // Calculate the duration of the audio file based on its length and format
                let audioFormat = audioFile.processingFormat
                let audioFrameCount = UInt64(audioFile.length)
                let audioDuration = Double(audioFrameCount) / audioFormat.sampleRate
                
                // Create an AVAudioPlayerNode and attach it to the audio engine
                let playerNode = AVAudioPlayerNode()
                audioEngine.attach(playerNode)
                
                // Connect the player node to the main mixer node
                audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
                
                // Schedule the audio file for playback on the player node
                playerNode.scheduleFile(audioFile, at: nil)
                
                // Start the audio engine
                try audioEngine.start()
                
                // Start playback of the wave file
                playerNode.play()
                
                // After the wave file finishes playing, speak the text
                DispatchQueue.main.asyncAfter(deadline: .now() + audioDuration) {
                    self.speakPhrase(phrase: alertTextmessage)
                }
            } catch {
                print("Error playing wave file: \(error.localizedDescription)")
            }
        } else {
            print("Wave file not found.")
        }
    }
    
    @objc func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Another app started playing audio
            anotherappPlaying = true
            print("Another app started playing audio")
        case .ended:
            anotherappPlaying = false
            // The audio session interruption ended
            print("Another app ended playing audio")
            configureAudioSession()
        }
    }
    
    func addToQueue(fileURL: URL, speakPhrase: String) {
        audioFilesQueue.append(fileURL)
        speakPhrasesQueue.append(speakPhrase)
        // If queue was empty, start playing the queue
        if audioFilesQueue.count == 1 {
            playQueue()
        }
    }
    
    func playQueue() {
        guard !audioFilesQueue.isEmpty else {
            print("Queue is empty.")
            return
        }
        let nextFileURL = audioFilesQueue.removeFirst()
        let nextSpeakPhrase = speakPhrasesQueue.isEmpty ? "" : speakPhrasesQueue.removeFirst()
        // Speak the phrase before playing the audio file
        speakPhrase(phrase: nextSpeakPhrase)
        // Delay playback to ensure speech synthesis completes before playing audio
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.playFile(filePath: nextFileURL, thenSpeakPhrase: nextSpeakPhrase)
        }
    }
    
    func stopCurrentPlayback() {
        if let playerNode = audioPlayerNode, playerNode.isPlaying {
            playerNode.stop()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("Speech synthesis cancelled")
        // Proceed with playing the next audio file
        playQueue()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Speech synthesis finished")
        // Proceed with playing the next audio file
        playQueue()
    }
    
}
// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVAudioSessionCategory(_ input: AVAudioSession.Category) -> String {
    return input.rawValue
}
