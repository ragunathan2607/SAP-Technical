*&---------------------------------------------------------------------*
*& Report ZMOC_MEETING_INVITE_NOTIF
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zmoc_meeting_invite_notif.

*&------------------------------------------------------------------------*
*& Module              : EHSM -MOC                                        *
*& Object ID           : CRQ87378                                         *
*& Package             : ZMOC                                             *
*& Technical           : Pavan S                                          *
*& Functional Analyst  : Ragunathan(thirucrx)                             *
*& Created date        : 28.September.2026                                *
*& Description         : MOC Meeting invite notification          )       *
*& Transport Request No: DVJK943233                                       *
*&------------------------------------------------------------------------*
*& Modification History (Include changes after production transport)      *
*&------------------------------------------------------------------------*
*& Request    |   Date     | Developer    |    Description
*&------------------------------------------------------------------------*
*&            |            |              |
*&------------------------------------------------------------------------*

*--------------------------------------------------------------------*
* SELECTION SCREEN
*--------------------------------------------------------------------*
TABLES : usr02.
DATA : lwf_smtpadr TYPE ad_smtpadr.
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: gp_org   TYPE ad_smtpadr DEFAULT 'organizer@yourdomain.com' OBLIGATORY,
**              gp_to    TYPE ad_smtpadr DEFAULT 'attendee@theirdomain.com' OBLIGATORY,
              gp_subj  TYPE so_obj_des DEFAULT 'Project Kickoff Meeting' OBLIGATORY,
              gp_loc   TYPE string     DEFAULT 'Microsoft Teams',
              gp_sdat  TYPE sy-datum   DEFAULT sy-datum OBLIGATORY,
              gp_stim  TYPE sy-uzeit   OBLIGATORY,
              gp_edat  TYPE sy-datum   DEFAULT sy-datum OBLIGATORY,
              gp_etim  TYPE sy-uzeit   OBLIGATORY,
              gp_tzone TYPE tznzone    DEFAULT sy-zonlo OBLIGATORY.
  SELECT-OPTIONS : gs_mail FOR lwf_smtpadr NO INTERVALS.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS: gp_desc TYPE string DEFAULT 'Please review the agenda before the call.'.
  " Select Options (gs_)
  SELECT-OPTIONS: gs_users FOR usr02-bname.

  " Routing Radiobuttons
  PARAMETERS: gp_outl RADIOBUTTON GROUP dest USER-COMMAND uc1 DEFAULT 'X',
              gp_sapi RADIOBUTTON GROUP dest,
              gp_both RADIOBUTTON GROUP dest.
SELECTION-SCREEN END OF BLOCK b2.


DATA : gwf_sub  TYPE sc_txtshor,
       gwl_to_t TYPE zehsm_ad_smtpadr_t.
*--------------------------------------------------------------------*
* INITIALIZATION
*--------------------------------------------------------------------*
INITIALIZATION.
  gp_stim = sy-uzeit.
  CALL FUNCTION 'CATT_ADD_TO_TIME'
    EXPORTING
      idate = sy-datum
      itime = sy-uzeit
      stdaz = 1
    IMPORTING
      edate = gp_edat
      etime = gp_etim.

*--------------------------------------------------------------------*
* START-OF-SELECTION
*--------------------------------------------------------------------*
START-OF-SELECTION.
**  lcl_meeting_manager=>execute_scheduling( ).
  DATA(lwf_meet_notif) = NEW zcl_ehsm_meeting_invite_notif( ).

  LOOP AT gs_mail INTO DATA(lwc_mail).
    APPEND lwc_mail-low TO gwl_to_t.
  ENDLOOP.
  " 1. Route to External Exchange (Outlook)
  IF gp_outl = 'X' OR gp_both = 'X'.
**    send_outlook_invite( ).
    lwf_meet_notif->send_invite_to_outlook(
      EXPORTING
        i_organizer   = gp_org                " E-Mail Address
        i_to_t        = gwl_to_t                " E-Mail Address
        i_sub         = gp_subj                " Short description of contents
        i_location    = gp_loc                 " Location
        i_date        = gp_sdat                " ABAP system field: Current date of application server
        i_start_time  = gp_stim                " ABAP System Field: Current Time of Application Server
        i_end_time    = gp_etim                " ABAP System Field: Current Time of Application Server
        i_tzone       = gp_tzone                " Time Zone (class always uses Saudi time UTC+3)
        i_description = gp_desc                " Description
      IMPORTING
        e_status      = DATA(lwf_status_mail)                 " Single-Character Flag
        e_message     = DATA(lwf_msg_mail)                    " Message
    ).
    MESSAGE lwf_msg_mail TYPE 'S' DISPLAY LIKE lwf_status_mail.

  ENDIF.
  " 2. Route to Internal SAP Calendar (SBWP)
  IF gp_sapi = 'X' OR gp_both = 'X'.
    gwf_sub = gp_subj.

    lwf_meet_notif->send_invite_to_wf_inbox(
      EXPORTING
        i_title              = gwf_sub                 " Short text
        i_meeting_date       = gp_sdat
        i_meeting_start_time = gp_stim
        i_meeting_end_time   = gp_etim
        i_location           = gp_loc
        i_users              = gs_users[]                 " Users table type
        i_description        = gp_desc
      IMPORTING
        e_status             = DATA(lwf_status)                " Single-Character Flag
        e_message            = DATA(lwf_msg)                 " Message
    ).
    MESSAGE lwf_msg TYPE lwf_status.

  ENDIF.
