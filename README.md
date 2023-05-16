# HarmonicClientSideAdTracking

A library for sending ad beacons from the client-side. Works with both traditional SSAI and HLS interstitials. Compatible with iOS/tvOS 15 and above.

## Installation

Using Swift Package Manager, enter the URL of this package:

```
https://github.com/harmonicinc-com/client-side-ad-tracking-ios-lib
```

## Usage

1. Import the library

    ```swift
    import HarmonicClientSideAdTracking
    ```

2. Create an `AdBeaconingSession` object:

    ```swift
    let mySession = AdBeaconingSession()
    ```

3. Optionally, set the session's player to your own instance of AVPlayer:

    ```swift
    let myAVPlayer = AVPlayer()
    mySession.player = myAVPlayer
    ```

4. Set the session's media URL to the master playlist of an HLS stream:

    ```swift
    mySession.mediaUrl = <hls-master-playlist-url>
    ```

    - Note that the `AdBeaconingSession` object will then do the following:
        - Try to obtain a manifest URL with a session ID (if the provided `mediaUrl` doesn't already contain one);
        - Try to obtain the corresponding metadata URL with the session ID.

5. Create a `HarmonicAdTracker` object and initialize it with the session created above:

    ```swift
    let adTracker: HarmonicAdTracker?
    adTracker = HarmonicAdTracker(session: mySession)
    ```

6. Start the ad tracker:

    ```swift
    adTracker?.start()
    ```

7. Start playing and beacons will be sent when ads are played:

    ```swift
    mySession.player.play()
    ```

8. You may observe the following information from the session instance:

    - To get the URLs with the session ID:
        ```swift
        let sessionInfo = mySession.sessionInfo
        ```
        URLs available:
        ```swift
        sessionInfo.mediaUrl
        sessionInfo.manifestUrl
        sessionInfo.adTrackingMetadataUrl
        ```
    - To get the list of `AdBreak`s returned from the ad metadata along with the status of the beaconing for each event.
        ```swift
        let adPods = mySession.adPods
        ```
        For example, in the first `AdBreak` of `adPods`:
        ```swift
        adPods[0].id
        adPods[0].startTime
        adPods[0].duration
        adPods[0].ads
        ```
        In the first `Ad` of `adPods[0].ads`:
        ```swift
        ads[0].id
        ads[0].startTime
        ads[0].duration
        ads[0].trackingEvents
        ```
        In the first `TrackingEvent` of `ads[0].trackingEvents`:
        ```swift
        trackingEvents[0].id
        trackingEvents[0].event
        trackingEvents[0].startTime
        trackingEvents[0].duration
        trackingEvents[0].signalingUrls
        trackingEvents[0].reportingState
        ```
    - To get the latest DataRange returned from the ad metadata.
        ```swift
        let latestDataRange = mySession.latestDataRange
        ```
        To get the time in `millisecondsSince1970`:
        ```swift
        latestDataRange.start
        latestDataRange.end
        ```
    - To get the status and information of the player.
        ```swift
        let playerObserver = mySession.playerObserver
        ```
        Information available:
        ```swift
        playerObserver.currentDate
        playerObserver.playhead
        playerObserver.primaryStatus
        playerObserver.hasInterstitialEvents
        playerObserver.interstitialStatus
        playerObserver.interstitialDate
        playerObserver.interstitialStoppedDate
        playerObserver.interstitialStartTime
        playerObserver.interstitialStopTime
        playerObserver.currentInterstitialDuration
        ```
    - To get the messages logged by the library.
        ```swift
        let logMessages = mySession.logMessages
        ```
        For example, in the first `LogMessage`:
        ```swift
        logMessages[0].timeStamp
        logMessages[0].message
        logMessages[0].isError
        ```

9. Stop the ad tracker when it is not needed:

    ```swift
    adTracker?.stop()
    ```

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
                mySession.mediaUrl = <hls-master-playlist-url>

                adTracker = HarmonicAdTracker(session: mySession)
                adTracker?.start()

                mySession.player.play()
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
import HarmonicClientSideAdTracking

class ViewController: UIViewController {
    private var mySession = AdBeaconingSession()
    private var adTracker: HarmonicAdTracker?

    override func viewDidAppear(_ animated: Bool) {
        mySession.mediaUrl = <hls-master-playlist-url>

        adTracker = HarmonicAdTracker(session: mySession)
        adTracker?.start()

        let controller = AVPlayerViewController()
        controller.player = mySession.player

        present(controller, animated: true) { [weak self] in
            guard let self = self else { return }
            self.mySession.player.play()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        adTracker?.stop()
    }
}
```

## Main SwiftUI views

The library consists of several SwiftUI views that are used in the demo project. They are used to show how to display the progress of beacon-sending, and are not required for the ad beaconing logic to work.

### `AdPodListView`

This view shows a list of `AdBreakView`s.

-   Each `AdBreakView` indicates an ad break, and shows a list of `AdView`s, each representing an ad in this ad break.
-   Each `AdView` indicates an ad, and shows a list of `TrackingEventView`s, each representing a tracking event in this ad.
-   Each `TrackingEventView` indicates a tracking event, and shows information for this particular tracking event, including:

    -   The event name
    -   The signaling URLs
    -   The time of the event
    -   The state of the beaconing of this event, which may be `idle`, `connecting`, `done`, or `failed`

### `SessionView`

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

### `PlayerView`

Contains a `VideoPlayer` with a debug overlay showing the real-world time and the latency. It also creates an `AVPlayerItem` for the player to play, and reloads the player when the `automaticallyPreservesTimeOffsetFromLive` option is changed.

## Demo app

A demo app (that can be run on both iOS and tvOS) on how this library (including the SwiftUI views) may be used is available at the following repository: https://github.com/harmonicinc-com/client-side-ad-tracking-ios
