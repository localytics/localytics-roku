# roku

Localytics library is contained in source/localytics/localytics.brs

## Initialization
*Localytics(appKey As String, sessionTimeout=1800 As Integer) as Object*

Create new Localytics instance on globalAA using your AppKey. optional_session_timeout_in_seconds defaults to 1800 seconds.

`m.Localytics = Localytics("xxxxxxxxx-xxxxxxxxxxxxx-xxxxxxxx-xxxxxxxxxxxxxx", optional_session_timeout_in_seconds)`


######Before Recording
Call AutoIntegrate will handle open/close session depending on optional_session_timeout_in_seconds set.

`m.Localytics.AutoIntegrate()`

##Set Profile Information
*SetCustomerId(value As String)*<br /> 
*SetCustomerEmail(value As String)*<br /> 
*SetCustomerFirstName(value As String)*<br /> 
*SetCustomerLastName(value As String)*<br /> 
*SetCustomerFullName(value As String)* 

If available, CustomerId should be set. Email and name fields are also available to further identify the user Profile.

```
m.Localytics.SetCustomerId("1a2b3c4d")

m.Localytics.SetCustomerEmail("test@test.com)
m.Localytics.SetCustomerFirstName("First")
m.Localytics.SetCustomerLastName("Last")
m.Localytics.SetCustomerFullName("Last, First")
```

##Custom Dimensions
*SetCustomDimension(i as Integer, value as String)*

Set Custom Dimension with their index and value.

```
m.Localytics.SetCustomDimension(0, "testCD0")
m.Localytics.SetCustomDimension(3, "testCD3")
m.Localytics.SetCustomDimension(5, "testCD5")
```

You can also clear a particular CustomDimension.

*ClearCustomDimension(index as Integer)*

`m.Localytics.ClearCustomDimension(1) 'provide the CustomDimension index`



## Tag Events
*TagEvent(name as String, attributes=invalid as Object, customerValueIncrease=0 as Integer)*

`m.Localytics.TagEvent("sample-TagEvent-init")`

`m.Localytics.TagEvent("RemoteKeyPressed", {location: "home", keyIndex: msg.GetIndex()})`


## Tag Screens
*TagScreen(name as String)*

`m.Localytics.TagScreen("home")`

## Keep Session Alive (optional)
This function is usually not necessary b/c TagEvent/TagScreen/ProcessPlayerMetrics function will automatically call KeepSessionAlive(). If there is no other interaction with this SDK, calling KeepSessionAlive() can prevent the current session from timing out.

`m.Localytics.KeepSessionAlive()`


## "Video Watched" Auto-tag Event
### Set Content Details
######Provide details about the content that will be played.
*SetContentLength(value as Integer)*<br />
*SetContentId(value="N/A" as Dynamic)*<br />
*SetContentTitle(value="N/A" as Dynamic)*<br />
*SetContentSeriesTitle(value="N/A" as Dynamic)*<br />
*SetContentCategory(value="N/A" as Dynamic)*<br />

These parameters should be set before the playback ends, at which point they will be processed.

All are optional parameters, but setting these with Integer or String value is highly recommended:
* Set the content length explicitly to allow proper calculation of some playback metrics.
* Set the other content metadata attributes to include in the "Video Watched" auto-tag event.

```
m.Localytics.SetContentLength(content_metadata.Length)
m.Localytics.SetContentId("12345")
m.Localytics.SetContentTitle(content_metadata.Title)
m.Localytics.SetContentSeriesTitle(content_metadata.TitleSeason)
m.Localytics.SetContentCategory(content_metadata.Categories)
```


###Integrate with roVideoPlayerEvent/roVideoScreenEvent
#####Set Position Notification Period for roVideoScreen/roVideoPlayer

Important to set this interval to a reasonable number. The accuracy of the playback metrics is dependent on how often Localytics is updated with playback progress.

```
screen = CreateObject("roVideoScreen")
screen.SetPositionNotificationPeriod(1)
```

#####Now pass the player events to the Localytics SDK to aggegrate playback metrics inside the player event loop.

*ProcessPlayerMetrics(event as Object)*

```
 while true
    msg = wait(0, port)
      if type(msg) = "roVideoScreenEvent" then
        
        ' Let Localytics Roku SDK process the msg first
        m.Localytics.ProcessPlayerMetrics(msg)
        
        ...
        ' Other processing
        ...

        if msg.isScreenClosed() then
            exit while
        end if
end while
```

### Other notes
* This sdk utilizes Registry Section under "com.localytics.*"
