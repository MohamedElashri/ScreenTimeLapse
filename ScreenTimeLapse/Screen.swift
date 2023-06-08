import Foundation
import ScreenCaptureKit
import AVFoundation
import SwiftUI

/// Records the output of a `SCDisplay` in a stream-like format using `SCStreamOutput`
///
/// Saves `CMSampleBuffers` into ``input`` and outputs then to ``writer``
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
        guard self.enabled else { return }
        guard self.state != .recording else { return }
        
        self.state = .recording
        setup(path: getFilename(), excluding: []) // TODO: implement logic which actually gets the excluding
    }
    
    func pauseRecording() {
        self.state = .paused
    }
    
    func resumeRecording() {
        self.state = .recording
    }
    
    func saveRecording() {
        guard self.enabled else { return }
        
        self.state = .stopped
        
        logger.log("Screen -- saved recording")
        
        // given this is a UI task, the main thread is running this application
        // screen recording is happening on another thread, a screen recorder might
        // be in the middle of appending data or handling data when this is happening
       
        // the stream of data needs to be stopped as per my notes on this
        // a pseudo-blocking data structure needs to exist to wait until the status is non-zero
        
        if let stream = stream {
            stream.stopCapture()
        }
        
        while(!(input?.isReadyForMoreMediaData ?? false)){
            logger.log("Not able to mark the stream as finished")
            sleep(1) // sleeping for a second
        }
        
        input?.markAsFinished()
        writer!.finishWriting { [self] in
            if self.writer!.status == .completed {
                // Asset writing completed successfully
            } else if writer!.status == .failed {
                // Asset writing failed with an error
                if let error = writer!.error {
                    logger.error("Asset writing failed with error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Sets up both *writing* and *saving*
    ///
    /// Creates ``writer`` and ``input`` to write assets
    /// Sets up the stream to use ``self`` as `SCStreamOutput`
    func setup(path: String, excluding: [SCRunningApplication]) {
        Task(priority: .userInitiated){
            do{
                (self.writer, self.input) = try setupWriter(screen: screen, path: path)
                
                logger.log("Setup Asset Writer \(self.writer)")
                logger.log("Setup Asset Writer Input \(self.input)")
                
                try setupStream(screen: screen, showCursor: showCursor, excluding: excluding)
                
                logger.debug("Setup stream")
            } catch{
                logger.error("Failed to setup stream")
            }
        }
    }
    
    /// Sets up the `AVAssetWriter` and `AVAssetWriterInput`
    ///
    /// ``stream(_:didOutputSampleBuffer:of:)`` relies on this to save data
    func setupWriter(screen: SCDisplay, path: String) throws -> (AVAssetWriter, AVAssetWriterInput) {
        let videoOutputSettings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: screen.width,
            AVVideoHeightKey: screen.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000, // Good for HEVC
            ]
        ]
        
        let audioOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000,
        ]
        
        let url = URL(string: path, relativeTo: .temporaryDirectory)!

        logger.debug("URL: \(url)")
        logger.debug("Path: \(path)")
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
                        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
        input.expectsMediaDataInRealTime = true
        
        logger.debug("Can I add the AssetWriterInput? \(writer.canAdd(input))")
        
        writer.add(input)
        
        debugPrintStatus(writer.status)
        
        return (writer, input)
    }
    
    /// Creates an `SCStream` with correct `filter` and `configuration`. ``self`` is set to recieve this data
    func setupStream(screen: SCDisplay, showCursor: Bool, excluding: [SCRunningApplication]) throws {
        let contentFilter = SCContentFilter(
            display: screen,
            excludingApplications: excluding,
            exceptingWindows: []
        )
        
        let config = SCStreamConfiguration()
        config.width = screen.width
        config.height = screen.height
        config.showsCursor = showCursor
        
        stream = SCStream(
            filter: contentFilter,
            configuration: config,
            delegate: StreamDelegate()
        )
        
        try stream!.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: .global(qos: .userInitiated)
        )
        
        stream!.startCapture(completionHandler: handleStreamStartFailure)
    }
    
    /// Generates a filename specific to `SCDisplay` and `CMTime`
    func getFilename() -> String {
        let randomValue = Int(arc4random_uniform(100_000)) + 1
        return "\(screen.displayID)-\(randomValue).mp4"
    }
    
    /// Saves each `CMSampleBuffer` from the screen
    func stream(_ stream: SCStream, didOutputSampleBuffer: CMSampleBuffer, of: SCStreamOutputType) {
        guard self.state == .recording else { return }
        
        guard didOutputSampleBuffer.isValid else {
            logger.error("The sample buffer IS NOT valid")
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
}

/// Defines behavior when the state of the `SCStream` changes.
///
/// Technically required, but less used in this instance
class StreamDelegate : NSObject, SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("The stream stopped with \(error.localizedDescription)")
    }
}
