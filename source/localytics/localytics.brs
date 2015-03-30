' Creates a new Localytics instance
' Note: 
' - "fresh" will clear previous stored values
' - "debug" will log some messages
Function LL_Create(appKey As String, sessionTimeout=0 As Integer, fresh=false As Boolean, debug=false As Boolean) As Object

    localytics = CreateObject("roAssociativeArray")
    
    ' Function for External Calls
    localytics.Init = ll_initialize
    localytics.SetCustomDimension = ll_set_custom_dimension
    localytics.TagEvent = ll_tag_event
    localytics.TagScreen = ll_tag_screen
    localytics.KeepSessionAlive = ll_keep_session_alive
    
    ' Shouldn't be call externally
    localytics.openSession = ll_open_session
    localytics.closeSession = ll_close_session
    localytics.deleteSessionData = ll_delete_session_data
    localytics.restoreSession = ll_restore_session
    localytics.persistSession = ll_persist_session
    localytics.loadCustomDimensions = ll_load_custom_dimensions
    localytics.processOutStandingRequest = ll_process_outstanding_request
    localytics.hasSession = ll_has_session
    localytics.send = ll_send
    localytics.getHeader = ll_get_header
    localytics.getSessionValue = ll_get_session_value
    localytics.setSessionValue = ll_set_session_value
    localytics.debugLog = ll_debug_log
    localytics.upload = ll_upload
    localytics.isPersistedAcrossSession = ll_is_persisted_across_session
    
    ' Fields Creation
    localytics.endpoint = "http://webanalytics.localytics.com/api/v2/applications/"
    localytics.appKey = appKey
    localytics.sessionTimeout = sessionTimeout
    localytics.outstandingRequests = CreateObject("roAssociativeArray") ' Volatile Store for roUrlTransfer response
    localytics.customDimensions = localytics.loadCustomDimensions() 
    localytics.debug = debug 'Extra loggin on/off
    localytics.keys = ll_get_storage_keys()
    
    if fresh then
        localytics.deleteSessionData(true)
    end if
    
    return localytics
End Function

'Initializes the session
Function ll_initialize()
    m.debugLog("ll_initialize()")
    m.restoreSession()
    
    currentTime = ll_get_timestamp_generator().asSeconds()
    lastActionTime = m.getSessionValue(m.keys.session_action_time)
    
    if not m.hasSession() then
        m.openSession()
    else if currentTime-lastActionTime > m.sessionTimeout
        m.debugLog("Session Timed Out")
        m.closeSession()
        m.openSession()
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
    
    'TODO Identity Stuff
    event.cid = m.getSessionValue(m.keys.install_uuid)
    event.utp = "anonymous"
    
    m.send(event)
End Function

' Closes a session on Localytics
Function ll_close_session()
    m.debugLog("ll_close_session()")
    
    lastActionTime = m.getSessionValue(m.keys.session_action_time)
    sessionTime = m.getSessionValue(m.keys.session_open_time)

    event = CreateObject("roAssociativeArray")
    event.dt = "c"
    event.u = ll_generate_guid()
    event.ss = sessionTime
    event.su = m.getSessionValue(m.keys.session_uuid)
    event.ct = lastActionTime ' TODO Double check these fields
    event.ctl = lastActionTime - sessionTime
    event.cta = lastActionTime - sessionTime 
    event.fl = "[" + m.getSessionValue(m.keys.screen_flows) +"]" 'Screen flows
    
    'TODO Identity Stuff
    event.cid = m.getSessionValue(m.keys.install_uuid)
    event.utp = "anonymous"

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
    
    m.KeepSessionAlive() 

    timestamp = ll_get_timestamp_generator()

    event = CreateObject("roAssociativeArray")
    event.dt = "e"
    event.ct = timestamp.asSeconds()
    event.u = ll_generate_guid()
    event.su = m.getSessionValue(m.keys.session_uuid)
    event.v = customerValueIncrease '??
    event.n = name 'Event name
    
    'TODO Identity Stuff
    event.cid = m.getSessionValue(m.keys.install_uuid)
    event.utp = "anonymous"
    
    event.attrs = attributes
    
    m.send(event)
End Function

Function ll_tag_screen(name as String)
    m.debugLog("ll_tag_screen()")
    m.KeepSessionAlive()
    
    screenFlows = m.getSessionValue(m.keys.screen_flows)
    
    if type(screenFlows) <> "roString" and type(screenFlows) <> "String"
        screenFlows = Chr(34) + name + Chr(34)
    else
        screenFlows = screenFlows + "," + Chr(34) + name + Chr(34) 
    end if
    
    m.setSessionValue(m.keys.screen_flows, screenFlows)
    
    m.debugLog("Screen Flows: " + m.getSessionValue(m.keys.screen_flows))
End Function

Function ll_set_custom_dimension(i as Integer, value as String)
    m.debugLog("ll_set_custom_dimension("+ i.toStr() + ", " + value + ")")
    if i>=0 and i < 10 and value <> invalid then
        cdKey = "c"+ i.ToStr()
        m.customDimensions[cdKey] = value
        ll_write_registry(cdKey, value, true)
    end if
End Function

Function ll_keep_session_alive()
    m.debugLog("ll_keep_session_alive()")
    
    timestamp = ll_get_timestamp_generator()
    m.setSessionValue(m.keys.session_action_time, timestamp.asSeconds())
    m.processOutStandingRequest()
End Function

Function ll_process_outstanding_request()
    m.debugLog("ll_process_outstanding_request()")
    
    for each key in m.outstandingRequests
        http = m.outstandingRequests[key]
        if type(http) = "roUrlTransfer" then
            port = http.GetMessagePort()
            if type(port) = "roMessagePort" then
                event = port.GetMessage()
                if type(event) = "roUrlEvent"
                    m.outstandingRequests.Delete(key)
                    m.debugLog("process_done: " + event.GetString())
                else
                    m.debugLog("not_done: " + key)
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
    header.attrs.dp = "Roku" 'device uuid
    header.attrs.du = ll_hash(di.GetDeviceUniqueId()) 'hashed device uuid
    header.attrs.dov = di.GetVersion() 'device version
    header.attrs.dmo = di.GetModel() 'device model
    
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
    http.SetPort(CreateObject("roMessagePort"))
    http.SetUrl(url)
    http.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    http.EnableEncodings(true)
    
    if (http.AsyncGetToString())
        m.outstandingRequests[url] = http
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
    keys.device_birth_time = "pa" 'page laod time (not relevant
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
    
    return keys
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

' Writes "value" to "key" of registry "section". "flush" = true will skip calling Flush, ideal for multiple writes
Function ll_write_registry(key As String, value As String, flush=true As Boolean, section="com.localytics" As String)
    sec = CreateObject("roRegistrySection", section)
    sec.Write(key, value)
    
    if flush then
        sec.Flush()
    end if
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
Function ll_set_session_value(param As String, value As Dynamic, flush=false As Boolean)
    if m.HasSession() AND param <> invalid AND value <> invalid then
        m["session"][param] = value
        ll_write_registry(param, ll_to_string(value), flush)
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
        else if type(params[key]) = "roInteger" OR type(params[key]) = "Integer" then
            result = result + Chr(34) + key + Chr(34) + ":" + (params[key]).ToStr() + ","
        else
            if params[key] = invalid or params[key] = "" then
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
    if type(variable) = "roInt" or type(variable) = "roInteger" or type(variable) = "Integer"
        return variable.ToStr()
    else if type(variable) = "roFloat" or type(variable) = "Float" then
        return Str(variable).Trim()
    else if type(variable) = "roBoolean" or type(variable) = "Boolean" then
        if variable = true then
            return "True"
        end if
        return "False"
    else if type(variable) = "roString" or type(variable) = "String" then
        return variable
    else if type(variable) = "roArray"
        return FormatJson(variable)
    else
        return type(variable)
    end if
End Function

Function ll_debug_log(line as String)
    if m.debug = true
        print "<ll_debug> " + line 
    end if
End Function