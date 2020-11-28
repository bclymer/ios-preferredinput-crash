# ios-preferredinput-crash

## What Is This?

This project is meant to demonstrate a method of consistently getting `AVAudioSession` to consistently fire `AVAudioSessionMediaServicesWereLostNotification` and `AVAudioSessionMediaServicesWereResetNotification`. According to Apple's documentation, these events should be rare

> Under rare circumstances, the system terminates and restarts its media services daemon.

So a method that uses only AVFoundation APIs (no direct use of Core Audio) that causes this to happen seems noteworthy.

## Explain the Issue

This happens when a bluetooth device is set as the preferred input with `AVAudioSession` and it disconnects while polling. The media services reset will happen while polling with either `AVCaptureSession` or `AVAudioEngine` (it's possible they both use the same API under the hood anyway for polling like `kAudioOutputUnitProperty_SetInputCallback`).

If the same bluetooth device is the implicit route (`preferredInput` is `nil` but it's the last device to connect) the reset does not happen, it must be explicit.

You can follow the repro steps below to cause the reset. Change the `captureMode` variable in `ViewController.swift` to change whether you use `AVAudioEngine` or `AVCaptureSession` to cause the reset.

## Impacted Devices / OS

All of my devices reproduce this issue. However, I don't have unlimited devices, so here's what I know this happens on
| Device Name | OS |
| -- | -- |
| iPhone 7 | iOS 14.2 |
| iPhone Xr | iOS 14.0.1 |
| iPad Air 2 | iOS 13.7 |

## Repro Steps

This project makes it easy to recreate the scenario that leads to a crash. It's easiest to have a bluetooth device that can provide input connected before launching the app. I am using a headset with the name `WH-1000XM3` for this example.

1. Launch the app. You will something like the following printed immediately.
    ```
    Connected WH-1000XM3 with new capture session
    AVAudioSessionRouteChangeNotification
    AVAudioEngine - Received a new sample rate of 16000.0 from WH-1000XM3
    ```
    This means a new session has started with your bluetooth headset as the current route. Then `AVAudioSession` posted a notification about the route changing, and finally `AVAudioEngine` receives input, and prints that the input is coming in at 16k Hz (the sample rate of my bluetooth headset).
1. Tap the "Swap" button on the screen. Now it should print:
    ```
    Swapping WH-1000XM3 for iPhone Microphone
    Connected iPhone Microphone with new capture session
    AVAudioSessionRouteChangeNotification
    AVAudioEngine - Received a new sample rate of 44100.0 from iPhone Microphone
    ````
    The first line is just for debugging info, stating the old and new input routes. Then it verifies that a new session was actually created with the new route. Once again `AVAudioSession` notifies you that a route change happens, and finally you get a callback with a new sample rate, because the default built-in mic runs at 44100 Hz.
1. Tap the "Swap" button one more time. It will again print
    ```
    Swapping iPhone Microphone for WH-1000XM3
    Connected WH-1000XM3 with new capture session
    AVAudioSessionRouteChangeNotification
    AVAudioEngine - Received a new sample rate of 16000.0 from WH-1000XM3
    ```
    This is the same as app launch, but now your bluetooth device is the explicit input, not implicit.
1. Turn off your bluetooth headset. This will print:
    ```
    AVAudioSessionMediaServicesWereLostNotification
    AVAudioSessionMediaServicesWereResetNotification
    ```
    This is a failure, all media services are shut down during this time. You can't do any I/O with video or audio.

It is important to note that out of all the notifications that we are listening to none of them fire before media services are lost.
```
AVAudioSession.interruptionNotification,
AVAudioSession.routeChangeNotification,
NSNotification.Name.AVAudioEngineConfigurationChange,
NSNotification.Name.AVCaptureInputPortFormatDescriptionDidChange,
NSNotification.Name.AVCaptureSessionRuntimeError,
NSNotification.Name.AVCaptureSessionWasInterrupted,
NSNotification.Name.AVCaptureSessionInterruptionEnded,
NSNotification.Name.AVCaptureSessionDidStopRunning,
NSNotification.Name.AVCaptureSessionDidStartRunning,
```
This means there is no simple way to change the preferred input or stop `AVAudioEngine`/`AVCaptureSession` in time to prevent the services loss.

So the total logs should look something like:
```
Connected WH-1000XM3 with new capture session
AVAudioSessionRouteChangeNotification
AVAudioEngine - Received a new sample rate of 16000.0 from WH-1000XM3
Swapping WH-1000XM3 for iPhone Microphone
Connected iPhone Microphone with new capture session
AVAudioSessionRouteChangeNotification
AVAudioEngine - Received a new sample rate of 44100.0 from iPhone Microphone
Swapping iPhone Microphone for WH-1000XM3
Connected WH-1000XM3 with new capture session
AVAudioSessionRouteChangeNotification
AVAudioEngine - Received a new sample rate of 16000.0 from WH-1000XM3
AVAudioSessionMediaServicesWereLostNotification
AVAudioSessionMediaServicesWereResetNotification
```
