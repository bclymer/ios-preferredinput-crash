import UIKit
import AVFoundation

// Forgive the low quality code, it's a PoC after all.
class ViewController: UIViewController, AVCaptureAudioDataOutputSampleBufferDelegate {

    private enum CaptureMode {
        case avCaptureSession
        case avAudioEngine
    }

    private let captureMode: CaptureMode = .avAudioEngine
    private var captureSession: AVCaptureSession?
    private var audioEngine: AVAudioEngine?
    private var lastSampleRate: Float64 = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        try! AVAudioSession.sharedInstance().setCategory(.record, mode: .videoRecording, options: .allowBluetooth)
        try! AVAudioSession.sharedInstance().setActive(true)

        // An array of notifications to print to the console when they fire
        [
            AVAudioSession.mediaServicesWereLostNotification,
            AVAudioSession.mediaServicesWereResetNotification,
            AVAudioSession.interruptionNotification,
            AVAudioSession.routeChangeNotification,
            NSNotification.Name.AVAudioEngineConfigurationChange,
            NSNotification.Name.AVCaptureInputPortFormatDescriptionDidChange,
            NSNotification.Name.AVCaptureSessionRuntimeError,
            NSNotification.Name.AVCaptureSessionWasInterrupted,
            NSNotification.Name.AVCaptureSessionInterruptionEnded,
            NSNotification.Name.AVCaptureSessionDidStopRunning,
            NSNotification.Name.AVCaptureSessionDidStartRunning,
        ].forEach { printNotification(name: $0) }
        createAndAttachMic()
    }

    private func printNotification(name: NSNotification.Name) {
        // this will just print the name of the notification for visibility into what is happening.
        NotificationCenter.default.addObserver(self, selector: #selector(somethingHappenedToServices(_:)), name: name, object: nil)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let format = CMSampleBufferGetFormatDescription(sampleBuffer)!
        let audioDescription: AudioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)!.pointee
        let sampleRate = audioDescription.mSampleRate
        if sampleRate != lastSampleRate {
            print("AVCaptureSession - Received a new sample rate of \(sampleRate) from \(AVAudioSession.sharedInstance().currentRoute.inputs.first!.portName)")
            lastSampleRate = sampleRate
        }
    }

    @IBAction private func swapDevices() {
        let isCurrentlyBluetooth = AVAudioSession.sharedInstance().currentRoute.inputs.first!.portType == .bluetoothHFP
        // If currently bluetooth, grab a non-bluetooth and vice-versa
        let newPort = AVAudioSession.sharedInstance().availableInputs?
            .first(where: { ($0.portType == .bluetoothHFP) != isCurrentlyBluetooth })
        guard let validPort = newPort else {
            print("Couldn't find a valid port. Looking for a \(isCurrentlyBluetooth ? "non-" : "")bluetooth port")
            return
        }
        switch captureMode {
        case .avCaptureSession:
            audioEngine?.stop()
            audioEngine = nil
        case .avAudioEngine:
            captureSession?.stopRunning()
            captureSession = nil
        }
        print("Swapping \(AVAudioSession.sharedInstance().currentRoute.inputs.first!.portName) for \(validPort.portName)")
        try! AVAudioSession.sharedInstance().setPreferredInput(newPort)
        createAndAttachMic()
    }

    private func createAndAttachMic() {
        switch captureMode {
        case .avCaptureSession:
            let cap = AVCaptureSession()
            cap.automaticallyConfiguresApplicationAudioSession = false
            let device = AVCaptureDevice.default(for: .audio)!
            let input = try! AVCaptureDeviceInput(device: device)
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "test-queue"))
            cap.beginConfiguration()
            cap.addInput(input)
            cap.addOutput(output)
            cap.commitConfiguration()
            cap.startRunning()
            captureSession = cap
        case .avAudioEngine:
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let bus = 0
            inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputNode.inputFormat(forBus: 0)) { (buffer, time) in
                if time.sampleRate != self.lastSampleRate {
                    print("AVAudioEngine - Received a new sample rate of \(time.sampleRate) from \(AVAudioSession.sharedInstance().currentRoute.inputs.first!.portName)")
                    self.lastSampleRate = time.sampleRate
                }
            }
            engine.prepare()
            try! engine.start()
            audioEngine = engine
        }

        print("Connected \(AVAudioSession.sharedInstance().currentRoute.inputs.first!.portName) with new capture session")
    }

    @objc
    private func somethingHappenedToServices(_ notification: Notification) {
        print(notification.name.rawValue)
    }

}
