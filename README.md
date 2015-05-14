# roku

Localytics library is contained in source/localytics/localytics.brs

## Initialization
Localytics(appKey As String, sessionTimeout=1800 As Integer) as Object

Create new Localytics instance on globalAA using your AppKey. optional_session_timeout_in_seconds defaults to 1800 seconds.

`m.LL = Localytics("xxxxxxxxx-xxxxxxxxxxxxx-xxxxxxxx-xxxxxxxxxxxxxx", optional_session_timeout_in_seconds)`


### Custom Dimensions
SetCustomDimension(i as Integer, value as String)

Set Custom Dimension with their index and value.

```
m.LL.SetCustomDimension(0, "testCD0")
m.LL.SetCustomDimension(3, "testCD3")
m.LL.SetCustomDimension(5, "testCD5")
```

You can also clear a particular CustomDimension.

ClearCustomDimension(index as Integer)

`m.LL.ClearCustomDimension(1) 'provide the CustomDimension index`


###Set Profile Information coming soon...


### Before Recording
Call AutoIntegrate will handle open/close session depending on optional_session_timeout_in_seconds set.

`m.LL.AutoIntegrate()`


## Tag Events
TagEvent(name as String, attributes=invalid as Object, customerValueIncrease=0 as Integer)

`m.LL.TagEvent("sample-TagEvent-init")`

`m.LL.TagEvent("RemoteKeyPressed", {location: "home", keyIndex: msg.GetIndex()})`


## Tag Screens
TagScreen(name as String)
`m.LL.TagScreen("home")`

## Keep Session Alive (optional)
This is automatically called on TagEvent/TagScreen. Depending on usage, you can call this in event loops.

`m.LL.KeepSessionAlive()`


## "Video Watched" Auto-tag Event
### Set Content Details
Provide details about the content that will be played.

SetContentDetails(content_length=0 as Integer, content_id="Not Avaialble" as Dynamic, content_title="Not Available" as Dynamic, content_series_title="Not Available" as Dynamic, content_category="Not Available" as Dynamic)

All are optional parameters, but setting these with Integer or String value is highly recommended:
* Set the content length explicitly to allow proper calculation of some playback metrics.
* Set the other content metadata attributes to include in the "Video Watched" auto-tag event.

`m.LL.SetContentDetails(content_metadata.Length, "1234", content_metadata.Title, content_metadata.TitleSeason, content_metadata.Categories)`


### Integrate with roVideoPlayerEvent/roVideoScreenEvent
1. Set Position Notification Period for roVideoScreen/roVideoPlayer

Important to set this interval to a reasonable number. The accuracy of the playback metrics is dependent on how often Localytics is updated with playback progress.

```
screen = CreateObject("roVideoScreen")
screen.SetPositionNotificationPeriod(1)
```

2. Now pass the player events to the Localytics SDK to aggegrate playback metrics inside the player event loop.

ProcessPlayerMetrics(event as Object)

```
 while true
    msg = wait(0, port)
      if type(msg) = "roVideoScreenEvent" then
        
        ' Let Localytics Roku SDK process the msg first
        m.LL.ProcessPlayerMetrics(msg)
        
        ...
        ' Other processing
        ...

        if msg.isScreenClosed() then
            exit while
        end if
end while
```
