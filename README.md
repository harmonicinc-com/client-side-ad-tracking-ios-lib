# HarmonicClientSideAdTracking

A library for sending ad beacons from the client-side. Works with both traditional SSAI and HLS interstitials. Compatible with iOS/tvOS 15 and above.

- [HarmonicClientSideAdTracking](#harmonicclientsideadtracking)
  - [Installation](#installation)
  - [Usage](#usage)
  - [Error Handling](#error-handling)
    - [1. Observing Latest Error](#1-observing-latest-error)
    - [2. Log Messages](#2-log-messages)
    - [Error Types](#error-types)
  - [Minimal working examples](#minimal-working-examples)
    - [SwiftUI](#swiftui)
    - [UIKit](#uikit)
  - [Main SwiftUI views](#main-swiftui-views)
    - [`AdPodListView`](#adpodlistview)
    - [`SessionView`](#sessionview)
    - [`PlayerView`](#playerview)
  - [Demo app](#demo-app)
  - [Appendix](#appendix)
    - [How the Playback URL and Beaconing URL are Obtained by the Library](#how-the-playback-url-and-beaconing-url-are-obtained-by-the-library)

## Installation

Using Swift Package Manager, enter the URL of this package:

```
https://github.com/harmonicinc-com/client-side-ad-tracking-ios-lib
```

[Back to TOC](#harmonicclientsideadtracking)

## Usage

1.  Import the library

    ```swift
    import HarmonicClientSideAdTracking
    ```

2.  Create an [`AdBeaconingSession`](Sources/HarmonicClientSideAdTracking/Models/AdBeaconingSession.swift) object:

    ```swift
    let mySession = AdBeaconingSession()
    ```

3.  Optionally, confgure the following options in your session:
    ```swift
    mySession.keepPodsForMs = 1_000 * 60 * 60 * 2  // Double: duration to cache ad metadata, defaults to 2 hours
    mySession.metadataUpdateInterval = 4 // TimeInterval: how often to fetch the ad metadata, defaults to 4 seconds
    ```

4.  Optionally, set the session's player to your own instance of AVPlayer:

    ```swift
    let myAVPlayer = AVPlayer()
    mySession.player = myAVPlayer
    ```

5.  Set the session's media URL to the master playlist of an HLS stream:

    ```swift
    mySession.mediaUrl = "<hls-master-playlist-url>"
    ```

    -   Note that the `AdBeaconingSession` object will then do the following:
        -   Try to obtain a manifest URL with a session ID (if the provided `mediaUrl` doesn't already contain one);
        -   Try to obtain the corresponding metadata URL with the session ID.

6.  Observe the session's `manifestUrl` by using the [`.onReceive(_:perform:)`](<https://developer.apple.com/documentation/swiftui/view/onreceive(_:perform:)>) method in SwiftUI (for UIKit, please see the [example](#uikit) below). When it is set and not empty, create an `AVPlayerItem` with the URL and set it in the player:

    ```swift
    if !manifestUrl.isEmpty {
        let myPlayerItem = AVPlayerItem(url: URL(string: manifestUrl)!)
        mySession.player.replaceCurrentItem(with: myPlayerItem)
    }
    ```

7.  Create a [`HarmonicAdTracker`](Sources/HarmonicClientSideAdTracking/AdTracker/HarmonicAdTracker.swift) object and initialize it with the session created above:

    ```swift
    let adTracker: HarmonicAdTracker?
    adTracker = HarmonicAdTracker(session: mySession)
    ```

8.  Start the ad tracker:

    ```swift
    adTracker?.start()
    ```

9.  Start playing and beacons will be sent when ads are played:

    ```swift
    mySession.player.play()
    ```

10. You may observe the following information from the session instance:

    -   To get the URLs with the session ID:
        ```swift
        let sessionInfo = mySession.sessionInfo
        ```
        URLs available:
        ```swift
        sessionInfo.mediaUrl                        // String
        sessionInfo.manifestUrl                     // String
        sessionInfo.adTrackingMetadataUrl           // String
        ```
    -   To get the list of `AdBreak`s returned from the ad metadata along with the status of the beaconing for each event.
        ```swift
        let adPods = mySession.adPods
        ```
        For example, in the first `AdBreak` of `adPods`:
        ```swift
        adPods[0].id                                // String
        adPods[0].startTime                         // Double: millisecondsSince1970
        adPods[0].duration                          // Double: milliseconds
        adPods[0].ads                               // [Ad]
        ```
        In the first `Ad` of `adPods[0].ads`:
        ```swift
        ads[0].id                                   // String
        ads[0].startTime                            // Double: millisecondsSince1970
        ads[0].duration                             // Double: milliseconds
        ads[0].trackingEvents                       // [TrackingEvent]
        ```
        In the first `TrackingEvent` of `ads[0].trackingEvents`:
        ```swift
        trackingEvents[0].event                     // EventType
        trackingEvents[0].startTime                 // Double: millisecondsSince1970
        trackingEvents[0].duration                  // Double: milliseconds
        trackingEvents[0].signalingUrls             // [String]
        trackingEvents[0].reportingState            // ReportingState
        ```
    -   To get the latest DataRange returned from the ad metadata.
        ```swift
        let latestDataRange = mySession.latestDataRange
        ```
        To get the time in `millisecondsSince1970`:
        ```swift
        latestDataRange.start                       // Double: millisecondsSince1970
        latestDataRange.end                         // Double: millisecondsSince1970
        ```
    -   To get the status and information of the player.
        ```swift
        let playerObserver = mySession.playerObserver
        ```
        Information available:
        ```swift
        playerObserver.currentDate                  // Date
        playerObserver.playhead                     // Double: millisecondsSince1970
        playerObserver.primaryStatus                // AVPlayer.TimeControlStatus
        playerObserver.hasInterstitialEvents        // Bool
        playerObserver.interstitialStatus           // AVPlayer.TimeControlStatus
        playerObserver.interstitialDate             // Double: millisecondsSince1970
        playerObserver.interstitialStoppedDate      // Double: millisecondsSince1970
        playerObserver.interstitialStartTime        // Double: seconds
        playerObserver.interstitialStopTime         // Double: seconds
        playerObserver.currentInterstitialDuration  // Double: milliseconds
        ```
    -   To get the messages logged by the library.
        ```swift
        let logMessages = mySession.logMessages
        ```
        For example, in the first `LogMessage`:
        ```swift
        logMessages[0].timeStamp                    // Double: secondsSince1970
        logMessages[0].message                      // String
        logMessages[0].isError                      // Bool
        logMessages[0].error                        // HarmonicAdTrackerError?: the error object if available
        ```
    -   To observe errors encountered by the library:
        ```swift
        // SwiftUI
        .onReceive(mySession.$latestError) { error in
            if let error = error {
                switch error {
                case .networkError(let message):
                    print("Network error: \(message)")
                case .metadataError(let message):
                    print("Metadata error: \(message)")
                case .beaconError(let message):
                    print("Beacon error: \(message)")
                }
            }
        }

        // UIKit / Combine
        var cancellables = Set<AnyCancellable>()
        
        mySession.$latestError
            .sink { error in
                if let error = error {
                    // Handle error
                    print("Ad tracking error: \(error)")
                }
            }
            .store(in: &cancellables)
        ```

11. Stop the ad tracker when it is not needed:

    ```swift
    adTracker?.stop()
    ```

12. (Optional) Manually cleanup the session before setting it to nil to ensure immediate memory cleanup:

    ```swift
    mySession.cleanup()
    mySession = nil  // or set to a new session
    ```

    -   Note: This step is optional as the session will automatically cleanup when deallocated, but calling `cleanup()` explicitly ensures immediate cleanup of player observers and prevents potential memory leaks.

[Back to TOC](#harmonicclientsideadtracking)

## Error Handling

The library provides multiple ways to monitor and handle errors:

### 1. Observing Latest Error

The `latestError` property on `AdBeaconingSession` publishes the most recent error encountered:

**SwiftUI Example:**

```swift
import SwiftUI
import HarmonicClientSideAdTracking

struct ContentView: View {
    @StateObject private var mySession = AdBeaconingSession()
    
    var body: some View {
        VideoPlayer(player: mySession.player)
            .onReceive(mySession.$latestError) { error in
                if let error = error {
                    handleError(error)
                }
            }
    }
    
    private func handleError(_ error: HarmonicAdTrackerError) {
        switch error {
        case .networkError(let message):
            print("Network error: \(message)")
            // Handle network-related errors (e.g., failed to load media or init session)
        case .metadataError(let message):
            print("Metadata error: \(message)")
            // Handle metadata-related errors (e.g., invalid ad metadata)
        case .beaconError(let message):
            print("Beacon error: \(message)")
            // Handle beacon sending errors (e.g., failed to send tracking beacon)
        }
    }
}
```

**UIKit Example:**

```swift
import UIKit
import Combine
import HarmonicClientSideAdTracking

class ViewController: UIViewController {
    private var mySession = AdBeaconingSession()
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Observe errors
        mySession.$latestError
            .compactMap { $0 } // Filter out nil values
            .sink { [weak self] error in
                self?.handleError(error)
            }
            .store(in: &cancellables)
    }
    
    private func handleError(_ error: HarmonicAdTrackerError) {
        switch error {
        case .networkError(let message):
            // Handle network error
            showAlert(title: "Network Error", message: message)
        case .metadataError(let message):
            // Handle metadata error
            showAlert(title: "Metadata Error", message: message)
        case .beaconError(let message):
            // Handle beacon error
            print("Beacon error (non-critical): \(message)")
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
```

### 2. Log Messages

For detailed logging information, you can observe the `logMessages` array which includes all errors with their associated error objects:

```swift
mySession.$logMessages
    .sink { messages in
        for message in messages where message.isError {
            print("Error at \(message.timeStamp): \(message.message)")
            if let error = message.error {
                // Access the structured error object
                print("Error type: \(error)")
            }
        }
    }
    .store(in: &cancellables)
```

### Error Types

The library defines three types of errors:

- **`networkError(String)`**: Network-related errors such as failed HTTP requests or connection issues, or when session initialization fails
- **`metadataError(String)`**: Errors related to fetching or parsing ad metadata
- **`beaconError(String)`**: Errors related to sending tracking beacons

[Back to TOC](#harmonicclientsideadtracking)

## Minimal working examples

In these examples, ad beacons will be sent while the stream is being played, but no UI is shown to indicate the progress of beaconing.

### SwiftUI

```swift
import SwiftUI
import AVKit
import HarmonicClientSideAdTracking

struct ContentView: View {
    @StateObject private var mySession = AdBeaconingSession()
    @State private var adTracker: HarmonicAdTracker?

    var body: some View {
        VideoPlayer(player: mySession.player)
            .onAppear {
                mySession.mediaUrl = "<hls-master-playlist-url>"
                adTracker = HarmonicAdTracker(session: mySession)
            }
            .onReceive(mySession.sessionInfo.$manifestUrl) { manifestUrl in
                if !manifestUrl.isEmpty {
                    let myPlayerItem = AVPlayerItem(url: URL(string: manifestUrl)!)
                    mySession.player.replaceCurrentItem(with: myPlayerItem)
                    mySession.player.play()
                    adTracker?.start()
                }
            }
            .onDisappear {
                adTracker?.stop()
            }
    }
}
```

### UIKit

```swift
import UIKit
import AVKit
import Combine
import HarmonicClientSideAdTracking

class ViewController: UIViewController {
    private var mySession = AdBeaconingSession()
    private var adTracker: HarmonicAdTracker?
    private var sessionSub: AnyCancellable?

    override func viewDidAppear(_ animated: Bool) {
        mySession.mediaUrl = "<hls-master-playlist-url>"
        adTracker = HarmonicAdTracker(session: mySession)

        let controller = AVPlayerViewController()
        controller.player = mySession.player
        present(controller, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sessionSub = mySession.$sessionInfo.sink { [weak self] sessionInfo in
            guard let self = self else { return }

            if !sessionInfo.manifestUrl.isEmpty {
                let myPlayerItem = AVPlayerItem(url: URL(string: sessionInfo.manifestUrl)!)
                mySession.player.replaceCurrentItem(with: myPlayerItem)
                mySession.player.play()
                adTracker?.start()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        adTracker?.stop()
    }
}
```

[Back to TOC](#harmonicclientsideadtracking)

## Main SwiftUI views

The library consists of several SwiftUI views that are used in the demo project. They are used to show how to display the progress of beacon-sending, and are not required for the ad beaconing logic to work.

### [`AdPodListView`](Sources/HarmonicClientSideAdTracking/Views/AdPodList/AdPodListView.swift)

This view shows a list of `AdBreakView`s.

-   Each [`AdBreakView`](Sources/HarmonicClientSideAdTracking/Views/AdPodList/AdBreakView.swift) indicates an ad break, and shows a list of `AdView`s, each representing an ad in this ad break.
-   Each [`AdView`](Sources/HarmonicClientSideAdTracking/Views/AdPodList/AdView.swift) indicates an ad, and shows a list of `TrackingEventView`s, each representing a tracking event in this ad.
-   Each [`TrackingEventView`](Sources/HarmonicClientSideAdTracking/Views/AdPodList/TrackingEventView.swift) indicates a tracking event, and shows information for this particular tracking event, including:

    -   The event name
    -   The signaling URLs
    -   The time of the event
    -   The state of the beaconing of this event, which may be `idle`, `connecting`, `done`, or `failed`

### [`SessionView`](Sources/HarmonicClientSideAdTracking/Views/SessionView.swift)

Shows information about playback:

-   Playhead
-   Time to next ad beack
-   If interstitials are available:
    -   Last interstitial's event date
    -   Last interstitial's start time
    -   Last interstitial's end time

Also, the different URLs of the session:

-   Media URL (set by the user)
-   Manifest URL (the redirected URL with a session ID)
-   Ad tracking metadata URL

### [`PlayerView`](Sources/HarmonicClientSideAdTracking/Views/PlayerView.swift)

Contains a [`VideoPlayer`](https://developer.apple.com/documentation/avkit/videoplayer) with a debug overlay showing the real-world time and the latency. It also reloads by creating a new instance of player when the session's [`automaticallyPreservesTimeOffsetFromLive`](https://developer.apple.com/documentation/avfoundation/avplayeritem/3229855-automaticallypreservestimeoffset) option is changed.

[Back to TOC](#harmonicclientsideadtracking)

## Demo app

A demo app (that can be run on both iOS and tvOS) on how this library (including the SwiftUI views) may be used is available at the following repository: https://github.com/harmonicinc-com/client-side-ad-tracking-ios

[Back to TOC](#harmonicclientsideadtracking)

## Appendix

### How the Playback URL and Beaconing URL are Obtained by the Library

> [!NOTE]  
> Applicable when `isInitRequest` in `AdBeaconingSession` is `true` (default is true).

1. The library sends a GET request to the manifest endpoint with the query param "initSession=true". For e.g., a GET request is sent to:
    ```
    https://my-host/variant/v1/hls/index.m3u8?initSession=true
    ```

2. The ad insertion service (PMM) responds with the URLs. For e.g.,
    ```
    {
        "manifestUrl": "./index.m3u8?sessid=a700d638-a4e8-49cd-b288-6809bd35a3ed&vosad_inst_id=pmm-0",
        "trackingUrl": "./metadata?sessid=a700d638-a4e8-49cd-b288-6809bd35a3ed&vosad_inst_id=pmm-0"
    }
    ```

3. The library constructs the URLs by combining the host in the original URL and the relative URLs obtained. For e.g.,
    ```
    Manifest URL: https://my-host/variant/v1/hls/index.m3u8?sessid=a700d638-a4e8-49cd-b288-6809bd35a3ed&vosad_inst_id=pmm-0

    Metadata URL: https://my-host/variant/v1/hls/metadata?sessid=a700d638-a4e8-49cd-b288-6809bd35a3ed&vosad_inst_id=pmm-0
    ```

> [!NOTE]  
> You may obtain these URLs from the `sessionInfo` property of your `AdBeaconingSession`.
