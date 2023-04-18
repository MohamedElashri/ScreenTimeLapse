import Foundation
import ScreenCaptureKit
import AVFoundation
import SwiftUI


/// Records the output of a screen in a stream-like format
class Screen: NSObject, SCStreamOutput, Recordable {
    var state: RecordingState = .stopped
    var lastSavedFrame: CMTime?
    var metaData: OutputInfo = OutputInfo()
    var enabled: Bool = false
    var writer: AVAssetWriter?
    var input: AVAssetWriterInput?
    
    // ScreenCaptureKit-Specific Functionality
    var screen: SCDisplay
    var stream: SCStream?
    var showCursor: Bool
        
    override var description: String {
        "[\(screen.width) x \(screen.height)] - Display \(screen.displayID)"
    }
    
    init(screen: SCDisplay, showCursor: Bool) {
        self.screen = screen
        self.showCursor = showCursor
    }
    
    // MARK: -User Interaction
    
    func startRecording() {
        if(self.state == .recording){return;}
        
        self.state = .recording
        setup(path: getFilename(), excluding: []) // TODO: implement logic which actually gets the excluding
        
        print("\(self.writer)")
        print("\(self.input)")
    }
    
    func pauseRecording() {
        self.state = .paused
    }
    
    func resumeRecording() {
        self.state = .recording
    }
    
    func saveRecording() {
        self.state = .stopped
        
        // TODO: save the file
    }
    
    func setup(path: String, excluding: [SCRunningApplication]) {
        do{
            (self.writer, self.input) = try setupWriter(screen: screen, path:path)
            try setupStream(screen: screen, showCursor: showCursor, excluding: excluding)
        } catch{
            print("Failed")
        }
    }
       
    func setupWriter(screen: SCDisplay, path: String) throws -> (AVAssetWriter, AVAssetWriterInput) { // TODO: convert this to a task
        // Creates the video input
        let outputSettings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: screen.width,
            AVVideoHeightKey: screen.height
        ]
        
        let url = URL(string: path, relativeTo: URL.desktopDirectory)!

        print("URL: \(url)")
        let writer = try AVAssetWriter(url: url, fileType: .mov)
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        
        print(writer.canAdd(input))
        writer.add(input) // TODO: Check if connecting these makes this work
    
        return (writer, input)
    }
    
    func setupStream(screen: SCDisplay, showCursor: Bool, excluding: [SCRunningApplication]) throws {
        let contentFilter = SCContentFilter(display: screen, excludingApplications: excluding, exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.width = screen.width
        config.height = screen.height
        config.showsCursor = showCursor
        
        stream = SCStream(filter: contentFilter, configuration: config, delegate: StreamDelegate())
        try stream!.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .background))
        stream!.startCapture(completionHandler: handleStreamStartFailure)
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer: CMSampleBuffer, of: SCStreamOutputType) {
        if self.state != .recording{
            return 
        }
        
        switch of{
            case .screen:
                handleVideo(buffer: didOutputSampleBuffer)
            case .audio:
                print("Audio should not be captured")
            default:
                print("Unknown future case")
        }
    }
    
    func getFilename() -> String {
        // TODO: change this back to CMTime().seconds
        "\(screen.displayID)-\(1000).mov"
    }
}

class StreamDelegate : NSObject, SCStreamDelegate{
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("The stream stopped")
    }
}
