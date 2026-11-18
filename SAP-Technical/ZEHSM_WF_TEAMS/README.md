# ZEHSM_WF_TEAMS – SAP workflow approvals in Microsoft Teams

OData V2 service `ZEHSM_WF_TEAMS_SRV` (S/4HANA 2022) that lets **Power Automate** create **Teams approvals**
from the pending work items in a user's SAP inbox, and post the Teams decision back to SAP to complete the work item.

## Flow

1. Power Automate → `GET WorkItemSet?$filter=UserId eq '..'` (or `Email eq '..'`) → new pending dialog work items
2. Power Automate creates the Teams approval → `POST SentAckSet` (item is marked as sent and not returned again)
3. Approver decides in Teams → Power Automate → `POST DecisionSet` → work item is completed in the approver's name and the workflow continues

The service behaves the same way as My Inbox:
* Decision options are the step's own options (`/IWWRK/CL_WF_READ_WORKITEM`, `SAP_WAPI_DECISION_READ`).
* The "comment mandatory" flag and nature come from SPRO *Maintain Task Names and Decision Options* (`/IWWRK/C_WFDEC`).
* The comment is saved as a work item comment attachment, then `SAP_WAPI_DECISION_COMPLETE` runs with `USER` = approver.

## Objects

| File / folder | Object | Purpose |
|---|---|---|
| `ZCL_EHSM_WF_TEAMS_API.abap` | Class `ZCL_EHSM_WF_TEAMS_API` | All the logic: user from ID or e-mail (USR21/ADR6), worklist, description, objects, comments, decision options, sent flag, decision execution, SLG1 log |
| `ZCL_ZEHSM_WF_TEAMS_DPC_EXT.abap` | Class `ZCL_ZEHSM_WF_TEAMS_DPC_EXT` | OData methods (SEGW-generated DPC extension) |
| `abapgit/` | abapGit offline repo | Structures `ZEHSM_S_WF_ITEM/_DECOPT/_OBJECT/_COMMENT/_DECISION/_ACK`, table `ZEHSM_WF_TEAMS`, message class `ZEHSM_WF_TEAMS`, class `ZCL_EHSM_WF_TEAMS_API` |

## Entities

| Entity set | Keys | Use |
|---|---|---|
| `WorkItemSet` | WiId | Pending items. Filters: `UserId` or `Email`, optional `IncludeSent` |
| `DecOptionSet` | WiId, DecisionKey | Decision options (nav `ToDecOptions`) |
| `ObjectSet` | WiId, SourceWiId, Catid, Typeid, Instid | Linked business objects (nav `ToObjects`) |
| `CommentSet` | WiId, DocId | Existing comments (nav `ToComments`) |
| `DecisionSet` (POST) | WiId | WiId, UserId/Email, DecisionKey, CommentText |
| `SentAckSet` (POST) | WiId | WiId, UserId/Email |

Main WorkItem fields:
* Work item no., task no. (TS…), workflow no. and template (WS…), title, description
* Status, priority, created date/time, deadline, created by, forwarded by
* Leading object, `DecisionSupported`, `AlreadySent`

## Installation

1. Create a sub-package (e.g. `ZEHSM_TEAMS` under `ZEHSM`).
   Do **not** link the abapGit repo to a package with other objects: abapGit would offer to delete them.
2. Zip the contents of `abapgit/` (`.abapgit.xml` + `src/`).
   In `ZABAPGIT`: **New Offline** → package `ZEHSM_TEAMS` → **Import zip** → **Pull**.
3. SLG0: log object `ZEHSM`, sub-object `WF_TEAMS`.
4. SEGW project `ZEHSM_WF_TEAMS` (package `ZEHSM_TEAMS`):
   * Import DDIC structures as entities `WorkItem`, `DecOption`, `Object`, `Comment`, `Decision`, `SentAck`, with default entity sets `<Entity>Set` and the keys from the table above.
   * Tick **Nullable** for `WiCd`, `WiLed` (WorkItem) and `CreatDate` (Comment).
   * Associations WorkItem 1 : 0..n, `WiId = WiId`, with navigation `ToDecOptions`, `ToObjects`, `ToComments`.
   * Generate with the default names (`ZCL_ZEHSM_WF_TEAMS_MPC/_DPC(_EXT)`, `ZEHSM_WF_TEAMS_SRV`).
5. Paste `ZCL_ZEHSM_WF_TEAMS_DPC_EXT.abap` into the DPC_EXT class and activate.
6. `/IWFND/MAINT_SERVICE` → Add Service, system alias `LOCAL`.
7. Test system only: SICF node `/sap/opu/odata/sap/zehsm_wf_teams_srv` → GUI Configuration → `~CHECK_CSRF_TOKEN = 0`.

## Message class ZEHSM_WF_TEAMS

001 user not found · 002 no user for e-mail · 003 e-mail used by more than one user · 004 UserId or Email missing ·
005 item not open in user's inbox · 006 not decidable from Teams · 007 invalid decision · 008 comment mandatory ·
009 comment not saved · 010 decision failed · 011 decision done · 012 marked as sent · 013 work item not found

## Test (/IWFND/GW_CLIENT, protocol HTTP)

Base: `/sap/opu/odata/sap/ZEHSM_WF_TEAMS_SRV`. For POST: headers `Content-Type` and `Accept` = `application/json`, JSON in the request body.

| # | Request | Expected |
|---|---|---|
| T1 | `GET /WorkItemSet?$filter=UserId eq 'APPROVER1'&$format=json` | Open dialog items (same as SBWP) |
| T2 | `GET /WorkItemSet?$filter=Email eq 'approver1@company.com'&$format=json` | Same as T1 |
| T3 | `GET /WorkItemSet?$filter=UserId eq 'APPROVER1'&$expand=ToDecOptions,ToObjects,ToComments&$format=json` | Options, objects, comments |
| T4 | `POST /SentAckSet` `{"WiId":"000000123456","UserId":"APPROVER1"}` | 201; `ZEHSM_WF_TEAMS` status S; item no longer in T1 |
| T5 | `GET /WorkItemSet?$filter=UserId eq 'APPROVER1' and IncludeSent eq true&$format=json` | Item back with `AlreadySent = true` |
| T6 | `GET /WorkItemSet('000000123456')/ToDecOptions?$format=json` | Decision keys of the item |
| T7 | `POST /DecisionSet` `{"WiId":"000000123456","UserId":"APPROVER1","DecisionKey":"0001","CommentText":"Approved from Teams"}` | 201; work item completed (SWIA), actual agent = approver, comment in My Inbox, table status D |
| T8 | Error cases: no filter, missing mandatory comment, wrong key, item already decided | 400 with messages 004 / 008 / 007 / 005, entries in SLG1 `ZEHSM` |

## Power Automate (outline)

1. Recurrence → HTTP GET `WorkItemSet` with `$expand=ToDecOptions`.
2. For each item with `DecisionSupported = true` → HTTP POST `SentAckSet`.
3. *Start and wait for an approval* with **Custom responses** = `DecisionText` values; details = `Description`, `TopWiId`, `WiId`, `LeadInstid`.
4. Map the chosen response back to `DecisionKey` → HTTP POST `DecisionSet` with the responder e-mail and comments.

## Notes / issues found during test

| Issue | Fix |
|---|---|
| abapGit: "HRNR / PDWS not supported" | Only a warning about existing objects in the package. Use a separate sub-package |
| Activation error "IV_WI_ID is not type-compatible with IV_V1" | Message parameters typed `CLIKE` (`CSEQUENCE` does not accept NUMC) |
| Gateway Client 403 "CSRF token validation failed" | JSON belongs in the request body, not the URI. Test system: `~CHECK_CSRF_TOKEN = 0` on the SICF node |
| SSL handshake failed, `SSSLERR_PEER_CERT_EXPIRED` | Expired server certificate (Basis, STRUST). Use HTTP; restart the Gateway Client with `/n` |

## Limits

* Only user-decision steps can be decided from Teams (`DecisionSupported`). Other tasks are returned so Teams can link to SAP.
* With several agents: once one decides, the others get message 005. Close their Teams cards in Power Automate.
* Production: remove the CSRF parameter, renew the SSL certificate, and give the technical user workflow authorization (S_WF_WI) to execute for other users.
