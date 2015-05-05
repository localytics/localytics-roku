# roku

Localytics library is contained in source/localytics/localytics.brs

`'Create new Localytics instance on globalAA using your AppKey. optional_session_timeout_in_seconds defaults to 1800 seconds.`

`m.LL = LL_Create("xxxxxxxxx-xxxxxxxxxxxxx-xxxxxxxx-xxxxxxxxxxxxxx", optional_session_timeout_in_seconds)`

`...`


`'Set CustomDimension`

`m.LL.SetCustomDimension(0, "testCD0")`

`m.LL.SetCustomDimension(3, "testCD3")`

`m.LL.SetCustomDimension(5, "testCD5")`

`...`

`'Clear CustomDimension`

`m.LL.ClearCustomDimension(1)`

`...`

`'Before Recording, call Init will handle open/close session depending on optional_session_timeout_in_seconds set.`

`m.LL.Init()`

`...`


`'Start Tagging Event`

`m.LL.TagEvent("sample-TagEvent-init")`

`...`

`m.LL.TagEvent("RemoteKeyPressed", {location: "home", keyIndex: msg.GetIndex()})`

`...`


`'Start Tagging Screens`

`m.LL.TagScreen("home")`

`...`


`'Keep Session Alive (optional). This is automatically called on TagEvent/TagScreen. Depending on usage, you can call this in event loops.`

`m.LL.KeepSessionAlive()`

`...`

`'"Video Watched" Auto-tag Event`

`'Set arbitrary content metadata attributes to include in the "Video Watched" auto-tag event.`

`m.LL.SetContentMetadata("Video Title", episode.Title)`
`m.LL.SetContentMetadata("Video ID", episode.ContentId)`

`...`

`'Set the content length explicitly to allow proper calculation of some playback metrics.`

`m.LL.SetContentMetadata("Video Title", episode.Title)`

`...`

`'Now pass the player events to the Localytics SDK to aggegrate playback metrics inside the player event loop.`

`while true`
`  msg = wait(0, port)`
`  m.LL.ProcessPlayerMetrics(msg)`
`end while`