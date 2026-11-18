# Activity template Excel upload – ZMOC_R_ACT_TEMPL_UPLOAD

| File | Content |
| --- | --- |
| `ZMOC_R_ACT_TEMPL_UPLOAD.abap` | Executable report (one source, local classes, no further objects needed) |
| `ZMOC_ACT_TEMPLATE_UPLOAD_TEST.xlsx` | Excel template with README sheet, column descriptions and MoC test data |

## Status

* First run in the source system (S/4HANA 758): reading, checks and database update of the test workbook
  worked (93 table keys, 13 long texts); the transport recording ended in dump `CALL_FUNCTION_CONFLICT_TAB_TYP`
  (no data was committed).
* Fixed in this version: the transport tables use the CTS table types `TR_OBJECTS` / `TR_KEYS`
  (method `RECORD_TRANSPORT`). The fixed version still has to be tested end to end.

## Installation

1. SE38 → create program `ZMOC_R_ACT_TEMPL_UPLOAD`, type *Executable program*, title
   *Upload of activity templates from Excel*, package e.g. `ZMOC`.
2. Paste the source, activate. Selection texts are set in the program (no text elements needed).
3. Optional: create a transaction (SE93) and a variant with *Test run* switched on.

Requirements: SAP_BASIS 7.40 SP08 or higher (syntax checked with abaplint for 7.40 SP08, 7.50 and 7.57),
Issue and Activity Management `/IAM/` (EHS Management of Change or QIM), class `CL_FDT_XL_SPREADSHEET`.
The user needs the view-maintenance authorization (`S_TABU_DIS` / `S_TABU_NAM`) for the
`/IAM/` views and a modifiable customizing request.

## Test with the delivered workbook

1. Run the report with *Test run* = X, *Default application* = `MOC`, file = `ZMOC_ACT_TEMPLATE_UPLOAD_TEST.xlsx`.
   The log lists every planned entry (green), warnings (yellow) and errors (red).
2. Run again without *Test run*, choose or enter a customizing request.
3. Check in SPRO / SM30 `/IAM/V_ACTIVTYP` (MoC: activity template view cluster) and in SE09 (request content).
4. Run the same file a second time: nothing must be planned (no green *New entry* lines) – the upload is
   idempotent, also for the automatically numbered codes.

Expected result of the test data (approximate – depends on what already exists in the client):

| Table | New entries |
| --- | --- |
| `/IAM/C_ACTIVTYP` | 13 templates `ZUPL_*` (task, sub-task, approval, notification, questionnaire, question catalog, 7 questions) |
| `/IAM/C_ACTIVTYPT` | 18 descriptions (13 EN, 5 DE) |
| SAPscript `IAMACTTMPL` / `ST` | 13 long texts (11 EN, 2 DE) |
| `/IAM/C_ACT_ACT` | 12 assignments (3 levels) |
| `/IAM/C_ACT_CDGR` | 3 code groups assigned (text type `ARESP`) |
| `/IAM/C_CODEGR(_T)` | 3 code groups, 5 texts |
| `/IAM/C_CODE(_T)` | 8 codes (4 with generated IDs `ZUPL_AREA_001..004`), 12 texts; `YES` / `NO` reused |
| `/IAM/C_CODE_REL` / `/IAM/C_CATCODREL` | 10 / 8 relations |
| `/IAM/C_ACT_REFOB` | 1 reference object type |

Rows starting with `*` in REFOBJECTS, FOAPARAMS, DIGSIG and PARTNERS are examples; remove the `*` to upload them.

## Behaviour

* **Modes** – default: create only; *Update existing entries*: change existing entries (only the columns present
  in the worksheet); *Replace assignments*: delete sub-templates / code groups / … of the uploaded templates that
  are not in the worksheet. Internal numbers (`INT_NUMBER`) are assigned automatically.
* **Checks** taken over from `/IAM/SAPLVIEWS`: key syntax (msg 001, 050–052), recursion of sub-templates (019),
  unique sort number (013), MoC description mandatory (150), inactive activity type (/IAM/OBJECT 241), response type
  rules of `LCL_V_ACTIVTYP`, code group without response type C (135), check tables, code-group authority.
* **Long text** – key from `/IAM/CL_LONGTEXT=>CREATE_LONGTEXT_KEY_ISS_ACT`, text converted with
  `CONVERT_STREAM_TO_ITF_TEXT`, `LONGTEXT_IND` maintained. `#DELETE#` deletes, empty keeps.
  MoC copies the long text into the activity only if the activity category has a text schema (`/IAM/C_ACT_CAT`).
* **Transport** – all customizing entries (also deletions) as `R3TR TABU` with keys, long texts as `R3TR TEXT`,
  recorded with `TR_APPEND_TO_COMM_OBJS_KEYS` in the request/task of the selection screen or of the popup
  (`TR_ORDER_CHOICE_CORRECTION`, category CUST). Database update and recording are one LUW: if recording fails,
  everything is rolled back. Default partners (`/IAM/D_ACTPTY_MD`) are master data and are not transported.
* **All or nothing** – a single error prevents posting.
