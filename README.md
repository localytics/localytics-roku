# roku

The Localytics library is contained in `sample/source/localytics.brs`.

Localytics currently runs off of a long running task. This task can be added to the `HomeScene` as a child object:
```
<LocalyticsTask id="LocalyticsTask" />
```
`HomeScene` must then find the task, observe when it has started, and then send it to all the components:
```
m.LocalyticsTask = m.top.findNode("LocalyticsTask")
m.localyticsTask.observeField("started", "OnLocalyticsTaskStarted")
m.LocalyticsTask.control = "RUN"

...

Sub OnLocalyticsTaskStarted()
  'Send task to all children
  m.GridScreen.localyticsTask = m.LocalyticsTask
End Sub

```
Each subsequent component must then add Localytics as a node on their interface:
```
<field id="localyticsTask" type="node"/>
```
And then find when the task is initialized and set it locally:
```
m.top.observeField("localyticsTask", "ll_init_component")

...

Sub ll_init_component()
  if (m.localyticsTask = invalid) then
    if (m.top.localyticsTask <> invalid) then
      m.localyticsTask = m.top.localyticsTask
    end if
  end if
End Sub

```
Finally, to tag an event, we must check to see if that task has been initialized:
```
Function safeFireLocalytics(key as String, value as Object) as Void
  if (m.LocalyticsTask <> invalid) then
    m.LocalyticsTask[key] = value
  end if
End Function
```
Then, we can tag our event:
```
safeFireLocalytics("event", {name: "GridScene Item Focused", attributes: { a: 1, b: 2}})
```

### Initialization (fields set on the LocalyticsTask component XML)
* appKey: your App Key
* sessionTimeout (optional): Timeout period, # of seconds of inactivity before considering a new session.
* secured (optional): The sdk will communicate with Localytics over HTTPS if `secured=true`. Setting this to `false` is only recommended for development/testing purpose, e.g. it may be easier to set up proxy and network debug tools over HTTP on Roku.
* debug (optional): If true, debug logging will be enabled.

###Set Profile Information
*ll_set_customer_id(value As String)*
*ll_set_customer_email(value As String)*
*ll_set_customer_first_name(value As String)*
*ll_set_customer_last_name(value As String)*
*ll_set_customer_full_name(value As String)*
```
m.localyticsTask.customer = {id: myId, email: myEmail, firstName: myFirstName, lastName: myLastName, fullName: myFullName}
```

If available, CustomerId should be set. Email and name fields are also available to further identify the user Profile.
You can set other custom attribute with the following:

*ll_set_profile_attribute(scope as String, key As String, value=invalid As Dynamic)*
```
m.localyticsTask.profileAttribute = {scope: myScope, key: myKey, value: myValue}
```
* scope("org" or "app"): set whether to set "org" or "app" level profile
* key: Profile attribute name
* value: Profile attribute value

###Custom Dimensions
*ll_set_custom_dimension(i as Integer, value as String)*
```
m.localyticsTask.customDimension = {i: myIndex, value: myValue}
```
* Set Custom Dimension with their index and value.

###Tag Events
*ll_tag_event(name as String, attributes=invalid as Object, customerValueIncrease=0 as Integer)*
```
m.localyticsTask.event = {name: myName, attributes:{attr1: val1, attr2: val2}}
```

###Tag Screens
*ll_tag_screen(name as String)*
```
m.localyticsTask.screen = {name: myScreen}
```

### Tag Video Player Details
######Provide details about the content that will be played.
*ll_process_player_metrics()*
*ll_process_video_metadata(data)*
```
m.localyticsTask.videoNode = myVideoPlayer
videoData = { title: myTitle }
m.localyticsTask.videoMetaData = videoData
```

### Other notes
* This sdk utilizes Registry Section under "com.localytics.\*"

## Using the sample app
This repo includes a sample app from Roku to test scene graph apps. To test the sdk:
* Replace your Localytics app key in main.brs
* Zip up all contents of the sample folder so all files are compressed (as described [here](https://blog.roku.com/developer/2016/02/04/hello-world/))
* Make a roku account and enable developer mode on the box (homex3, upx2, right, left, right, left, right)
* Point a web browser to the device IP (something like 10.X.X.X) and enter creds (e.g., rokudev/rokudev)
* Upload the compressed folder and install
* Check the [debug console](https://sdkdocs.roku.com/display/sdkdoc/Debugging+Your+Application) by entering `telnet YOUR_ROKU_IP 8085` into a console
