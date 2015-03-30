# roku

Localytics library is contained in source/localytics/localytics.brs

Create new Localytics instance on globalAA using your AppKey
`m.LL = LL_Create("xxxxxxxxx-xxxxxxxxxxxxx-xxxxxxxx-xxxxxxxxxxxxxx", optional_session_timeout_in_seconds)`

...

Set CustomDimension

`m.LL.SetCustomDimension(0, "testCD0")`
`m.LL.SetCustomDimension(3, "testCD3")`
`m.LL.SetCustomDimension(5, "testCD5")`

Before Recording, call Init will handle open/close session depending on optional_session_timeout_in_seconds set

`m.LL.Init()`

...

Start Tagging Event

`m.LL.TagEvent("sample-TagEvent-init")`
`...`
`m.LL.TagEvent("RemoteKeyPressed", {location: "home", keyIndex: msg.GetIndex()})`


Start Tagging Screens

`m.LL.TagScreen("home")`

...

Keep Session Alive (optional). This is automatically called on TagEvent/TagScreen. Depending on usage, you can call this in event loops.

`m.LL.KeepSessionAlive()`
