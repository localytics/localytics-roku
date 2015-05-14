'********************************************************************
'**  Video Player Example Application - Main
'**  November 2009
'**  Copyright (c) 2009 Roku Inc. All Rights Reserved.
'********************************************************************

Sub Main()

    'initialize theme attributes like titles, logos and overhang color
    initTheme()
    
    'initialize Localytics
    initLocalytics()

    'prepare the screen for display and get ready to begin
    screen=preShowHomeScreen("", "")
    if screen=invalid then
        print "unexpected error in preShowHomeScreen"
        return
    end if

    'set to go, time to get started
    showHomeScreen(screen)
End Sub


'*************************************************************
'** Set the configurable theme attributes for the application
'** 
'** Configure the custom overhang and Logo attributes
'** Theme attributes affect the branding of the application
'** and are artwork, colors and offsets specific to the app
'*************************************************************

Sub initTheme()

    app = CreateObject("roAppManager")
    theme = CreateObject("roAssociativeArray")

    theme.OverhangOffsetSD_X = "72"
    theme.OverhangOffsetSD_Y = "31"
    theme.OverhangSliceSD = "pkg:/images/Overhang_Background_SD.png"
    theme.OverhangLogoSD  = "pkg:/images/Overhang_Logo_SD.png"

    theme.OverhangOffsetHD_X = "125"
    theme.OverhangOffsetHD_Y = "35"
    theme.OverhangSliceHD = "pkg:/images/Overhang_Background_HD.png"
    theme.OverhangLogoHD  = "pkg:/images/Overhang_Logo_HD.png"

    app.SetTheme(theme)

End Sub

' initialize Localytics
Function initLocalytics() As Void
    ' Create new Localytics instance on globalAA
    m.Localytics = Localytics("5fc02c21045a8b8a0fa396d-53c62af6-c9af-11e4-aecd-009c5fda0a25", 1800, false, true) ' Use Your AppKey here
    
    m.Localytics.SetCustomDimension(0, "testCD0")
    m.Localytics.SetCustomDimension(3, "testCD3")
    m.Localytics.SetCustomDimension(5, "testCD5")
    m.Localytics.SetCustomDimension(9, "testCD9")
    
    m.Localytics.AutoIntegrate()

    'Set Customer Identifiers
    m.Localytics.SetCustomerId("test_customer_1")
    
    'Set profile attributes
    m.Localytics.SetCustomerEmail("customer@email.com")
    m.Localytics.SetCustomerFirstName("First")
    m.Localytics.SetCustomerLastName("Last")
    
    'Clear profile attributes
    m.Localytics.SetCustomerFullName("")
    
    ' Tag Event
    m.Localytics.TagEvent("sample-TagEvent-init")
End Function


