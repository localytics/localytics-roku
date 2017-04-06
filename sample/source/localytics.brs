Function init()
    m.top.functionName = "execLocalyticsLoop"
end Function

'Runs as a part of LocalyticsTask'
Function execLocalyticsLoop() as Void
    port = CreateObject("roMessagePort")
    m.top.observeField("event", port)
    m.top.observeField("screen", port)
    m.top.observeField("customer", port)
    m.top.observeField("profileAttribute", port)
    m.top.observeField("customDimension", port)
    m.top.observeField("videoNode", port)
    m.top.observeField("videoMetaData", port)

    appKey = m.top.appKey
    secured = m.top.secured
    sessionTimeout = m.top.sessionTimeout
    debug = m.top.debug
    if (appKey = Invalid) then
      print "ERROR: *** Required Localytics app key is not set - exiting LocalyticsTask ***"
      return
    end if
    if (debug = Invalid) then
      debug = false
    end if
    if (secured = Invalid) then
      secured = true
    end if
    if (sessionTimeout = Invalid) then
      sessionTimeout = 1800
    end if
    initLocalytics(appKey, sessionTimeout, secured, false, debug)

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
                        ll_set_profile_attribute(data.scope, data.key, data.value)
                    end if
                else if field = "customDimension" then
                    if data.i <> invalid and data.value <> invalid then
                        ll_set_custom_dimension(data.i, data.value)
                    end if
                else if field = "videoNode" then
                    m.localytics.videoPlayer = data
                    ll_process_player_metrics()
                else if field = "videoMetaData" then
                    ll_process_video_metadata(data)
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
    new_localytics.libraryVersion = "roku_4.0.2"

    ll_debug_log("init Localytics: "+appKey)

    if secured then
        new_localytics.uriScheme = "https"
    else
        new_localytics.uriScheme = "http"
    end if

    new_localytics.secured = secured
    new_localytics.endpoint = new_localytics.uriScheme + "://analytics.localytics.com/api/v2/applications/"
    new_localytics.profileEndpoint = new_localytics.uriScheme + "://profile.localytics.com/v1/apps/"
    new_localytics.appKey = appKey
    new_localytics.sessionTimeout = sessionTimeout
    new_localytics.outstandingRequests = CreateObject("roAssociativeArray") ' Volatile Store for roUrlTransfer response
    new_localytics.customDimensions = ll_load_custom_dimensions()
    new_localytics.maxScreenFlowLength = 2500
    new_localytics.keys = ll_get_storage_keys()
    new_localytics.constants = ll_get_constants()

    if fresh then
        ll_delete_session_data()
    end if

    ll_initialize_session()
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

Function ll_delete_session_data()
    sec = CreateObject("roRegistrySection", m.localytics.constants.section_session)

    for each key in sec.GetKeyList()
      sec.Delete(key)
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
    if ll_has_session() = false then
        ll_debug_log("Localytics tag screen failed: no session")
        return -1
    end if
    ll_check_session_timeout()
    ll_keep_session_alive("ll_tag_screen")

    screenFlows = ll_get_session_value(m.localytics.keys.screen_flows)

    if (not ll_is_string(screenFlows)) or screenFlows.Len() = 0
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
Function ll_process_video_metadata(data)
  ll_clear_registry(true,m.localytics.constants.section_metadata)
  for each item in data.items()
      ll_write_registry_dyn(item.key, item.value, false, m.localytics.constants.section_metadata)
  end for
  ll_write_registry_dyn("metadataTime", ll_get_timestamp_generator(), true, m.localytics.constants.section_metadata)
End Function

Function ll_process_player_metrics()
    ll_debug_log("ll_process_player_metrics()")

    if (m.localytics.videoPlayer <> Invalid and m.localytics.videoPlayer.streamInfo <> Invalid) then
        sectionName = m.localytics.constants.section_playback

        state = m.localytics.videoPlayer.state
        position = m.localytics.videoPlayer.position
        streamInfo = m.localytics.videoPlayer.streamInfo
        timeToStartStreaming = m.localytics.videoPlayer.timeToStartStreaming

        message = "Playback state: " + state + ", Position: " + position.ToStr()
        ' If playback is active, make sure to keep the session alive
        if (state = "buffering" or state = "playing" or state = "paused") then
            ll_keep_session_alive("ll_process_player_metrics")
        end if
        if state = "error" then
          message = message + ", Message: " + m.localytics.videoPlayer.errorMsg

          ll_write_registry(m.localytics.keys.auto_playback_pending, "true", false, sectionName)
          ll_write_registry(m.localytics.keys.auto_playback_url, streamInfo.streamUrl, false, sectionName)

          ll_write_registry(m.localytics.keys.auto_playback_end_reason, m.localytics.constants.finish_reason_playback_error, true, sectionName)
        else if state = "playing" then
          ll_write_registry(m.localytics.keys.auto_playback_pending, "true", false, sectionName)
          ll_write_registry(m.localytics.keys.auto_playback_url, streamInfo.streamUrl, false, sectionName)
          ll_write_registry(m.localytics.keys.auto_playback_buffer, timeToStartStreaming.ToStr(), false, sectionName)
          content_length = m.localytics.videoPlayer.duration
          if content_length > 0 then
              ll_write_registry(m.localytics.keys.auto_playback_length, content_length.ToStr(), false, m.localytics.constants.section_playback)
          else
              ll_delete_registry(m.localytics.keys.auto_playback_length, m.localytics.constants.section_playback, false)
          end if

          timeWatched = ll_get_session_value(m.localytics.keys.auto_playback_watched, true)
          if (not ll_is_integer(timeWatched)) or position > timeWatched then 'Same as MAX(timeWatched, position)
              ll_write_registry(m.localytics.keys.auto_playback_watched, position.ToStr(), false, sectionName)
          end if

          ll_write_registry(m.localytics.keys.auto_playback_current_time, position.ToStr(), true, sectionName)
        else if state = "stopped" then
          ll_write_registry(m.localytics.keys.auto_playback_end_reason, m.localytics.constants.finish_reason_user_exited, true, sectionName)
          'Attempt to fire player metrics
          ll_send_player_metrics()
        else if state = "finished" then
          ll_write_registry(m.localytics.keys.auto_playback_end_reason, m.localytics.constants.finish_reason_playback_ended, true, sectionName)
          'Attempt to fire player metrics
          ll_send_player_metrics()
        end if
        ll_debug_log("ll_process_player_metrics(" + message + ")")
    end if
End Function

Function ll_send_player_metrics()
    ll_debug_log("ll_send_player_metrics()")

    playback_section = m.localytics.constants.section_playback

    if ll_read_registry(m.localytics.keys.auto_playback_pending, "false", playback_section) = "true" then
        attributes = CreateObject("roAssociativeArray")

        ' Process metadata
        metadata_section= CreateObject("roRegistrySection", m.localytics.constants.section_metadata)
        for each key in metadata_section.GetKeyList()
          if (key <> "metadataTime") then
            attributes[key] = metadata_section.Read(key)
          end if
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
    ll_add_request_to_pending(request, invalid, m.localytics.constants.request_type_analytics)
    ll_upload_next_pending()
End Function

Function ll_add_request_to_pending(url As String, bodyData As Object, requestType as String)
    pending_requests = ParseJson(ll_read_registry("pending_requests", "[]"))

    request = createObject("roAssociativeArray")
    request.url = url
    if (bodyData <> invalid) then
        request.body = bodyData
    end if
    request.requestType = requestType
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
        if (next_request.requestType = m.localytics.constants.request_type_analytics) then
          ll_upload(next_request.url)
        else
          ll_upload_profile(next_request.url, next_request.body)
        end if
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
        analyticsRequest = CreateObject("roAssociativeArray")
        analyticsRequest.type="analytics"
        analyticsRequest.url=url
        analyticsRequest.request=http
        m.localytics.outstandingRequests[url]=analyticsRequest
    end if
End Function

Function ll_process_outstanding_request()
    ll_debug_log("ll_process_outstanding_request()")
    outstandingRequests = createObject("roAssociativeArray")
    ll_debug_log("Processing - there are " + ll_to_string(m.localytics.outstandingRequests.Count()) + " requests outstanding")
    for each item in m.localytics.outstandingRequests.Items()
        http = item.value.request
        if type(http) = "roUrlTransfer" then
            port = http.GetPort()
            if type(port) = "roMessagePort" then
                event = port.GetMessage()
                if type(event) = "roUrlEvent"
                    ll_debug_log("process_done: " + event.GetString())

                    if ll_should_retry_request(event.GetResponseCode()) then
                        ll_add_request_to_pending(item.value.url, item.value.body, item.value.type)
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

    if attributes = invalid or attributes.IsEmpty() or (not ll_is_valid_string(customerId)) then return -1

    endpoint = m.localytics.profileEndpoint + m.localytics.appKey + "/profiles/" + customerId

    bodyData = { attributes: attributes, database: scope}

    ll_add_request_to_pending(endpoint, bodyData, m.localytics.constants.request_type_profile)

    ll_upload_next_pending()
End Function

Function ll_upload_profile(endpoint as String, bodyData as Object)
    customerId = ll_read_registry(m.localytics.keys.profile_customer_id)
    installId = ll_read_registry(m.localytics.keys.install_uuid, ll_generate_guid())

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

    ' Must nest it in attributes json
    body = ll_set_params_as_string(bodyData)

    ll_debug_log("ll_patch_profile(url:" +endpoint+ ", body: " +body+ ")")

    if (http.AsyncPostFromString(body)) then
        profileRequest = CreateObject("roAssociativeArray")
        profileRequest.type="profile"
        profileRequest.url=endpoint
        profileRequest.body=bodyData
        profileRequest.request=http
        m.localytics.outstandingRequests[endpoint+body] = profileRequest
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
    constants.section_session = "com.localytics.session"
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

    constants.request_type_analytics = "analytics"
    constants.request_type_profile = "profile"

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

Function ll_read_registry_bool(key As String, default="" as String, section="com.localytics" As String) As Boolean
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
        return ll_read_registry_int(param, "", m.localytics.constants.section_session)
      else if bool then
        return ll_read_registry_bool(param, "", m.localytics.constants.section_session)
      else
        return ll_read_registry(param, "", m.localytics.constants.section_session)
      end if
    end if

    ' Return type sensitive defaults
    if decimal then
      return -1
    else if bool then
      return false
    else
      return ""
    end if
End Function

Function ll_set_session_value(param As String, value As Dynamic, flush=false As Boolean, persist=true As Boolean)
    if ll_has_session() AND param <> invalid AND value <> invalid then
        ll_write_registry(param, ll_to_string(value), flush, m.localytics.constants.section_session)
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
