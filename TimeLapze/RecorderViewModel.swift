import ScreenCaptureKit
import AVFoundation

/// Represents a syncronized session of ``Recordable`` objects
class RecorderViewModel: ObservableObject {
    @Published var apps: [SCRunningApplication : Bool] = [:]
    
    @Published var cameras: [Camera] = []
    @Published var screens: [Screen] = []
    
    @Published var state: RecordingState = .stopped
    @Published var showCursor: Bool = false
    
    /// Makes an asyncronous call to `ScreenCaptureKit` to get valid `SCScreens` and `SCRunningApplication`s connected to the computer
    @MainActor
    func getDisplayInfo() async {
        do{
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            
            self.apps = convertApps(apps: content.applications)
            self.screens = convertDisplays(displays: content.displays)
        }catch{
            print(error.localizedDescription)
        }
    }
    
    init() {
        getCameras()
        Task(priority: .userInitiated){
            await getDisplayInfo()
        }
    }
    
    /// Gets all cameras attached to the computer and creates ``MyRecordingCamera``s for them
    func getCameras(){
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified)
        
        self.cameras = convertCameras(camera: discovery.devices)
    }
    
    /// This functions inverts the ``self.apps`` list from include to exclude
    /// - Returns: The list of apps which should be disabled
    func getExcludedApps() -> [SCRunningApplication]{
        return self.apps.filter{elem in
            !elem.value
        }.map{elem in elem.key}
    }
    
    /// Breaks aparts `apps` to what should be **included**
    var includedApps: [SCRunningApplication] {
        apps.keys.filter{apps[$0]!}.sorted(by: <)
    }
    
    /// Breaks aparts `apps` to what should be **excluded**
    var excludedApps: [SCRunningApplication] {
        apps.keys.filter{!apps[$0]!}.sorted(by: <)
    }
    
    // MARK: -Recording
    
    /// Starts recording ``cameras`` and ``screens``
    func startRecording(){
        self.state = .recording
        
        logger.log("Started recording at RecorderViewModel")
        
        let excludedApps = apps.filter{ !$0.value }.map{ $0.key }
        
        self.cameras.indices
            .forEach{ index in
                cameras[index].startRecording()
            }
        
        self.screens.indices
            .forEach{ index in
                screens[index].startRecording(excluding: excludedApps, showCursor: showCursor)
            }
    }
    
    /// Pauses recording ``screens`` and ``cameras``
    func pauseRecording(){
        self.state = .paused
        
        self.cameras.indices
            .forEach{ index in
                cameras[index].pauseRecording()
            }
        
        self.screens.indices
            .forEach{ index in
                screens[index].pauseRecording()
            }
    }
    
    /// Resumes recoriding ``screens`` and ``cameras``
    func resumeRecording(){
        self.state = .recording
        
        self.cameras.indices
            .forEach{ index in
                cameras[index].resumeRecording()
            }
        
        self.screens.indices
            .forEach{ index in
                screens[index].resumeRecording()
            }
    }
    
    func stopRecording(){
        self.state = .stopped
        
        self.cameras.indices
            .forEach{ index in
                cameras[index].stopRecording()
            }
        
        self.screens.indices
            .forEach{ index in
                screens[index].stopRecording()
            }
    }
    
    /// Saves the ``cameras`` and ``screens``
    func saveRecordings(){
        self.cameras.indices
            .forEach{ index in
                cameras[index].saveRecording()
            }
        
        self.screens.indices
            .forEach{ index in
                screens[index].saveRecording()
            }
    }
    
    // MARK: -Toggles
    
    func toggleScreen(screen: Screen){
        screen.enabled.toggle()
        objectWillChange.send()
    }
    
    /// Turns a `SCRunningApplication` on or off in the ``apps`` dictionary
    func toggleApp(app: SCRunningApplication){
        if let row = apps.first(where: {$0.key.processID == app.processID}){
            apps[row.key] = !row.value
        }
        objectWillChange.send()
    }
    
    /// Toggles a ``Camera``
    ///
    /// Rather than a dictionary like ``apps`` this was encapsulated in a custom struct
    func toggleCameras(camera: Camera){
        camera.enabled.toggle()
        objectWillChange.send()
    }
    
    /// Checks to make sure at least one ``Screen`` or ``Camera`` is enabled
    func recordersDisabled() -> Bool{
        !(cameras.contains{ $0.enabled } || screens.contains{ $0.enabled })
    }
    
    // MARK: -Applications Menu
    
    /// Flips the enabled and disabled app in ``apps``
    func invertApplications() {
        for appName in self.apps.keys{
            self.apps[appName]!.toggle()
        }
    }
    
    /// Resets ``apps`` by setting each `value` to `true`
    func resetApps() {
        for appName in self.apps.keys{
            self.apps[appName]! = true // enabled by default
        }
        
        refreshApps()
    }
    
    /// Refreshes ``apps`` to get new infromation
    ///
    /// Ideally, finding new apps would be done in a periodic manner
    func refreshApps() {
        Task(priority: .userInitiated){
            await getDisplayInfo()
        }
    }
    
    /// Generates an dictionary with `SCRunningApplication` keys and `Bool` value
    private func convertApps(apps input: [SCRunningApplication]) -> [SCRunningApplication : Bool]{
        let returnApps = input
            .filter{app in
                Bundle.main.bundleIdentifier != app.bundleIdentifier
                && !app.applicationName.isEmpty
            }
            .map{ app in
                (app, self.apps[app] ?? true)
            }
        
        return Dictionary(uniqueKeysWithValues: returnApps)
    }
    
    /// Turns an array of `SCDisplays` into new ``Screen``s
    private func convertDisplays(displays input: [SCDisplay]) -> [Screen]{
        var newScreens = input
            .filter{ display in
                !self.screens.contains{recorder in
                    recorder.screen == display
                }}
            .map(getScreenRecorder)
        
        for screen in self.screens{
            newScreens.append(screen)
        }
        
        newScreens = newScreens
            .sorted{ (first, second) in
                first.screen.displayID < second.screen.displayID
            }
        
        if self.screens.isEmpty, !newScreens.isEmpty{
            newScreens.first!.enabled = true
        }
        
        return newScreens
    }
    
    /// Converts a `AVCaptureDevice` array from from a Discovery session into custom ``Camera`` object
    private func convertCameras(camera input: [AVCaptureDevice]) -> [Camera]{
        var newCameras = input
            .filter{ camera in
                !self.cameras.contains{ recorder in
                    recorder.inputDevice == camera
                }
            }.map(getCameraRecorder)
        
        for camera in self.cameras{
            newCameras.append(camera)
        }
        
        newCameras = newCameras
            .sorted{ (first, second) in
                first.inputDevice.uniqueID < second.inputDevice.uniqueID
            }
        
        return newCameras
    }
    
    // MARK: -Timing
    
    /// Returns the current time (in output units) of the recording
    var currentTime : CMTime {
        for screen in screens {
            if screen.enabled {
                return screen.time
            }
        }
        
        for camera in cameras {
            if camera.enabled {
                return camera.time
            }
        }
        
        return CMTime.zero
    }
    
    // MARK: -Recorder Creation
    
    /// Converts a `SCDisplay` into a ``Screen``
    private func getScreenRecorder(_ screen: SCDisplay) -> Screen{
        Screen(screen: screen, showCursor: showCursor)
    }
    
    /// Converts a `AVCaptureDevice` into a ``Camera``
    private func getCameraRecorder(_ camera: AVCaptureDevice) -> Camera{
        Camera(camera: camera)
    }
}
