# roku

The Localytics library is contained in `sample/source/localytics.brs`.

NOTE: All functions are currently available only from `main.brs` except the `ll_tag_event` and `ll_tag_screen` as shown in the sample app.

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
  if (m.LocalyticsTask = Invalid) then
    if (m.top.localyticsTask <> Invalid) then
      m.LocalyticsTask = m.top.localyticsTask
    end if
  end if
End Sub

```
Finally, to tag an event, we must check to see if that task has been initialized:
```
Function safeFireLocalyticsEvent(event as Object) as Void
  if (m.LocalyticsTask <> Invalid) then
    m.LocalyticsTask.event = event
  end if
End Function
```
Then, we can tag our event:
```
safeFireLocalyticsEvent({name: "GridScene Item Focused", attributes: { a: 1, b: 2}})
```

## Initialization
*initLocalytics(appKey As String, sessionTimeout=1800 As Integer, secured=true As Boolean) as Object*
* appKey: your App Key
* sessionTimeout (optional): Timeout period, # of seconds of inactivity before considering a new session.
* secured (optional): The sdk will communicate with Localytics over HTTPS if `secured=true`. Setting this to `false` is only recommended for development/testing purpose, e.g. it may be easier to set up proxy and network debug tools over HTTP on Roku.

###Set Profile Information
*ll_set_customer_id(value As String)*
*ll_set_customer_email(value As String)*
*ll_set_customer_first_name(value As String)*
*ll_set_customer_last_name(value As String)*
*ll_set_customer_full_name(value As String)*

If available, CustomerId should be set. Email and name fields are also available to further identify the user Profile.
You can set other custom attribute with the following:

*ll_set_profile_attribute(scope as String, key As String, value=invalid As Dynamic)*
* scope("org" or "app"): set whether to set "org" or "app" level profile
* key: Profile attribute name
* value: Profile attribute value

###Custom Dimensions
*ll_set_custom_dimension(i as Integer, value as String)*
* Set Custom Dimension with their index and value.

###Tag Events
*ll_tag_event(name as String, attributes=invalid as Object, customerValueIncrease=0 as Integer)*

###Tag Screens
*ll_tag_screen(name as String)*

### Set Content Details
######Provide details about the content that will be played.
*ll_set_content_id(value="N/A" as Dynamic)*
*ll_set_content_length(value as Integer)*
*ll_set_content_title(value="N/A" as Dynamic)*
*ll_set_content_series_title(value="N/A" as Dynamic)*
*ll_set_content_category(value="N/A" as Dynamic)*

These parameters should be set before the playback ends, at which point they will be processed.

All are optional parameters, but setting these with Integer or String value is highly recommended:
* Set the content length explicitly to allow proper calculation of some playback metrics.
* Set the other content metadata attributes to include in the "Video Watched" auto-tag event.

#####Now pass the player events to the Localytics SDK to aggegrate playback metrics inside the player event loop.

*ll_process_player_metrics(event as Object)*

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
