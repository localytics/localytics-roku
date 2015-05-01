'**********************************************************
'**  Video Player Example Application - Video Playback 
'**  November 2009
'**  Copyright (c) 2009 Roku Inc. All Rights Reserved.
'**********************************************************

'***********************************************************
'** Create and show the video screen.  The video screen is
'** a special full screen video playback component.  It 
'** handles most of the keypresses automatically and our
'** job is primarily to make sure it has the correct data 
'** at startup. We will receive event back on progress and
'** error conditions so it's important to monitor these to
'** understand what's going on, especially in the case of errors
'***********************************************************  
Function showVideoScreen(episode As Object)

    if type(episode) <> "roAssociativeArray" then
        print "invalid data passed to showVideoScreen"
        return -1
    endif

    port = CreateObject("roMessagePort")
    screen = CreateObject("roVideoScreen")
    screen.SetMessagePort(port)

    screen.Show()
    
    ' Important to set this interval to a reasonable number. The accuracy of the playback metrics is dependent
    ' on how often Localytics is updated with playback progress.
    screen.SetPositionNotificationPeriod(1)
    
    screen.SetContent(episode)
    
    ' Set Content Metadata here
    m.LL.SetContentMetadata("Video Title", episode.Title)
    ' Pass in the content length to allow proper calculation of some metrics. Use the key provided by SDK
    m.LL.SetContentMetadata(m.LL.MetadataKey.length_seconds, episode.Length)
    
    screen.Show()
    
    m.LL.TagScreen("video")

    'Uncomment his line to dump the contents of the episode to be played
    'PrintAA(episode)

    while true
        msg = wait(0, port)

        if type(msg) = "roVideoScreenEvent" then
            'Hook in Localytics to receive player events here
            m.LL.ProcessPlayerMetrics(msg)
            'print "showHomeScreen | msg = "; msg.getMessage() " | index = "; msg.GetIndex()
            
            if msg.isRequestFailed()
                print "Video request failure: "; msg.GetIndex(); " " msg.GetData() 
            else if msg.isStatusMessage()
                print "Video status: "; msg.GetIndex(); " " msg.GetData() 
            else if msg.isButtonPressed()
                print "Button pressed: "; msg.GetIndex(); " " msg.GetData()
            else if msg.isPlaybackPosition() then
                print "Playback position: "; msg.GetIndex()
                nowpos = msg.GetIndex()
                RegWrite(episode.ContentId, nowpos.toStr())
            else 
                print "Unexpected event type: "; msg.GetType()
            end if
            
            if msg.isScreenClosed() then
                print "Screen closed"
                exit while
            end if
        else
            print "Unexpected message class: "; type(msg)
        end if
    end while

End Function

