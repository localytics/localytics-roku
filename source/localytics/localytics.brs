' Creates a new Localytics instance
' Note: 
' - "fresh" will clear previous stored values
' - "debug" will log some messages
Function Localytics(appKey As String, sessionTimeout=1800 As Integer, secured=true As Boolean, fresh=false As Boolean, debug=false As Boolean) As Object

    new_localytics = CreateObject("roAssociativeArray")
    
    new_localytics.libraryVersion = "roku_3.0.0"
    
    ' Function for External Calls
    new_localytics.AutoIntegrate = ll_initialize
    new_localytics.SetCustomDimension = ll_set_custom_dimension
    new_localytics.TagEvent = ll_tag_event
    new_localytics.TagScreen = ll_tag_screen
    new_localytics.KeepSessionAlive = ll_keep_session_alive
    
    new_localytics.SetContentLength = ll_set_content_length
    new_localytics.SetContentId = ll_set_content_id
    new_localytics.SetContentTitle = ll_set_content_title
    new_localytics.SetContentSeriesTitle = ll_set_content_series_title
    new_localytics.SetContentCategory = ll_set_content_category

    new_localytics.ProcessPlayerMetrics = ll_process_player_metrics
    
    new_localytics.SetCustomerId = ll_set_customer_id
    new_localytics.SetCustomerEmail = ll_set_customer_email
    new_localytics.SetCustomerFullName = ll_set_customer_full_name
    new_localytics.SetCustomerFirstName = ll_set_customer_first_name
    new_localytics.SetCustomerLastName = ll_set_customer_last_name    
    new_localytics.SetProfileAttribute = ll_set_profile_attribute

    ' Shouldn't be call externally
    new_localytics.openSession = ll_open_session
    new_localytics.closeSession = ll_close_session
    new_localytics.deleteSessionData = ll_delete_session_data
    new_localytics.restoreSession = ll_restore_session
    new_localytics.persistSession = ll_persist_session
    new_localytics.checkSessionTimeout = ll_check_session_timeout
    new_localytics.loadCustomDimensions = ll_load_custom_dimensions
    new_localytics.clearCustomDimension = ll_clear_custom_dimension
    new_localytics.processOutStandingRequest = ll_process_outstanding_request
    new_localytics.hasSession = ll_has_session
    new_localytics.send = ll_send
    new_localytics.getHeader = ll_get_header
    new_localytics.getSessionValue = ll_get_session_value
    new_localytics.setSessionValue = ll_set_session_value
    new_localytics.debugLog = ll_debug_log
    new_localytics.upload = ll_upload
    new_localytics.isPersistedAcrossSession = ll_is_persisted_across_session
    
    new_localytics.screenViewed = ll_screen_viewed
    new_localytics.setContentMetadata = ll_set_content_metadata
    new_localytics.sendPlayerMetrics = ll_send_player_metrics
    new_localytics.patchProfile = ll_patch_profile
    
    ' Fields Creation
    if secured then
        new_localytics.uriScheme = "https"
    else
        new_localytics.uriScheme = "http"
    end if
    
    new_localytics.secured = secured
    new_localytics.endpoint = new_localytics.uriScheme + "://webanalytics.localytics.com/api/v2/applications/"
    new_localytics.profileEndpoint = new_localytics.uriScheme + "://profile.localytics.com/v1/apps/"
    new_localytics.appKey = appKey
    new_localytics.sessionTimeout = sessionTimeout
    new_localytics.outstandingRequests = CreateObject("roAssociativeArray") ' Volatile Store for roUrlTransfer response
    new_localytics.customDimensions = new_localytics.loadCustomDimensions() 
    new_localytics.debug = debug 'Extra loggin on/off
    new_localytics.maxScreenFlowLength = 2500
    new_localytics.keys = ll_get_storage_keys()
    new_localytics.constants = ll_get_constants()
       
    if fresh then
        new_localytics.deleteSessionData(true)
    end if
    
    return new_localytics
End Function

'Initializes the session
Function ll_initialize()
    m.debugLog("ll_initialize()")
    m.restoreSession()
    
    if not m.hasSession() then
        m.openSession()
    else
        m.checkSessionTimeout(true)
    end if
End Function

' Opens a session on Localytics
Function ll_open_session()
    m.debugLog("ll_open_session()")
    m.session = CreateObject("roAssociativeArray")
    m.setSessionValue(m.keys.install_uuid, ll_read_registry(m.keys.install_uuid, ll_generate_guid()))
    m.setSessionValue(m.keys.session_uuid, ll_generate_guid(), false)
    m.setSessionValue(m.keys.session_index, ll_read_registry(m.keys.session_index, "0").ToInt() + 1, false)
    m.setSessionValue(m.keys.sequence_index, 0, false)
    
    for i=0 to 9
        cdKey = "c" + i.ToStr()
        m.setSessionValue(cdKey, ll_read_registry(cdKey), false)
    next

    ' Save session start time
    timestamp = ll_get_timestamp_generator()
    time = timestamp.asSeconds()
    m.setSessionValue(m.keys.session_open_time, time, false)
    m.setSessionValue(m.keys.session_action_time, time)
    
    m.persistSession()
            
    'Session Open
    event = CreateObject("roAssociativeArray")
    event.dt = "s"
    event.ct = time 'Open Time
    event.u = m.getSessionValue(m.keys.session_uuid)
    event.nth = m.getSessionValue(m.keys.session_index) 'Need to persist this value
    event.mc = "" '?? null is ok
    event.mm = "" '?? null is ok
    event.ms = "" '?? null is ok
    
    customerId = m.getSessionValue(m.keys.profile_customer_id)
    if ll_is_valid_string(customerId) then
        event.cid = customerId
        event.utp = "known"
    else
        event.cid = m.getSessionValue(m.keys.install_uuid)
        event.utp = "anonymous"
    end if
    
    m.send(event)
End Function

' Closes a session on Localytics
Function ll_close_session(isInit=false as Boolean)
    m.debugLog("ll_close_session()")
    
    lastActionTime = m.getSessionValue(m.keys.session_action_time)
    sessionTime = m.getSessionValue(m.keys.session_open_time)

    m.KeepSessionAlive("ll_close_session")
    
    ' Process previous session outstandings (auto-tags)
    if isInit then
        m.screenViewed("[External]", lastActionTime)
    else
        m.screenViewed("[Inactivity]", lastActionTime)
    end if
        
    m.sendPlayerMetrics()'Attempt to fire player metrics
            
    event = CreateObject("roAssociativeArray")
    event.dt = "c"
    event.u = ll_generate_guid()
    event.ss = sessionTime
    event.su = m.getSessionValue(m.keys.session_uuid)
    event.ct = lastActionTime ' TODO Double check these fields
    event.ctl = lastActionTime - sessionTime
    event.cta = lastActionTime - sessionTime 
    
    screenFlows = m.getSessionValue(m.keys.screen_flows)
    if ll_is_string(screenFlows) then
        event.fl = "[" + screenFlows +"]" 'Screen flows
    else
        event.fl = "[]"
    end if
        
    customerId = m.getSessionValue(m.keys.profile_customer_id)
    if ll_is_valid_string(customerId) then
        event.cid = customerId
        event.utp = "known"
    else
        event.cid = m.getSessionValue(m.keys.install_uuid)
        event.utp = "anonymous"
    end if

    m.send(event)
    
    m.deleteSessionData()
End Function

Function ll_delete_session_data(clearAllFields=false As Boolean, section="com.localytics" As String)
    sec = CreateObject("roRegistrySection", section)
    
    for each key in sec.GetKeyList()
        if clearAllFields or not m.isPersistedAcrossSession(key) then
            sec.Delete(key)
        end if
    next
    
    sec.Flush()
End Function

' Tags an event
Function ll_tag_event(name as String, attributes=invalid as Object, customerValueIncrease=0 as Integer)
    m.debugLog("ll_tag_event()")
    if m.HasSession() = false then
        return -1
    end if
    m.checkSessionTimeout()
    m.KeepSessionAlive("ll_tag_event")

    timestamp = ll_get_timestamp_generator()

    event = CreateObject("roAssociativeArray")
    event.dt = "e"
    event.ct = timestamp.asSeconds()
    event.u = ll_generate_guid()
    event.su = m.getSessionValue(m.keys.session_uuid)
    event.v = customerValueIncrease '??
    event.n = name 'Event name
    
    customerId = m.getSessionValue(m.keys.profile_customer_id)
    if ll_is_valid_string(customerId) then
        event.cid = customerId
        event.utp = "known"
    else
        event.cid = m.getSessionValue(m.keys.install_uuid)
        event.utp = "anonymous"
    end if
    
    event.attrs = attributes
    
    m.send(event)
End Function

Function ll_tag_screen(name as String)
    m.debugLog("ll_tag_screen()")
    m.checkSessionTimeout()
    m.KeepSessionAlive("ll_tag_screen")
    
    screenFlows = m.getSessionValue(m.keys.screen_flows)
    
    if not ll_is_string(screenFlows)
        screenFlows = Chr(34) + name + Chr(34)
        m.setSessionValue(m.keys.screen_flows, screenFlows)
    else if screenFlows.Len() < m.maxScreenFlowLength then
        screenFlows = screenFlows + "," + Chr(34) + name + Chr(34) 
        m.setSessionValue(m.keys.screen_flows, screenFlows)
    end if
    
    m.screenViewed(name) 'Auto-tag
    
    m.debugLog("Screen Flows: " + m.getSessionValue(m.keys.screen_flows))
End Function

Function ll_screen_viewed(currentScreen="" as String, lastActionTime=-1 as Integer)
    m.debugLog("ll_screen_viewed()")

    previousScreen = m.getSessionValue(m.keys.auto_previous_screen)
    previousScreenTime = m.getSessionValue(m.keys.auto_previous_screen_time)

    if lastActionTime > -1 then
        time = lastActionTime
    else
        timestamp = ll_get_timestamp_generator()
        time = timestamp.asSeconds()
    end if
    
    if  ll_is_valid_string(previousScreen) and ll_is_integer(previousScreenTime) then
        attributes = CreateObject("roAssociativeArray")
        if currentScreen = "" then
            currentScreen = m.constants.not_available
        end if
        timeOnScreen = time - previousScreenTime
        attributes[m.constants.current_screen] = currentScreen
        attributes[m.constants.previous_screen] = previousScreen
        attributes[m.constants.time_on_screen] = timeOnScreen
        
        m.debugLog("ll_screen_viewed(currentScreen: " + currentScreen + ", previousScreen: " + previousScreen + ", timeOnScreen: " + timeOnScreen.ToStr() + ")")
        
        m.TagEvent(m.constants.event_screen_viewed, attributes)
    end if
    
    m.setSessionValue(m.keys.auto_previous_screen, currentScreen, false)
    m.setSessionValue(m.keys.auto_previous_screen_time, time)
End Function

Function ll_set_custom_dimension(i as Integer, value as String)
    m.debugLog("ll_set_custom_dimension("+ i.toStr() + ", " + value + ")")
    if i>=0 and i < 10 and value <> invalid then
        cdKey = "c"+ i.ToStr()
        m.customDimensions[cdKey] = value
        ll_write_registry(cdKey, value, true)
    end if
End Function

Function ll_clear_custom_dimension(i as Integer)
    m.debugLog("ll_clear_custom_dimension("+ i.toStr() + ")")
    m.SetCustomDimension(i, "")
End Function


' Sets Content Metadata for auto-tagging. If "value" is empty, the key is deleted.
Function ll_set_content_metadata(key as String, value as Dynamic, required=false as Boolean, flush=true as Boolean)
    m.debugLog("ll_set_content_metadata("+ key + ", " + ll_to_string(value) + ")")
    
    if ll_is_string(key)
        strValue = ll_to_string(value)
        if ll_is_valid_string(strValue) then
            ll_write_registry(key, strValue, flush, m.constants.section_metadata)
        else if required then
            ll_write_registry(key, m.constants.not_available, flush, m.constants.section_metadata) ' Remove the attribute if value is invalid or empty
        else
            ll_delete_registry(key, m.constants.section_metadata, flush)
        end if
    end if
End Function

Function ll_set_content_length(value as Integer, flush=true as Boolean)
    m.debugLog("ll_set_content_length( Content Length: " + value.ToStr() + ")")
    
    if value > 0 then
        ll_write_registry(m.keys.auto_playback_length, value.ToStr(), flush, m.constants.section_playback)
    else
        ll_delete_registry(m.keys.auto_playback_length, m.constants.section_playback, flush)
    end if
End Function

Function ll_set_content_id(value="N/A" as Dynamic)
    m.setContentMetadata(m.constants.content_id, value, true, true)
End Function

Function ll_set_content_title(value="N/A" as Dynamic)
    m.setContentMetadata(m.constants.content_title, value, true, true)
End Function

Function ll_set_content_series_title(value="N/A" as Dynamic)
    m.setContentMetadata(m.constants.content_series_title, value, true, true)
End Function

Function ll_set_content_category(value="N/A" as Dynamic)
    m.setContentMetadata(m.constants.content_category, value, true, true)
End Function

Function ll_process_player_metrics(event as Object)
    m.debugLog("ll_process_player_metrics()")
    
    if type(event) = "roVideoScreenEvent" or type(event) = "roVideoPlayerEvent" then
        sectionName = m.constants.section_playback
        message = "Type: unexpected"
        
        pausedSession = m.getSessionValue(m.keys.auto_playback_paused_session)
        if not (event.isResumed() or (ll_is_boolean(pausedSession) and pausedSession = true)) then
            m.KeepSessionAlive("ll_process_player_metrics")
        end if
        
        if event.isRequestFailed()
            message = "Type: isRequestFailed, Index: " + event.GetIndex().ToStr() + ", Message: " + event.GetMessage()
            
            ll_write_registry(m.keys.auto_playback_pending, "true", false, sectionName)
            ll_write_registry(m.keys.auto_playback_url, event.GetInfo()["Url"], false, sectionName)
            ll_write_registry(m.keys.auto_playback_end_reason, m.constants.finish_reason_playback_error, true, sectionName)
        else if event.isPlaybackPosition() then
            message = "Type: isPlaybackPosition,  Index: " + event.GetIndex().ToStr()
            
            bufferStartTime = m.getSessionValue(m.keys.auto_playback_buffer_start)
            bufferTime = m.getSessionValue(m.keys.auto_playback_buffer)
            if ll_is_integer(bufferStartTime) and (not ll_is_integer(bufferTime)) then
                'Only set buffer time if it hasn't been set yet
                timestamp = ll_get_timestamp_generator()
                bufferTotal = timestamp.asSeconds() - bufferStartTime
                ll_write_registry(m.keys.auto_playback_buffer, bufferTotal.ToStr(), false, sectionName)
                m.setSessionValue(m.keys.auto_playback_buffer, bufferTotal, false, false)
            end if
            
            playbackPosition = event.GetIndex().ToStr()
            
            timeWatched = m.getSessionValue(m.keys.auto_playback_watched)
            if (not ll_is_integer(timeWatched)) or playbackPosition > timeWatched then 'Same as MAX(timeWatched, playbackPosition)
                m.setSessionValue(m.keys.auto_playback_watched, playbackPosition, false, false)
                ll_write_registry(m.keys.auto_playback_watched, playbackPosition, false, sectionName)
            end if
            
            ll_write_registry(m.keys.auto_playback_current_time, playbackPosition, true, sectionName)
        else if event.isStreamStarted()
            message = "Type: isStreamStarted,  Index: " + event.GetIndex().ToStr() + ", Url: " + event.GetInfo()["Url"]
            
            IsUnderrun = event.GetInfo()["IsUnderrun"]
            if IsUnderrun = false then
                timestamp = ll_get_timestamp_generator()
                m.setSessionValue(m.keys.auto_playback_buffer_start, timestamp.asSeconds(), false, false)
            end if
            
            ll_write_registry(m.keys.auto_playback_pending, "true", false, sectionName)
            ll_write_registry(m.keys.auto_playback_url, event.GetInfo()["Url"], true, sectionName)
        else if event.isFullResult()
            message = "Type: isFullResult"
            
            ll_write_registry(m.keys.auto_playback_end_reason, m.constants.finish_reason_playback_ended, true, sectionName)
        else if event.isPartialResult()
            message = "Type: isPartialResult"
            
            ll_write_registry(m.keys.auto_playback_end_reason, m.constants.finish_reason_user_exited, true, sectionName)
        else if event.isPaused()
            message = "Type: isPaused"
            m.setSessionValue(m.keys.auto_playback_paused_session, true, false, false)
        else if event.isResumed()
            message = "Type: isResumed"
            m.setSessionValue(m.keys.auto_playback_paused_session, false, false, false)
        else if event.isScreenClosed()
            message = "Type: isScreenClosed"
                      
            ' Clear temporary values
            m.setSessionValue(m.keys.auto_playback_buffer, "", false, false)
            m.setSessionValue(m.keys.auto_playback_buffer_start, "", false, false)
            m.setSessionValue(m.keys.auto_playback_watched, "", false, false)
            m.setSessionValue(m.keys.auto_playback_paused_session, "", false, false)
            'Attempt to fire player metrics
            m.sendPlayerMetrics()

'        else if event.isStreamSegmentInfo()
'            m.debugLog("ll_process_player_metrics(Type: isStreamSegmentInfo, Index: " + event.GetIndex().ToStr() + ", SegUrl: " + event.GetInfo()["SegUrl"] + ")")
'        else if event.isStatusMessage()
'            m.debugLog("ll_process_player_metrics(Type: isStatusMessage, Message: " + event.GetMessage() + ")")
'        else
'            m.debugLog("ll_process_player_metrics(Type: unexpected type)")
        end if
        m.debugLog("ll_process_player_metrics(" + message + ")")
    end if
End Function

Function ll_send_player_metrics()
    m.debugLog("ll_send_player_metrics()")

    playback_section = m.constants.section_playback

    if ll_read_registry(m.keys.auto_playback_pending, "false", playback_section) = "true" then
        attributes = CreateObject("roAssociativeArray")
        
        ' Required metadata fields
        attributes[m.constants.content_id] = m.constants.not_available
        attributes[m.constants.content_title] = m.constants.not_available
        attributes[m.constants.content_series_title] = m.constants.not_available
        attributes[m.constants.content_category] = m.constants.not_available
        
        ' Process metadata
        metadata_section= CreateObject("roRegistrySection", m.constants.section_metadata)
        for each key in metadata_section.GetKeyList()
            attributes[key] = metadata_section.Read(key)
        end for
        
        ' Fill Playback Data
        contentUrl = ll_read_registry(m.keys.auto_playback_url, m.constants.not_available, playback_section)
        attributes[m.constants.content_url] = contentUrl
        
        endReason = ll_read_registry(m.keys.auto_playback_end_reason, m.constants.finish_reason_unknown, playback_section)
        attributes[m.constants.content_did_reach_end] = ll_to_string(endReason = m.constants.finish_reason_playback_ended)
        attributes[m.constants.end_reason] = endReason
        
        bufferTime = ll_read_registry(m.keys.auto_playback_buffer, m.constants.not_available, playback_section)
        attributes[m.constants.content_time_to_buffer_seconds] = bufferTime
        
        playbackTime = ll_read_registry(m.keys.auto_playback_current_time, m.constants.not_available, playback_section)
        attributes[m.constants.content_timestamp] = playbackTime
        
        contentLength = ll_read_registry(m.keys.auto_playback_length, m.constants.not_available, playback_section)
        attributes[m.constants.content_length] = contentLength
        
        timeWatched = ll_read_registry(m.keys.auto_playback_watched, m.constants.not_available, playback_section)
        attributes[m.constants.content_played_seconds] = timeWatched
        
        percentComplete = m.constants.not_available
        if contentLength.ToInt() > 0 then
            if endReason = m.constants.finish_reason_playback_ended then
                percentComplete = 100
            else
                percentComplete = Int((timeWatched.ToInt()/contentLength.ToInt())*100)
            end if
        end if
        attributes[m.constants.content_played_percent] = percentComplete
        
        for each key in attributes ' clean up as string fields
            attributes[key] = ll_json_escape_string(attributes[key])
        end for 
        
        m.TagEvent(m.constants.event_video_watched, attributes, timeWatched.ToInt())
        
        ' Cleanup
        ll_clear_registry(true,m.constants.section_metadata)
        ll_clear_registry(true,m.constants.section_playback)
    end if
End Function


Function ll_keep_session_alive(source="external" As String)
    m.debugLog("ll_keep_session_alive(Source: " + source + ")")
    
    timestamp = ll_get_timestamp_generator()
    m.setSessionValue(m.keys.session_action_time, timestamp.asSeconds())
    m.processOutStandingRequest()
End Function

Function ll_check_session_timeout(isInit=false as Boolean)
    currentTime = ll_get_timestamp_generator().asSeconds()
    lastActionTime = m.getSessionValue(m.keys.session_action_time)
    diff = currentTime-lastActionTime
    
    m.debugLog("ll_check_session_timeout("+ m.sessionTimeout.toStr() +"): Inactive for " + diff.toStr())
    
    if isInit then
        if m.sessionTimeout = 0 or diff > m.sessionTimeout then
            m.closeSession(isInit)
            m.openSession()
        else
            m.screenViewed("[External]", lastActionTime)
        end if
    else if (m.sessionTimeout > 0 and diff > m.sessionTimeout)then
       m.closeSession(isInit)
       m.openSession()
    end if
End Function

Function ll_process_outstanding_request()
    m.debugLog("ll_process_outstanding_request()")
    
    for each key in m.outstandingRequests
        http = m.outstandingRequests[key]
        if type(http) = "roUrlTransfer" then
            port = http.GetPort()
            if type(port) = "roMessagePort" then
                event = port.GetMessage()
                if type(event) = "roUrlEvent"
                    m.outstandingRequests.Delete(key)
                    m.debugLog("process_done: " + event.GetString())
                else
                    m.debugLog("process_not_done: " + key)
                end if
            end if
        end if
    next
End Function

Function ll_persist_session()
    ' any extra persistence to registry setSessionValue automatically call write registry
    m.debugLog("ll_persist_session()")
End Function

Function ll_restore_session() As Boolean
    m.debugLog("ll_restore_session()")
    oldSession = CreateObject("roAssociativeArray")
    oldSession[m.keys.session_uuid] = ll_read_registry(m.keys.session_uuid)
    
    if oldSession[m.keys.session_uuid] = "" then
        return false
    end if
    
    oldSession[m.keys.install_uuid] = ll_read_registry(m.keys.install_uuid, ll_generate_guid())
    oldSession[m.keys.session_index] = ll_read_registry(m.keys.session_index).ToInt()
    oldSession[m.keys.sequence_index] = ll_read_registry(m.keys.sequence_index).ToInt()
    oldSession[m.keys.session_open_time] = ll_read_registry(m.keys.session_open_time).ToInt() 
    oldSession[m.keys.session_action_time] = ll_read_registry(m.keys.session_action_time).ToInt()  
    oldSession[m.keys.screen_flows] = ll_read_registry(m.keys.screen_flows)
    oldSession[m.keys.profile_customer_id] = ll_read_registry(m.keys.profile_customer_id)

    ' auto-tag metrics
    oldSession[m.keys.auto_previous_screen] = ll_read_registry(m.keys.auto_previous_screen)
    oldSession[m.keys.auto_previous_screen_time] = ll_read_registry(m.keys.auto_previous_screen_time).ToInt()
    
    for i=0 to 9
        cdKey = "c" + i.ToStr()
        oldSession[cdKey] = ll_read_registry(cdKey)
    next
    
    m.session = oldSession
       
    return true
End Function

Function ll_load_custom_dimensions() As Object
    m.debugLog("ll_load_custom_dimensions()")
    oldCustomDimensions = CreateObject("roAssociativeArray")
    
    for i=0 to 9
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
    header.attrs.au = m.appKey
    header.attrs.iu = m.getSessionValue(m.keys.install_uuid)
    
    di = CreateObject("roDeviceInfo")
    ai = CreateObject("roAppInfo")
    
    header.attrs.dp = "Roku"
    header.attrs.du = ll_hash(di.GetDeviceUniqueId()) 'hashed device uuid
    header.attrs.dov = di.GetVersion() 'device version
    header.attrs.dmo = di.GetModel() 'device model
    
    header.attrs.lv = m.libraryVersion
    header.attrs.dma = "Roku"
    header.attrs.dll = di.GetCurrentLocale().Left(2)
    header.attrs.dlc = di.GetCountryCode()
    header.attrs.av = ai.GetVersion()

    header.ids = CreateObject("roAssociativeArray")
    return header
End Function

' Wrapper function - adds the required header data to each call
Function ll_send(event As Object)
    for i=0 to 9
        cdKey = "c" + i.ToStr()
        value = m.customDimensions[cdKey]
        if value <> invalid and value <> "" then
            event[cdKey] = value
        end if
    next
    
    timestamp = ll_get_timestamp_generator()
    
    seq = m.getSessionValue(m.keys.sequence_index)
    header = m.getHeader(seq)
    m.setSessionValue(m.keys.sequence_index, seq+1)
    
    baseUrl = m.endpoint
    appKey = m.appKey
    path = "/uploads/image.gif?client_date=" + timestamp.asSeconds().ToStr()
    callback = "&callback=z"
    data = "&data="

    ' Need to escape parameters
    urlTransfer = CreateObject("roUrlTransfer")
    params = urlTransfer.Escape(ll_set_params_as_string(header)) + "%0A" + urlTransfer.Escape(ll_set_params_as_string(event))

    request = baseUrl + appKey + path + callback + data + params
    m.debugLog("ll_send(): " + urlTransfer.Unescape(request))
    m.upload(request)
End Function

Function ll_upload(url As String)
    http = CreateObject("roUrlTransfer")
    
    if m.secured then
        http.SetCertificatesFile("common:/certs/ca-bundle.crt")
        http.InitClientCertificates()
    end if
    
    http.SetPort(CreateObject("roMessagePort"))
    http.SetUrl(url)
    http.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    http.EnableEncodings(true)
    
    if (http.AsyncGetToString())
        m.outstandingRequests[url] = http
    endif
End Function


'************************************************************
' Customer Profile Functions
'************************************************************
Function ll_set_customer_id(customerId="" As String)
    m.debugLog("ll_set_customer_id()")

    m.setSessionValue(m.keys.profile_customer_id, customerId)
End Function

Function ll_set_customer_email(customerEmail As String)
    m.debugLog("ll_set_customer_email()")

    m.SetProfileAttribute("org", m.keys.profile_customer_email, customerEmail)
End Function

Function ll_set_customer_full_name(fullName As String)
    m.debugLog("ll_set_customer_full_name()")

    m.SetProfileAttribute("org", m.keys.profile_customer_full_name, fullName)
End Function

Function ll_set_customer_first_name(firstName As String)
    m.debugLog("ll_set_customer_first_name()")

    m.SetProfileAttribute("org", m.keys.profile_customer_first_name, firstName)
End Function

Function ll_set_customer_last_name(lastName As String)
    m.debugLog("ll_set_customer_last_name()")

    m.SetProfileAttribute("org", m.keys.profile_customer_last_name, lastName)
End Function

Function ll_set_profile_attribute(scope as String, key As String, value=invalid As Dynamic)
    if key.Len() > 0 then
        attribute = CreateObject("roAssociativeArray")
        attribute[key] = value
        m.patchProfile(scope, attribute)
    end if
End Function

Function ll_patch_profile(scope as String, attributes=invalid As Object)
    customerId = m.getSessionValue(m.keys.profile_customer_id)
    installId = ll_read_registry(m.keys.install_uuid, ll_generate_guid())

    if attributes = invalid or attributes.IsEmpty() or (not ll_is_valid_string(customerId)) then return -1
    
    endpoint = m.profileEndpoint + m.appKey + "/profiles/" + customerId
    
    http = CreateObject("roUrlTransfer")
    
    if m.secured then
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
    
    m.debugLog("ll_patch_profile(url:" +endpoint+ ", body: " +body+ ")")
    
    if (http.AsyncPostFromString(body))
        m.outstandingRequests[endpoint+body] = http
    endif
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

Function ll_is_persisted_across_session(storageKey) As Boolean    
    return storageKey = m.keys.install_uuid or storageKey = m.keys.session_index or ll_is_custom_dimensions_key(storageKey)
End Function

Function ll_is_custom_dimensions_key(storageKey) As Boolean
    for i=0 to 9
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
    return m.session <> invalid
End Function

' Manages the current instance's variables, ie. appKey, sessionStartTime, clientId ...
Function ll_get_session_value(param As String) As Dynamic
    if m.HasSession() AND param <> invalid then
        return m["session"][param]
    end if
    
    return ""
End Function
Function ll_set_session_value(param As String, value As Dynamic, flush=false As Boolean, persist=true As Boolean)
    if m.HasSession() AND param <> invalid AND value <> invalid then
        m["session"][param] = value
        
        if persist then
            ll_write_registry(param, ll_to_string(value), flush)
        end if
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

Function ll_json_escape_string(variable As Dynamic) As Dynamic
    if ll_is_string(variable) then
        return variable.Replace(Chr(34), "\" + Chr(34))
    else
        return variable
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

Function ll_debug_log(line as String)
    if m.debug = true
        print "<ll_debug> " + line 
    end if
End Function