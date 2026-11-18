# SAP Outlook Invite using ABAP

Sends an Outlook meeting invite from SAP (EHSM MOC, package `ZMOC`) as an email with an
`invite.ics` calendar attachment, using BCS (`CL_BCS`).

## Objects

| File | Object | Purpose |
|---|---|---|
| `ZCL_EHSM_MEETING_INVITE_NOTIF.abap` | Class `ZCL_EHSM_MEETING_INVITE_NOTIF` | Builds the iCalendar (`.ics`) and sends the mail; also sends the SAP My Inbox (SBWP) appointment |
| `ZMOC_MEETING_INVITE_NOTIF.abap` | Report `ZMOC_MEETING_INVITE_NOTIF` | Selection screen to send the invite to Outlook, SAP My Inbox or both |

## How it works

1. `CONVERT_TO_ZULU` converts the entered date/time to UTC (`YYYYMMDDTHHMMSSZ`).
2. `SEND_INVITE_TO_OUTLOOK` builds an RFC 5545 `VCALENDAR` with `METHOD:REQUEST`
   (organizer, attendees, start/end, location, summary, description).
3. The mail body is HTML: meeting details plus guidelines on how to add the invite to the calendar.
4. The calendar is attached as `invite.ics` (attachment type `ICS`, UTF-8, CRLF line endings).
5. Sender = organizer, recipients = attendees, sent immediately via SAPconnect.

## Issues fixed

| Problem | Cause | Fix |
|---|---|---|
| Attachment `Content-Class_urn_content-classes_calendarmessage_....809_X` could not be opened | Document type `CAL` (not a valid SAP type) and MIME headers passed in `i_header`, which BCS uses as document attributes, not mail headers | HTML body + `ICS` attachment with `&SO_FILENAME=invite.ics` |
| `DTSTART: 202T610251Z` (invalid date) | Wrong timestamp-to-text conversion | `CONVERT DATE ... INTO TIME STAMP` + `CONVERT TIME STAMP ... TIME ZONE 'UTC'` |
| `DTSTAMP` = meeting start time | Used start time instead of creation time | `GET TIME STAMP` (current UTC) |
| Meeting scheduled 2 hours late (2-3 PM became 4-5 PM) | Users' SU01 time zone is `CET` (Europe/Berlin); `sy-zonlo` was used for conversion | Class always uses site time zone `UTC+3` (Saudi Arabia, Jubail; no daylight saving) |
| Special characters breaking the invite | No escaping of `\ ; ,` and line breaks | RFC 5545 escaping for summary, description, location |
| Error handling | `MESSAGE ... TYPE 'E'` inside the class | Errors returned in `E_STATUS` / `E_MESSAGE` |

## Behaviour in Outlook

- The invite arrives as an email with `invite.ics`. Outlook shows **Add to calendar**
  (or opens a calendar item on double-click). The email body explains the steps for
  classic Outlook, new Outlook / Outlook on the web, and the Outlook mobile app.
- Accept / Decline responses are not sent back to the organizer with this approach.
  BCS cannot send the calendar as the mail body itself (`text/calendar`), which Outlook
  needs to show a native meeting request.
- When the organizer is also an attendee, Outlook never shows Accept / Decline for them.
- `MICROSOFT TEAMS` is location text only; no Teams link is created.

## Prerequisites

- The organizer address must be a real mailbox that SAPconnect may send as.
- If the attachment arrives as `application/octet-stream`, maintain the MIME mapping
  `ics` -> `text/calendar` (Basis to confirm where it is maintained in your release).
- Recommended: set SU01 time zone of site users to `Asia/Riyadh`.

## Installation

1. SE24: class `ZCL_EHSM_MEETING_INVITE_NOTIF` (package `ZMOC`) - switch to source-code based mode,
   paste `ZCL_EHSM_MEETING_INVITE_NOTIF.abap`, activate.
2. SE38: report `ZMOC_MEETING_INVITE_NOTIF` - paste `ZMOC_MEETING_INVITE_NOTIF.abap`, activate.
3. Required DDIC objects: table types `ZEHSM_AD_SMTPADR_T` (e-mail addresses) and `ZMOC_USERS_TT` (users).

## Testing

1. Run `ZMOC_MEETING_INVITE_NOTIF` (or create an event from the app) with a colleague as attendee.
2. SOST: the attachment shows as `invite.ics`.
3. Outlook: entered time (e.g. 14:00-15:00) shows as 2-3 PM Saudi time; `.ics` contains `T110000Z`-`T120000Z`.
