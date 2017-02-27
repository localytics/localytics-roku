
Function init()
    m.top.functionName = "execLocalyticsLoop"
end Function

' TODO: test that session length looks proper
' test screens
' push outstanding requests into the registry, and retry if bad response codes
' add a registry section for persistent data (customer, profile, etc.)

'Runs as a part of LocalyticsTask'
Function execLocalyticsLoop()
    port = CreateObject("roMessagePort")
    m.top.observeField("event", port)
    m.top.observeField("screen", port)
    m.top.observeField("customer", port)
    m.top.observeField("profileAttribute", port)
    m.top.observeField("customDimension", port)
    m.top.observeField("content", port)
    m.top.observeField("playerObject", port)

    ll_restore_context()

    ll_debug_log("execLocalyticsLoop")
    m.top.started = true
    while true
        msg = wait(10000, port)
        if msg = invalid then
            ll_keep_session_alive("Wait Timeout")
        else
            if type(msg) = "roSGNodeEvent" then
                field = msg.getField()
                data = msg.getData()

                if field = "event" then
                    if data.name <> invalid then
                        ll_tag_event(data.name, data.attributes)
                    end if
                else if field = "screen" then
                    if data.name <> invalid then
                        ll_tag_screen(data.name)
                    end if
                else if field = "customer" then
                    if data.id <> invalid then
                        ll_set_customer_id(data.id)
                    end if
                    if data.email <> invalid then
                        ll_set_customer_email(data.email)
                    end if
                    if data.firstName <> invalid then
                        ll_set_customer_first_name(data.firstName)
                    end if
                    if data.lastName <> invalid then
                        ll_set_customer_last_name(data.lastName)
                    end if
                    if data.fullName <> invalid then
                        ll_set_customer_full_name(data.fullName)
                    end if
                else if field = "profileAttribute" then
                    if data.scope <> invalid and data.key <> invalid then
                        ll_set_profile_attribute(data.scope, data.key, data.attributes)
                    end if
                else if field = "customDimension" then
                    if data.i <> invalid and data.value <> invalid then
                        ll_set_custom_dimension(data.i, data.value)
                    end if
                else if field = "content" then
                    if data.id <> invalid then
                        ll_set_content_id(data.id)
                    end if
                    if data.length <> invalid then
                        ll_set_content_length(data.length)
                    end if
                    if data.title <> invalid then
                        ll_set_content_title(data.title)
                    end if
                    if data.seriesTitle <> invalid then
                        ll_set_content_series_title(data.seriesTitle)
                    end if
                    if data.category <> invalid then
                        ll_set_content_category(data.category)
                    end if
                else if field = "playerObject" then
                    if data.event <> invalid then
                        ll_process_player_metrics(data.event)
                    end if
                end if
            end if
        end if
    end while

End Function

' Creates a new Localytics instance
' Note:
' - "fresh" will clear previous stored values
' - "debug" will log some messages
Function initLocalytics(appKey As String, sessionTimeout=1800 As Integer, secured=true As Boolean, fresh=false As Boolean, debug=true As Boolean) As Void
    new_localytics = CreateObject("roAssociativeArray")
    m.localytics = new_localytics

    new_localytics.debug = debug 'Extra loggin on/off
    new_localytics.libraryVersion = "roku_3.0.0"

    ll_debug_log("init Localytics: "+appKey)

    if secured then
        new_localytics.uriScheme = "https"
    else
        new_localytics.uriScheme = "http"
    end if

    new_localytics.secured = secured
    new_localytics.endpoint = new_localytics.uriScheme + "://analytics.localytics.com/api/v2/applifuckingcations/"
    new_localytics.profileEndpoint = new_localytics.uriScheme + "://profile.localytics.com/v1/apps/"
    new_localytics.appKey = appKey
    new_localytics.sessionTimeout = sessionTimeout
    new_localytics.outstandingRequests = CreateObject("roAssociativeArray") ' Volatile Store for roUrlTransfer response
    new_localytics.customDimensions = ll_load_custom_dimensions()
    new_localytics.maxScreenFlowLength = 2500
    new_localytics.keys = ll_get_storage_keys()
    new_localytics.constants = ll_get_constants()

    if fresh then
        ll_delete_session_data(true)
    end if

    'persist the interesting bits
    ll_write_registry("appKey", appKey, false)
    ll_write_registry_dyn("sessionTimeout", sessionTimeout, false)
    ll_write_registry_dyn("secured", debug, false)
    ll_write_registry_dyn("debug", debug, true)
End Function

'restore the local m.localytics array, then restore any session data
Function ll_restore_context()
  if m.localytics = invalid then
    appKey = ll_read_registry("appKey")
    sessionTimeout = ll_read_registry_int("sessionTimeout", "1800")
    secured = ll_read_registry_bool("secured", "True")
    debug = ll_read_registry_bool("debug", "False")
    initLocalytics(appKey, sessionTimeout, secured, false, debug)
    ll_debug_log("ll_restore_context")
    ll_initialize_session()
  else
    ll_debug_log("ll_restore_context: already restored")
  end if
End Function

'Initializes the session
Function ll_initialize_session()
    ll_debug_log("ll_initialize_session()")
    ll_restore_session()

    if not ll_has_session() then
        ll_open_session()
    else
        ll_check_session_timeout(true)
    end if
End Function

' Opens a session on Localytics
Function ll_open_session()
    ll_debug_log("ll_open_session()")
    m.localytics.session = CreateObject("roAssociativeArray")
    ll_read_registry(m.localytics.keys.install_uuid, ll_generate_guid())
    ll_set_session_value(m.localytics.keys.session_uuid, ll_generate_guid(), false)
    ll_write_registry_dyn(m.localytics.keys.session_index, ll_read_registry(m.localytics.keys.session_index, "0").ToInt() + 1)
    ll_set_session_value(m.localytics.keys.sequence_index, 0, false)

    ' Save session start time
    timestamp = ll_get_timestamp_generator()
    time = timestamp.asSeconds()
    ll_set_session_value(m.localytics.keys.session_open_time, time, false)
    ll_set_session_value(m.localytics.keys.session_action_time, time)

    'Session Open
    event = CreateObject("roAssociativeArray")
    event.dt = "s"
    event.ct = time 'Open Time
    event.u = ll_get_session_value(m.localytics.keys.session_uuid)
    event.nth = ll_read_registry(m.localytics.keys.session_index) 'Need to persist this value
    event.mc = "" '?? null is ok
    event.mm = "" '?? null is ok
    event.ms = "" '?? null is ok

    customerId = ll_read_registry(m.localytics.keys.profile_customer_id)
    if ll_is_valid_string(customerId) then
        event.cid = customerId
        event.utp = "known"
    else
        event.cid = ll_read_registry(m.localytics.keys.install_uuid)
        event.utp = "anonymous"
    end if

    ll_send(event)
End Function

' Closes a session on Localytics
Function ll_close_session(isInit=false as Boolean)
    ll_debug_log("ll_close_session()")

    lastActionTime = ll_get_session_value(m.localytics.keys.session_action_time, true)
    sessionTime = ll_get_session_value(m.localytics.keys.session_open_time, true)

    ll_keep_session_alive("ll_close_session")

    ' Process previous session outstandings (auto-tags)
    if isInit then
        ll_screen_viewed("[External]", lastActionTime)
    else
        ll_screen_viewed("[Inactivity]", lastActionTime)
    end if

    ll_send_player_metrics()'Attempt to fire player metrics

    event = CreateObject("roAssociativeArray")
    event.dt = "c"
    event.u = ll_generate_guid()
    event.ss = sessionTime
    event.su = ll_get_session_value(m.localytics.keys.session_uuid)
    event.ct = lastActionTime ' TODO Double check these fields
    event.ctl = lastActionTime - sessionTime
    event.cta = lastActionTime - sessionTime

    screenFlows = ll_get_session_value(m.localytics.keys.screen_flows)
    if ll_is_string(screenFlows) then
        event.fl = "[" + screenFlows +"]" 'Screen flows
    else
        event.fl = "[]"
    end if

    customerId = ll_read_registry(m.localytics.keys.profile_customer_id)
    if ll_is_valid_string(customerId) then
        event.cid = customerId
        event.utp = "known"
    else
        event.cid = ll_read_registry(m.localytics.keys.install_uuid)
        event.utp = "anonymous"
    end if

    ll_send(event)

    ll_delete_session_data()
End Function

Function ll_delete_session_data(clearAllFields=false As Boolean, section="com.localytics.session" As String)
    sec = CreateObject("roRegistrySection", section)

    for each key in sec.GetKeyList()
        if clearAllFields then
            sec.Delete(key)
        end if
    next

    sec.Flush()
End Function

' Tags an event
Function ll_tag_event(name as String, attributes=invalid as Object, customerValueIncrease=0 as Integer)
    ll_debug_log("ll_tag_event()")
    if ll_has_session() = false then
        ll_debug_log("Localytics tag event failed: no session")
        return -1
    end if
    ll_check_session_timeout()
    ll_keep_session_alive("ll_tag_event")

    timestamp = ll_get_timestamp_generator()

    event = CreateObject("roAssociativeArray")
    event.dt = "e"
    event.ct = timestamp.asSeconds()
    event.u = ll_generate_guid()
    event.su = ll_get_session_value(m.localytics.keys.session_uuid)
    event.v = customerValueIncrease '??
    event.n = name 'Event name

    customerId = ll_read_registry(m.localytics.keys.profile_customer_id)
    if ll_is_valid_string(customerId) then
        event.cid = customerId
        event.utp = "known"
    else
        event.cid = ll_read_registry(m.localytics.keys.install_uuid)
        event.utp = "anonymous"
    end if

    event.attrs = attributes

    ll_send(event)
End Function

Function ll_tag_screen(name as String)
    ll_debug_log("ll_tag_screen()")
    ll_check_session_timeout()
    ll_keep_session_alive("ll_tag_screen")

    screenFlows = ll_get_session_value(m.localytics.keys.screen_flows)

    if not ll_is_string(screenFlows)
        screenFlows = Chr(34) + name + Chr(34)
        ll_set_session_value(m.localytics.keys.screen_flows, screenFlows)
    else if screenFlows.Len() < m.localytics.maxScreenFlowLength then
        screenFlows = screenFlows + "," + Chr(34) + name + Chr(34)
        ll_set_session_value(m.localytics.keys.screen_flows, screenFlows)
    end if

    ll_screen_viewed(name) 'Auto-tag

    ll_debug_log("Screen Flows: " + ll_get_session_value(m.localytics.keys.screen_flows))
End Function

Function ll_screen_viewed(currentScreen="" as String, lastActionTime=-1 as Integer)
    ll_debug_log("ll_screen_viewed()")

    previousScreen = ll_get_session_value(m.localytics.keys.auto_previous_screen)
    previousScreenTime = ll_get_session_value(m.localytics.keys.auto_previous_screen_time, true)

    if lastActionTime > -1 then
        time = lastActionTime
    else
        timestamp = ll_get_timestamp_generator()
        time = timestamp.asSeconds()
    end if

    if  ll_is_valid_string(previousScreen) and ll_is_integer(previousScreenTime) then
        attributes = CreateObject("roAssociativeArray")
        if currentScreen = "" then
            currentScreen = m.localytics.constants.not_available
        end if
        timeOnScreen = time - previousScreenTime
        attributes[m.localytics.constants.current_screen] = currentScreen
        attributes[m.localytics.constants.previous_screen] = previousScreen
        attributes[m.localytics.constants.time_on_screen] = timeOnScreen

        ll_debug_log("ll_screen_viewed(currentScreen: " + currentScreen + ", previousScreen: " + previousScreen + ", timeOnScreen: " + timeOnScreen.ToStr() + ")")

        ll_tag_event(m.localytics.constants.event_screen_viewed, attributes)
    end if

    ll_set_session_value(m.localytics.keys.auto_previous_screen, currentScreen, false)
    ll_set_session_value(m.localytics.keys.auto_previous_screen_time, time)
End Function

Function ll_set_custom_dimension(i as Integer, value as String)
    ll_debug_log("ll_set_custom_dimension("+ i.toStr() + ", " + value + ")")
    if i>=0 and i < 10 and value <> invalid then
        cdKey = "c"+ i.ToStr()
        m.localytics.customDimensions[cdKey] = value
        ll_write_registry(cdKey, value, true)
    end if
End Function

Function ll_clear_custom_dimension(i as Integer)
    ll_debug_log("ll_clear_custom_dimension("+ i.toStr() + ")")
    ll_set_custom_dimension(i, "")
End Function


' Sets Content Metadata for auto-tagging. If "value" is empty, the key is deleted.
Function ll_set_content_metadata(key as String, value as Dynamic, required=false as Boolean, flush=true as Boolean)
    ll_debug_log("ll_set_content_metadata("+ key + ", " + _str_string(value) + ")")

    if ll_is_string(key)
        strValue = ll_to_string(value)
        if ll_is_valid_string(strValue) then
            ll_write_registry(key, strValue, flush, m.localytics.constants.section_metadata)
        else if required then
            ll_write_registry(key, m.localytics.constants.not_available, flush, m.localytics.constants.section_metadata) ' Remove the attribute if value is invalid or empty
        else
            ll_delete_registry(key, m.localytics.constants.section_metadata, flush)
        end if
    end if
End Function

Function ll_set_content_length(value as Integer, flush=true as Boolean)
    ll_debug_log("ll_set_content_length( Content Length: " + value.ToStr() + ")")

    if value > 0 then
        ll_write_registry(m.localytics.keys.auto_playback_length, value.ToStr(), flush, m.localytics.constants.section_playback)
    else
        ll_delete_registry(m.localytics.keys.auto_playback_length, m.localytics.constants.section_playback, flush)
    end if
End Function

Function ll_set_content_id(value="N/A" as Dynamic)
    ll_set_content_metadata(m.localytics.constants.content_id, value, true, true)
End Function

Function ll_set_content_title(value="N/A" as Dynamic)
    ll_set_content_metadata(m.localytics.constants.content_title, value, true, true)
End Function

Function ll_set_content_series_title(value="N/A" as Dynamic)
    ll_set_content_metadata(m.localytics.constants.content_series_title, value, true, true)
End Function

Function ll_set_content_category(value="N/A" as Dynamic)
    ll_set_content_metadata(m.localytics.constants.content_category, value, true, true)
End Function

Function ll_process_player_metrics(event as Object)
    ll_debug_log("ll_process_player_metrics()")

    if type(event) = "roVideoScreenEvent" or type(event) = "roVideoPlayerEvent" then
        sectionName = m.localytics.constants.section_playback
        message = "Type: unexpected"

        pausedSession = ll_get_session_value(m.localytics.keys.auto_playback_paused_session, false, true)
        if not (event.isResumed() or (ll_is_boolean(pausedSession) and pausedSession = true)) then
            ll_keep_session_alive("ll_process_player_metrics")
        end if

        if event.isRequestFailed()
            message = "Type: isRequestFailed, Index: " + event.GetIndex().ToStr() + ", Message: " + event.GetMessage()

            ll_write_registry(m.localytics.keys.auto_playback_pending, "true", false, sectionName)
            ll_write_registry(m.localytics.keys.auto_playback_url, event.GetInfo()["Url"], false, sectionName)
            ll_write_registry(m.localytics.keys.auto_playback_end_reason, m.localytics.constants.finish_reason_playback_error, true, sectionName)
        else if event.isPlaybackPosition() then
            message = "Type: isPlaybackPosition,  Index: " + event.GetIndex().ToStr()

            bufferStartTime = ll_get_session_value(m.localytics.keys.auto_playback_buffer_start, true)
            bufferTime = ll_get_session_value(m.localytics.keys.auto_playback_buffer, true)
            if ll_is_integer(bufferStartTime) and (not ll_is_integer(bufferTime)) then
                'Only set buffer time if it hasn't been set yet
                timestamp = ll_get_timestamp_generator()
                bufferTotal = timestamp.asSeconds() - bufferStartTime
                ll_write_registry(m.localytics.keys.auto_playback_buffer, bufferTotal.ToStr(), false, sectionName)
                ll_set_session_value(m.localytics.keys.auto_playback_buffer, bufferTotal, false, false)
            end if

            playbackPosition = event.GetIndex().ToStr()

            timeWatched = ll_get_session_value(m.localytics.keys.auto_playback_watched, true)
            if (not ll_is_integer(timeWatched)) or playbackPosition > timeWatched then 'Same as MAX(timeWatched, playbackPosition)
                ll_set_session_value(m.localytics.keys.auto_playback_watched, playbackPosition, false, false)
                ll_write_registry(m.localytics.keys.auto_playback_watched, playbackPosition, false, sectionName)
            end if

            ll_write_registry(m.localytics.keys.auto_playback_current_time, playbackPosition, true, sectionName)
        else if event.isStreamStarted()
            message = "Type: isStreamStarted,  Index: " + event.GetIndex().ToStr() + ", Url: " + event.GetInfo()["Url"]

            IsUnderrun = event.GetInfo()["IsUnderrun"]
            if IsUnderrun = false then
                timestamp = ll_get_timestamp_generator()
                ll_set_session_value(m.localytics.keys.auto_playback_buffer_start, timestamp.asSeconds(), false, false)
            end if

            ll_write_registry(m.localytics.keys.auto_playback_pending, "true", false, sectionName)
            ll_write_registry(m.localytics.keys.auto_playback_url, event.GetInfo()["Url"], true, sectionName)
        else if event.isFullResult()
            message = "Type: isFullResult"

            ll_write_registry(m.localytics.keys.auto_playback_end_reason, m.localytics.constants.finish_reason_playback_ended, true, sectionName)
        else if event.isPartialResult()
            message = "Type: isPartialResult"

            ll_write_registry(m.localytics.keys.auto_playback_end_reason, m.localytics.constants.finish_reason_user_exited, true, sectionName)
        else if event.isPaused()
            message = "Type: isPaused"
            ll_set_session_value(m.localytics.keys.auto_playback_paused_session, true, false, false)
        else if event.isResumed()
            message = "Type: isResumed"
            ll_set_session_value(m.localytics.keys.auto_playback_paused_session, false, false, false)
        else if event.isScreenClosed()
            message = "Type: isScreenClosed"

            ' Clear temporary values
            ll_set_session_value(m.localytics.keys.auto_playback_buffer, "", false, false)
            ll_set_session_value(m.localytics.keys.auto_playback_buffer_start, "", false, false)
            ll_set_session_value(m.localytics.keys.auto_playback_watched, "", false, false)
            ll_set_session_value(m.localytics.keys.auto_playback_paused_session, "", false, false)
            'Attempt to fire player metrics
            ll_send_player_metrics()

'        else if event.isStreamSegmentInfo()
'            ll_debug_log("ll_process_player_metrics(Type: isStreamSegmentInfo, Index: " + event.GetIndex().ToStr() + ", SegUrl: " + event.GetInfo()["SegUrl"] + ")")
'        else if event.isStatusMessage()
'            ll_debug_log("ll_process_player_metrics(Type: isStatusMessage, Message: " + event.GetMessage() + ")")
'        else
'            ll_debug_log("ll_process_player_metrics(Type: unexpected type)")
        end if
        ll_debug_log("ll_process_player_metrics(" + message + ")")
    end if
End Function

Function ll_send_player_metrics()
    ll_debug_log("ll_send_player_metrics()")

    playback_section = m.localytics.constants.section_playback

    if ll_read_registry(m.localytics.keys.auto_playback_pending, "false", playback_section) = "true" then
        attributes = CreateObject("roAssociativeArray")

        ' Required metadata fields
        attributes[m.localytics.constants.content_id] = m.localytics.constants.not_available
        attributes[m.localytics.constants.content_title] = m.localytics.constants.not_available
        attributes[m.localytics.constants.content_series_title] = m.localytics.constants.not_available
        attributes[m.localytics.constants.content_category] = m.localytics.constants.not_available

        ' Process metadata
        metadata_section= CreateObject("roRegistrySection", m.localytics.constants.section_metadata)
        for each key in metadata_section.GetKeyList()
            attributes[key] = metadata_section.Read(key)
        end for

        ' Fill Playback Data
        contentUrl = ll_read_registry(m.localytics.keys.auto_playback_url, m.localytics.constants.not_available, playback_section)
        attributes[m.localytics.constants.content_url] = contentUrl

        endReason = ll_read_registry(m.localytics.keys.auto_playback_end_reason, m.localytics.constants.finish_reason_unknown, playback_section)
        attributes[m.localytics.constants.content_did_reach_end] = ll_to_string(endReason = m.localytics.constants.finish_reason_playback_ended)
        attributes[m.localytics.constants.end_reason] = endReason

        bufferTime = ll_read_registry(m.localytics.keys.auto_playback_buffer, m.localytics.constants.not_available, playback_section)
        attributes[m.localytics.constants.content_time_to_buffer_seconds] = bufferTime

        playbackTime = ll_read_registry(m.localytics.keys.auto_playback_current_time, m.localytics.constants.not_available, playback_section)
        attributes[m.localytics.constants.content_timestamp] = playbackTime

        contentLength = ll_read_registry(m.localytics.keys.auto_playback_length, m.localytics.constants.not_available, playback_section)
        attributes[m.localytics.constants.content_length] = contentLength

        timeWatched = ll_read_registry(m.localytics.keys.auto_playback_watched, m.localytics.constants.not_available, playback_section)
        attributes[m.localytics.constants.content_played_seconds] = timeWatched

        percentComplete = m.localytics.constants.not_available
        if contentLength.ToInt() > 0 then
            if endReason = m.localytics.constants.finish_reason_playback_ended then
                percentComplete = 100
            else
                percentComplete = Int((timeWatched.ToInt()/contentLength.ToInt())*100)
            end if
        end if
        attributes[m.localytics.constants.content_played_percent] = percentComplete

        for each key in attributes ' clean up as string fields
            attributes[key] = ll_json_escape_string(attributes[key])
        end for

        ll_tag_event(m.localytics.constants.event_video_watched, attributes, timeWatched.ToInt())

        ' Cleanup
        ll_clear_registry(true,m.localytics.constants.section_metadata)
        ll_clear_registry(true,m.localytics.constants.section_playback)
    end if
End Function


Function ll_keep_session_alive(source="external" As String)
    ll_debug_log("ll_keep_session_alive(Source: " + source + ")")

    timestamp = ll_get_timestamp_generator()
    ll_set_session_value(m.localytics.keys.session_action_time, timestamp.asSeconds())
    ll_process_outstanding_request()
End Function

Function ll_check_session_timeout(isInit=false as Boolean)
    currentTime = ll_get_timestamp_generator().asSeconds()
    lastActionTime = ll_get_session_value(m.localytics.keys.session_action_time, true)
    diff = currentTime-lastActionTime

    ll_debug_log("ll_check_session_timeout("+ m.localytics.sessionTimeout.toStr() +"): Inactive for " + diff.toStr())

    if isInit then
        if m.localytics.sessionTimeout = 0 or diff > m.localytics.sessionTimeout then
            ll_close_session(isInit)
            ll_open_session()
        else
            ll_screen_viewed("[External]", lastActionTime)
        end if
    else if (m.localytics.sessionTimeout > 0 and diff > m.localytics.sessionTimeout)then
       ll_close_session(isInit)
       ll_open_session()
    end if
End Function

Function ll_restore_session() As Boolean
    ll_debug_log("ll_restore_session()")
    oldSession = CreateObject("roAssociativeArray")
    oldSession[m.localytics.keys.session_uuid] = ll_read_registry(m.localytics.keys.session_uuid)

    if oldSession[m.localytics.keys.session_uuid] = "" then
        return false
    end if

    oldSession[m.localytics.keys.install_uuid] = ll_read_registry(m.localytics.keys.install_uuid, ll_generate_guid())
    oldSession[m.localytics.keys.session_index] = ll_read_registry(m.localytics.keys.session_index).ToInt()
    oldSession[m.localytics.keys.sequence_index] = ll_read_registry(m.localytics.keys.sequence_index).ToInt()
    oldSession[m.localytics.keys.session_open_time] = ll_read_registry(m.localytics.keys.session_open_time).ToInt()
    oldSession[m.localytics.keys.session_action_time] = ll_read_registry(m.localytics.keys.session_action_time).ToInt()
    oldSession[m.localytics.keys.screen_flows] = ll_read_registry(m.localytics.keys.screen_flows)
    oldSession[m.localytics.keys.profile_customer_id] = ll_read_registry(m.localytics.keys.profile_customer_id)

    ' auto-tag metrics
    oldSession[m.localytics.keys.auto_previous_screen] = ll_read_registry(m.localytics.keys.auto_previous_screen)
    oldSession[m.localytics.keys.auto_previous_screen_time] = ll_read_registry(m.localytics.keys.auto_previous_screen_time).ToInt()

    for i=0 to 19
        cdKey = "c" + i.ToStr()
        oldSession[cdKey] = ll_read_registry(cdKey)
    next

    m.localytics.session = oldSession

    return true
End Function

Function ll_load_custom_dimensions() As Object
    ll_debug_log("ll_load_custom_dimensions()")
    oldCustomDimensions = CreateObject("roAssociativeArray")

    for i=0 to 19
        cdKey = "c" + i.ToStr()
        oldCustomDimensions[cdKey] = ll_read_registry(cdKey)
    next

    return oldCustomDimensions
End Function

' Returns the header required for each upload
Function ll_get_header(seq As Integer) As Object
    header = CreateObject("roAssociativeArray")
    header.dt = "h"
    header.seq = seq
    header.u = ll_generate_guid()
    header.attrs = CreateObject("roAssociativeArray")
    header.attrs.dt = "a"
    header.attrs.au = m.localytics.appKey
    header.attrs.iu = ll_read_registry(m.localytics.keys.install_uuid)

    di = CreateObject("roDeviceInfo")
    ai = CreateObject("roAppInfo")

    header.attrs.dp = "Roku"
    header.attrs.du = ll_hash(di.GetDeviceUniqueId()) 'hashed device uuid
    header.attrs.dov = di.GetVersion() 'device version
    header.attrs.dmo = di.GetModel() 'device model

    header.attrs.lv = m.localytics.libraryVersion
    header.attrs.dma = "Roku"
    header.attrs.dll = di.GetCurrentLocale().Left(2)
    header.attrs.dlc = di.GetCountryCode()
    header.attrs.av = ai.GetVersion()

    header.ids = CreateObject("roAssociativeArray")
    return header
End Function

' Wrapper function - adds the required header data to each call
Function ll_send(event As Object)
    ll_debug_log("ll_send()")
    for i=0 to 19
        cdKey = "c" + i.ToStr()
        value = m.localytics.customDimensions[cdKey]
        if value <> invalid and value <> "" then
            event[cdKey] = value
        end if
    next

    timestamp = ll_get_timestamp_generator()

    seq = ll_get_session_value(m.localytics.keys.sequence_index, true)
    header = ll_get_header(seq)
    ll_set_session_value(m.localytics.keys.sequence_index, seq+1)

    baseUrl = m.localytics.endpoint
    appKey = m.localytics.appKey
    path = "/uploads/image.gif?client_date=" + timestamp.asSeconds().ToStr()
    callback = "&callback=z"
    data = "&data="

    ' Need to escape parameters
    urlTransfer = CreateObject("roUrlTransfer")
    params = urlTransfer.Escape(ll_set_params_as_string(header)) + "%0A" + urlTransfer.Escape(ll_set_params_as_string(event))

    request = baseUrl + appKey + path + callback + data + params
    ll_debug_log("ll_send(): " + urlTransfer.Unescape(request))

    ' Put event on the event queue
    ll_add_request_to_pending(request)
    ll_upload_next_pending()
End Function

Function ll_add_request_to_pending(request As String)
    urlTransfer = CreateObject("roUrlTransfer")
    pending_requests = ParseJson(ll_read_registry("pending_requests", "[]"))
    pending_requests.Push(request)

    ll_write_registry_dyn("pending_requests", pending_requests)
End Function

Function ll_upload_next_pending()
    urlTransfer = CreateObject("roUrlTransfer")
    pending_requests = ParseJson(ll_read_registry("pending_requests", "[]"))
    ll_debug_log("Uploading next event.  Queue size: (" + ll_to_string(pending_requests.Count()) + ")")
    next_request = pending_requests.Shift()
    if next_request <> invalid then
        ll_write_registry_dyn("pending_requests", pending_requests)
        ll_upload(next_request)
    end if
End Function

Function ll_upload(url As String)
    http = CreateObject("roUrlTransfer")

    if m.localytics.secured then
        http.SetCertificatesFile("common:/certs/ca-bundle.crt")
        http.InitClientCertificates()
    end if

    http.SetPort(CreateObject("roMessagePort"))
    http.SetUrl(url)
    http.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    http.EnableEncodings(true)

    if (http.AsyncGetToString())
        m.localytics.outstandingRequests[url] = http
    end if
End Function

Function ll_process_outstanding_request()
    ll_debug_log("ll_process_outstanding_request()")
    outstandingRequests = createObject("roAssociativeArray")
    ll_debug_log("Processing - there are " + ll_to_string(m.localytics.outstandingRequests.Count()) + " requests outstanding")
    for each item in m.localytics.outstandingRequests.Items()
        http = item.value
        if type(http) = "roUrlTransfer" then
            port = http.GetPort()
            if type(port) = "roMessagePort" then
                event = port.GetMessage()
                if type(event) = "roUrlEvent"
                    ll_debug_log("process_done: " + event.GetString())

                    if ll_should_retry_request(event.GetResponseCode()) then
                        ll_add_request_to_pending(http.GetUrl())
                    end if


                else
                    outstandingRequests[item.key] = item.value
                    ll_debug_log("process_not_done: " + item.key)
                end if
            end if
        end if
    end for

    m.localytics.outstandingRequests = outstandingRequests
    ll_upload_next_pending()
End Function

Function ll_should_retry_request(responseCode As Integer) as Boolean
    ll_debug_log("roUrlEvent response code: " + ll_to_string(responseCode))
    if (responseCode >= 500 and responseCode <= 599) or responseCode = 429 or responseCode < 0
        ll_debug_log("request server error " + ll_to_string(responseCode) + ": adding back to pending requests")
        return true
    else if responseCode >= 400 and responseCode <= 499
        ll_debug_log("request client error " + ll_to_string(responseCode) + ": skipping request")
        return false
    end if

    return false
End Function

'************************************************************
' Customer Profile Functions
'************************************************************
Function ll_set_customer_id(customerId="" As String)
    ll_debug_log("ll_set_customer_id()")

    ll_write_registry(m.localytics.keys.profile_customer_id, customerId)
End Function

Function ll_set_customer_email(customerEmail As String)
    ll_debug_log("ll_set_customer_email()")

    ll_set_profile_attribute("org", m.localytics.keys.profile_customer_email, customerEmail)
End Function

Function ll_set_customer_full_name(fullName As String)
    ll_debug_log("ll_set_customer_full_name()")

    ll_set_profile_attribute("org", m.localytics.keys.profile_customer_full_name, fullName)
End Function

Function ll_set_customer_first_name(firstName As String)
    ll_debug_log("ll_set_customer_first_name()")

    ll_set_profile_attribute("org", m.localytics.keys.profile_customer_first_name, firstName)
End Function

Function ll_set_customer_last_name(lastName As String)
    ll_debug_log("ll_set_customer_last_name()")

    ll_set_profile_attribute("org", m.localytics.keys.profile_customer_last_name, lastName)
End Function

Function ll_set_profile_attribute(scope as String, key As String, value=invalid As Dynamic)
    if key.Len() > 0 then
        attribute = CreateObject("roAssociativeArray")
        attribute[key] = value
        ll_patch_profile(scope, attribute)
    end if
End Function

Function ll_patch_profile(scope as String, attributes=invalid As Object)
    customerId = ll_read_registry(m.localytics.keys.profile_customer_id)
    installId = ll_read_registry(m.localytics.keys.install_uuid, ll_generate_guid())

    if attributes = invalid or attributes.IsEmpty() or (not ll_is_valid_string(customerId)) then return -1

    endpoint = m.localytics.profileEndpoint + m.localytics.appKey + "/profiles/" + customerId

    http = CreateObject("roUrlTransfer")

    if m.localytics.secured then
        http.SetCertificatesFile("common:/certs/ca-bundle.crt")
        http.InitClientCertificates()
    end if

    http.SetPort(CreateObject("roMessagePort"))
    http.SetUrl(endpoint)

    http.AddHeader("Content-Type", "application/json")

    timestamp = ll_get_timestamp_generator()
    http.AddHeader("x-install-id", installId)
    http.AddHeader("x-upload-time", timestamp.asSeconds().toStr())
    http.AddHeader("x-customer-id", customerId)
    http.EnableEncodings(true)

    bodyData = { attributes: attributes, database: scope}

    ' Must nest it in attributes json
    body = ll_set_params_as_string(bodyData)

    ll_debug_log("ll_patch_profile(url:" +endpoint+ ", body: " +body+ ")")

    if (http.AsyncPostFromString(body))
        m.localytics.outstandingRequests[endpoint+body] = http
    end if
End Function


'************************************************************
'Helper Functions
'************************************************************
Function ll_get_storage_keys() As Object
    keys = CreateObject("roAssociativeArray")

    keys.install_uuid = "iu"
    keys.event_store = "es" 'not used on web
    keys.current_header = "ch" 'not used on web
    keys.device_birth_time = "pa" 'page load time (not relevant)
    keys.session_uuid = "csu"
    keys.session_open_time = "cst"
    keys.session_action_time = "ct"
    keys.session_index = "csi"
    keys.sequence_index = "csq"
    keys.customer_id = "cid"
    keys.last_open_time = "lot" 'not used on web
    keys.last_close_time = "lct" 'not used on web
    keys.screen_flows = "fl"
    keys.custom_dimensions = "cd"
    keys.identifiers = "ids"

    keys.auto_previous_screen = "als" 'not used on web
    keys.auto_previous_screen_time = "alst" 'not used on web

    keys.auto_playback_pending = "app"
    keys.auto_playback_length = "apl"
    keys.auto_playback_url = "apu"
    keys.auto_playback_end_reason = "aper"
    keys.auto_playback_watched = "apw"
    keys.auto_playback_current_time = "apct"
    keys.auto_playback_buffer = "apb"
    keys.auto_playback_buffer_start = "apbs"
    keys.auto_playback_paused_session = "apps"

    keys.profile_customer_id = "pcid"
    keys.profile_customer_email = "email"
    keys.profile_customer_full_name = "full_name"
    keys.profile_customer_first_name = "first_name"
    keys.profile_customer_last_name = "last_name"
    return keys
End Function

Function ll_get_constants() As Object
    constants = CreateObject("roAssociativeArray")

    constants.event_screen_viewed = "Screen Viewed"
    constants.event_video_watched = "Video Watched"


    constants.section_metadata = "com.localytics.metadata"
    constants.section_playback = "com.localytics.playback"

    constants.finish_reason_playback_ended = "Playback Ended"
    constants.finish_reason_playback_error = "Playback Error"
    constants.finish_reason_user_exited = "User Exited"
    constants.finish_reason_unknown = "Unknown"

    constants.current_screen = "Current Screen"
    constants.previous_screen = "Previous Screen"
    constants.time_on_screen = "Time On Screen (Seconds)"
    constants.not_available = "N/A"
    constants.content_url = "Content URL"
    constants.content_id = "Content ID"
    constants.content_title = "Content Title"
    constants.content_series_title = "Content Series Title"
    constants.content_category = "Content Category"

    constants.content_length = "Content Length (Seconds)"
    constants.content_played_seconds = "Content Played (Seconds)"
    constants.content_played_percent = "Content Played (Percent)"
    constants.content_did_reach_end = "Content Did Reach End"
    constants.end_reason = "End Reason"
    constants.content_time_to_buffer_seconds = "Content Time to Buffer (Seconds)"
    constants.content_timestamp = "Content Timestamp"
    return constants
End Function

Function ll_is_custom_dimensions_key(storageKey) As Boolean
    for i=0 to 19
        cdKey = "c" + i.ToStr()
        if storageKey = cdKey then
            return true
        end if
    next
    return false
End Function

' Reads from "key" of registry "section". If value doesn't exist, "default" will be used
Function ll_read_registry(key As String, default="" As String, section="com.localytics" As String) As String
    sec = CreateObject("roRegistrySection", section)
    if sec.Exists(key) then
        return sec.Read(key)
    end if
    ll_write_registry(key, default, false, section)
    return default
End Function

Function ll_read_registry_bool(key As String, default="" As String, section="com.localytics" As String) As Boolean
    if ll_read_registry(key, default, section) = "True" then
        return true
    end if
    return false
End Function

Function ll_read_registry_int(key As String, default="" As String, section="com.localytics" As String) As Integer
    return ll_read_registry(key, default, section).toInt()
End Function

' Same as ll_write_registry, but takes any type
Function ll_write_registry_dyn(key As String, value As Dynamic, flush=true As Boolean, section="com.localytics" As String)
  ll_write_registry(key, ll_to_string(value), flush, section)
End Function

' Writes "value" to "key" of registry "section". "flush" = false will skip calling Flush(), ideal for multiple writes
Function ll_write_registry(key As String, value As String, flush=true As Boolean, section="com.localytics" As String)
    sec = CreateObject("roRegistrySection", section)
    sec.Write(key, value)

    if flush then
        sec.Flush()
    end if
End Function

' Deletes "key" of registry "section". "flush" = false will skip calling Flush(), ideal for multiple deletes
Function ll_delete_registry(key As String, section="com.localytics" As String, flush=true As Boolean)
    sec = CreateObject("roRegistrySection", section)
    sec.Delete(key)

    if flush then
        sec.Flush()
    end if
End Function

' Writes "value" to "key" of registry "section". "flush" = false will skip calling Flush(), ideal for multiple writes
Function ll_clear_registry(flush=true As Boolean, section="com.localytics" As String)
    sec = CreateObject("roRegistrySection", section)

    for each key in sec.GetKeyList()
        sec.Delete(key)
    next

    sec.Flush()
End Function

' True if the instance has been initialized
Function ll_has_session() As Boolean
    ll_debug_log("ll_has_session() -> " + ll_to_string(m.localytics.session))
    return m.localytics.session <> invalid
End Function

' Manages the current instance's variables, ie. appKey, sessionStartTime, clientId ...
Function ll_get_session_value(param As String, decimal=false as Boolean, bool=false as Boolean) As Dynamic
    if ll_has_session() AND param <> invalid then
      if decimal then
        return ll_read_registry_int(param, "", "com.localytics.session")
      else if bool then
        return ll_read_registry_bool(param, "", "com.localytics.session")
      else
        return ll_read_registry(param, "", "com.localytics.session")
      end if
    end if

    return ""
End Function

Function ll_set_session_value(param As String, value As Dynamic, flush=false As Boolean, persist=true As Boolean)
    if ll_has_session() AND param <> invalid AND value <> invalid then
        ll_write_registry(param, ll_to_string(value), flush, "com.localytics.session")
    end if
End Function

' Returns a roDateTime object for timestamp purposes
Function ll_get_timestamp_generator() As Object
    Return CreateObject("roDateTime")
End Function

' Generates a fixed format guid of format xxxxxxxx-xxxx-4xxx-xxxx (loosely based on web sdk
Function ll_generate_guid() As String
    Return ll_get_random_hex_string(8) + "-" + ll_get_random_hex_string(4) + "-4" + ll_get_random_hex_string(3) + "-" + ll_get_random_hex_string(4) + "-" + ll_get_random_hex_string(12)
End Function

' Generates a random hex string of param length
Function ll_get_random_hex_string(length As Integer) As String
    chars = "0123456789ABCDEF"
    hexString = ""
    For i = 1 to length
        hexString = hexString + chars.Mid(Rnd(16) - 1, 1)
    Next
    Return hexString
End Function

' SHA-1 hash
Function ll_hash(value As String) As String
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(value)
    digest = CreateObject("roEVPDigest")
    digest.Setup("sha1")
    digest.Update(ba)
    result = digest.Final()
    return result
End Function

' Quick and dirty function to convert params into string form (Some issues with FormatJSON and Parse JSON...)
Function ll_set_params_as_string(params As Object) As String
    result = "{"
    for each key in params
        'TODO refactor for array
        if key = "fl" then
            result = result + Chr(34) + key + Chr(34) + ":" + params[key] + ","
        else if type(params[key]) = "roAssociativeArray" then
            result = result + Chr(34) + key + Chr(34) + ":" + ll_set_params_as_string(params[key]) + ","
        else if ll_is_integer(params[key]) then
            result = result + Chr(34) + key + Chr(34) + ":" + (params[key]).ToStr() + ","
        else
            if params[key] = invalid or (ll_is_string(params[key]) and not ll_is_valid_string(params[key])) then
                result = result + Chr(34) + key + Chr(34) + ":null" + ","
            else
                result = result + Chr(34) + key + Chr(34) + ":" + Chr(34) + ll_to_string(params[key]) + Chr(34) + ","
            end if
        end if
    end for
    if result.Len() > 1 then
        result = result.Left(result.Len() - 1)
    end if
    return result + "}"
End Function

Function ll_to_string(variable As Dynamic) As String
    if ll_is_integer(variable)
        return variable.ToStr()
    else if type(variable) = "roFloat" or type(variable) = "Float" then
        return Str(variable).Trim()
    else if type(variable) = "roBoolean" or type(variable) = "Boolean" then
        if variable = true then
            return "True"
        end if
        return "False"
    else if ll_is_string(variable) then
        return variable
    else if type(variable) = "roArray"
        return FormatJson(variable)
    else
        return type(variable)
    end if
End Function

Function ll_is_integer(variable As Dynamic) As Boolean
    return (type(variable) = "roInt" or type(variable) = "roInteger" or type(variable) = "Integer")
End Function

Function ll_is_boolean(variable As Dynamic) As Boolean
    return (type(variable) = "roBoolean" or type(variable) = "Boolean")
End Function

Function ll_is_string(variable As Dynamic) As Boolean
    return (type(variable) = "roString" or type(variable) = "String")
End Function

' Valid string is of type "roString" or "String" and Length > 0
Function ll_is_valid_string(variable As Dynamic) As Boolean
    return (ll_is_string(variable) and variable.Len() > 0)
End Function

Function ll_debug_log(line as Dynamic)
    if m.localytics.debug = true
        if ll_is_string(line) then
          print "<ll_debug> " + line
        else
          print "<ll_debug>" + ll_to_string(line)
        end if
        return ""
    end if
End Function

Function ll_json_escape_string(variable As Dynamic) As Dynamic
    if ll_is_string(variable) then
        return variable.Replace(Chr(34), "\" + Chr(34))
    else
        return variable
    end if
End Function
