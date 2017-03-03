' ********** Copyright 2016 Roku Corp.  All Rights Reserved. **********
 ' inits grid screen
 ' creates all children
 ' sets all observers
Function Init()
    ? "[GridScreen] Init"
    m.top.observeField("focusedChild", "OnChildFocused")
    m.rowList = m.top.findNode("RowList")

    'Add this to listen for when the task is ready
    m.top.observeField("localyticsTask", "ll_init_component")
    m.Description = m.top.findNode("Description")
    m.Background = m.top.findNode("Background")
    m.focusCount = 0
End Function

' handler of focused child in GridScreen
Sub OnChildFocused()
    if m.top.isInFocusChain() and not m.rowList.hasFocus() then
        m.rowList.setFocus(true)
    end if
End Sub

'  Add These two helper functions
Sub ll_init_component()
  if (m.LocalyticsTask = invalid) then
    if (m.top.localyticsTask <> invalid) then
      m.LocalyticsTask = m.top.localyticsTask
      ' Fire any events related to this screen starting
      m.LocalyticsTask.event = {name: "GridScene Init"}
    end if
  end if
End Sub

Function safeFireLocalytics(key as String, value as Object) as Void
  if (m.LocalyticsTask <> invalid) then
    m.LocalyticsTask[key] = value
  end if
End Function

' handler of focused item in RowList
Sub OnItemFocused()
    itemFocused = m.top.itemFocused
    ? ">> GridScreen > OnItemFocused"; itemFocused

    'Test Localytics events
    'm.focusCount++

    'safeFireLocalytics("event", {name: "GridScene Item Focused", attributes: { a: 1, b: 2}})
    'safeFireLocalytics("customDimension", { i: 4, value: "Jeff's Dimension"} )
    'screenId = m.focusCount MOD 3
    'safeFireLocalytics("screen", {name: "Test Screen " + screenId.ToStr()})
    'if (m.focusCount MOD 2 = 0) then
    ''  safeFireLocalytics("profileAttribute", {scope: "app", key: "rokuTest", value: "App Focus Count" + m.focusCount.ToStr()})
    ''  safeFireLocalytics("customer", { email: "jlevine@localytics.com", fullName: "Jeff Levine", firstName: "Jeff1", lastName: "Levine1"})
    'else
    ''    safeFireLocalytics("profileAttribute", {scope: "org", key: "rokuTest", value: invalid})
    ''  end if

    'When an item gains the key focus, set to a 2-element array,
    'where element 0 contains the index of the focused row,
    'and element 1 contains the index of the focused item in that row.
    if itemFocused.Count() = 2 then
        'get content node by index from grid
        focusedContent = m.top.content.getChild(itemFocused[0]).getChild(itemFocused[1])

        if focusedContent <> invalid then
            'set focused content to top interface
            m.top.focusedContent = focusedContent

            'set content to description node
            m.Description.content = focusedContent

            'set background wallpaper
            m.Background.uri = focusedContent.hdBackgroundImageUrl
        end if
    end if
end Sub
