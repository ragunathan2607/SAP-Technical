class ZCL_EHSM_MEETING_INVITE_NOTIF definition
  public
  final
  create public .

public section.

  methods SEND_INVITE_TO_WF_INBOX
    importing
      !I_TITLE type SC_TXTSHOR
      !I_MEETING_DATE type SY-DATUM
      !I_MEETING_START_TIME type SY-UZEIT
      !I_MEETING_END_TIME type SY-UZEIT
      !I_LOCATION type STRING optional
      !I_USERS type ZMOC_USERS_TT
      !I_DESCRIPTION type STRING optional
    exporting
      !E_STATUS type CHAR1
      !E_MESSAGE type STRING .
  methods SEND_INVITE_TO_OUTLOOK
    importing
      !I_ORGANIZER type AD_SMTPADR
      !I_TO_T type ZEHSM_AD_SMTPADR_T
      !I_SUB type SO_OBJ_DES
      !I_LOCATION type STRING default 'MICROSOFT TEAMS'
      !I_DATE type SYST-DATUM
      !I_START_TIME type SYST-UZEIT
      !I_END_TIME type SYST-UZEIT
      !I_TZONE type TZNZONE
      !I_DESCRIPTION type STRING optional
    exporting
      !E_STATUS type CHAR1
      !E_MESSAGE type STRING .

protected section.

private section.

  methods CONVERT_TO_ZULU
    importing
      !I_DATE type SY-DATUM
      !I_TIME type SY-UZEIT
      !I_TZONE type TZNZONE
    returning
      value(R_ZULU) type STRING .
ENDCLASS.

CLASS zcl_ehsm_meeting_invite_notif IMPLEMENTATION.

  METHOD send_invite_to_wf_inbox.
    " Local Variables (lwf_), Work Areas (lwc_), and Internal Tables (lwl_)
    DATA: lwf_appointment TYPE REF TO cl_appointment,
          lwc_participant TYPE scspart,
          lwl_text        TYPE TABLE OF soli,
          lwc_text        TYPE soli,
          lwl_users       TYPE TABLE OF xubname,
          lwf_user        TYPE xubname.

    " 1. Create Appointment Object
    CREATE OBJECT lwf_appointment.

    " 2. Set Meeting Title, Location, and Type
    lwf_appointment->set_title( i_title ).
    lwf_appointment->set_location_string( i_location ).
    lwf_appointment->set_type( 'MEETING' ).

    " 3. Set Date and Time
    lwf_appointment->set_date(
      EXPORTING
        date_from = i_meeting_date
        time_from = i_meeting_start_time
        date_to   = i_meeting_date
        time_to   = i_meeting_end_time
    ).

    " 4. Set Meeting Description/Body
    lwc_text-line = 'Hello team,'.
    APPEND lwc_text TO lwl_text.
    lwc_text-line = ''.
    APPEND lwc_text TO lwl_text.
    lwc_text-line = i_description.
    APPEND lwc_text TO lwl_text.

    lwf_appointment->set_text( lwl_text ).

    " 5. Add Participants
    " A. Add Sender (Organizer)
    CLEAR lwc_participant.
    lwc_participant-participan = sy-uname.
    lwc_participant-send_mail  = 'X'.
    lwf_appointment->add_participant( participant = lwc_participant ).

    " B. Add Receivers (Multiple Users)
    IF i_users[] IS NOT INITIAL.
      SELECT bname FROM usr02
        INTO TABLE lwl_users
        WHERE bname IN i_users.

      IF sy-subrc = 0.
        LOOP AT lwl_users INTO lwf_user.
          CLEAR lwc_participant.
          lwc_participant-participan = lwf_user.
          lwc_participant-send_mail  = 'X'.
          lwf_appointment->add_participant( participant = lwc_participant ).
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF sy-subrc = 0 AND lwl_users IS NOT INITIAL.
      " 6. Save and Send the Appointment
      lwf_appointment->save(
        EXPORTING
          send_invitation = 'X'
        EXCEPTIONS
          OTHERS = 1
      ).
      COMMIT WORK AND WAIT.
      " 7. Handle the Result
      e_status = 'S'.
      e_message = 'Meeting invites sent successfully to SBWP!'.
    ELSE.
      e_status = 'E'.
      e_message = 'Error occurred while sending meeting invites.'.
**    MESSAGE 'Error occurred while sending meeting invites.' TYPE 'E'.
    ENDIF.

  ENDMETHOD.

METHOD send_invite_to_outlook.
  DATA: lo_send_request TYPE REF TO cl_bcs,
        lo_document     TYPE REF TO cl_document_bcs,
        lwl_hex_payload TYPE solix_tab,
        lwf_ics_string  TYPE string,
        lwf_size        TYPE so_obj_len,
        lwf_crlf        TYPE string,
        lwf_uuid        TYPE string,
        lwf_attende_str TYPE string,
        lwf_start_utc   TYPE string,
        lwf_end_utc     TYPE string,
        lwf_stamp_utc   TYPE string,
        lwf_now         TYPE timestamp,
        lwf_d           TYPE d,
        lwf_t           TYPE t,
        lwf_summary     TYPE string,
        lwf_descr       TYPE string,
        lwf_loc         TYPE string,
        lwf_html        TYPE string,
        lwl_html_soli   TYPE soli_tab.
  lwf_crlf = cl_abap_char_utilities=>cr_lf.
  CONSTANTS gc_site_tzone TYPE tznzone VALUE 'UTC+3'.

  TRY.
      lwf_uuid = cl_system_uuid=>create_uuid_c32_static( ).
    CATCH cx_uuid_error.
      GET TIME STAMP FIELD lwf_now.
      lwf_uuid = |{ lwf_now }{ sy-uname }|.
  ENDTRY.

  " 1. Dates in UTC (YYYYMMDDTHHMMSSZ)
  lwf_start_utc = convert_to_zulu( i_date = i_date i_time = i_start_time i_tzone = gc_site_tzone ).
  lwf_end_utc   = convert_to_zulu( i_date = i_date i_time = i_end_time   i_tzone = gc_site_tzone ).
  GET TIME STAMP FIELD lwf_now.
  CONVERT TIME STAMP lwf_now TIME ZONE 'UTC' INTO DATE lwf_d TIME lwf_t.
  lwf_stamp_utc = |{ lwf_d }T{ lwf_t }Z|.

  " 2. Escape free text (RFC 5545: \ ; , and line breaks)
  lwf_summary = i_sub.
  lwf_descr   = i_description.
  lwf_loc     = i_location.
  REPLACE ALL OCCURRENCES OF `\` IN lwf_summary WITH `\\`.
  REPLACE ALL OCCURRENCES OF `;` IN lwf_summary WITH `\;`.
  REPLACE ALL OCCURRENCES OF `,` IN lwf_summary WITH `\,`.
  REPLACE ALL OCCURRENCES OF `\` IN lwf_descr   WITH `\\`.
  REPLACE ALL OCCURRENCES OF `;` IN lwf_descr   WITH `\;`.
  REPLACE ALL OCCURRENCES OF `,` IN lwf_descr   WITH `\,`.
  REPLACE ALL OCCURRENCES OF lwf_crlf IN lwf_descr WITH `\n`.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lwf_descr WITH `\n`.
  REPLACE ALL OCCURRENCES OF `,` IN lwf_loc     WITH `\,`.
  REPLACE ALL OCCURRENCES OF `;` IN lwf_loc     WITH `\;`.

  LOOP AT i_to_t INTO DATA(lwc_email_addres).
    lwf_attende_str = lwf_attende_str &&
      |ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:{ lwc_email_addres }{ lwf_crlf }|.
  ENDLOOP.

  " 3. Build ICS
  lwf_ics_string = |BEGIN:VCALENDAR{ lwf_crlf }| &&
                   |PRODID:-//SAP ABAP//EHSM MOC//EN{ lwf_crlf }| &&
                   |VERSION:2.0{ lwf_crlf }| &&
                   |METHOD:REQUEST{ lwf_crlf }| &&
                   |BEGIN:VEVENT{ lwf_crlf }| &&
                   |UID:{ lwf_uuid }@sap.com{ lwf_crlf }| &&
                   |SEQUENCE:0{ lwf_crlf }| &&
                   |STATUS:CONFIRMED{ lwf_crlf }| &&
                   |ORGANIZER:mailto:{ i_organizer }{ lwf_crlf }| &&
                   lwf_attende_str &&
                   |DTSTAMP:{ lwf_stamp_utc }{ lwf_crlf }| &&
                   |DTSTART:{ lwf_start_utc }{ lwf_crlf }| &&
                   |DTEND:{ lwf_end_utc }{ lwf_crlf }| &&
                   |LOCATION:{ lwf_loc }{ lwf_crlf }| &&
                   |SUMMARY:{ lwf_summary }{ lwf_crlf }| &&
                   |DESCRIPTION:{ lwf_descr }{ lwf_crlf }| &&
                   |PRIORITY:5{ lwf_crlf }| &&
                   |CLASS:PUBLIC{ lwf_crlf }| &&
                   |TRANSP:OPAQUE{ lwf_crlf }| &&
                   |END:VEVENT{ lwf_crlf }| &&
                   |END:VCALENDAR{ lwf_crlf }|.

  TRY.
      cl_bcs_convert=>string_to_solix(
        EXPORTING iv_string   = lwf_ics_string
                  iv_codepage = '4110'
                  iv_add_bom  = space
        IMPORTING et_solix    = lwl_hex_payload
                  ev_size     = lwf_size ).

      lo_send_request = cl_bcs=>create_persistent( ).

      " 4. Body = plain text, calendar = .ics part (type ICS -> text/calendar)
*      lo_document = cl_document_bcs=>create_document(
*        i_type    = 'RAW'
*        i_subject = i_sub
*        i_text    = VALUE soli_tab( ( line = |Meeting: { i_sub }| )
*                                    ( line = |Location: { i_location }| ) ) ).
      " 4. HTML body: meeting details + guidelines to add the invite to the calendar
      lwf_html =
        `<div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#222;">` &&
        `<p>Dear Participant,</p>` &&
        `<p>You are invited to the following meeting.</p>` &&
        `<table cellpadding="5" style="border-collapse:collapse;">` &&
        `<tr><td style="padding-right:15px;"><strong>Meeting:</strong></td><td>` &&
           escape( val = CONV string( i_sub ) format = cl_abap_format=>e_html_text ) && `</td></tr>` &&
        `<tr><td style="padding-right:15px;"><strong>Date:</strong></td><td>` &&
           |{ i_date DATE = USER }| && `</td></tr>` &&
        `<tr><td style="padding-right:15px;"><strong>Time:</strong></td><td>` &&
           |{ i_start_time TIME = USER } - { i_end_time TIME = USER } (Saudi Arabia time, UTC+3)| && `</td></tr>` &&
        `<tr><td style="padding-right:15px;"><strong>Location:</strong></td><td>` &&
           escape( val = CONV string( i_location ) format = cl_abap_format=>e_html_text ) && `</td></tr>` &&
        `<tr><td style="padding-right:15px;vertical-align:top;"><strong>Remarks:</strong></td><td>` &&
           escape( val = CONV string( i_description ) format = cl_abap_format=>e_html_text ) && `</td></tr>` &&
        `</table>` &&

        `<p style="margin-top:20px;"><strong>How to add this meeting to your calendar</strong></p>` &&
        `<p>The meeting is attached to this email as <strong>invite.ics</strong>. ` &&
        `It is not added to your calendar automatically. Please add it using one of the options below:</p>` &&

        `<p><strong>Outlook desktop (classic Outlook)</strong></p>` &&
        `<ol>` &&
        `<li>Double-click the attachment <strong>invite.ics</strong> in this email.</li>` &&
        `<li>The meeting opens as a calendar item.</li>` &&
        `<li>Click <strong>Save &amp; Close</strong>. The meeting is now in your calendar.</li>` &&
        `</ol>` &&

        `<p><strong>New Outlook / Outlook on the web</strong></p>` &&
        `<ol>` &&
        `<li>Click <strong>Add to calendar</strong> shown on the invite.ics attachment ` &&
        `(or at the top of this email).</li>` &&
        `<li>Check the date and time, then click <strong>Save</strong>.</li>` &&
        `</ol>` &&

        `<p><strong>Outlook mobile app</strong></p>` &&
        `<ol>` &&
        `<li>Tap the attachment <strong>invite.ics</strong>.</li>` &&
        `<li>Tap <strong>Add to calendar</strong>.</li>` &&
        `</ol>` &&

        `<p><strong>Please note:</strong></p>` &&
        `<ul>` &&
        `<li>The meeting time is converted to your own time zone automatically.</li>` &&
        `<li>Accept / Decline responses are not sent from this invite. ` &&
        `If you cannot attend, please inform the organizer: <a href="mailto:` && i_organizer && `">` &&
           i_organizer && `</a>.</li>` &&
        `<li>If the meeting is changed, a new invite will be sent. ` &&
        `Please delete the old entry from your calendar and add the new one.</li>` &&
        `</ul>` &&

        `<p><strong>This is a system generated email. Please do not reply.</strong></p>` &&
        `</div>`.

      lwl_html_soli = cl_bcs_convert=>string_to_soli( lwf_html ).

      lo_document = cl_document_bcs=>create_document(
        i_type    = 'HTM'
        i_subject = i_sub
        i_text    = lwl_html_soli ).

      lo_document->add_attachment(
        i_attachment_type    = 'ICS'
        i_attachment_subject = 'invite'
        i_attachment_size    = lwf_size
        i_att_content_hex    = lwl_hex_payload
        i_attachment_header  = VALUE soli_tab( ( line = '&SO_FILENAME=invite.ics' ) ) ).

      lo_send_request->set_document( lo_document ).

      " Sender MUST be the same address as ORGANIZER
      lo_send_request->set_sender( cl_cam_address_bcs=>create_internet_address( i_organizer ) ).

      LOOP AT i_to_t INTO DATA(lwc_email_address).
        lo_send_request->add_recipient(
          i_recipient = cl_cam_address_bcs=>create_internet_address( lwc_email_address )
          i_express   = 'X' ).
      ENDLOOP.

      lo_send_request->set_send_immediately( abap_true ).

      IF lo_send_request->send( ) = abap_true.
        COMMIT WORK.
        e_status  = 'S'.
        e_message = 'Meeting request sent'.
      ELSE.
        e_status  = 'E'.
        e_message = 'Failed to send meeting request'.
      ENDIF.

    CATCH cx_bcs INTO DATA(lx_bcs).
      e_status  = 'E'.
      e_message = lx_bcs->get_text( ).
  ENDTRY.
ENDMETHOD.

  METHOD convert_to_zulu.
  DATA: lwf_ts TYPE timestamp,
        lwf_d  TYPE d,
        lwf_t  TYPE t.

  CONVERT DATE i_date TIME i_time INTO TIME STAMP lwf_ts TIME ZONE i_tzone.
  CONVERT TIME STAMP lwf_ts TIME ZONE 'UTC' INTO DATE lwf_d TIME lwf_t.
  r_zulu = |{ lwf_d }T{ lwf_t }Z|.          " e.g. 20261025T090725Z
ENDMETHOD.

ENDCLASS.
