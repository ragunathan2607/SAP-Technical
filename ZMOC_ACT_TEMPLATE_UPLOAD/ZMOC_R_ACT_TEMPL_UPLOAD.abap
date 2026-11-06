*&---------------------------------------------------------------------*
*& Report ZMOC_R_ACT_TEMPL_UPLOAD
*&---------------------------------------------------------------------*
*& Excel upload of IAM activity templates (EHS Management of Change,
*& QIM and other IAM applications)
*&
*& One Excel workbook (.xlsx) creates / changes
*&  - activity templates with all attributes      /IAM/C_ACTIVTYP
*&  - description and long text in all languages  /IAM/C_ACTIVTYPT and
*&                                                SAPscript text
*&                                                IAMACTTMPL / ST
*&  - activity templates assigned below activity   /IAM/C_ACT_ACT
*&    templates (sub-activity templates)
*&  - code groups of the templates (responses)     /IAM/C_ACT_CDGR
*&  - catalogs, code groups and codes, created     /IAM/C_CATALOG(_T)
*&    automatically from the workbook              /IAM/C_CODEGR(_T)
*&                                                 /IAM/C_CODE(_T)
*&                                                 /IAM/C_CATCODREL
*&                                                 /IAM/C_CODE_REL
*&  - reference object types                       /IAM/C_ACT_REFOB
*&  - parameters of the follow-up action           /IAM/C_ACT_PARA
*&  - digital signature                            /IAM/C_ACT_DS
*&  - default partners (master data, used by QIM)  /IAM/D_ACTPTY_MD
*&
*& All customizing changes are recorded in a customizing transport
*& request: R3TR TABU with the table keys (also for deletions) and
*& R3TR TEXT for the long texts (as /IAM/CL_LONGTEXT->TRANSPORT).
*&
*& Worksheets (all optional): CODES, TEMPLATES, TEXTS, HIERARCHY,
*& CODEGROUPS, REFOBJECTS, FOAPARAMS, DIGSIG, PARTNERS
*&  Row 1  : technical column names (column order is free)
*&  Row 2ff: data. Rows with '*' in column A are comments.
*&
*& The checks are taken over from the view maintenance of function
*& group /IAM/VIEWS (program /IAM/SAPLVIEWS, views /IAM/V_ACTIVTYP,
*& /IAM/V_ACT_ACT, /IAM/V_ACT_CDGR, ... and the MoC view variants
*& /IAM/VV_*_MOC) - see comments "SAPLVIEWS".
*& Nothing is posted as long as one error exists (all or nothing).
*&---------------------------------------------------------------------*
REPORT zmoc_r_act_templ_upload.

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
TYPES:
  ty_sheet TYPE c LENGTH 20,
  tt_int   TYPE STANDARD TABLE OF i WITH EMPTY KEY,

  " raw worksheet content
  BEGIN OF ty_cell,
    field TYPE string,
    value TYPE string,
  END OF ty_cell,
  tt_cell TYPE SORTED TABLE OF ty_cell WITH UNIQUE KEY field,
  BEGIN OF ty_xrow,
    row   TYPE i,
    cells TYPE tt_cell,
  END OF ty_xrow,
  tt_xrow TYPE STANDARD TABLE OF ty_xrow WITH EMPTY KEY,
  BEGIN OF ty_xsheet,
    name   TYPE ty_sheet,
    fields TYPE string_table,
    rows   TYPE tt_xrow,
  END OF ty_xsheet,
  tt_xsheet TYPE SORTED TABLE OF ty_xsheet WITH UNIQUE KEY name,

  " message log
  BEGIN OF ty_log,
    light  TYPE c LENGTH 1,
    msgty  TYPE symsgty,
    sheet  TYPE ty_sheet,
    row    TYPE i,
    object TYPE c LENGTH 80,
    text   TYPE c LENGTH 220,
  END OF ty_log,
  tt_log TYPE STANDARD TABLE OF ty_log WITH EMPTY KEY,

  " planned database changes
  BEGIN OF ty_plan,
    tabname TYPE tabname,
    action  TYPE c LENGTH 1,          " I insert, U update, D delete, - none
    sheet   TYPE ty_sheet,
    row     TYPE i,
    object  TYPE string,
    data    TYPE REF TO data,
  END OF ty_plan,
  tt_plan TYPE STANDARD TABLE OF ty_plan WITH EMPTY KEY,
  BEGIN OF ty_ltplan,
    action TYPE c LENGTH 1,           " S save, D delete
    sheet  TYPE ty_sheet,
    row    TYPE i,
    header TYPE thead,
    lines  TYPE tline_tab,
  END OF ty_ltplan,
  tt_ltplan TYPE STANDARD TABLE OF ty_ltplan WITH EMPTY KEY,

  " ---- worksheet CODES: catalog / code group / code
  BEGIN OF ty_s_code,
    x_row          TYPE i,
    x_error        TYPE abap_bool,
    application    TYPE /iam/c_catalog-application,
    cata           TYPE /iam/c_catalog-cata,
    cata_text      TYPE /iam/c_catalog_t-cata_text,
    codegroup      TYPE /iam/c_codegr-codegroup,
    codegroup_text TYPE /iam/c_codegr_t-codegroup_text,
    auth_group     TYPE /iam/c_codegr-auth_group,
    code           TYPE /iam/c_code-code,
    code_text      TYPE /iam/c_code_t-code_text,
    langu          TYPE /iam/c_code_t-langu,
    code_cmnt_mand TYPE /iam/c_code_rel-code_cmnt_mand,
    inactive       TYPE /iam/c_code_rel-inactive,
  END OF ty_s_code,
  tt_s_code TYPE STANDARD TABLE OF ty_s_code WITH EMPTY KEY,

  " ---- worksheet TEMPLATES: activity template
  BEGIN OF ty_s_tmpl,
    x_row            TYPE i,
    x_error          TYPE abap_bool,
    x_action         TYPE c LENGTH 1,   " I new, U changed, N unchanged, S skipped
    application      TYPE /iam/c_activtyp-application,
    activity_type    TYPE /iam/c_activtyp-activity_type,
    langu            TYPE /iam/c_activtypt-langu,
    description      TYPE /iam/c_activtypt-description,
    acttype          TYPE /iam/c_activtyp-acttype,
    auth_group       TYPE /iam/c_activtyp-auth_group,
    code             TYPE /iam/c_activtyp-code,
    duration         TYPE /iam/c_activtyp-duration,
    duration_unit    TYPE /iam/c_activtyp-duration_unit,
    response_type    TYPE /iam/c_activtyp-response_type,
    response_unit    TYPE /iam/c_activtyp-response_unit,
    act_long_term    TYPE /iam/c_activtyp-act_long_term,
    act_mandatory    TYPE /iam/c_activtyp-act_mandatory,
    auto_rule_execut TYPE /iam/c_activtyp-auto_rule_execut,
    act_follow_up    TYPE /iam/c_activtyp-act_follow_up,
    follow_up_mode   TYPE /iam/c_activtyp-follow_up_mode,
    inactive         TYPE /iam/c_activtyp-inactive,
    cmnt_mandatory   TYPE /iam/c_activtyp-cmnt_mandatory,
    longtext         TYPE string,
  END OF ty_s_tmpl,
  tt_s_tmpl TYPE STANDARD TABLE OF ty_s_tmpl WITH EMPTY KEY,

  " ---- worksheet TEXTS: description / long text in further languages
  BEGIN OF ty_s_text,
    x_row         TYPE i,
    x_error       TYPE abap_bool,
    application   TYPE /iam/c_activtypt-application,
    activity_type TYPE /iam/c_activtypt-activity_type,
    langu         TYPE /iam/c_activtypt-langu,
    description   TYPE /iam/c_activtypt-description,
    longtext      TYPE string,
  END OF ty_s_text,
  tt_s_text TYPE STANDARD TABLE OF ty_s_text WITH EMPTY KEY,

  " ---- worksheet HIERARCHY: sub-activity templates
  BEGIN OF ty_s_hier,
    x_row           TYPE i,
    x_error         TYPE abap_bool,
    application     TYPE /iam/c_act_act-application,
    activity_type   TYPE /iam/c_act_act-activity_type,
    sub_act_type    TYPE /iam/c_act_act-sub_act_type,
    sort_no         TYPE /iam/c_act_act-sort_no,
    proposal_ind    TYPE /iam/c_act_act-proposal_ind,
    cont_incomplete TYPE /iam/c_act_act-cont_incomplete,
    obligatory      TYPE /iam/c_act_act-obligatory,
    inactive        TYPE /iam/c_act_act-inactive,
  END OF ty_s_hier,
  tt_s_hier TYPE STANDARD TABLE OF ty_s_hier WITH EMPTY KEY,

  " ---- worksheet CODEGROUPS: code groups of the template
  BEGIN OF ty_s_cdgr,
    x_row          TYPE i,
    x_error        TYPE abap_bool,
    application    TYPE /iam/c_act_cdgr-application,
    activity_type  TYPE /iam/c_act_cdgr-activity_type,
    text_type_code TYPE /iam/c_act_cdgr-text_type_code,
    codegroup      TYPE /iam/c_act_cdgr-codegroup,
    code           TYPE /iam/c_act_cdgr-code,
    inactive       TYPE /iam/c_act_cdgr-inactive,
  END OF ty_s_cdgr,
  tt_s_cdgr TYPE STANDARD TABLE OF ty_s_cdgr WITH EMPTY KEY,

  " ---- worksheet REFOBJECTS: reference object types
  BEGIN OF ty_s_refob,
    x_row         TYPE i,
    x_error       TYPE abap_bool,
    application   TYPE /iam/c_act_refob-application,
    activity_type TYPE /iam/c_act_refob-act_template,
    ref_obj_type  TYPE /iam/c_act_refob-ref_obj_type,
    inactive      TYPE /iam/c_act_refob-inactive,
  END OF ty_s_refob,
  tt_s_refob TYPE STANDARD TABLE OF ty_s_refob WITH EMPTY KEY,

  " ---- worksheet FOAPARAMS: parameters of the follow-up action
  BEGIN OF ty_s_para,
    x_row           TYPE i,
    x_error         TYPE abap_bool,
    application     TYPE /iam/c_act_para-application,
    activity_type   TYPE /iam/c_act_para-act_template,
    foa_param_id    TYPE /iam/c_act_para-foa_param_id,
    foa_param_value TYPE /iam/c_act_para-foa_param_value,
  END OF ty_s_para,
  tt_s_para TYPE STANDARD TABLE OF ty_s_para WITH EMPTY KEY,

  " ---- worksheet DIGSIG: digital signature
  BEGIN OF ty_s_ds,
    x_row         TYPE i,
    x_error       TYPE abap_bool,
    application   TYPE /iam/c_act_ds-application,
    activity_type TYPE /iam/c_act_ds-activity_type,
    action_alias  TYPE /iam/c_act_ds-action_alias,
    sign_type     TYPE /iam/c_act_ds-sign_type,
    sign_strat    TYPE /iam/c_act_ds-sign_strat,
  END OF ty_s_ds,
  tt_s_ds TYPE STANDARD TABLE OF ty_s_ds WITH EMPTY KEY,

  " ---- worksheet PARTNERS: default partners (master data)
  BEGIN OF ty_s_pty,
    x_row           TYPE i,
    x_error         TYPE abap_bool,
    application     TYPE /iam/d_actpty_md-application,
    activity_type   TYPE /iam/d_actpty_md-activity_type,
    party_role_code TYPE /iam/d_actpty_md-party_role_code,
    bu_partner      TYPE /iam/d_actpty_md-bu_partner,
    party_position  TYPE /iam/d_actpty_md-party_position,
    inactive        TYPE /iam/d_actpty_md-inactive,
  END OF ty_s_pty,
  tt_s_pty TYPE STANDARD TABLE OF ty_s_pty WITH EMPTY KEY,

  " ---- customizing buffers (= target state after the upload)
  tt_i_appl    TYPE SORTED TABLE OF /iam/i_appl
               WITH UNIQUE KEY client application,
  tt_acttype   TYPE SORTED TABLE OF /iam/c_acttype
               WITH UNIQUE KEY client application acttyp,
  tt_authgr    TYPE SORTED TABLE OF /iam/c_authgr
               WITH UNIQUE KEY client application auth_group,
  tt_follup    TYPE SORTED TABLE OF /iam/i_follup
               WITH UNIQUE KEY client act_follow_up,
  tt_i_type    TYPE SORTED TABLE OF /iam/i_type
               WITH UNIQUE KEY client type,
  tt_i_a_act   TYPE STANDARD TABLE OF /iam/i_a_act WITH EMPTY KEY,
  tt_role_cd   TYPE SORTED TABLE OF /iam/c_role_cd
               WITH UNIQUE KEY client application party_role_code,
  tt_catalog   TYPE SORTED TABLE OF /iam/c_catalog
               WITH UNIQUE KEY client cata,
  tt_catalog_t TYPE SORTED TABLE OF /iam/c_catalog_t
               WITH UNIQUE KEY client langu cata,
  tt_codegr    TYPE SORTED TABLE OF /iam/c_codegr
               WITH UNIQUE KEY client codegroup,
  tt_codegr_t  TYPE SORTED TABLE OF /iam/c_codegr_t
               WITH UNIQUE KEY client langu codegroup,
  tt_code      TYPE SORTED TABLE OF /iam/c_code
               WITH UNIQUE KEY client code,
  tt_code_t    TYPE SORTED TABLE OF /iam/c_code_t
               WITH UNIQUE KEY client langu code,
  tt_code_rel  TYPE SORTED TABLE OF /iam/c_code_rel
               WITH UNIQUE KEY client codegroup code,
  tt_catcodrel TYPE SORTED TABLE OF /iam/c_catcodrel
               WITH UNIQUE KEY client cata code,
  tt_activtyp  TYPE SORTED TABLE OF /iam/c_activtyp
               WITH UNIQUE KEY client application activity_type,
  tt_activtypt TYPE SORTED TABLE OF /iam/c_activtypt
               WITH UNIQUE KEY client langu application activity_type,
  tt_act_act   TYPE SORTED TABLE OF /iam/c_act_act
               WITH UNIQUE KEY client application activity_type int_number,
  tt_act_cdgr  TYPE SORTED TABLE OF /iam/c_act_cdgr
               WITH UNIQUE KEY client application activity_type int_number,
  tt_act_refob TYPE SORTED TABLE OF /iam/c_act_refob
               WITH UNIQUE KEY client application act_template int_number,
  tt_act_para  TYPE SORTED TABLE OF /iam/c_act_para
               WITH UNIQUE KEY client application act_template int_number,
  tt_act_ds    TYPE SORTED TABLE OF /iam/c_act_ds
               WITH UNIQUE KEY client application activity_type action_alias,
  tt_actpty_md TYPE SORTED TABLE OF /iam/d_actpty_md
               WITH UNIQUE KEY client application activity_type int_number.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE gv_t01.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS rb_pc RADIOBUTTON GROUP src DEFAULT 'X' USER-COMMAND src.
    SELECTION-SCREEN COMMENT 3(40) gv_c01 FOR FIELD rb_pc.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS rb_srv RADIOBUTTON GROUP src ##NEEDED.
    SELECTION-SCREEN COMMENT 3(40) gv_c02 FOR FIELD rb_srv.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_c03 FOR FIELD p_file.
    SELECTION-SCREEN POSITION 33.
    PARAMETERS p_file TYPE string LOWER CASE VISIBLE LENGTH 45.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE gv_t02.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_c04 FOR FIELD p_appl.
    SELECTION-SCREEN POSITION 33.
    PARAMETERS p_appl TYPE /iam/application DEFAULT 'MOC'.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_c05 FOR FIELD p_langu.
    SELECTION-SCREEN POSITION 33.
    PARAMETERS p_langu TYPE spras DEFAULT sy-langu.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN SKIP 1.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_test AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 3(70) gv_c06 FOR FIELD p_test.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_upd AS CHECKBOX DEFAULT ' '.
    SELECTION-SCREEN COMMENT 3(70) gv_c07 FOR FIELD p_upd.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_repl AS CHECKBOX DEFAULT ' '.
    SELECTION-SCREEN COMMENT 3(70) gv_c08 FOR FIELD p_repl.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_auto AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT 3(70) gv_c09 FOR FIELD p_auto.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b02.

SELECTION-SCREEN BEGIN OF BLOCK b03 WITH FRAME TITLE gv_t03.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_c10 FOR FIELD p_trkorr.
    SELECTION-SCREEN POSITION 33.
    PARAMETERS p_trkorr TYPE trkorr.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN COMMENT /1(75) gv_c11.
  SELECTION-SCREEN COMMENT /1(75) gv_c12.
SELECTION-SCREEN END OF BLOCK b03.

*----------------------------------------------------------------------*
* Exception
*----------------------------------------------------------------------*
CLASS lcx_upload DEFINITION INHERITING FROM cx_static_check FINAL.
  PUBLIC SECTION.
    DATA mv_text TYPE string READ-ONLY.
    METHODS constructor
      IMPORTING
        iv_text  TYPE string OPTIONAL
        previous TYPE REF TO cx_root OPTIONAL.
ENDCLASS.

*----------------------------------------------------------------------*
* Helper functions
*----------------------------------------------------------------------*
CLASS lcl_util DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS trim
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.
    CLASS-METHODS header_name
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_name) TYPE string.
    CLASS-METHODS get_comp
      IMPORTING is_data         TYPE any
                iv_name         TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.
    CLASS-METHODS same_values
      IMPORTING is_a           TYPE any
                is_b           TYPE any
                it_fields      TYPE string_table
      RETURNING VALUE(rv_same) TYPE abap_bool.
    CLASS-METHODS merge_fields
      IMPORTING is_source TYPE any
                it_fields TYPE string_table
      CHANGING  cs_target TYPE any.
    CLASS-METHODS is_flag_field
      IMPORTING iv_field       TYPE csequence
      RETURNING VALUE(rv_flag) TYPE abap_bool.
ENDCLASS.

*----------------------------------------------------------------------*
* Message log
*----------------------------------------------------------------------*
CLASS lcl_log DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS add
      IMPORTING
        iv_msgty  TYPE symsgty
        iv_text   TYPE csequence
        iv_sheet  TYPE ty_sheet OPTIONAL
        iv_row    TYPE i OPTIONAL
        iv_object TYPE csequence OPTIONAL.
    METHODS add_sy
      IMPORTING
        iv_msgty  TYPE symsgty OPTIONAL
        iv_sheet  TYPE ty_sheet OPTIONAL
        iv_row    TYPE i OPTIONAL
        iv_object TYPE csequence OPTIONAL.
    METHODS count
      IMPORTING iv_msgty        TYPE symsgty
      RETURNING VALUE(rv_count) TYPE i.
    METHODS display
      IMPORTING iv_title TYPE csequence.
  PRIVATE SECTION.
    DATA mt_log TYPE tt_log.
    METHODS set_column_text
      IMPORTING io_columns TYPE REF TO cl_salv_columns_table
                iv_column  TYPE lvc_fname
                iv_text    TYPE csequence
      RAISING   cx_salv_not_found.
ENDCLASS.

*----------------------------------------------------------------------*
* Upload
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_settings,
        file    TYPE string,
        on_pc   TYPE abap_bool,
        appl    TYPE /iam/application,
        langu   TYPE spras,
        test    TYPE abap_bool,
        update  TYPE abap_bool,
        replace TYPE abap_bool,
        auto    TYPE abap_bool,
        trkorr  TYPE trkorr,
      END OF ty_settings.

    CLASS-METHODS f4_file
      IMPORTING iv_on_pc TYPE abap_bool
      CHANGING  cv_file  TYPE string.
    METHODS constructor
      IMPORTING is_settings TYPE ty_settings.
    METHODS run.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_keybuf,
        tabname TYPE tabname,
        fields  TYPE ddfields,
      END OF ty_keybuf,
      BEGIN OF ty_plan_idx,
        key   TYPE string,
        index TYPE i,
      END OF ty_plan_idx,
      BEGIN OF ty_edge,
        appl   TYPE /iam/application,
        parent TYPE /iam/act_template,
        child  TYPE /iam/act_template,
      END OF ty_edge,
      BEGIN OF ty_text_req,
        application   TYPE /iam/c_activtypt-application,
        activity_type TYPE /iam/c_activtypt-activity_type,
        langu         TYPE /iam/c_activtypt-langu,
        description   TYPE /iam/c_activtypt-description,
        longtext      TYPE string,
        may_update    TYPE abap_bool,
        sheet         TYPE ty_sheet,
        row           TYPE i,
      END OF ty_text_req.

    CONSTANTS:
      BEGIN OF gc_sheet,
        codes      TYPE ty_sheet VALUE 'CODES',
        templates  TYPE ty_sheet VALUE 'TEMPLATES',
        texts      TYPE ty_sheet VALUE 'TEXTS',
        hierarchy  TYPE ty_sheet VALUE 'HIERARCHY',
        codegroups TYPE ty_sheet VALUE 'CODEGROUPS',
        refobjects TYPE ty_sheet VALUE 'REFOBJECTS',
        foaparams  TYPE ty_sheet VALUE 'FOAPARAMS',
        digsig     TYPE ty_sheet VALUE 'DIGSIG',
        partners   TYPE ty_sheet VALUE 'PARTNERS',
      END OF gc_sheet,
      gc_lt_delete   TYPE string VALUE `#DELETE#`,
      gc_tab_partner TYPE tabname VALUE '/IAM/D_ACTPTY_MD'.

    DATA ms_set          TYPE ty_settings.
    DATA mo_log          TYPE REF TO lcl_log.
    DATA mv_xdata        TYPE xstring.
    DATA mt_sheets       TYPE tt_xsheet.
    DATA mt_plan         TYPE tt_plan.
    DATA mt_plan_idx     TYPE HASHED TABLE OF ty_plan_idx WITH UNIQUE KEY key.
    DATA mt_ltplan       TYPE tt_ltplan.
    DATA mt_keybuf       TYPE HASHED TABLE OF ty_keybuf WITH UNIQUE KEY tabname.
    DATA mt_edges        TYPE SORTED TABLE OF ty_edge WITH NON-UNIQUE KEY appl parent.
    DATA mv_order        TYPE trkorr.
    DATA mv_task         TYPE trkorr.
    DATA mv_no_transport TYPE abap_bool.

    " worksheet data and the columns contained in the worksheet
    DATA mt_x_code  TYPE tt_s_code.
    DATA mt_f_code  TYPE string_table.
    DATA mt_x_tmpl  TYPE tt_s_tmpl.
    DATA mt_f_tmpl  TYPE string_table.
    DATA mt_x_text  TYPE tt_s_text.
    DATA mt_f_text  TYPE string_table.
    DATA mt_x_hier  TYPE tt_s_hier.
    DATA mt_f_hier  TYPE string_table.
    DATA mt_x_cdgr  TYPE tt_s_cdgr.
    DATA mt_f_cdgr  TYPE string_table.
    DATA mt_x_refob TYPE tt_s_refob.
    DATA mt_f_refob TYPE string_table.
    DATA mt_x_para  TYPE tt_s_para.
    DATA mt_f_para  TYPE string_table.
    DATA mt_x_ds    TYPE tt_s_ds.
    DATA mt_f_ds    TYPE string_table.
    DATA mt_x_pty   TYPE tt_s_pty.
    DATA mt_f_pty   TYPE string_table.

    " customizing (target state)
    DATA mt_i_appl    TYPE tt_i_appl.
    DATA mt_acttype   TYPE tt_acttype.
    DATA mt_authgr    TYPE tt_authgr.
    DATA mt_follup    TYPE tt_follup.
    DATA mt_i_type    TYPE tt_i_type.
    DATA mt_i_a_act   TYPE tt_i_a_act.
    DATA mt_role_cd   TYPE tt_role_cd.
    DATA mt_catalog   TYPE tt_catalog.
    DATA mt_catalog_t TYPE tt_catalog_t.
    DATA mt_codegr    TYPE tt_codegr.
    DATA mt_codegr_t  TYPE tt_codegr_t.
    DATA mt_code      TYPE tt_code.
    DATA mt_code_t    TYPE tt_code_t.
    DATA mt_code_rel  TYPE tt_code_rel.
    DATA mt_catcodrel TYPE tt_catcodrel.
    DATA mt_activtyp  TYPE tt_activtyp.
    DATA mt_activtypt TYPE tt_activtypt.
    DATA mt_act_act   TYPE tt_act_act.
    DATA mt_act_cdgr  TYPE tt_act_cdgr.
    DATA mt_act_refob TYPE tt_act_refob.
    DATA mt_act_para  TYPE tt_act_para.
    DATA mt_act_ds    TYPE tt_act_ds.
    DATA mt_actpty_md TYPE tt_actpty_md.

    " ---- input
    METHODS read_file
      RAISING lcx_upload.
    METHODS parse_workbook
      RAISING lcx_upload.
    METHODS is_known_sheet
      IMPORTING iv_sheet        TYPE ty_sheet
      RETURNING VALUE(rv_known) TYPE abap_bool.
    METHODS load_buffers.
    METHODS map_sheets.
    METHODS map_sheet
      IMPORTING iv_sheet  TYPE ty_sheet
      EXPORTING et_fields TYPE string_table
      CHANGING  ct_data   TYPE STANDARD TABLE.
    METHODS convert_value
      IMPORTING iv_value  TYPE string
                iv_field  TYPE csequence
      CHANGING  cv_target TYPE any
      RAISING   lcx_upload.
    METHODS convert_langu
      IMPORTING iv_value  TYPE string
      CHANGING  cv_target TYPE any
      RAISING   lcx_upload.
    METHODS convert_unit
      IMPORTING iv_value  TYPE string
      CHANGING  cv_target TYPE any
      RAISING   lcx_upload.

    " ---- planning (validation, no database change)
    METHODS plan_codes.
    METHODS plan_catalog
      IMPORTING is_code      TYPE ty_s_code
                iv_new_group TYPE abap_bool
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS codegroup_auth_ok
      IMPORTING is_code      TYPE ty_s_code
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS determine_code_id
      IMPORTING is_code        TYPE ty_s_code
      RETURNING VALUE(rv_code) TYPE /iam/code.
    METHODS plan_templates.
    METHODS check_template
      IMPORTING iv_row         TYPE i
                iv_object      TYPE csequence
                iv_description TYPE csequence
                iv_langu       TYPE spras
      EXPORTING ev_ok          TYPE abap_bool
      CHANGING  cs_tmpl        TYPE /iam/c_activtyp.
    METHODS plan_texts.
    METHODS plan_text_request
      IMPORTING is_req TYPE ty_text_req.
    METHODS plan_hierarchy.
    METHODS check_sort_numbers.
    METHODS is_reachable
      IMPORTING iv_appl         TYPE /iam/application
                iv_from         TYPE /iam/act_template
                iv_to           TYPE /iam/act_template
      RETURNING VALUE(rv_found) TYPE abap_bool.
    METHODS plan_codegroups.
    METHODS plan_refobjects.
    METHODS plan_foaparams.
    METHODS plan_digsig.
    METHODS plan_partners.
    METHODS plan_child_table
      IMPORTING iv_tabname    TYPE tabname
                iv_sheet      TYPE ty_sheet
                iv_tmpl_field TYPE fieldname
                iv_num_field  TYPE fieldname
                iv_bkey       TYPE string
                it_fields     TYPE string_table
                it_new        TYPE STANDARD TABLE
                it_rows       TYPE tt_int
      CHANGING  ct_db         TYPE ANY TABLE.
    METHODS final_checks.
    METHODS check_authority.
    METHODS check_transport.
    METHODS summarize.

    " ---- posting
    METHODS post.
    METHODS select_request
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS record_transport
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS transport_needed
      RETURNING VALUE(rv_needed) TYPE abap_bool.

    " ---- helpers
    METHODS add_plan
      IMPORTING iv_tabname TYPE tabname
                iv_action  TYPE char1
                is_data    TYPE any
                iv_sheet   TYPE ty_sheet OPTIONAL
                iv_row     TYPE i OPTIONAL
                iv_object  TYPE csequence OPTIONAL.
    METHODS add_ltplan
      IMPORTING is_header TYPE thead
                iv_action TYPE char1
                it_lines  TYPE tline_tab OPTIONAL
                iv_sheet  TYPE ty_sheet
                iv_row    TYPE i
                iv_object TYPE csequence.
    METHODS is_planned
      IMPORTING iv_tabname        TYPE tabname
                is_data           TYPE any
      RETURNING VALUE(rv_planned) TYPE abap_bool.
    METHODS build_tabkey
      IMPORTING iv_tabname    TYPE tabname
                is_data       TYPE any
      RETURNING VALUE(rv_key) TYPE trobj_name.
    METHODS get_key_fields
      IMPORTING iv_tabname       TYPE tabname
      RETURNING VALUE(rt_fields) TYPE ddfields.
    METHODS longtext_header
      IMPORTING iv_appl          TYPE /iam/application
                iv_tmpl          TYPE /iam/act_template
                iv_langu         TYPE spras
      RETURNING VALUE(rs_header) TYPE thead.
    METHODS longtext_exists
      IMPORTING is_header        TYPE thead
      RETURNING VALUE(rv_exists) TYPE abap_bool.
    METHODS read_longtext
      IMPORTING is_header       TYPE thead
      RETURNING VALUE(rt_lines) TYPE tline_tab.
    METHODS convert_longtext
      IMPORTING iv_text         TYPE string
                iv_langu        TYPE spras
      RETURNING VALUE(rt_lines) TYPE tline_tab.
    METHODS check_new_key
      IMPORTING iv_key       TYPE csequence
                iv_sheet     TYPE ty_sheet
                iv_row       TYPE i
                iv_object    TYPE csequence
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS appl_ok
      IMPORTING iv_appl      TYPE /iam/application
                iv_sheet     TYPE ty_sheet
                iv_row       TYPE i
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS template_exists
      IMPORTING iv_appl          TYPE /iam/application
                iv_tmpl          TYPE /iam/act_template
      RETURNING VALUE(rv_exists) TYPE abap_bool.
    METHODS check_child_template
      IMPORTING iv_appl      TYPE /iam/application
                iv_tmpl      TYPE /iam/act_template
                iv_sheet     TYPE ty_sheet
                iv_row       TYPE i
                iv_object    TYPE csequence
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS describe
      IMPORTING is_data        TYPE any
                it_fields      TYPE string_table
      RETURNING VALUE(rv_text) TYPE string.
    METHODS err
      IMPORTING iv_text   TYPE csequence
                iv_sheet  TYPE ty_sheet OPTIONAL
                iv_row    TYPE i OPTIONAL
                iv_object TYPE csequence OPTIONAL.
    METHODS warn
      IMPORTING iv_text   TYPE csequence
                iv_sheet  TYPE ty_sheet OPTIONAL
                iv_row    TYPE i OPTIONAL
                iv_object TYPE csequence OPTIONAL.
    METHODS info
      IMPORTING iv_text   TYPE csequence
                iv_sheet  TYPE ty_sheet OPTIONAL
                iv_row    TYPE i OPTIONAL
                iv_object TYPE csequence OPTIONAL.
ENDCLASS.

*----------------------------------------------------------------------*
* Events
*----------------------------------------------------------------------*
INITIALIZATION.
  gv_t01 = 'Excel workbook (.xlsx)'.
  gv_c01 = 'File on PC (presentation server)'.
  gv_c02 = 'File on application server'.
  gv_c03 = 'File path'.
  gv_t02 = 'Processing'.
  gv_c04 = 'Default application'.
  gv_c05 = 'Default language of the texts'.
  gv_c06 = 'Test run (check only, nothing is posted)'.
  gv_c07 = 'Update existing entries'.
  gv_c08 = 'Replace assignments of the uploaded templates (delete others)'.
  gv_c09 = 'Create missing catalogs, code groups and codes'.
  gv_t03 = 'Customizing transport request'.
  gv_c10 = 'Request / task'.
  gv_c11 = 'All changes are recorded in a customizing request.'.
  gv_c12 = 'Empty: the request is chosen in a popup before posting.'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  lcl_app=>f4_file( EXPORTING iv_on_pc = rb_pc
                    CHANGING  cv_file  = p_file ).

START-OF-SELECTION.
  NEW lcl_app( VALUE #( file    = p_file
                        on_pc   = rb_pc
                        appl    = p_appl
                        langu   = p_langu
                        test    = p_test
                        update  = p_upd
                        replace = p_repl
                        auto    = p_auto
                        trkorr  = p_trkorr ) )->run( ).

*----------------------------------------------------------------------*
* Implementations
*----------------------------------------------------------------------*
CLASS lcx_upload IMPLEMENTATION.
  METHOD constructor.
    super->constructor( previous = previous ).
    mv_text = iv_text.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_util IMPLEMENTATION.

  METHOD trim.
    " remove leading / trailing blanks, tabs and line breaks
    DATA: lv_ws  TYPE string,
          lv_chr TYPE string,
          lv_len TYPE i,
          lv_beg TYPE i,
          lv_end TYPE i,
          lv_pos TYPE i.

    lv_ws  = ` ` && cl_abap_char_utilities=>horizontal_tab && cl_abap_char_utilities=>cr_lf.
    lv_len = strlen( iv_text ).
    WHILE lv_beg < lv_len.
      lv_chr = substring( val = iv_text off = lv_beg len = 1 ).
      IF lv_chr CA lv_ws.
        lv_beg = lv_beg + 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    lv_end = lv_len.
    WHILE lv_end > lv_beg.
      lv_pos = lv_end - 1.
      lv_chr = substring( val = iv_text off = lv_pos len = 1 ).
      IF lv_chr CA lv_ws.
        lv_end = lv_pos.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    rv_text = substring( val = iv_text off = lv_beg len = lv_end - lv_beg ).
  ENDMETHOD.

  METHOD header_name.
    " 'ACTIVITY_TYPE*' / 'ACTIVITY_TYPE (Template)' -> 'ACTIVITY_TYPE'
    DATA: lv_text TYPE string,
          lv_word TYPE string,
          lv_rest TYPE string,
          lv_cr   TYPE c LENGTH 1.

    lv_cr   = cl_abap_char_utilities=>cr_lf.          " first character = CR
    lv_text = to_upper( iv_text ).
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_text WITH ` `.
    REPLACE ALL OCCURRENCES OF lv_cr IN lv_text WITH ` `.
    REPLACE ALL OCCURRENCES OF `*` IN lv_text WITH ` `.
    lv_text = trim( lv_text ).
    SPLIT lv_text AT ` ` INTO lv_word lv_rest.
    SPLIT lv_word AT `(` INTO rv_name lv_rest.
  ENDMETHOD.

  METHOD get_comp.
    FIELD-SYMBOLS <lv_value> TYPE any.
    ASSIGN COMPONENT iv_name OF STRUCTURE is_data TO <lv_value>.
    IF sy-subrc = 0.
      rv_value = <lv_value>.
    ENDIF.
  ENDMETHOD.

  METHOD same_values.
    FIELD-SYMBOLS: <lv_a> TYPE any,
                   <lv_b> TYPE any.
    DATA lv_field TYPE string.

    rv_same = abap_true.
    LOOP AT it_fields INTO lv_field.
      ASSIGN COMPONENT lv_field OF STRUCTURE is_a TO <lv_a>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      ASSIGN COMPONENT lv_field OF STRUCTURE is_b TO <lv_b>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF <lv_a> <> <lv_b>.
        rv_same = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD merge_fields.
    " take over the columns that are contained in the worksheet
    FIELD-SYMBOLS: <lv_source> TYPE any,
                   <lv_target> TYPE any.
    DATA lv_field TYPE string.

    LOOP AT it_fields INTO lv_field.
      ASSIGN COMPONENT lv_field OF STRUCTURE is_source TO <lv_source>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      ASSIGN COMPONENT lv_field OF STRUCTURE cs_target TO <lv_target>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      <lv_target> = <lv_source>.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_flag_field.
    CASE iv_field.
      WHEN 'ACT_LONG_TERM' OR 'ACT_MANDATORY' OR 'AUTO_RULE_EXECUT' OR 'INACTIVE'
        OR 'PROPOSAL_IND' OR 'CONT_INCOMPLETE' OR 'OBLIGATORY' OR 'CODE_CMNT_MAND'.
        rv_flag = abap_true.
      WHEN OTHERS.
        rv_flag = abap_false.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.

CLASS lcl_log IMPLEMENTATION.

  METHOD add.
    DATA ls_log TYPE ty_log.

    ls_log-msgty  = iv_msgty.
    ls_log-sheet  = iv_sheet.
    ls_log-row    = iv_row.
    ls_log-object = iv_object.
    ls_log-text   = iv_text.
    CASE iv_msgty.
      WHEN 'E' OR 'A' OR 'X'.
        ls_log-light = '1'.
      WHEN 'W'.
        ls_log-light = '2'.
      WHEN 'S'.
        ls_log-light = '3'.
      WHEN OTHERS.
        CLEAR ls_log-light.
    ENDCASE.
    APPEND ls_log TO mt_log.
  ENDMETHOD.

  METHOD add_sy.
    DATA: lv_text  TYPE string,
          lv_msgty TYPE symsgty.

    lv_msgty = sy-msgty.
    IF iv_msgty IS NOT INITIAL.
      lv_msgty = iv_msgty.
    ENDIF.
    IF lv_msgty IS INITIAL.
      lv_msgty = 'E'.
    ENDIF.
    IF sy-msgid IS INITIAL.
      lv_text = 'Error without message text'.
    ELSE.
      MESSAGE ID sy-msgid TYPE 'I' NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_text.
    ENDIF.
    add( iv_msgty  = lv_msgty
         iv_text   = lv_text
         iv_sheet  = iv_sheet
         iv_row    = iv_row
         iv_object = iv_object ).
  ENDMETHOD.

  METHOD count.
    LOOP AT mt_log TRANSPORTING NO FIELDS WHERE msgty = iv_msgty.
      rv_count = rv_count + 1.
    ENDLOOP.
  ENDMETHOD.

  METHOD display.
    DATA: lo_alv     TYPE REF TO cl_salv_table,
          lo_columns TYPE REF TO cl_salv_columns_table,
          lx_salv    TYPE REF TO cx_salv_error.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv
                                CHANGING  t_table      = mt_log ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_columns = lo_alv->get_columns( ).
        lo_columns->set_optimize( abap_true ).
        lo_columns->set_exception_column( 'LIGHT' ).
        set_column_text( io_columns = lo_columns iv_column = 'MSGTY'  iv_text = 'Type' ).
        set_column_text( io_columns = lo_columns iv_column = 'SHEET'  iv_text = 'Worksheet' ).
        set_column_text( io_columns = lo_columns iv_column = 'ROW'    iv_text = 'Row' ).
        set_column_text( io_columns = lo_columns iv_column = 'OBJECT' iv_text = 'Object' ).
        set_column_text( io_columns = lo_columns iv_column = 'TEXT'   iv_text = 'Message' ).
        lo_alv->get_display_settings( )->set_list_header( CONV lvc_title( iv_title ) ).
        lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_error INTO lx_salv.
        MESSAGE lx_salv TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD set_column_text.
    DATA lo_column TYPE REF TO cl_salv_column.

    lo_column = io_columns->get_column( iv_column ).
    lo_column->set_short_text( CONV scrtext_s( iv_text ) ).
    lo_column->set_medium_text( CONV scrtext_m( iv_text ) ).
    lo_column->set_long_text( CONV scrtext_l( iv_text ) ).
  ENDMETHOD.

ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

*----------------------------------------------------------------------*
* Selection screen / control
*----------------------------------------------------------------------*
  METHOD f4_file.
    DATA: lt_files  TYPE filetable,
          ls_file   TYPE file_table,
          lv_rc     TYPE i,
          lv_action TYPE i.

    IF iv_on_pc = abap_false.
      RETURN.
    ENDIF.
    cl_gui_frontend_services=>file_open_dialog(
      EXPORTING
        window_title = 'Select Excel workbook'
        file_filter  = 'Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*'
      CHANGING
        file_table   = lt_files
        rc           = lv_rc
        user_action  = lv_action
      EXCEPTIONS
        OTHERS       = 1 ).
    IF sy-subrc = 0 AND lv_action = cl_gui_frontend_services=>action_ok.
      READ TABLE lt_files INTO ls_file INDEX 1.
      IF sy-subrc = 0.
        cv_file = ls_file-filename.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD constructor.
    ms_set = is_settings.
    CREATE OBJECT mo_log.
  ENDMETHOD.

  METHOD run.
    DATA: lx_upload TYPE REF TO lcx_upload,
          lv_errors TYPE i.

    TRY.
        read_file( ).
        parse_workbook( ).
      CATCH lcx_upload INTO lx_upload.
        err( lx_upload->mv_text ).
        mo_log->display( 'Upload of activity templates' ).
        RETURN.
    ENDTRY.

    load_buffers( ).
    map_sheets( ).
    IF mt_x_code IS INITIAL AND mt_x_tmpl IS INITIAL AND mt_x_text IS INITIAL AND
       mt_x_hier IS INITIAL AND mt_x_cdgr IS INITIAL AND mt_x_refob IS INITIAL AND
       mt_x_para IS INITIAL AND mt_x_ds IS INITIAL AND mt_x_pty IS INITIAL.
      err( 'The workbook contains no data rows in the worksheets CODES, TEMPLATES, TEXTS, HIERARCHY, CODEGROUPS, REFOBJECTS, FOAPARAMS, DIGSIG, PARTNERS' ).
    ENDIF.

    " order matters: codes before templates, templates before assignments
    plan_codes( ).
    plan_templates( ).
    plan_texts( ).
    plan_hierarchy( ).
    plan_codegroups( ).
    plan_refobjects( ).
    plan_foaparams( ).
    plan_digsig( ).
    plan_partners( ).
    final_checks( ).
    check_authority( ).
    check_transport( ).
    summarize( ).

    lv_errors = mo_log->count( 'E' ).
    IF lv_errors > 0.
      err( |{ lv_errors } error(s) found - nothing was posted. Correct the workbook and start the upload again.| ).
    ELSEIF transport_needed( ) = abap_false AND mt_plan IS INITIAL.
      info( 'No changes necessary - the customizing corresponds to the workbook' ).
    ELSEIF ms_set-test = abap_true.
      mo_log->add( iv_msgty = 'S'
                   iv_text  = 'Test run - nothing was posted. Start again without test run to post the changes.' ).
    ELSE.
      post( ).
    ENDIF.

    mo_log->display( |Upload of activity templates: { ms_set-file }| ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Input
*----------------------------------------------------------------------*
  METHOD read_file.
    CONSTANTS lc_zip TYPE x LENGTH 2 VALUE '504B'.   " 'PK' = zip container (.xlsx)
    DATA: lt_bin  TYPE solix_tab,
          lv_len  TYPE i,
          lx_file TYPE REF TO cx_root.

    IF ms_set-file IS INITIAL.
      RAISE EXCEPTION TYPE lcx_upload EXPORTING iv_text = 'Enter the path of the Excel workbook'.
    ENDIF.

    IF ms_set-on_pc = abap_true.
      cl_gui_frontend_services=>gui_upload(
        EXPORTING
          filename   = ms_set-file
          filetype   = 'BIN'
        IMPORTING
          filelength = lv_len
        CHANGING
          data_tab   = lt_bin
        EXCEPTIONS
          OTHERS     = 1 ).
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE lcx_upload EXPORTING iv_text = |File { ms_set-file } cannot be read from the PC|.
      ENDIF.
      mv_xdata = cl_bcs_convert=>solix_to_xstring( it_solix = lt_bin
                                                   iv_size  = lv_len ).
    ELSE.
      TRY.
          OPEN DATASET ms_set-file FOR INPUT IN BINARY MODE.
          IF sy-subrc <> 0.
            RAISE EXCEPTION TYPE lcx_upload
              EXPORTING iv_text = |File { ms_set-file } cannot be opened on the application server|.
          ENDIF.
          READ DATASET ms_set-file INTO mv_xdata.
          CLOSE DATASET ms_set-file.
        CATCH cx_sy_file_open cx_sy_file_authority cx_sy_file_io cx_sy_file_open_mode INTO lx_file.
          RAISE EXCEPTION TYPE lcx_upload
            EXPORTING iv_text  = lx_file->get_text( )
                      previous = lx_file.
      ENDTRY.
    ENDIF.

    IF xstrlen( mv_xdata ) < 4 OR mv_xdata(2) <> lc_zip.
      RAISE EXCEPTION TYPE lcx_upload
        EXPORTING iv_text = 'The file is not an Excel workbook (.xlsx) - save it as "Excel Workbook" and repeat'.
    ENDIF.
  ENDMETHOD.

  METHOD parse_workbook.
    DATA: lo_excel  TYPE REF TO cl_fdt_xl_spreadsheet,
          lt_ws     TYPE if_fdt_doc_spreadsheet=>t_worksheet_names,
          lv_ws     TYPE string,
          lr_data   TYPE REF TO data,
          lt_hdr    TYPE string_table,
          ls_sheet  TYPE ty_xsheet,
          ls_xrow   TYPE ty_xrow,
          ls_cell   TYPE ty_cell,
          lv_sheet  TYPE ty_sheet,
          lv_name   TYPE string,
          lv_value  TYPE string,
          lv_first  TYPE string,
          lv_row    TYPE i,
          lv_col    TYPE i,
          lx_root   TYPE REF TO cx_root.
    FIELD-SYMBOLS: <lt_data> TYPE STANDARD TABLE,
                   <ls_line> TYPE any,
                   <lv_cell> TYPE any.

    TRY.
        CREATE OBJECT lo_excel
          EXPORTING
            document_name = ms_set-file
            xdocument     = mv_xdata.
        lo_excel->if_fdt_doc_spreadsheet~get_worksheet_names(
          IMPORTING worksheet_names = lt_ws ).
      CATCH cx_root INTO lx_root.
        RAISE EXCEPTION TYPE lcx_upload
          EXPORTING iv_text  = |The Excel workbook cannot be read: { lx_root->get_text( ) }|
                    previous = lx_root.
    ENDTRY.

    LOOP AT lt_ws INTO lv_ws.
      lv_sheet = to_upper( lcl_util=>trim( lv_ws ) ).
      IF is_known_sheet( lv_sheet ) = abap_false.
        IF lv_sheet <> 'README' AND lv_sheet <> 'LISTS'.
          info( |Worksheet { lv_ws } is not used by the upload| ).
        ENDIF.
        CONTINUE.
      ENDIF.

      TRY.
          lr_data = lo_excel->if_fdt_doc_spreadsheet~get_itab_from_worksheet( lv_ws ).
        CATCH cx_root INTO lx_root.
          err( iv_sheet = lv_sheet iv_text = |Worksheet cannot be read: { lx_root->get_text( ) }| ).
          CONTINUE.
      ENDTRY.
      IF lr_data IS NOT BOUND.
        CONTINUE.
      ENDIF.
      ASSIGN lr_data->* TO <lt_data>.

      CLEAR: ls_sheet, lt_hdr.
      ls_sheet-name = lv_sheet.
      LOOP AT <lt_data> ASSIGNING <ls_line>.
        lv_row = sy-tabix.
        IF lv_row = 1.
          " row 1: technical column names
          lv_col = 0.
          DO.
            lv_col = lv_col + 1.
            ASSIGN COMPONENT lv_col OF STRUCTURE <ls_line> TO <lv_cell>.
            IF sy-subrc <> 0.
              EXIT.
            ENDIF.
            lv_value = <lv_cell>.
            lv_name  = lcl_util=>header_name( lv_value ).
            IF lv_name IS NOT INITIAL AND line_exists( ls_sheet-fields[ table_line = lv_name ] ).
              warn( iv_sheet = lv_sheet iv_object = lv_name
                    iv_text  = |Column { lv_name } exists twice - the second column is ignored| ).
              CLEAR lv_name.
            ENDIF.
            APPEND lv_name TO lt_hdr.
            IF lv_name IS NOT INITIAL.
              APPEND lv_name TO ls_sheet-fields.
            ENDIF.
          ENDDO.
          CONTINUE.
        ENDIF.

        " data row
        CLEAR: ls_xrow, lv_first.
        ls_xrow-row = lv_row.
        LOOP AT lt_hdr INTO lv_name.
          lv_col = sy-tabix.
          ASSIGN COMPONENT lv_col OF STRUCTURE <ls_line> TO <lv_cell>.
          IF sy-subrc <> 0.
            EXIT.
          ENDIF.
          lv_value = lcl_util=>trim( CONV string( <lv_cell> ) ).
          IF lv_col = 1.
            lv_first = lv_value.
          ENDIF.
          IF lv_name IS INITIAL OR lv_value IS INITIAL.
            CONTINUE.
          ENDIF.
          ls_cell-field = lv_name.
          ls_cell-value = lv_value.
          INSERT ls_cell INTO TABLE ls_xrow-cells.
        ENDLOOP.
        " comment / description rows start with '*' in column A
        IF lv_first IS NOT INITIAL AND lv_first(1) = '*'.
          CONTINUE.
        ENDIF.
        IF ls_xrow-cells IS INITIAL.
          CONTINUE.
        ENDIF.
        APPEND ls_xrow TO ls_sheet-rows.
      ENDLOOP.

      INSERT ls_sheet INTO TABLE mt_sheets.
      IF sy-subrc <> 0.
        warn( iv_sheet = lv_sheet iv_text = |Worksheet { lv_ws } exists twice - only the first one is used| ).
      ELSE.
        info( iv_sheet = lv_sheet iv_text = |{ lines( ls_sheet-rows ) } data row(s) read| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_known_sheet.
    CASE iv_sheet.
      WHEN gc_sheet-codes OR gc_sheet-templates OR gc_sheet-texts OR gc_sheet-hierarchy
        OR gc_sheet-codegroups OR gc_sheet-refobjects OR gc_sheet-foaparams
        OR gc_sheet-digsig OR gc_sheet-partners.
        rv_known = abap_true.
      WHEN OTHERS.
        rv_known = abap_false.
    ENDCASE.
  ENDMETHOD.

  METHOD load_buffers.
    " current state of the customizing (bypassing the table buffer)
    SELECT * FROM /iam/i_appl      BYPASSING BUFFER INTO TABLE mt_i_appl.
    SELECT * FROM /iam/c_acttype   BYPASSING BUFFER INTO TABLE mt_acttype.
    SELECT * FROM /iam/c_authgr    BYPASSING BUFFER INTO TABLE mt_authgr.
    SELECT * FROM /iam/i_follup    BYPASSING BUFFER INTO TABLE mt_follup.
    SELECT * FROM /iam/i_type      BYPASSING BUFFER INTO TABLE mt_i_type.
    SELECT * FROM /iam/i_a_act     BYPASSING BUFFER INTO TABLE mt_i_a_act.
    SELECT * FROM /iam/c_role_cd   BYPASSING BUFFER INTO TABLE mt_role_cd.
    SELECT * FROM /iam/c_catalog   BYPASSING BUFFER INTO TABLE mt_catalog.
    SELECT * FROM /iam/c_catalog_t BYPASSING BUFFER INTO TABLE mt_catalog_t.
    SELECT * FROM /iam/c_codegr    BYPASSING BUFFER INTO TABLE mt_codegr.
    SELECT * FROM /iam/c_codegr_t  BYPASSING BUFFER INTO TABLE mt_codegr_t.
    SELECT * FROM /iam/c_code      BYPASSING BUFFER INTO TABLE mt_code.
    SELECT * FROM /iam/c_code_t    BYPASSING BUFFER INTO TABLE mt_code_t.
    SELECT * FROM /iam/c_code_rel  BYPASSING BUFFER INTO TABLE mt_code_rel.
    SELECT * FROM /iam/c_catcodrel BYPASSING BUFFER INTO TABLE mt_catcodrel.
    SELECT * FROM /iam/c_activtyp  BYPASSING BUFFER INTO TABLE mt_activtyp.
    SELECT * FROM /iam/c_activtypt BYPASSING BUFFER INTO TABLE mt_activtypt.
    SELECT * FROM /iam/c_act_act   BYPASSING BUFFER INTO TABLE mt_act_act.
    SELECT * FROM /iam/c_act_cdgr  BYPASSING BUFFER INTO TABLE mt_act_cdgr.
    SELECT * FROM /iam/c_act_refob BYPASSING BUFFER INTO TABLE mt_act_refob.
    SELECT * FROM /iam/c_act_para  BYPASSING BUFFER INTO TABLE mt_act_para.
    SELECT * FROM /iam/c_act_ds    BYPASSING BUFFER INTO TABLE mt_act_ds.
    SELECT * FROM /iam/d_actpty_md BYPASSING BUFFER INTO TABLE mt_actpty_md.
  ENDMETHOD.

  METHOD map_sheets.
    map_sheet( EXPORTING iv_sheet = gc_sheet-codes      IMPORTING et_fields = mt_f_code  CHANGING ct_data = mt_x_code ).
    map_sheet( EXPORTING iv_sheet = gc_sheet-templates  IMPORTING et_fields = mt_f_tmpl  CHANGING ct_data = mt_x_tmpl ).
    map_sheet( EXPORTING iv_sheet = gc_sheet-texts      IMPORTING et_fields = mt_f_text  CHANGING ct_data = mt_x_text ).
    map_sheet( EXPORTING iv_sheet = gc_sheet-hierarchy  IMPORTING et_fields = mt_f_hier  CHANGING ct_data = mt_x_hier ).
    map_sheet( EXPORTING iv_sheet = gc_sheet-codegroups IMPORTING et_fields = mt_f_cdgr  CHANGING ct_data = mt_x_cdgr ).
    map_sheet( EXPORTING iv_sheet = gc_sheet-refobjects IMPORTING et_fields = mt_f_refob CHANGING ct_data = mt_x_refob ).
    map_sheet( EXPORTING iv_sheet = gc_sheet-foaparams  IMPORTING et_fields = mt_f_para  CHANGING ct_data = mt_x_para ).
    map_sheet( EXPORTING iv_sheet = gc_sheet-digsig     IMPORTING et_fields = mt_f_ds    CHANGING ct_data = mt_x_ds ).
    map_sheet( EXPORTING iv_sheet = gc_sheet-partners   IMPORTING et_fields = mt_f_pty   CHANGING ct_data = mt_x_pty ).
  ENDMETHOD.

  METHOD map_sheet.
    " moves the cells of a worksheet into the typed structure (by column name)
    DATA: lr_proto TYPE REF TO data,
          lx_conv  TYPE REF TO lcx_upload,
          lv_field TYPE string.
    FIELD-SYMBOLS: <ls_sheet>  TYPE ty_xsheet,
                   <ls_xrow>   TYPE ty_xrow,
                   <ls_cell>   TYPE ty_cell,
                   <ls_proto>  TYPE any,
                   <ls_data>   TYPE any,
                   <lv_target> TYPE any,
                   <lv_row>    TYPE any,
                   <lv_error>  TYPE any,
                   <lv_appl>   TYPE any,
                   <lv_langu>  TYPE any.

    CLEAR et_fields.
    READ TABLE mt_sheets ASSIGNING <ls_sheet> WITH TABLE KEY name = iv_sheet.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    et_fields = <ls_sheet>-fields.

    CREATE DATA lr_proto LIKE LINE OF ct_data.
    ASSIGN lr_proto->* TO <ls_proto>.
    LOOP AT et_fields INTO lv_field.
      ASSIGN COMPONENT lv_field OF STRUCTURE <ls_proto> TO <lv_target>.
      IF sy-subrc <> 0 OR lv_field CP 'X_*'.
        warn( iv_sheet = iv_sheet iv_object = lv_field
              iv_text  = |Column { lv_field } is not known in worksheet { iv_sheet } and is ignored| ).
      ENDIF.
    ENDLOOP.

    LOOP AT <ls_sheet>-rows ASSIGNING <ls_xrow>.
      APPEND INITIAL LINE TO ct_data ASSIGNING <ls_data>.
      ASSIGN COMPONENT 'X_ROW' OF STRUCTURE <ls_data> TO <lv_row>.
      <lv_row> = <ls_xrow>-row.
      ASSIGN COMPONENT 'X_ERROR' OF STRUCTURE <ls_data> TO <lv_error>.

      LOOP AT <ls_xrow>-cells ASSIGNING <ls_cell> WHERE field NP 'X_*'.
        ASSIGN COMPONENT <ls_cell>-field OF STRUCTURE <ls_data> TO <lv_target>.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        TRY.
            convert_value( EXPORTING iv_value  = <ls_cell>-value
                                     iv_field  = <ls_cell>-field
                           CHANGING  cv_target = <lv_target> ).
          CATCH lcx_upload INTO lx_conv.
            <lv_error> = abap_true.
            err( iv_sheet  = iv_sheet
                 iv_row    = <ls_xrow>-row
                 iv_object = <ls_cell>-field
                 iv_text   = lx_conv->mv_text ).
        ENDTRY.
      ENDLOOP.

      " defaults of the selection screen
      ASSIGN COMPONENT 'APPLICATION' OF STRUCTURE <ls_data> TO <lv_appl>.
      IF sy-subrc = 0 AND <lv_appl> IS INITIAL.
        <lv_appl> = ms_set-appl.
      ENDIF.
      ASSIGN COMPONENT 'LANGU' OF STRUCTURE <ls_data> TO <lv_langu>.
      IF sy-subrc = 0 AND <lv_langu> IS INITIAL.
        <lv_langu> = ms_set-langu.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD convert_value.
    " converts the cell content like the dynpro input of SM30:
    " upper case (domain w/o lower case), conversion exit, length, fixed values
    CONSTANTS lc_eps TYPE decfloat34 VALUE '0.000001'.
    DATA: lo_elem    TYPE REF TO cl_abap_elemdescr,
          ls_dfies   TYPE dfies,
          lt_fix     TYPE ddfixvalues,
          ls_fix     TYPE ddfixvalue,
          lv_value   TYPE string,
          lv_upper   TYPE string,
          lv_digits  TYPE string,
          lv_allowed TYPE string,
          lv_maxlen  TYPE i,
          lv_dec     TYPE decfloat34,
          lv_round   TYPE decfloat34,
          lv_pack    TYPE p LENGTH 16 DECIMALS 0,
          lv_fm      TYPE rs38l_fnam,
          lv_found   TYPE abap_bool.

    lv_value = lcl_util=>trim( iv_value ).
    CLEAR cv_target.
    IF lv_value IS INITIAL.
      RETURN.
    ENDIF.

    " long texts (string)
    IF cl_abap_typedescr=>describe_by_data( cv_target )->type_kind = cl_abap_typedescr=>typekind_string.
      cv_target = lv_value.
      RETURN.
    ENDIF.

    IF iv_field = 'LANGU'.
      convert_langu( EXPORTING iv_value  = lv_value
                     CHANGING  cv_target = cv_target ).
      RETURN.
    ENDIF.

    IF lcl_util=>is_flag_field( iv_field ) = abap_true.
      lv_upper = to_upper( lv_value ).
      CASE lv_upper.
        WHEN 'X' OR '1' OR 'TRUE' OR 'YES' OR 'Y' OR 'JA' OR 'J' OR 'WAHR'.
          cv_target = abap_true.
        WHEN '0' OR 'FALSE' OR 'NO' OR 'N' OR 'NEIN' OR 'FALSCH' OR '-'.
          cv_target = abap_false.
        WHEN OTHERS.
          RAISE EXCEPTION TYPE lcx_upload
            EXPORTING iv_text = |"{ lv_value }" is not a valid indicator - use X or leave the cell empty|.
      ENDCASE.
      RETURN.
    ENDIF.

    lo_elem ?= cl_abap_typedescr=>describe_by_data( cv_target ).
    IF lo_elem->is_ddic_type( ) = abap_true.
      lo_elem->get_ddic_field( RECEIVING  p_flddescr = ls_dfies
                               EXCEPTIONS OTHERS     = 1 ).
      IF sy-subrc <> 0.
        CLEAR ls_dfies.
      ENDIF.
    ENDIF.

    " like dynpro input: upper case unless the domain allows lower case
    IF ls_dfies-lowercase IS INITIAL AND
       ( lo_elem->type_kind = cl_abap_typedescr=>typekind_char OR
         lo_elem->type_kind = cl_abap_typedescr=>typekind_num ).
      lv_value = to_upper( lv_value ).
    ENDIF.

    CASE lo_elem->type_kind.
      WHEN cl_abap_typedescr=>typekind_char.
        lv_maxlen = lo_elem->output_length.
        IF ls_dfies-leng > 0.
          lv_maxlen = ls_dfies-leng.
        ENDIF.
        IF strlen( lv_value ) > lv_maxlen.
          RAISE EXCEPTION TYPE lcx_upload
            EXPORTING iv_text = |"{ lv_value }" is too long - maximum { lv_maxlen } characters|.
        ENDIF.
        CASE ls_dfies-convexit.
          WHEN space.
            cv_target = lv_value.
          WHEN 'CUNIT'.
            convert_unit( EXPORTING iv_value  = lv_value
                          CHANGING  cv_target = cv_target ).
          WHEN OTHERS.
            lv_fm = |CONVERSION_EXIT_{ ls_dfies-convexit }_INPUT|.
            CALL FUNCTION lv_fm
              EXPORTING
                input  = lv_value
              IMPORTING
                output = cv_target
              EXCEPTIONS
                OTHERS = 1.
            IF sy-subrc <> 0.
              RAISE EXCEPTION TYPE lcx_upload
                EXPORTING iv_text = |"{ lv_value }" is not valid (conversion exit { ls_dfies-convexit })|.
            ENDIF.
        ENDCASE.

      WHEN cl_abap_typedescr=>typekind_num.
        lv_digits = lv_value.
        IF lv_digits CN '0123456789'.
          " numeric Excel cell, e.g. 10.0
          REPLACE ALL OCCURRENCES OF ',' IN lv_digits WITH '.'.
          TRY.
              lv_dec = lv_digits.
            CATCH cx_sy_conversion_error.
              RAISE EXCEPTION TYPE lcx_upload EXPORTING iv_text = |"{ lv_value }" is not a number|.
          ENDTRY.
          IF lv_dec < 0 OR frac( lv_dec ) <> 0.
            RAISE EXCEPTION TYPE lcx_upload
              EXPORTING iv_text = |"{ lv_value }" is not a positive whole number|.
          ENDIF.
          lv_pack   = lv_dec.
          lv_digits = lv_pack.
          CONDENSE lv_digits.
        ENDIF.
        SHIFT lv_digits LEFT DELETING LEADING '0'.
        IF strlen( lv_digits ) > lo_elem->output_length.
          RAISE EXCEPTION TYPE lcx_upload
            EXPORTING iv_text = |"{ lv_value }" is too large - maximum { lo_elem->output_length } digits|.
        ENDIF.
        cv_target = lv_digits.

      WHEN cl_abap_typedescr=>typekind_packed OR cl_abap_typedescr=>typekind_int
        OR cl_abap_typedescr=>typekind_decfloat16 OR cl_abap_typedescr=>typekind_decfloat34
        OR cl_abap_typedescr=>typekind_float.
        REPLACE ALL OCCURRENCES OF ',' IN lv_value WITH '.'.
        TRY.
            lv_dec = lv_value.
          CATCH cx_sy_conversion_error.
            RAISE EXCEPTION TYPE lcx_upload EXPORTING iv_text = |"{ lv_value }" is not a number|.
        ENDTRY.
        IF lv_dec < 0.
          RAISE EXCEPTION TYPE lcx_upload EXPORTING iv_text = |Negative values are not allowed ({ lv_value })|.
        ENDIF.
        lv_round = round( val = lv_dec dec = lo_elem->decimals ).
        IF abs( lv_dec - lv_round ) > lc_eps.
          RAISE EXCEPTION TYPE lcx_upload
            EXPORTING iv_text = |"{ lv_value }" has too many decimal places - maximum { lo_elem->decimals }|.
        ENDIF.
        TRY.
            cv_target = lv_round.
          CATCH cx_sy_conversion_error.
            RAISE EXCEPTION TYPE lcx_upload EXPORTING iv_text = |"{ lv_value }" is too large|.
        ENDTRY.

      WHEN OTHERS.
        TRY.
            cv_target = lv_value.
          CATCH cx_sy_conversion_error.
            RAISE EXCEPTION TYPE lcx_upload EXPORTING iv_text = |"{ lv_value }" is not a valid value|.
        ENDTRY.
    ENDCASE.

    " fixed values of the domain (response type, comment mandatory, ...)
    IF ls_dfies-valexi = abap_true AND cv_target IS NOT INITIAL.
      lo_elem->get_ddic_fixed_values( RECEIVING  p_fixed_values = lt_fix
                                      EXCEPTIONS OTHERS         = 1 ).
      IF sy-subrc = 0 AND lt_fix IS NOT INITIAL.
        lv_found = abap_false.
        LOOP AT lt_fix INTO ls_fix.
          IF ( ls_fix-option = 'BT' AND cv_target BETWEEN ls_fix-low AND ls_fix-high ) OR
             ( ls_fix-option <> 'BT' AND cv_target = ls_fix-low ).
            lv_found = abap_true.
            EXIT.
          ENDIF.
          IF ls_fix-low IS NOT INITIAL.
            lv_allowed = |{ lv_allowed } { ls_fix-low }|.
          ENDIF.
        ENDLOOP.
        IF lv_found = abap_false.
          RAISE EXCEPTION TYPE lcx_upload
            EXPORTING iv_text = |"{ lv_value }" is not allowed - allowed values:{ lv_allowed }|.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD convert_langu.
    " ISO code (EN, DE) or SAP language key (E, D)
    DATA: lv_spras TYPE spras,
          lv_in    TYPE spras,
          lv_laiso TYPE laiso,
          lv_ok    TYPE abap_bool.

    IF strlen( iv_value ) = 1.
      lv_in = iv_value.
      SELECT SINGLE spras FROM t002 INTO lv_spras WHERE spras = lv_in.
      IF sy-subrc <> 0.
        lv_in = to_upper( iv_value ).
        SELECT SINGLE spras FROM t002 INTO lv_spras WHERE spras = lv_in.
      ENDIF.
      IF sy-subrc = 0.
        lv_ok = abap_true.
      ENDIF.
    ELSEIF strlen( iv_value ) = 2.
      lv_laiso = to_upper( iv_value ).
      CALL FUNCTION 'CONVERSION_EXIT_ISOLA_INPUT'
        EXPORTING
          input            = lv_laiso
        IMPORTING
          output           = lv_spras
        EXCEPTIONS
          unknown_language = 1
          OTHERS           = 2.
      IF sy-subrc = 0 AND lv_spras IS NOT INITIAL.
        lv_ok = abap_true.
      ENDIF.
    ENDIF.
    IF lv_ok = abap_false.
      RAISE EXCEPTION TYPE lcx_upload
        EXPORTING iv_text = |Language "{ iv_value }" is not valid - use the ISO code (EN, DE, ...)|.
    ENDIF.
    cv_target = lv_spras.
  ENDMETHOD.

  METHOD convert_unit.
    " external unit of the logon language (DAY, H) or internal unit (TAG, H)
    DATA: lv_input TYPE c LENGTH 3,
          lv_unit  TYPE t006-msehi,
          lv_ok    TYPE abap_bool.

    lv_input = to_upper( iv_value ).
    CALL FUNCTION 'CONVERSION_EXIT_CUNIT_INPUT'
      EXPORTING
        input          = lv_input
        language       = sy-langu
      IMPORTING
        output         = lv_unit
      EXCEPTIONS
        unit_not_found = 1
        OTHERS         = 2.
    IF sy-subrc = 0 AND lv_unit IS NOT INITIAL.
      lv_ok = abap_true.
    ELSE.
      SELECT SINGLE msehi FROM t006 INTO lv_unit WHERE msehi = lv_input.
      IF sy-subrc = 0.
        lv_ok = abap_true.
      ENDIF.
    ENDIF.
    IF lv_ok = abap_false.
      RAISE EXCEPTION TYPE lcx_upload EXPORTING iv_text = |Unit "{ iv_value }" is not defined (table T006)|.
    ENDIF.
    cv_target = lv_unit.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Worksheet CODES - catalogs, code groups and codes
*----------------------------------------------------------------------*
  METHOD plan_codes.
    DATA: ls_codegr    TYPE /iam/c_codegr,
          ls_codegr_t  TYPE /iam/c_codegr_t,
          ls_code      TYPE /iam/c_code,
          ls_code_t    TYPE /iam/c_code_t,
          ls_code_rel  TYPE /iam/c_code_rel,
          ls_rel_db    TYPE /iam/c_code_rel,
          ls_catcodrel TYPE /iam/c_catcodrel,
          lv_new_group TYPE abap_bool,
          lv_grp_text  TYPE /iam/c_codegr_t-codegroup_text,
          lt_rel_seen  TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_rel_key   TYPE string,
          lv_obj       TYPE string,
          lv_dummy     TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_code.

    LOOP AT mt_x_code ASSIGNING <ls_x> WHERE x_error = abap_false.
      lv_obj = |{ <ls_x>-codegroup } { <ls_x>-code }|.
      IF appl_ok( iv_appl = <ls_x>-application iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-codegroup IS INITIAL.
        err( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_text = 'Code group (CODEGROUP) is mandatory' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.

      " ---- code group (SAPLVIEWS: LCL_V_CODEGR)
      READ TABLE mt_codegr INTO ls_codegr
           WITH TABLE KEY client = sy-mandt codegroup = <ls_x>-codegroup.
      IF sy-subrc = 0.
        lv_new_group = abap_false.
        IF <ls_x>-cata IS INITIAL.
          <ls_x>-cata = ls_codegr-cata.
        ELSEIF <ls_x>-cata <> ls_codegr-cata.
          err( iv_sheet  = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
               iv_text   = |Code group { <ls_x>-codegroup } belongs to catalog { ls_codegr-cata }, not to { <ls_x>-cata }| ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        IF <ls_x>-auth_group IS NOT INITIAL AND <ls_x>-auth_group <> ls_codegr-auth_group.
          IF ms_set-update = abap_false.
            warn( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
                  iv_text  = 'Authorization group of the code group differs - not changed (update mode is off)' ).
          ELSEIF codegroup_auth_ok( <ls_x> ) = abap_false.
            <ls_x>-x_error = abap_true.
            CONTINUE.
          ELSE.
            ls_codegr-auth_group = <ls_x>-auth_group.
            add_plan( iv_tabname = '/IAM/C_CODEGR' iv_action = 'U' is_data = ls_codegr
                      iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
            MODIFY TABLE mt_codegr FROM ls_codegr.
          ENDIF.
        ENDIF.
      ELSE.
        lv_new_group = abap_true.
        IF check_new_key( iv_key = <ls_x>-codegroup iv_sheet = gc_sheet-codes
                          iv_row = <ls_x>-x_row     iv_object = lv_obj ) = abap_false.
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        IF ms_set-auto = abap_false.
          MESSAGE e039(/iam/config) WITH <ls_x>-codegroup INTO lv_dummy.
          mo_log->add_sy( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        IF <ls_x>-cata IS INITIAL.
          err( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
               iv_text  = 'Catalog (CATA) is mandatory for a new code group' ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        IF <ls_x>-auth_group IS NOT INITIAL AND
           NOT line_exists( mt_authgr[ client = sy-mandt application = <ls_x>-application auth_group = <ls_x>-auth_group ] ).
          err( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
               iv_text  = |Authorization group { <ls_x>-auth_group } is not defined for application { <ls_x>-application }| ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
      ENDIF.

      " ---- catalog (created if missing) and catalog text
      IF plan_catalog( is_code = <ls_x> iv_new_group = lv_new_group ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.

      IF lv_new_group = abap_true.
        " SAPLVIEWS: LCL_V_CODEGR->FILL_FIELDS4NEW_ENTRY (owner, authority check)
        IF codegroup_auth_ok( <ls_x> ) = abap_false.
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        CLEAR ls_codegr.
        ls_codegr-client     = sy-mandt.
        ls_codegr-codegroup  = <ls_x>-codegroup.
        ls_codegr-cata       = <ls_x>-cata.
        ls_codegr-auth_group = <ls_x>-auth_group.
        ls_codegr-owner      = sy-uname.
        add_plan( iv_tabname = '/IAM/C_CODEGR' iv_action = 'I' is_data = ls_codegr
                  iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
        INSERT ls_codegr INTO TABLE mt_codegr.
      ENDIF.

      " ---- code group text
      lv_grp_text = <ls_x>-codegroup_text.
      IF lv_grp_text IS INITIAL AND lv_new_group = abap_true.
        lv_grp_text = <ls_x>-codegroup.
        warn( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
              iv_text  = 'No code group text (CODEGROUP_TEXT) - the code group ID is used as text' ).
      ENDIF.
      IF lv_grp_text IS NOT INITIAL.
        READ TABLE mt_codegr_t INTO ls_codegr_t
             WITH TABLE KEY client = sy-mandt langu = <ls_x>-langu codegroup = <ls_x>-codegroup.
        IF sy-subrc <> 0.
          CLEAR ls_codegr_t.
          ls_codegr_t-client         = sy-mandt.
          ls_codegr_t-langu          = <ls_x>-langu.
          ls_codegr_t-codegroup      = <ls_x>-codegroup.
          ls_codegr_t-codegroup_text = lv_grp_text.
          add_plan( iv_tabname = '/IAM/C_CODEGR_T' iv_action = 'I' is_data = ls_codegr_t
                    iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
          INSERT ls_codegr_t INTO TABLE mt_codegr_t.
        ELSEIF ls_codegr_t-codegroup_text <> lv_grp_text.
          IF is_planned( iv_tabname = '/IAM/C_CODEGR_T' is_data = ls_codegr_t ) = abap_true.
            warn( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
                  iv_text  = 'Different texts for the same code group - the first text is used' ).
          ELSEIF ms_set-update = abap_true.
            ls_codegr_t-codegroup_text = lv_grp_text.
            add_plan( iv_tabname = '/IAM/C_CODEGR_T' iv_action = 'U' is_data = ls_codegr_t
                      iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
            MODIFY TABLE mt_codegr_t FROM ls_codegr_t.
          ELSE.
            warn( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
                  iv_text  = 'Code group text differs - not changed (update mode is off)' ).
          ENDIF.
        ENDIF.
      ENDIF.

      " ---- code (SAPLVIEWS: LCL_V_CODE)
      IF <ls_x>-code IS INITIAL AND <ls_x>-code_text IS INITIAL.
        CONTINUE.                                   " row defines the code group only
      ENDIF.
      IF <ls_x>-code IS INITIAL.
        " automatic code ID: same text in the code group -> reuse, else <code group>_<nnn>
        <ls_x>-code = determine_code_id( <ls_x> ).
        IF <ls_x>-code IS INITIAL.
          err( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
               iv_text  = 'No free code ID found - enter the code ID in column CODE' ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        lv_obj = |{ <ls_x>-codegroup } { <ls_x>-code }|.
        info( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
              iv_text  = |Code ID { <ls_x>-code } determined for text "{ <ls_x>-code_text }"| ).
      ENDIF.

      READ TABLE mt_code INTO ls_code WITH TABLE KEY client = sy-mandt code = <ls_x>-code.
      IF sy-subrc <> 0.
        IF check_new_key( iv_key = <ls_x>-code iv_sheet = gc_sheet-codes
                          iv_row = <ls_x>-x_row iv_object = lv_obj ) = abap_false.
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        IF ms_set-auto = abap_false.
          err( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
               iv_text  = |Code { <ls_x>-code } does not exist (automatic creation is switched off)| ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        IF <ls_x>-code_text IS INITIAL.
          err( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
               iv_text  = 'Code text (CODE_TEXT) is mandatory for a new code' ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
        CLEAR ls_code.
        ls_code-client = sy-mandt.
        ls_code-code   = <ls_x>-code.
        ls_code-owner  = sy-uname.
        add_plan( iv_tabname = '/IAM/C_CODE' iv_action = 'I' is_data = ls_code
                  iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
        INSERT ls_code INTO TABLE mt_code.
      ENDIF.

      " code text
      IF <ls_x>-code_text IS NOT INITIAL.
        READ TABLE mt_code_t INTO ls_code_t
             WITH TABLE KEY client = sy-mandt langu = <ls_x>-langu code = <ls_x>-code.
        IF sy-subrc <> 0.
          CLEAR ls_code_t.
          ls_code_t-client    = sy-mandt.
          ls_code_t-langu     = <ls_x>-langu.
          ls_code_t-code      = <ls_x>-code.
          ls_code_t-code_text = <ls_x>-code_text.
          add_plan( iv_tabname = '/IAM/C_CODE_T' iv_action = 'I' is_data = ls_code_t
                    iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
          INSERT ls_code_t INTO TABLE mt_code_t.
        ELSEIF ls_code_t-code_text <> <ls_x>-code_text.
          IF is_planned( iv_tabname = '/IAM/C_CODE_T' is_data = ls_code_t ) = abap_true.
            warn( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
                  iv_text  = 'Different texts for the same code - the first text is used' ).
          ELSEIF ms_set-update = abap_true.
            ls_code_t-code_text = <ls_x>-code_text.
            add_plan( iv_tabname = '/IAM/C_CODE_T' iv_action = 'U' is_data = ls_code_t
                      iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
            MODIFY TABLE mt_code_t FROM ls_code_t.
          ELSE.
            warn( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
                  iv_text  = |Code { <ls_x>-code } exists with text "{ ls_code_t-code_text }" - not changed (update mode is off)| ).
          ENDIF.
        ENDIF.
      ENDIF.

      " catalog -> code (/IAM/V_CATCODREL)
      IF NOT line_exists( mt_catcodrel[ client = sy-mandt cata = <ls_x>-cata code = <ls_x>-code ] ).
        CLEAR ls_catcodrel.
        ls_catcodrel-client = sy-mandt.
        ls_catcodrel-cata   = <ls_x>-cata.
        ls_catcodrel-code   = <ls_x>-code.
        add_plan( iv_tabname = '/IAM/C_CATCODREL' iv_action = 'I' is_data = ls_catcodrel
                  iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
        INSERT ls_catcodrel INTO TABLE mt_catcodrel.
      ENDIF.

      " code group -> code (/IAM/V_CODE_REL); further rows of the same code
      " (e.g. translations) do not change the flags of the first row
      lv_rel_key = |{ <ls_x>-codegroup }/{ <ls_x>-code }|.
      INSERT lv_rel_key INTO TABLE lt_rel_seen.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      CLEAR ls_code_rel.
      ls_code_rel-client         = sy-mandt.
      ls_code_rel-codegroup      = <ls_x>-codegroup.
      ls_code_rel-code           = <ls_x>-code.
      ls_code_rel-inactive       = <ls_x>-inactive.
      ls_code_rel-code_cmnt_mand = <ls_x>-code_cmnt_mand.
      READ TABLE mt_code_rel INTO ls_rel_db
           WITH TABLE KEY client = sy-mandt codegroup = <ls_x>-codegroup code = <ls_x>-code.
      IF sy-subrc <> 0.
        add_plan( iv_tabname = '/IAM/C_CODE_REL' iv_action = 'I' is_data = ls_code_rel
                  iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
        INSERT ls_code_rel INTO TABLE mt_code_rel.
      ELSE.
        IF NOT line_exists( mt_f_code[ table_line = `INACTIVE` ] ).
          ls_code_rel-inactive = ls_rel_db-inactive.
        ENDIF.
        IF NOT line_exists( mt_f_code[ table_line = `CODE_CMNT_MAND` ] ).
          ls_code_rel-code_cmnt_mand = ls_rel_db-code_cmnt_mand.
        ENDIF.
        IF ls_code_rel <> ls_rel_db.
          IF ms_set-update = abap_true.
            add_plan( iv_tabname = '/IAM/C_CODE_REL' iv_action = 'U' is_data = ls_code_rel
                      iv_sheet   = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj ).
            MODIFY TABLE mt_code_rel FROM ls_code_rel.
          ELSE.
            warn( iv_sheet = gc_sheet-codes iv_row = <ls_x>-x_row iv_object = lv_obj
                  iv_text  = 'Code assignment differs (inactive / comment mandatory) - not changed (update mode is off)' ).
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD plan_catalog.
    DATA: ls_catalog   TYPE /iam/c_catalog,
          ls_catalog_t TYPE /iam/c_catalog_t,
          lv_text      TYPE /iam/c_catalog_t-cata_text,
          lv_new       TYPE abap_bool,
          lv_obj       TYPE string.

    rv_ok  = abap_true.
    lv_obj = |{ is_code-cata }|.
    READ TABLE mt_catalog INTO ls_catalog WITH TABLE KEY client = sy-mandt cata = is_code-cata.
    IF sy-subrc = 0.
      IF iv_new_group = abap_true AND ls_catalog-application IS NOT INITIAL AND
         ls_catalog-application <> is_code-application.
        warn( iv_sheet = gc_sheet-codes iv_row = is_code-x_row iv_object = lv_obj
              iv_text  = |Catalog { is_code-cata } belongs to application { ls_catalog-application }| ).
      ENDIF.
    ELSE.
      IF check_new_key( iv_key = is_code-cata iv_sheet = gc_sheet-codes
                        iv_row = is_code-x_row iv_object = lv_obj ) = abap_false.
        rv_ok = abap_false.
        RETURN.
      ENDIF.
      IF ms_set-auto = abap_false.
        err( iv_sheet = gc_sheet-codes iv_row = is_code-x_row iv_object = lv_obj
             iv_text  = |Catalog { is_code-cata } does not exist (automatic creation is switched off)| ).
        rv_ok = abap_false.
        RETURN.
      ENDIF.
      lv_new = abap_true.
      CLEAR ls_catalog.
      ls_catalog-client      = sy-mandt.
      ls_catalog-cata        = is_code-cata.
      ls_catalog-application = is_code-application.
      add_plan( iv_tabname = '/IAM/C_CATALOG' iv_action = 'I' is_data = ls_catalog
                iv_sheet   = gc_sheet-codes iv_row = is_code-x_row iv_object = lv_obj ).
      INSERT ls_catalog INTO TABLE mt_catalog.
    ENDIF.

    lv_text = is_code-cata_text.
    IF lv_text IS INITIAL AND lv_new = abap_true.
      lv_text = is_code-cata.
    ENDIF.
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE mt_catalog_t INTO ls_catalog_t
         WITH TABLE KEY client = sy-mandt langu = is_code-langu cata = is_code-cata.
    IF sy-subrc <> 0.
      CLEAR ls_catalog_t.
      ls_catalog_t-client    = sy-mandt.
      ls_catalog_t-langu     = is_code-langu.
      ls_catalog_t-cata      = is_code-cata.
      ls_catalog_t-cata_text = lv_text.
      add_plan( iv_tabname = '/IAM/C_CATALOG_T' iv_action = 'I' is_data = ls_catalog_t
                iv_sheet   = gc_sheet-codes iv_row = is_code-x_row iv_object = lv_obj ).
      INSERT ls_catalog_t INTO TABLE mt_catalog_t.
    ELSEIF ls_catalog_t-cata_text <> lv_text.
      IF is_planned( iv_tabname = '/IAM/C_CATALOG_T' is_data = ls_catalog_t ) = abap_true.
        RETURN.                                     " first text of the worksheet wins
      ELSEIF ms_set-update = abap_true.
        ls_catalog_t-cata_text = lv_text.
        add_plan( iv_tabname = '/IAM/C_CATALOG_T' iv_action = 'U' is_data = ls_catalog_t
                  iv_sheet   = gc_sheet-codes iv_row = is_code-x_row iv_object = lv_obj ).
        MODIFY TABLE mt_catalog_t FROM ls_catalog_t.
      ELSE.
        warn( iv_sheet = gc_sheet-codes iv_row = is_code-x_row iv_object = lv_obj
              iv_text  = 'Catalog text differs - not changed (update mode is off)' ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD codegroup_auth_ok.
    " SAPLVIEWS: LCL_V_CODEGR->FILL_FIELDS4NEW_ENTRY
    DATA lx_auth TYPE REF TO /iam/cx_iam_config_authority.

    rv_ok = abap_true.
    TRY.
        /iam/cl_authority_factory=>get_config_auth_instance( )->check_codegroup_maintenance(
          iv_application = is_code-application
          iv_catalog     = is_code-cata
          iv_auth_group  = is_code-auth_group ).
      CATCH /iam/cx_iam_config_authority INTO lx_auth.
        rv_ok = abap_false.
        err( iv_sheet = gc_sheet-codes iv_row = is_code-x_row iv_object = is_code-codegroup
             iv_text  = lx_auth->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD determine_code_id.
    DATA: ls_rel    TYPE /iam/c_code_rel,
          ls_code_t TYPE /iam/c_code_t,
          lv_text   TYPE string,
          lv_cmp    TYPE string,
          lv_num    TYPE n LENGTH 3,
          lv_code   TYPE /iam/code.

    " 1) code of the same code group with the same text (repeated upload)
    lv_text = to_upper( is_code-code_text ).
    LOOP AT mt_code_rel INTO ls_rel WHERE codegroup = is_code-codegroup.
      READ TABLE mt_code_t INTO ls_code_t
           WITH TABLE KEY client = sy-mandt langu = is_code-langu code = ls_rel-code.
      IF sy-subrc = 0.
        lv_cmp = to_upper( ls_code_t-code_text ).
        IF lv_cmp = lv_text.
          rv_code = ls_rel-code.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " 2) new ID <code group>_<nnn>
    DO 999 TIMES.
      lv_num  = sy-index.
      lv_code = |{ is_code-codegroup }_{ lv_num }|.
      IF NOT line_exists( mt_code[ client = sy-mandt code = lv_code ] ).
        rv_code = lv_code.
        RETURN.
      ENDIF.
    ENDDO.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Worksheet TEMPLATES - activity templates (/IAM/V_ACTIVTYP)
*----------------------------------------------------------------------*
  METHOD plan_templates.
    DATA: ls_db     TYPE /iam/c_activtyp,
          ls_new    TYPE /iam/c_activtyp,
          ls_target TYPE /iam/c_activtyp,
          lt_seen   TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_obj    TYPE string,
          lv_exists TYPE abap_bool,
          lv_ok     TYPE abap_bool,
          lv_dummy  TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_tmpl.

    LOOP AT mt_x_tmpl ASSIGNING <ls_x> WHERE x_error = abap_false.
      lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type }|.
      IF appl_ok( iv_appl = <ls_x>-application iv_sheet = gc_sheet-templates iv_row = <ls_x>-x_row ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-activity_type IS INITIAL.
        MESSAGE e001(/iam/config) INTO lv_dummy.
        mo_log->add_sy( iv_sheet = gc_sheet-templates iv_row = <ls_x>-x_row iv_object = 'ACTIVITY_TYPE' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      INSERT lv_obj INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        err( iv_sheet = gc_sheet-templates iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Template is contained more than once in the worksheet' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.

      READ TABLE mt_activtyp INTO ls_db
           WITH TABLE KEY client = sy-mandt application = <ls_x>-application activity_type = <ls_x>-activity_type.
      lv_exists = xsdbool( sy-subrc = 0 ).
      " SAPLVIEWS: EVENT_05_CHECK_NEW_ACTIVTYP -> CHECK_NEW_KEY
      IF lv_exists = abap_false AND
         check_new_key( iv_key = <ls_x>-activity_type iv_sheet = gc_sheet-templates
                        iv_row = <ls_x>-x_row         iv_object = lv_obj ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.

      ls_new        = CORRESPONDING #( <ls_x> ).
      ls_new-client = sy-mandt.
      IF lv_exists = abap_true.
        " only the columns of the worksheet are changed
        ls_target = ls_db.
        lcl_util=>merge_fields( EXPORTING is_source = ls_new
                                          it_fields = mt_f_tmpl
                                CHANGING  cs_target = ls_target ).
      ELSE.
        ls_target = ls_new.
      ENDIF.

      check_template( EXPORTING iv_row         = <ls_x>-x_row
                                iv_object      = lv_obj
                                iv_description = <ls_x>-description
                                iv_langu       = <ls_x>-langu
                      IMPORTING ev_ok          = lv_ok
                      CHANGING  cs_tmpl        = ls_target ).
      IF lv_ok = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.

      IF lv_exists = abap_false.
        <ls_x>-x_action = 'I'.
        add_plan( iv_tabname = '/IAM/C_ACTIVTYP' iv_action = 'I' is_data = ls_target
                  iv_sheet   = gc_sheet-templates iv_row = <ls_x>-x_row iv_object = lv_obj ).
        INSERT ls_target INTO TABLE mt_activtyp.
      ELSEIF ms_set-update = abap_false.
        <ls_x>-x_action = 'S'.
        IF ls_target = ls_db.
          info( iv_sheet = gc_sheet-templates iv_row = <ls_x>-x_row iv_object = lv_obj
                iv_text  = 'Template exists already - not processed (update mode is off)' ).
        ELSE.
          warn( iv_sheet = gc_sheet-templates iv_row = <ls_x>-x_row iv_object = lv_obj
                iv_text  = 'Template exists already with different values - not changed (update mode is off)' ).
        ENDIF.
      ELSEIF ls_target = ls_db.
        <ls_x>-x_action = 'N'.
      ELSE.
        <ls_x>-x_action = 'U'.
        add_plan( iv_tabname = '/IAM/C_ACTIVTYP' iv_action = 'U' is_data = ls_target
                  iv_sheet   = gc_sheet-templates iv_row = <ls_x>-x_row iv_object = lv_obj ).
        MODIFY TABLE mt_activtyp FROM ls_target.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_template.
    " field rules of SAPLVIEWS: LCL_V_ACTIVTYP (FIELD_MODIFICATION, CHECK_ACTIVTYP,
    " CHECK_ACTTYPE, INITIALIZE_FIELDS, CHECK_ACTIVTYP_DESCRIPTION)
    DATA: ls_acttype TYPE /iam/c_acttype,
          lv_dummy   TYPE string.

    ev_ok = abap_true.

    " activity type
    IF cs_tmpl-acttype IS INITIAL.
      err( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
           iv_text  = 'Activity type (ACTTYPE) is mandatory' ).
      ev_ok = abap_false.
      RETURN.
    ENDIF.
    READ TABLE mt_acttype INTO ls_acttype
         WITH TABLE KEY client = sy-mandt application = cs_tmpl-application acttyp = cs_tmpl-acttype.
    IF sy-subrc <> 0.
      err( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
           iv_text  = |Activity type { cs_tmpl-acttype } is not defined for application { cs_tmpl-application }| ).
      ev_ok = abap_false.
      RETURN.
    ENDIF.
    IF ls_acttype-inactive = abap_true.
      MESSAGE e241(/iam/object) WITH cs_tmpl-acttype INTO lv_dummy.
      mo_log->add_sy( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object ).
      ev_ok = abap_false.
      RETURN.
    ENDIF.

    " MoC: the description is mandatory (msg 150)
    IF cs_tmpl-application = /iam/if_appl_c=>sc_application-moc AND iv_description IS INITIAL AND
       NOT line_exists( mt_activtypt[ client        = sy-mandt
                                      langu         = iv_langu
                                      application   = cs_tmpl-application
                                      activity_type = cs_tmpl-activity_type ] ).
      MESSAGE e150(/iam/config) INTO lv_dummy.
      mo_log->add_sy( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object ).
      ev_ok = abap_false.
    ENDIF.

    " information activities (INITIALIZE_FIELDS)
    IF ls_acttype-act_category = /iam/if_appl_c=>sc_activity_category-information AND
       ( cs_tmpl-response_unit IS NOT INITIAL OR cs_tmpl-act_follow_up    IS NOT INITIAL OR
         cs_tmpl-act_long_term IS NOT INITIAL OR cs_tmpl-auth_group       IS NOT INITIAL OR
         cs_tmpl-duration      IS NOT INITIAL OR cs_tmpl-auto_rule_execut IS NOT INITIAL OR
         cs_tmpl-duration_unit IS NOT INITIAL OR cs_tmpl-response_type    IS NOT INITIAL ).
      CLEAR: cs_tmpl-response_unit, cs_tmpl-act_follow_up, cs_tmpl-act_long_term,
             cs_tmpl-auth_group, cs_tmpl-auto_rule_execut, cs_tmpl-duration,
             cs_tmpl-duration_unit, cs_tmpl-response_type.
      MESSAGE s002(/iam/config_int) INTO lv_dummy.
      mo_log->add_sy( iv_msgty = 'W' iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object ).
    ENDIF.

    " response unit only for quantitative responses (CHECK_ACTIVTYP)
    IF cs_tmpl-response_type <> /iam/if_appl_c=>sc_resp_type_cd-quantitative AND
       cs_tmpl-response_unit IS NOT INITIAL.
      CLEAR cs_tmpl-response_unit.
      warn( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
            iv_text  = 'Response unit is only used for response type Q - removed' ).
    ENDIF.
    IF cs_tmpl-response_type = /iam/if_appl_c=>sc_resp_type_cd-quantitative AND
       cs_tmpl-response_unit IS INITIAL.
      err( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
           iv_text  = 'Response type Q (quantitative) requires a response unit (RESPONSE_UNIT)' ).
      ev_ok = abap_false.
    ENDIF.

    " no follow-up action for information and question activities (FIELD_MODIFICATION)
    IF ( ls_acttype-act_category = /iam/if_appl_c=>sc_activity_category-information OR
         ls_acttype-act_category = /iam/if_appl_c=>sc_activity_category-question ) AND
       ( cs_tmpl-act_follow_up IS NOT INITIAL OR cs_tmpl-follow_up_mode IS NOT INITIAL ).
      CLEAR: cs_tmpl-act_follow_up, cs_tmpl-follow_up_mode.
      warn( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
            iv_text  = |No follow-up action possible for activity category { ls_acttype-act_category } - removed| ).
    ENDIF.

    " MoC: mandatory only for response type C / T, comment mandatory only for T
    IF cs_tmpl-application = /iam/if_appl_c=>sc_application-moc.
      IF cs_tmpl-act_mandatory IS NOT INITIAL AND
         cs_tmpl-response_type <> /iam/if_appl_c=>sc_resp_type_cd-code AND
         cs_tmpl-response_type <> /iam/if_appl_c=>sc_resp_type_cd-tristate.
        CLEAR cs_tmpl-act_mandatory.
        warn( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
              iv_text  = 'MoC: indicator ACT_MANDATORY is only possible for response type C or T - removed' ).
      ENDIF.
      IF cs_tmpl-cmnt_mandatory IS NOT INITIAL AND
         cs_tmpl-response_type <> /iam/if_appl_c=>sc_resp_type_cd-tristate.
        CLEAR cs_tmpl-cmnt_mandatory.
        warn( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
              iv_text  = 'MoC: CMNT_MANDATORY is only possible for response type T - removed' ).
      ENDIF.
      " fields that the MoC view variant /IAM/VV_ACTIVTYP_MOC does not offer
      IF cs_tmpl-auth_group       IS NOT INITIAL OR cs_tmpl-act_long_term  IS NOT INITIAL OR
         cs_tmpl-auto_rule_execut IS NOT INITIAL OR cs_tmpl-follow_up_mode IS NOT INITIAL OR
         cs_tmpl-code             IS NOT INITIAL.
        warn( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
              iv_text  = 'MoC: AUTH_GROUP, ACT_LONG_TERM, AUTO_RULE_EXECUT, FOLLOW_UP_MODE, CODE are not offered in /IAM/VV_ACTIVTYP_MOC' ).
      ENDIF.
    ENDIF.

    " check tables
    IF cs_tmpl-auth_group IS NOT INITIAL AND
       NOT line_exists( mt_authgr[ client = sy-mandt application = cs_tmpl-application auth_group = cs_tmpl-auth_group ] ).
      err( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
           iv_text  = |Authorization group { cs_tmpl-auth_group } is not defined for application { cs_tmpl-application }| ).
      ev_ok = abap_false.
    ENDIF.
    IF cs_tmpl-code IS NOT INITIAL AND NOT line_exists( mt_code[ client = sy-mandt code = cs_tmpl-code ] ).
      err( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
           iv_text  = |Code { cs_tmpl-code } does not exist - create it in worksheet CODES| ).
      ev_ok = abap_false.
    ENDIF.
    IF cs_tmpl-duration > 0 AND cs_tmpl-duration_unit IS INITIAL.
      err( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
           iv_text  = 'A duration requires a duration unit (DURATION_UNIT)' ).
      ev_ok = abap_false.
    ENDIF.
    IF cs_tmpl-act_follow_up IS NOT INITIAL AND
       NOT line_exists( mt_follup[ client = sy-mandt act_follow_up = cs_tmpl-act_follow_up ] ).
      err( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
           iv_text  = |Follow-up action { cs_tmpl-act_follow_up } is not defined (/IAM/I_FOLLUP)| ).
      ev_ok = abap_false.
    ENDIF.
    IF cs_tmpl-act_follow_up IS INITIAL AND cs_tmpl-follow_up_mode IS NOT INITIAL.
      CLEAR cs_tmpl-follow_up_mode.
      warn( iv_sheet = gc_sheet-templates iv_row = iv_row iv_object = iv_object
            iv_text  = 'FOLLOW_UP_MODE without follow-up action - removed' ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Descriptions and long texts (TEMPLATES + TEXTS)
*----------------------------------------------------------------------*
  METHOD plan_texts.
    DATA: ls_req  TYPE ty_text_req,
          lt_seen TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_key  TYPE string,
          lv_obj  TYPE string.
    FIELD-SYMBOLS: <ls_t>  TYPE ty_s_tmpl,
                   <ls_tx> TYPE ty_s_text.

    " language of the worksheet TEMPLATES
    LOOP AT mt_x_tmpl ASSIGNING <ls_t>
         WHERE x_error = abap_false AND ( x_action = 'I' OR x_action = 'U' OR x_action = 'N' ).
      CLEAR ls_req.
      ls_req-application   = <ls_t>-application.
      ls_req-activity_type = <ls_t>-activity_type.
      ls_req-langu         = <ls_t>-langu.
      ls_req-description   = <ls_t>-description.
      ls_req-longtext      = <ls_t>-longtext.
      ls_req-may_update    = abap_true.
      ls_req-sheet         = gc_sheet-templates.
      ls_req-row           = <ls_t>-x_row.
      lv_key = |{ ls_req-application }/{ ls_req-activity_type }/{ ls_req-langu }|.
      INSERT lv_key INTO TABLE lt_seen.
      plan_text_request( ls_req ).
    ENDLOOP.

    " further languages of the worksheet TEXTS
    LOOP AT mt_x_text ASSIGNING <ls_tx> WHERE x_error = abap_false.
      lv_obj = |{ <ls_tx>-application }/{ <ls_tx>-activity_type } { <ls_tx>-langu }|.
      IF check_child_template( iv_appl  = <ls_tx>-application iv_tmpl = <ls_tx>-activity_type
                               iv_sheet = gc_sheet-texts       iv_row  = <ls_tx>-x_row
                               iv_object = lv_obj ) = abap_false.
        <ls_tx>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      lv_key = |{ <ls_tx>-application }/{ <ls_tx>-activity_type }/{ <ls_tx>-langu }|.
      INSERT lv_key INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        err( iv_sheet = gc_sheet-texts iv_row = <ls_tx>-x_row iv_object = lv_obj
             iv_text  = 'Text for this template and language is maintained twice (worksheets TEMPLATES / TEXTS)' ).
        <ls_tx>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      CLEAR ls_req.
      ls_req-application   = <ls_tx>-application.
      ls_req-activity_type = <ls_tx>-activity_type.
      ls_req-langu         = <ls_tx>-langu.
      ls_req-description   = <ls_tx>-description.
      ls_req-longtext      = <ls_tx>-longtext.
      ls_req-may_update    = ms_set-update.
      ls_req-sheet         = gc_sheet-texts.
      ls_req-row           = <ls_tx>-x_row.
      plan_text_request( ls_req ).
    ENDLOOP.
  ENDMETHOD.

  METHOD plan_text_request.
    " SAPLVIEWS: LCL_VIEWS->EXECUTE_FCODE 'MAINT_LONGTEXT' / LCL_V_ACTIVTYP->COPY_LONGTEXT
    DATA: ls_txt_db    TYPE /iam/c_activtypt,
          ls_txt       TYPE /iam/c_activtypt,
          ls_header    TYPE thead,
          lt_lines     TYPE tline_tab,
          lt_old       TYPE tline_tab,
          lv_txt_exist TYPE abap_bool,
          lv_lt_exist  TYPE abap_bool,
          lv_lt_action TYPE c LENGTH 1,
          lv_upper     TYPE string,
          lv_obj       TYPE string,
          lv_dummy     TYPE string.

    lv_obj = |{ is_req-application }/{ is_req-activity_type } { is_req-langu }|.
    READ TABLE mt_activtypt INTO ls_txt_db
         WITH TABLE KEY client        = sy-mandt
                        langu         = is_req-langu
                        application   = is_req-application
                        activity_type = is_req-activity_type.
    lv_txt_exist = xsdbool( sy-subrc = 0 ).
    ls_header    = longtext_header( iv_appl  = is_req-application
                                    iv_tmpl  = is_req-activity_type
                                    iv_langu = is_req-langu ).
    lv_lt_exist  = longtext_exists( ls_header ).

    " ---- long text
    IF is_req-longtext IS NOT INITIAL.
      lv_upper = to_upper( is_req-longtext ).
      IF lv_upper = gc_lt_delete.
        IF lv_lt_exist = abap_true.
          lv_lt_action = 'D'.
        ELSE.
          info( iv_sheet = is_req-sheet iv_row = is_req-row iv_object = lv_obj
                iv_text  = 'No long text exists - nothing to delete' ).
        ENDIF.
      ELSE.
        lt_lines = convert_longtext( iv_text = is_req-longtext iv_langu = is_req-langu ).
        IF lv_lt_exist = abap_true.
          lt_old = read_longtext( ls_header ).
          IF lt_old = lt_lines.
            info( iv_sheet = is_req-sheet iv_row = is_req-row iv_object = lv_obj
                  iv_text  = 'Long text is unchanged' ).
          ELSE.
            lv_lt_action = 'S'.
          ENDIF.
        ELSE.
          lv_lt_action = 'S'.
        ENDIF.
      ENDIF.
      IF lv_lt_action IS NOT INITIAL AND lv_lt_exist = abap_true AND is_req-may_update = abap_false.
        warn( iv_sheet = is_req-sheet iv_row = is_req-row iv_object = lv_obj
              iv_text  = 'Long text exists already - not changed (update mode is off)' ).
        CLEAR lv_lt_action.
      ENDIF.
    ENDIF.

    " ---- description (/IAM/C_ACTIVTYPT)
    IF lv_txt_exist = abap_false.
      IF is_req-description IS INITIAL.
        IF is_req-application = /iam/if_appl_c=>sc_application-moc.
          MESSAGE e150(/iam/config) INTO lv_dummy.
          mo_log->add_sy( iv_sheet = is_req-sheet iv_row = is_req-row iv_object = lv_obj ).
        ELSE.
          err( iv_sheet = is_req-sheet iv_row = is_req-row iv_object = lv_obj
               iv_text  = 'Description (DESCRIPTION) is mandatory for a new language' ).
        ENDIF.
        RETURN.
      ENDIF.
      CLEAR ls_txt.
      ls_txt-client        = sy-mandt.
      ls_txt-langu         = is_req-langu.
      ls_txt-application   = is_req-application.
      ls_txt-activity_type = is_req-activity_type.
      ls_txt-description   = is_req-description.
      ls_txt-longtext_ind  = lv_lt_exist.
    ELSE.
      ls_txt = ls_txt_db.
      IF is_req-description IS NOT INITIAL AND is_req-description <> ls_txt_db-description.
        IF is_req-may_update = abap_true.
          ls_txt-description = is_req-description.
        ELSE.
          warn( iv_sheet = is_req-sheet iv_row = is_req-row iv_object = lv_obj
                iv_text  = |Description "{ ls_txt_db-description }" exists already - not changed (update mode is off)| ).
        ENDIF.
      ENDIF.
    ENDIF.

    " long text indicator (LONGTEXT_IND = long text with content exists)
    CASE lv_lt_action.
      WHEN 'S'.
        ls_txt-longtext_ind = abap_true.
      WHEN 'D'.
        ls_txt-longtext_ind = abap_false.
      WHEN OTHERS.
    ENDCASE.

    IF lv_txt_exist = abap_false.
      add_plan( iv_tabname = '/IAM/C_ACTIVTYPT' iv_action = 'I' is_data = ls_txt
                iv_sheet   = is_req-sheet iv_row = is_req-row iv_object = lv_obj ).
      INSERT ls_txt INTO TABLE mt_activtypt.
    ELSEIF ls_txt <> ls_txt_db.
      add_plan( iv_tabname = '/IAM/C_ACTIVTYPT' iv_action = 'U' is_data = ls_txt
                iv_sheet   = is_req-sheet iv_row = is_req-row iv_object = lv_obj ).
      MODIFY TABLE mt_activtypt FROM ls_txt.
    ENDIF.

    IF lv_lt_action IS NOT INITIAL.
      add_ltplan( is_header = ls_header
                  iv_action = lv_lt_action
                  it_lines  = lt_lines
                  iv_sheet  = is_req-sheet
                  iv_row    = is_req-row
                  iv_object = lv_obj ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Worksheet HIERARCHY - sub-activity templates (/IAM/V_ACT_ACT)
*----------------------------------------------------------------------*
  METHOD plan_hierarchy.
    DATA: lt_new     TYPE STANDARD TABLE OF /iam/c_act_act WITH EMPTY KEY,
          lt_rows    TYPE tt_int,
          ls_new     TYPE /iam/c_act_act,
          ls_aa      TYPE /iam/c_act_act,
          ls_edge    TYPE ty_edge,
          lt_seen    TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lt_parents TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_key     TYPE string,
          lv_obj     TYPE string,
          lv_dummy   TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_hier.

    IF mt_x_hier IS INITIAL.
      RETURN.
    ENDIF.

    " ---- row checks
    LOOP AT mt_x_hier ASSIGNING <ls_x> WHERE x_error = abap_false.
      lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type } -> { <ls_x>-sub_act_type }|.
      IF appl_ok( iv_appl = <ls_x>-application iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-activity_type IS INITIAL OR <ls_x>-sub_act_type IS INITIAL.
        err( iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Parent template (ACTIVITY_TYPE) and sub-template (SUB_ACT_TYPE) are mandatory' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF template_exists( iv_appl = <ls_x>-application iv_tmpl = <ls_x>-activity_type ) = abap_false.
        err( iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = |Parent template { <ls_x>-activity_type } does not exist (neither in the system nor in worksheet TEMPLATES)| ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF template_exists( iv_appl = <ls_x>-application iv_tmpl = <ls_x>-sub_act_type ) = abap_false.
        err( iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = |Sub-template { <ls_x>-sub_act_type } does not exist (neither in the system nor in worksheet TEMPLATES)| ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      " SAPLVIEWS: CHECK_SUB_ACT_RECURSION - parent and child identical
      IF <ls_x>-activity_type = <ls_x>-sub_act_type.
        MESSAGE e019(/iam/config) INTO lv_dummy.
        mo_log->add_sy( iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row iv_object = lv_obj ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      lv_key = |{ <ls_x>-application }/{ <ls_x>-activity_type }/{ <ls_x>-sub_act_type }|.
      INSERT lv_key INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        err( iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Assignment is contained more than once in the worksheet' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-application = /iam/if_appl_c=>sc_application-moc AND <ls_x>-proposal_ind = abap_true.
        warn( iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row iv_object = lv_obj
              iv_text  = 'MoC: PROPOSAL_IND is not offered in view /IAM/VV_ACT_ACT_MOC' ).
      ENDIF.
      lv_key = |{ <ls_x>-application }/{ <ls_x>-activity_type }|.
      INSERT lv_key INTO TABLE lt_parents.
    ENDLOOP.

    " ---- SAPLVIEWS: CHECK_SUB_ACT_RECURSION on the resulting hierarchy
    CLEAR mt_edges.
    LOOP AT mt_act_act INTO ls_aa.
      lv_key = |{ ls_aa-application }/{ ls_aa-activity_type }|.
      IF ms_set-replace = abap_true AND line_exists( lt_parents[ table_line = lv_key ] ).
        CONTINUE.                                   " will be replaced by the worksheet
      ENDIF.
      ls_edge-appl   = ls_aa-application.
      ls_edge-parent = ls_aa-activity_type.
      ls_edge-child  = ls_aa-sub_act_type.
      INSERT ls_edge INTO TABLE mt_edges.
    ENDLOOP.
    LOOP AT mt_x_hier ASSIGNING <ls_x> WHERE x_error = abap_false.
      ls_edge-appl   = <ls_x>-application.
      ls_edge-parent = <ls_x>-activity_type.
      ls_edge-child  = <ls_x>-sub_act_type.
      INSERT ls_edge INTO TABLE mt_edges.
    ENDLOOP.
    LOOP AT mt_x_hier ASSIGNING <ls_x> WHERE x_error = abap_false.
      IF is_reachable( iv_appl = <ls_x>-application
                       iv_from = <ls_x>-sub_act_type
                       iv_to   = <ls_x>-activity_type ) = abap_true.
        lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type } -> { <ls_x>-sub_act_type }|.
        MESSAGE e019(/iam/config) INTO lv_dummy.
        mo_log->add_sy( iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row iv_object = lv_obj ).
        <ls_x>-x_error = abap_true.
      ENDIF.
    ENDLOOP.

    " ---- plan /IAM/C_ACT_ACT (internal number per parent)
    LOOP AT mt_x_hier ASSIGNING <ls_x> WHERE x_error = abap_false.
      CLEAR ls_new.
      ls_new        = CORRESPONDING #( <ls_x> ).
      ls_new-client = sy-mandt.
      APPEND ls_new TO lt_new.
      APPEND <ls_x>-x_row TO lt_rows.
    ENDLOOP.
    plan_child_table( EXPORTING iv_tabname    = '/IAM/C_ACT_ACT'
                                iv_sheet      = gc_sheet-hierarchy
                                iv_tmpl_field = 'ACTIVITY_TYPE'
                                iv_num_field  = 'INT_NUMBER'
                                iv_bkey       = `SUB_ACT_TYPE`
                                it_fields     = mt_f_hier
                                it_new        = lt_new
                                it_rows       = lt_rows
                      CHANGING  ct_db         = mt_act_act ).

    check_sort_numbers( ).
  ENDMETHOD.

  METHOD check_sort_numbers.
    " SAPLVIEWS: CHECK_SORT_NO - sort number unique below a parent template
    DATA: ls_aa    TYPE /iam/c_act_act,
          lv_count TYPE i,
          lv_obj   TYPE string,
          lv_dummy TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_hier.

    LOOP AT mt_x_hier ASSIGNING <ls_x> WHERE x_error = abap_false AND sort_no IS NOT INITIAL.
      lv_count = 0.
      LOOP AT mt_act_act INTO ls_aa WHERE application   = <ls_x>-application
                                      AND activity_type = <ls_x>-activity_type
                                      AND sort_no       = <ls_x>-sort_no.
        lv_count = lv_count + 1.
      ENDLOOP.
      IF lv_count > 1.
        lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type } -> { <ls_x>-sub_act_type }|.
        MESSAGE e013(/iam/config) WITH <ls_x>-sort_no INTO lv_dummy.
        mo_log->add_sy( iv_sheet = gc_sheet-hierarchy iv_row = <ls_x>-x_row iv_object = lv_obj ).
        <ls_x>-x_error = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_reachable.
    DATA: lt_stack   TYPE STANDARD TABLE OF /iam/act_template WITH EMPTY KEY,
          lt_visited TYPE SORTED TABLE OF /iam/act_template WITH UNIQUE KEY table_line,
          lv_node    TYPE /iam/act_template,
          lv_lines   TYPE i,
          ls_edge    TYPE ty_edge.

    APPEND iv_from TO lt_stack.
    WHILE lt_stack IS NOT INITIAL.
      lv_lines = lines( lt_stack ).
      READ TABLE lt_stack INTO lv_node INDEX lv_lines.
      DELETE lt_stack INDEX lv_lines.
      IF lv_node = iv_to.
        rv_found = abap_true.
        RETURN.
      ENDIF.
      INSERT lv_node INTO TABLE lt_visited.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      LOOP AT mt_edges INTO ls_edge WHERE appl = iv_appl AND parent = lv_node.
        APPEND ls_edge-child TO lt_stack.
      ENDLOOP.
    ENDWHILE.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Worksheet CODEGROUPS - code groups of the template (/IAM/V_ACT_CDGR)
*----------------------------------------------------------------------*
  METHOD plan_codegroups.
    DATA: lt_new   TYPE STANDARD TABLE OF /iam/c_act_cdgr WITH EMPTY KEY,
          lt_rows  TYPE tt_int,
          ls_new   TYPE /iam/c_act_cdgr,
          ls_tmpl  TYPE /iam/c_activtyp,
          lt_seen  TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_key   TYPE string,
          lv_obj   TYPE string,
          lv_dummy TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_cdgr.

    LOOP AT mt_x_cdgr ASSIGNING <ls_x> WHERE x_error = abap_false.
      IF <ls_x>-text_type_code IS INITIAL.
        <ls_x>-text_type_code = /iam/if_appl_c=>sc_text_type-act_response.   " ARESP
      ENDIF.
      lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type } { <ls_x>-text_type_code } { <ls_x>-codegroup }|.
      IF check_child_template( iv_appl  = <ls_x>-application iv_tmpl = <ls_x>-activity_type
                               iv_sheet = gc_sheet-codegroups iv_row = <ls_x>-x_row
                               iv_object = lv_obj ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-codegroup IS INITIAL.
        err( iv_sheet = gc_sheet-codegroups iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Code group (CODEGROUP) is mandatory' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      " SAPLVIEWS: LCL_V_ACT_CDGR->FILL_RESPONSE_CDGR (msg 039)
      IF NOT line_exists( mt_codegr[ client = sy-mandt codegroup = <ls_x>-codegroup ] ).
        MESSAGE e039(/iam/config) WITH <ls_x>-codegroup INTO lv_dummy.
        mo_log->add_sy( iv_sheet = gc_sheet-codegroups iv_row = <ls_x>-x_row iv_object = lv_obj ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-code IS NOT INITIAL AND
         NOT line_exists( mt_code_rel[ client = sy-mandt codegroup = <ls_x>-codegroup code = <ls_x>-code ] ).
        err( iv_sheet = gc_sheet-codegroups iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = |Default code { <ls_x>-code } is not assigned to code group { <ls_x>-codegroup }| ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-application = /iam/if_appl_c=>sc_application-moc AND <ls_x>-code IS NOT INITIAL.
        warn( iv_sheet = gc_sheet-codegroups iv_row = <ls_x>-x_row iv_object = lv_obj
              iv_text  = 'MoC: a default code is not offered in view /IAM/VV_ACT_CDGR_MOC' ).
      ENDIF.
      lv_key = lv_obj.
      INSERT lv_key INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        err( iv_sheet = gc_sheet-codegroups iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Entry is contained more than once in the worksheet' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      " SAPLVIEWS: LCL_V_ACT_CDGR->CHECK_NEW_TEXT_TYPE (msg 135)
      READ TABLE mt_activtyp INTO ls_tmpl
           WITH TABLE KEY client = sy-mandt application = <ls_x>-application activity_type = <ls_x>-activity_type.
      IF ls_tmpl-response_type <> /iam/if_appl_c=>sc_resp_type_cd-code AND
         ( <ls_x>-text_type_code = /iam/if_appl_c=>sc_text_type-act_response OR
           <ls_x>-application    = /iam/if_appl_c=>sc_application-moc ).
        MESSAGE w135(/iam/config) WITH <ls_x>-activity_type INTO lv_dummy.
        mo_log->add_sy( iv_msgty = 'W' iv_sheet = gc_sheet-codegroups iv_row = <ls_x>-x_row iv_object = lv_obj ).
      ENDIF.

      CLEAR ls_new.
      ls_new        = CORRESPONDING #( <ls_x> ).
      ls_new-client = sy-mandt.
      APPEND ls_new TO lt_new.
      APPEND <ls_x>-x_row TO lt_rows.
    ENDLOOP.
    plan_child_table( EXPORTING iv_tabname    = '/IAM/C_ACT_CDGR'
                                iv_sheet      = gc_sheet-codegroups
                                iv_tmpl_field = 'ACTIVITY_TYPE'
                                iv_num_field  = 'INT_NUMBER'
                                iv_bkey       = `TEXT_TYPE_CODE CODEGROUP`
                                it_fields     = mt_f_cdgr
                                it_new        = lt_new
                                it_rows       = lt_rows
                      CHANGING  ct_db         = mt_act_cdgr ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Worksheet REFOBJECTS - reference object types (/IAM/V_ACT_REFOB)
*----------------------------------------------------------------------*
  METHOD plan_refobjects.
    DATA: lt_new  TYPE STANDARD TABLE OF /iam/c_act_refob WITH EMPTY KEY,
          lt_rows TYPE tt_int,
          ls_new  TYPE /iam/c_act_refob,
          lt_seen TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_key  TYPE string,
          lv_obj  TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_refob.

    LOOP AT mt_x_refob ASSIGNING <ls_x> WHERE x_error = abap_false.
      lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type } { <ls_x>-ref_obj_type }|.
      IF check_child_template( iv_appl  = <ls_x>-application iv_tmpl = <ls_x>-activity_type
                               iv_sheet = gc_sheet-refobjects iv_row = <ls_x>-x_row
                               iv_object = lv_obj ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-ref_obj_type IS INITIAL OR
         NOT line_exists( mt_i_type[ client = sy-mandt type = <ls_x>-ref_obj_type ] ).
        err( iv_sheet = gc_sheet-refobjects iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = |Object type "{ <ls_x>-ref_obj_type }" is not defined (/IAM/I_TYPE)| ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      lv_key = lv_obj.
      INSERT lv_key INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        err( iv_sheet = gc_sheet-refobjects iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Entry is contained more than once in the worksheet' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      CLEAR ls_new.
      ls_new-client       = sy-mandt.
      ls_new-application  = <ls_x>-application.
      ls_new-act_template = <ls_x>-activity_type.
      ls_new-ref_obj_type = <ls_x>-ref_obj_type.
      ls_new-inactive     = <ls_x>-inactive.
      APPEND ls_new TO lt_new.
      APPEND <ls_x>-x_row TO lt_rows.
    ENDLOOP.
    plan_child_table( EXPORTING iv_tabname    = '/IAM/C_ACT_REFOB'
                                iv_sheet      = gc_sheet-refobjects
                                iv_tmpl_field = 'ACT_TEMPLATE'
                                iv_num_field  = 'INT_NUMBER'
                                iv_bkey       = `REF_OBJ_TYPE`
                                it_fields     = mt_f_refob
                                it_new        = lt_new
                                it_rows       = lt_rows
                      CHANGING  ct_db         = mt_act_refob ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Worksheet FOAPARAMS - parameters of the follow-up action (/IAM/V_ACT_PARA)
*----------------------------------------------------------------------*
  METHOD plan_foaparams.
    DATA: lt_new  TYPE STANDARD TABLE OF /iam/c_act_para WITH EMPTY KEY,
          lt_rows TYPE tt_int,
          ls_new  TYPE /iam/c_act_para,
          ls_tmpl TYPE /iam/c_activtyp,
          lt_seen TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_key  TYPE string,
          lv_obj  TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_para.

    LOOP AT mt_x_para ASSIGNING <ls_x> WHERE x_error = abap_false.
      lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type } { <ls_x>-foa_param_id }|.
      IF check_child_template( iv_appl  = <ls_x>-application iv_tmpl = <ls_x>-activity_type
                               iv_sheet = gc_sheet-foaparams iv_row = <ls_x>-x_row
                               iv_object = lv_obj ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-foa_param_id IS INITIAL.
        err( iv_sheet = gc_sheet-foaparams iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Parameter ID (FOA_PARAM_ID) is mandatory' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      lv_key = lv_obj.
      INSERT lv_key INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        err( iv_sheet = gc_sheet-foaparams iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Parameter is contained more than once in the worksheet' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      READ TABLE mt_activtyp INTO ls_tmpl
           WITH TABLE KEY client = sy-mandt application = <ls_x>-application activity_type = <ls_x>-activity_type.
      IF ls_tmpl-act_follow_up IS INITIAL.
        warn( iv_sheet = gc_sheet-foaparams iv_row = <ls_x>-x_row iv_object = lv_obj
              iv_text  = 'The template has no follow-up action (ACT_FOLLOW_UP) - parameter is not evaluated' ).
      ENDIF.
      CLEAR ls_new.
      ls_new-client          = sy-mandt.
      ls_new-application     = <ls_x>-application.
      ls_new-act_template    = <ls_x>-activity_type.
      ls_new-foa_param_id    = <ls_x>-foa_param_id.
      ls_new-foa_param_value = <ls_x>-foa_param_value.
      APPEND ls_new TO lt_new.
      APPEND <ls_x>-x_row TO lt_rows.
    ENDLOOP.
    plan_child_table( EXPORTING iv_tabname    = '/IAM/C_ACT_PARA'
                                iv_sheet      = gc_sheet-foaparams
                                iv_tmpl_field = 'ACT_TEMPLATE'
                                iv_num_field  = 'INT_NUMBER'
                                iv_bkey       = `FOA_PARAM_ID`
                                it_fields     = mt_f_para
                                it_new        = lt_new
                                it_rows       = lt_rows
                      CHANGING  ct_db         = mt_act_para ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Worksheet DIGSIG - digital signature (/IAM/V_ACT_DS)
*----------------------------------------------------------------------*
  METHOD plan_digsig.
    DATA: lt_new   TYPE STANDARD TABLE OF /iam/c_act_ds WITH EMPTY KEY,
          lt_rows  TYPE tt_int,
          ls_new   TYPE /iam/c_act_ds,
          lt_seen  TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_strat TYPE tc85-signstrat,
          lv_key   TYPE string,
          lv_obj   TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_ds.

    LOOP AT mt_x_ds ASSIGNING <ls_x> WHERE x_error = abap_false.
      TRANSLATE <ls_x>-action_alias TO UPPER CASE.
      lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type } { <ls_x>-action_alias }|.
      IF check_child_template( iv_appl  = <ls_x>-application iv_tmpl = <ls_x>-activity_type
                               iv_sheet = gc_sheet-digsig iv_row = <ls_x>-x_row
                               iv_object = lv_obj ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      READ TABLE mt_i_a_act TRANSPORTING NO FIELDS
           WITH KEY application = <ls_x>-application action_alias = <ls_x>-action_alias.
      IF <ls_x>-action_alias IS INITIAL OR sy-subrc <> 0.
        err( iv_sheet = gc_sheet-digsig iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = |Action "{ <ls_x>-action_alias }" is not defined for application { <ls_x>-application } (/IAM/I_A_ACT)| ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-sign_strat IS NOT INITIAL.
        SELECT SINGLE signstrat FROM tc85 INTO lv_strat WHERE signstrat = <ls_x>-sign_strat.
        IF sy-subrc <> 0.
          err( iv_sheet = gc_sheet-digsig iv_row = <ls_x>-x_row iv_object = lv_obj
               iv_text  = |Signature strategy { <ls_x>-sign_strat } is not defined (TC85)| ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
      ENDIF.
      lv_key = lv_obj.
      INSERT lv_key INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        err( iv_sheet = gc_sheet-digsig iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Entry is contained more than once in the worksheet' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      CLEAR ls_new.
      ls_new        = CORRESPONDING #( <ls_x> ).
      ls_new-client = sy-mandt.
      APPEND ls_new TO lt_new.
      APPEND <ls_x>-x_row TO lt_rows.
    ENDLOOP.
    plan_child_table( EXPORTING iv_tabname    = '/IAM/C_ACT_DS'
                                iv_sheet      = gc_sheet-digsig
                                iv_tmpl_field = 'ACTIVITY_TYPE'
                                iv_num_field  = ''
                                iv_bkey       = `ACTION_ALIAS`
                                it_fields     = mt_f_ds
                                it_new        = lt_new
                                it_rows       = lt_rows
                      CHANGING  ct_db         = mt_act_ds ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Worksheet PARTNERS - default partners (/IAM/V_ACTPTY_MD, master data)
*----------------------------------------------------------------------*
  METHOD plan_partners.
    DATA: lt_new     TYPE STANDARD TABLE OF /iam/d_actpty_md WITH EMPTY KEY,
          lt_rows    TYPE tt_int,
          ls_new     TYPE /iam/d_actpty_md,
          lt_seen    TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_partner TYPE bu_partner,
          lv_key     TYPE string,
          lv_obj     TYPE string.
    FIELD-SYMBOLS <ls_x> TYPE ty_s_pty.

    LOOP AT mt_x_pty ASSIGNING <ls_x> WHERE x_error = abap_false.
      lv_obj = |{ <ls_x>-application }/{ <ls_x>-activity_type } { <ls_x>-party_role_code } { <ls_x>-bu_partner } { <ls_x>-party_position }|.
      IF check_child_template( iv_appl  = <ls_x>-application iv_tmpl = <ls_x>-activity_type
                               iv_sheet = gc_sheet-partners iv_row = <ls_x>-x_row
                               iv_object = lv_obj ) = abap_false.
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-party_role_code IS INITIAL OR
         NOT line_exists( mt_role_cd[ client = sy-mandt application = <ls_x>-application party_role_code = <ls_x>-party_role_code ] ).
        err( iv_sheet = gc_sheet-partners iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = |Partner role "{ <ls_x>-party_role_code }" is not defined for application { <ls_x>-application }| ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-bu_partner IS INITIAL AND <ls_x>-party_position IS INITIAL.
        err( iv_sheet = gc_sheet-partners iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Enter a business partner (BU_PARTNER) or a position (PARTY_POSITION)' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-bu_partner IS NOT INITIAL.
        SELECT SINGLE partner FROM but000 INTO lv_partner WHERE partner = <ls_x>-bu_partner.
        IF sy-subrc <> 0.
          err( iv_sheet = gc_sheet-partners iv_row = <ls_x>-x_row iv_object = lv_obj
               iv_text  = |Business partner { <ls_x>-bu_partner } does not exist| ).
          <ls_x>-x_error = abap_true.
          CONTINUE.
        ENDIF.
      ENDIF.
      lv_key = lv_obj.
      INSERT lv_key INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        err( iv_sheet = gc_sheet-partners iv_row = <ls_x>-x_row iv_object = lv_obj
             iv_text  = 'Entry is contained more than once in the worksheet' ).
        <ls_x>-x_error = abap_true.
        CONTINUE.
      ENDIF.
      IF <ls_x>-application <> /iam/if_appl_c=>sc_application-qim.
        warn( iv_sheet = gc_sheet-partners iv_row = <ls_x>-x_row iv_object = lv_obj
              iv_text  = 'Default partners per activity template are only offered for QIM in the view maintenance' ).
      ENDIF.
      CLEAR ls_new.
      ls_new        = CORRESPONDING #( <ls_x> ).
      ls_new-client = sy-mandt.
      APPEND ls_new TO lt_new.
      APPEND <ls_x>-x_row TO lt_rows.
    ENDLOOP.
    plan_child_table( EXPORTING iv_tabname    = gc_tab_partner
                                iv_sheet      = gc_sheet-partners
                                iv_tmpl_field = 'ACTIVITY_TYPE'
                                iv_num_field  = 'INT_NUMBER'
                                iv_bkey       = `PARTY_ROLE_CODE BU_PARTNER PARTY_POSITION`
                                it_fields     = mt_f_pty
                                it_new        = lt_new
                                it_rows       = lt_rows
                      CHANGING  ct_db         = mt_actpty_md ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Generic: assignment tables of a template with internal number
* (INT_NUMBER = next free number per template, like EVENT_01_SAVE_RESP_CDGR)
*----------------------------------------------------------------------*
  METHOD plan_child_table.
    TYPES: BEGIN OF lty_tkey,
             appl   TYPE /iam/application,
             tmpl   TYPE /iam/act_template,
             maxnum TYPE i,
           END OF lty_tkey.
    DATA: lt_tkey  TYPE SORTED TABLE OF lty_tkey WITH UNIQUE KEY appl tmpl,
          ls_tkey  TYPE lty_tkey,
          lt_bkey  TYPE string_table,
          lt_cmp   TYPE string_table,
          lt_keep  TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lt_del   TYPE STANDARD TABLE OF REF TO data WITH EMPTY KEY,
          lr_row   TYPE REF TO data,
          lr_tgt   TYPE REF TO data,
          lr_del   TYPE REF TO data,
          lv_idx   TYPE i,
          lv_row   TYPE i,
          lv_num   TYPE i,
          lv_key   TYPE string,
          lv_obj   TYPE string.
    FIELD-SYMBOLS: <ls_new>   TYPE any,
                   <ls_row>   TYPE any,
                   <ls_tgt>   TYPE any,
                   <ls_db>    TYPE any,
                   <ls_match> TYPE any,
                   <ls_del>   TYPE any,
                   <lv_num>   TYPE any,
                   <lv_dbnum> TYPE any,
                   <ls_tkey>  TYPE lty_tkey.

    IF it_new IS INITIAL.
      RETURN.
    ENDIF.

    SPLIT iv_bkey AT space INTO TABLE lt_bkey.
    DELETE lt_bkey WHERE table_line IS INITIAL.
    APPEND 'APPLICATION' TO lt_cmp.
    APPEND iv_tmpl_field TO lt_cmp.
    APPEND LINES OF lt_bkey TO lt_cmp.

    " templates of the worksheet and highest internal number in use
    LOOP AT it_new ASSIGNING <ls_new>.
      ls_tkey-appl   = lcl_util=>get_comp( is_data = <ls_new> iv_name = 'APPLICATION' ).
      ls_tkey-tmpl   = lcl_util=>get_comp( is_data = <ls_new> iv_name = iv_tmpl_field ).
      ls_tkey-maxnum = 0.
      INSERT ls_tkey INTO TABLE lt_tkey.
    ENDLOOP.
    IF iv_num_field IS NOT INITIAL.
      LOOP AT ct_db ASSIGNING <ls_db>.
        ls_tkey-appl = lcl_util=>get_comp( is_data = <ls_db> iv_name = 'APPLICATION' ).
        ls_tkey-tmpl = lcl_util=>get_comp( is_data = <ls_db> iv_name = iv_tmpl_field ).
        READ TABLE lt_tkey ASSIGNING <ls_tkey> WITH TABLE KEY appl = ls_tkey-appl tmpl = ls_tkey-tmpl.
        IF sy-subrc = 0.
          lv_num = lcl_util=>get_comp( is_data = <ls_db> iv_name = iv_num_field ).
          IF lv_num > <ls_tkey>-maxnum.
            <ls_tkey>-maxnum = lv_num.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " compare with the existing entries (same business key -> same internal number)
    LOOP AT it_new ASSIGNING <ls_new>.
      lv_idx = sy-tabix.
      READ TABLE it_rows INTO lv_row INDEX lv_idx.
      CREATE DATA lr_row LIKE <ls_new>.
      ASSIGN lr_row->* TO <ls_row>.
      <ls_row> = <ls_new>.
      lv_obj = describe( is_data = <ls_row> it_fields = lt_cmp ).

      UNASSIGN <ls_match>.
      LOOP AT ct_db ASSIGNING <ls_db>.
        IF lcl_util=>same_values( is_a = <ls_row> is_b = <ls_db> it_fields = lt_cmp ) = abap_true.
          lv_key = build_tabkey( iv_tabname = iv_tabname is_data = <ls_db> ).
          IF NOT line_exists( lt_keep[ table_line = lv_key ] ).
            ASSIGN <ls_db> TO <ls_match>.
            EXIT.
          ENDIF.
        ENDIF.
      ENDLOOP.

      IF <ls_match> IS ASSIGNED.
        IF iv_num_field IS NOT INITIAL.
          ASSIGN COMPONENT iv_num_field OF STRUCTURE <ls_row> TO <lv_num>.
          ASSIGN COMPONENT iv_num_field OF STRUCTURE <ls_match> TO <lv_dbnum>.
          <lv_num> = <lv_dbnum>.
        ENDIF.
        " only the columns of the worksheet are changed
        CREATE DATA lr_tgt LIKE <ls_new>.
        ASSIGN lr_tgt->* TO <ls_tgt>.
        <ls_tgt> = <ls_match>.
        lcl_util=>merge_fields( EXPORTING is_source = <ls_row>
                                          it_fields = it_fields
                                CHANGING  cs_target = <ls_tgt> ).
        lv_key = build_tabkey( iv_tabname = iv_tabname is_data = <ls_tgt> ).
        INSERT lv_key INTO TABLE lt_keep.
        IF <ls_tgt> = <ls_match>.
          info( iv_sheet = iv_sheet iv_row = lv_row iv_object = lv_obj
                iv_text  = 'Entry exists already and is unchanged' ).
        ELSEIF ms_set-update = abap_true OR ms_set-replace = abap_true.
          add_plan( iv_tabname = iv_tabname iv_action = 'U' is_data = <ls_tgt>
                    iv_sheet   = iv_sheet   iv_row    = lv_row iv_object = lv_obj ).
          MODIFY TABLE ct_db FROM <ls_tgt>.
        ELSE.
          warn( iv_sheet = iv_sheet iv_row = lv_row iv_object = lv_obj
                iv_text  = 'Entry exists already with different values - not changed (update mode is off)' ).
        ENDIF.
      ELSE.
        IF iv_num_field IS NOT INITIAL.
          ls_tkey-appl = lcl_util=>get_comp( is_data = <ls_row> iv_name = 'APPLICATION' ).
          ls_tkey-tmpl = lcl_util=>get_comp( is_data = <ls_row> iv_name = iv_tmpl_field ).
          READ TABLE lt_tkey ASSIGNING <ls_tkey> WITH TABLE KEY appl = ls_tkey-appl tmpl = ls_tkey-tmpl.
          IF sy-subrc <> 0.
            CONTINUE.
          ENDIF.
          <ls_tkey>-maxnum = <ls_tkey>-maxnum + 1.
          IF <ls_tkey>-maxnum > 999.
            err( iv_sheet = iv_sheet iv_row = lv_row iv_object = lv_obj
                 iv_text  = 'More than 999 entries per template are not possible' ).
            CONTINUE.
          ENDIF.
          ASSIGN COMPONENT iv_num_field OF STRUCTURE <ls_row> TO <lv_num>.
          <lv_num> = <ls_tkey>-maxnum.
        ENDIF.
        INSERT <ls_row> INTO TABLE ct_db.
        IF sy-subrc <> 0.
          err( iv_sheet = iv_sheet iv_row = lv_row iv_object = lv_obj
               iv_text  = 'Entry exists already (duplicate key)' ).
          CONTINUE.
        ENDIF.
        lv_key = build_tabkey( iv_tabname = iv_tabname is_data = <ls_row> ).
        INSERT lv_key INTO TABLE lt_keep.
        add_plan( iv_tabname = iv_tabname iv_action = 'I' is_data = <ls_row>
                  iv_sheet   = iv_sheet   iv_row    = lv_row iv_object = lv_obj ).
      ENDIF.
    ENDLOOP.

    " replace mode: entries of the uploaded templates that are not in the worksheet
    IF ms_set-replace = abap_true.
      LOOP AT ct_db ASSIGNING <ls_db>.
        ls_tkey-appl = lcl_util=>get_comp( is_data = <ls_db> iv_name = 'APPLICATION' ).
        ls_tkey-tmpl = lcl_util=>get_comp( is_data = <ls_db> iv_name = iv_tmpl_field ).
        IF NOT line_exists( lt_tkey[ appl = ls_tkey-appl tmpl = ls_tkey-tmpl ] ).
          CONTINUE.
        ENDIF.
        lv_key = build_tabkey( iv_tabname = iv_tabname is_data = <ls_db> ).
        IF line_exists( lt_keep[ table_line = lv_key ] ).
          CONTINUE.
        ENDIF.
        CREATE DATA lr_del LIKE <ls_db>.
        ASSIGN lr_del->* TO <ls_del>.
        <ls_del> = <ls_db>.
        APPEND lr_del TO lt_del.
      ENDLOOP.
      LOOP AT lt_del INTO lr_del.
        ASSIGN lr_del->* TO <ls_del>.
        lv_obj = describe( is_data = <ls_del> it_fields = lt_cmp ).
        warn( iv_sheet = iv_sheet iv_object = lv_obj
              iv_text  = 'Entry is not contained in the worksheet and is deleted (replace mode)' ).
        add_plan( iv_tabname = iv_tabname iv_action = 'D' is_data = <ls_del>
                  iv_sheet   = iv_sheet   iv_object = lv_obj ).
        DELETE TABLE ct_db FROM <ls_del>.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Final checks, authority, transport, summary
*----------------------------------------------------------------------*
  METHOD final_checks.
    DATA: ls_tmpl TYPE /iam/c_activtyp,
          lv_obj  TYPE string,
          lv_cdgr TYPE abap_bool.
    FIELD-SYMBOLS: <ls_t>    TYPE ty_s_tmpl,
                   <ls_cdgr> TYPE /iam/c_act_cdgr.

    " response type code without code group
    LOOP AT mt_x_tmpl ASSIGNING <ls_t> WHERE x_error = abap_false AND ( x_action = 'I' OR x_action = 'U' ).
      READ TABLE mt_activtyp INTO ls_tmpl
           WITH TABLE KEY client = sy-mandt application = <ls_t>-application activity_type = <ls_t>-activity_type.
      IF sy-subrc <> 0 OR ls_tmpl-response_type <> /iam/if_appl_c=>sc_resp_type_cd-code.
        CONTINUE.
      ENDIF.
      lv_cdgr = abap_false.
      LOOP AT mt_act_cdgr ASSIGNING <ls_cdgr> WHERE application   = ls_tmpl-application
                                               AND activity_type = ls_tmpl-activity_type
                                               AND inactive      = abap_false.
        lv_cdgr = abap_true.
        EXIT.
      ENDLOOP.
      IF lv_cdgr = abap_false.
        lv_obj = |{ <ls_t>-application }/{ <ls_t>-activity_type }|.
        warn( iv_sheet = gc_sheet-templates iv_row = <ls_t>-x_row iv_object = lv_obj
              iv_text  = 'Response type C (code), but no code group is assigned (worksheet CODEGROUPS)' ).
      ENDIF.
    ENDLOOP.

    IF line_exists( mt_plan[ tabname = gc_tab_partner ] ).
      warn( iv_text = 'Default partners (/IAM/D_ACTPTY_MD) are master data: not recorded in the transport request, upload them in every client' ).
    ENDIF.
  ENDMETHOD.

  METHOD check_authority.
    " authorization of the view maintenance (S_TABU_DIS / S_TABU_NAM): the
    " general view or - for MoC - the MoC view variant must be maintainable
    DATA: lt_checks TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lt_views  TYPE string_table,
          lv_views  TYPE string,
          lv_view   TYPE tabname,
          lv_name   TYPE string,
          lv_ok     TYPE abap_bool.
    FIELD-SYMBOLS <ls_plan> TYPE ty_plan.

    LOOP AT mt_plan ASSIGNING <ls_plan> WHERE action <> '-'.
      CASE <ls_plan>-tabname.
        WHEN '/IAM/C_ACTIVTYP' OR '/IAM/C_ACTIVTYPT'.
          lv_views = `/IAM/V_ACTIVTYP /IAM/VV_ACTIVTYP_MOC`.
        WHEN '/IAM/C_ACT_ACT'.
          lv_views = `/IAM/V_ACT_ACT /IAM/VV_ACT_ACT_MOC`.
        WHEN '/IAM/C_ACT_CDGR'.
          lv_views = `/IAM/V_ACT_CDGR /IAM/VV_ACT_CDGR_MOC`.
        WHEN '/IAM/C_ACT_DS'.
          lv_views = `/IAM/V_ACT_DS /IAM/VV_ACT_DS_MOC`.
        WHEN '/IAM/C_ACT_REFOB'.
          lv_views = `/IAM/V_ACT_REFOB`.
        WHEN '/IAM/C_ACT_PARA'.
          lv_views = `/IAM/V_ACT_PARA`.
        WHEN '/IAM/D_ACTPTY_MD'.
          lv_views = `/IAM/V_ACTPTY_MD`.
        WHEN '/IAM/C_CATALOG' OR '/IAM/C_CATALOG_T'.
          lv_views = `/IAM/V_CATALOG`.
        WHEN '/IAM/C_CODEGR' OR '/IAM/C_CODEGR_T'.
          lv_views = `/IAM/V_CODEGR`.
        WHEN '/IAM/C_CODE' OR '/IAM/C_CODE_T'.
          lv_views = `/IAM/V_CODE`.
        WHEN '/IAM/C_CODE_REL'.
          lv_views = `/IAM/V_CODE_REL`.
        WHEN '/IAM/C_CATCODREL'.
          lv_views = `/IAM/V_CATCODREL`.
        WHEN OTHERS.
          lv_views = <ls_plan>-tabname.
      ENDCASE.
      INSERT lv_views INTO TABLE lt_checks.
    ENDLOOP.
    IF mt_ltplan IS NOT INITIAL.
      lv_views = `/IAM/V_ACTIVTYP /IAM/VV_ACTIVTYP_MOC`.
      INSERT lv_views INTO TABLE lt_checks.
    ENDIF.

    LOOP AT lt_checks INTO lv_views.
      SPLIT lv_views AT space INTO TABLE lt_views.
      lv_ok = abap_false.
      LOOP AT lt_views INTO lv_name.
        lv_view = lv_name.
        CALL FUNCTION 'VIEW_AUTHORITY_CHECK'
          EXPORTING
            view_action = 'U'
            view_name   = lv_view
          EXCEPTIONS
            OTHERS      = 1.
        IF sy-subrc = 0.
          lv_ok = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_ok = abap_false.
        err( iv_object = lv_views
             iv_text   = |No authorization to maintain { lv_views } (S_TABU_DIS / S_TABU_NAM)| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_transport.
    " client setting and customizing request (validated before anything is posted)
    DATA: ls_e070       TYPE e070,
          ls_task       TYPE e070,
          lv_client     TYPE e070c-client,
          lv_cccoractiv TYPE t000-cccoractiv.

    CLEAR: mv_order, mv_task, mv_no_transport.
    IF transport_needed( ) = abap_false.
      RETURN.
    ENDIF.

    " SCC4: changes and transports for client-specific objects
    SELECT SINGLE cccoractiv FROM t000 INTO lv_cccoractiv WHERE mandt = sy-mandt.
    CASE lv_cccoractiv.
      WHEN '2'.
        err( |Client { sy-mandt }: changes to client-specific customizing are not allowed (SCC4)| ).
        RETURN.
      WHEN '3'.
        warn( |Client { sy-mandt }: transports are not allowed (SCC4) - the changes are not recorded in a request| ).
        mv_no_transport = abap_true.
        RETURN.
      WHEN OTHERS.
    ENDCASE.

    IF ms_set-trkorr IS INITIAL.
      IF sy-batch = abap_true AND ms_set-test = abap_false.
        err( 'Background processing: enter the customizing request on the selection screen' ).
      ELSE.
        info( 'The changes will be recorded in a customizing request - it is requested in a popup before posting' ).
      ENDIF.
      RETURN.
    ENDIF.

    SELECT SINGLE * FROM e070 INTO ls_e070 WHERE trkorr = ms_set-trkorr.
    IF sy-subrc <> 0.
      err( iv_object = ms_set-trkorr iv_text = |Transport request { ms_set-trkorr } does not exist| ).
      RETURN.
    ENDIF.
    IF ls_e070-trstatus <> 'D'.
      err( iv_object = ms_set-trkorr
           iv_text   = |Request { ms_set-trkorr } is not modifiable (status { ls_e070-trstatus })| ).
      RETURN.
    ENDIF.
    CASE ls_e070-trfunction.
      WHEN 'W'.                                    " customizing request
        mv_order = ls_e070-trkorr.
        SELECT SINGLE * FROM e070 INTO ls_task
          WHERE strkorr  = ls_e070-trkorr
            AND as4user  = sy-uname
            AND trstatus = 'D'.
        IF sy-subrc = 0.
          mv_task = ls_task-trkorr.
        ENDIF.
      WHEN 'Q'.                                    " customizing task
        IF ls_e070-as4user <> sy-uname.
          err( iv_object = ms_set-trkorr
               iv_text   = |Task { ms_set-trkorr } belongs to user { ls_e070-as4user }| ).
          RETURN.
        ENDIF.
        mv_task  = ls_e070-trkorr.
        mv_order = ls_e070-strkorr.
      WHEN OTHERS.
        err( iv_object = ms_set-trkorr
             iv_text   = |{ ms_set-trkorr } is not a customizing request or customizing task (type { ls_e070-trfunction })| ).
        RETURN.
    ENDCASE.

    " customizing requests are client-specific
    SELECT SINGLE client FROM e070c INTO lv_client WHERE trkorr = mv_order.
    IF sy-subrc = 0 AND lv_client IS NOT INITIAL AND lv_client <> sy-mandt.
      err( iv_object = mv_order
           iv_text   = |Request { mv_order } belongs to client { lv_client } - use a request of client { sy-mandt }| ).
      RETURN.
    ENDIF.
    info( iv_object = mv_order iv_text = |The changes will be recorded in customizing request { mv_order }| ).
  ENDMETHOD.

  METHOD summarize.
    TYPES: BEGIN OF lty_sum,
             tabname TYPE tabname,
             ins     TYPE i,
             upd     TYPE i,
             del     TYPE i,
           END OF lty_sum.
    DATA: lt_sum   TYPE SORTED TABLE OF lty_sum WITH UNIQUE KEY tabname,
          ls_sum   TYPE lty_sum,
          lv_save  TYPE i,
          lv_del   TYPE i,
          lv_tabkeys TYPE i.
    FIELD-SYMBOLS: <ls_plan> TYPE ty_plan,
                   <ls_sum>  TYPE lty_sum,
                   <ls_lt>   TYPE ty_ltplan.

    LOOP AT mt_plan ASSIGNING <ls_plan> WHERE action <> '-'.
      READ TABLE lt_sum ASSIGNING <ls_sum> WITH TABLE KEY tabname = <ls_plan>-tabname.
      IF sy-subrc <> 0.
        CLEAR ls_sum.
        ls_sum-tabname = <ls_plan>-tabname.
        INSERT ls_sum INTO TABLE lt_sum ASSIGNING <ls_sum>.
      ENDIF.
      CASE <ls_plan>-action.
        WHEN 'I'.
          <ls_sum>-ins = <ls_sum>-ins + 1.
        WHEN 'U'.
          <ls_sum>-upd = <ls_sum>-upd + 1.
        WHEN 'D'.
          <ls_sum>-del = <ls_sum>-del + 1.
        WHEN OTHERS.
      ENDCASE.
      IF <ls_plan>-tabname <> gc_tab_partner.
        lv_tabkeys = lv_tabkeys + 1.
      ENDIF.
    ENDLOOP.
    LOOP AT lt_sum INTO ls_sum.
      info( iv_object = ls_sum-tabname
            iv_text   = |{ ls_sum-tabname }: { ls_sum-ins } new, { ls_sum-upd } changed, { ls_sum-del } deleted| ).
    ENDLOOP.
    LOOP AT mt_ltplan ASSIGNING <ls_lt>.
      IF <ls_lt>-action = 'D'.
        lv_del = lv_del + 1.
      ELSE.
        lv_save = lv_save + 1.
      ENDIF.
    ENDLOOP.
    IF mt_ltplan IS NOT INITIAL.
      info( iv_object = 'IAMACTTMPL'
            iv_text   = |Long texts: { lv_save } saved, { lv_del } deleted| ).
    ENDIF.
    IF transport_needed( ) = abap_true AND mv_no_transport = abap_false.
      info( iv_text = |Transport: { lv_tabkeys } table key(s) (R3TR TABU) and { lines( mt_ltplan ) } long text(s) (R3TR TEXT) to be recorded| ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Posting
*----------------------------------------------------------------------*
  METHOD post.
    DATA: lt_tab    TYPE SORTED TABLE OF tabname WITH UNIQUE KEY table_line,
          lt_locked TYPE STANDARD TABLE OF tabname WITH EMPTY KEY,
          lv_tab    TYPE tabname,
          lv_error  TYPE abap_bool.
    FIELD-SYMBOLS: <ls_plan> TYPE ty_plan,
                   <ls_data> TYPE any,
                   <ls_lt>   TYPE ty_ltplan.

    " 1) customizing request - chosen before locking and before any database
    "    change (creating a request in the popup commits)
    IF select_request( ) = abap_false.
      err( 'Nothing was posted' ).
      RETURN.
    ENDIF.

    " 2) lock the tables as the view maintenance does (E_TABLE)
    LOOP AT mt_plan ASSIGNING <ls_plan>.
      INSERT <ls_plan>-tabname INTO TABLE lt_tab.
    ENDLOOP.
    IF mt_ltplan IS NOT INITIAL.
      lv_tab = '/IAM/C_ACTIVTYPT'.
      INSERT lv_tab INTO TABLE lt_tab.
    ENDIF.
    LOOP AT lt_tab INTO lv_tab.
      CALL FUNCTION 'ENQUEUE_E_TABLE'
        EXPORTING
          mode_rstable   = 'E'
          tabname        = lv_tab
          _scope         = '1'
        EXCEPTIONS
          foreign_lock   = 1
          system_failure = 2
          OTHERS         = 3.
      IF sy-subrc = 1.
        err( iv_object = lv_tab iv_text = |Table { lv_tab } is locked by user { sy-msgv1 }| ).
        lv_error = abap_true.
        EXIT.
      ELSEIF sy-subrc <> 0.
        err( iv_object = lv_tab iv_text = |Table { lv_tab } cannot be locked| ).
        lv_error = abap_true.
        EXIT.
      ENDIF.
      APPEND lv_tab TO lt_locked.
    ENDLOOP.

    " 3) customizing tables
    IF lv_error = abap_false.
      LOOP AT mt_plan ASSIGNING <ls_plan> WHERE action <> '-'.
        lv_tab = <ls_plan>-tabname.
        ASSIGN <ls_plan>-data->* TO <ls_data>.
        CASE <ls_plan>-action.
          WHEN 'I'.
            INSERT (lv_tab) FROM <ls_data>.
          WHEN 'U'.
            UPDATE (lv_tab) FROM <ls_data>.
          WHEN 'D'.
            DELETE (lv_tab) FROM <ls_data>.
          WHEN OTHERS.
        ENDCASE.
        IF sy-subrc <> 0.
          err( iv_sheet = <ls_plan>-sheet iv_row = <ls_plan>-row iv_object = <ls_plan>-object
               iv_text  = |Database operation { <ls_plan>-action } on table { lv_tab } failed| ).
          lv_error = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 4) long texts (SAPscript IAMACTTMPL / ST)
    IF lv_error = abap_false.
      LOOP AT mt_ltplan ASSIGNING <ls_lt>.
        IF <ls_lt>-action = 'D'.
          CALL FUNCTION 'DELETE_TEXT'
            EXPORTING
              id              = <ls_lt>-header-tdid
              language        = <ls_lt>-header-tdspras
              name            = <ls_lt>-header-tdname
              object          = <ls_lt>-header-tdobject
              savemode_direct = abap_true
            EXCEPTIONS
              OTHERS          = 1.
        ELSE.
          CALL FUNCTION 'SAVE_TEXT'
            EXPORTING
              header          = <ls_lt>-header
              savemode_direct = abap_true
            TABLES
              lines           = <ls_lt>-lines
            EXCEPTIONS
              OTHERS          = 1.
        ENDIF.
        IF sy-subrc <> 0.
          mo_log->add_sy( iv_msgty  = 'E'
                          iv_sheet  = <ls_lt>-sheet
                          iv_row    = <ls_lt>-row
                          iv_object = <ls_lt>-header-tdname ).
          lv_error = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 5) record everything in the customizing request
    IF lv_error = abap_false AND record_transport( ) = abap_false.
      lv_error = abap_true.
    ENDIF.

    " 6) all or nothing
    IF lv_error = abap_true.
      ROLLBACK WORK.
      err( 'All changes were rolled back - nothing was posted' ).
    ELSE.
      COMMIT WORK AND WAIT.
      mo_log->add( iv_msgty = 'S'
                   iv_text  = |Posted: { lines( mt_plan ) } table entries and { lines( mt_ltplan ) } long texts| ).
    ENDIF.

    LOOP AT lt_locked INTO lv_tab.
      CALL FUNCTION 'DEQUEUE_E_TABLE'
        EXPORTING
          mode_rstable = 'E'
          tabname      = lv_tab.
    ENDLOOP.
  ENDMETHOD.

  METHOD select_request.
    rv_ok = abap_true.
    IF mv_no_transport = abap_true OR transport_needed( ) = abap_false OR mv_order IS NOT INITIAL.
      RETURN.
    ENDIF.
    " standard popup: choose or create a customizing request
    CALL FUNCTION 'TR_ORDER_CHOICE_CORRECTION'
      EXPORTING
        iv_category = 'CUST'
      IMPORTING
        ev_order    = mv_order
        ev_task     = mv_task
      EXCEPTIONS
        OTHERS      = 1.
    IF sy-subrc <> 0 OR mv_order IS INITIAL.
      CLEAR: mv_order, mv_task.
      err( 'No customizing request selected' ).
      rv_ok = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD record_transport.
    " R3TR TABU with table keys (also deletions) + R3TR TEXT for the long texts
    " TR_OBJECTS / TR_KEYS: CTS table types (standard key). TR_APPEND_TO_COMM_OBJS_KEYS
    " passes WT_E071K[] on to TR_EC_CUST_ORIG_LANG (CT_KEYS) - a table with another
    " key definition (e.g. EMPTY KEY) ends in CALL_FUNCTION_CONFLICT_TAB_TYP
    DATA: lt_e071   TYPE tr_objects,
          lt_e071k  TYPE tr_keys,
          ls_e071   TYPE e071,
          ls_e071k  TYPE e071k,
          lt_tab    TYPE SORTED TABLE OF tabname WITH UNIQUE KEY table_line,
          lt_keys   TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lv_tab    TYPE tabname,
          lv_key    TYPE string,
          lv_target TYPE trkorr.
    FIELD-SYMBOLS: <ls_plan> TYPE ty_plan,
                   <ls_data> TYPE any,
                   <ls_lt>   TYPE ty_ltplan.

    rv_ok = abap_true.
    IF mv_no_transport = abap_true OR transport_needed( ) = abap_false.
      RETURN.
    ENDIF.

    LOOP AT mt_plan ASSIGNING <ls_plan> WHERE tabname <> gc_tab_partner AND action <> '-'.
      ASSIGN <ls_plan>-data->* TO <ls_data>.
      CLEAR ls_e071k.
      ls_e071k-pgmid      = 'R3TR'.
      ls_e071k-object     = 'TABU'.
      ls_e071k-objname    = <ls_plan>-tabname.
      ls_e071k-mastertype = 'TABU'.
      ls_e071k-mastername = <ls_plan>-tabname.
      ls_e071k-tabkey     = build_tabkey( iv_tabname = <ls_plan>-tabname is_data = <ls_data> ).
      lv_key = |{ ls_e071k-objname }:{ ls_e071k-tabkey }|.
      INSERT lv_key INTO TABLE lt_keys.
      IF sy-subrc = 0.
        APPEND ls_e071k TO lt_e071k.
        INSERT <ls_plan>-tabname INTO TABLE lt_tab.
      ENDIF.
    ENDLOOP.
    LOOP AT lt_tab INTO lv_tab.
      CLEAR ls_e071.
      ls_e071-pgmid    = 'R3TR'.
      ls_e071-object   = 'TABU'.
      ls_e071-obj_name = lv_tab.
      ls_e071-objfunc  = 'K'.
      APPEND ls_e071 TO lt_e071.
    ENDLOOP.
    " as /IAM/CL_LONGTEXT->TRANSPORT: <object>,<name>,<id>,<language>
    LOOP AT mt_ltplan ASSIGNING <ls_lt>.
      CLEAR ls_e071.
      ls_e071-pgmid  = 'R3TR'.
      ls_e071-object = 'TEXT'.
      CONCATENATE <ls_lt>-header-tdobject <ls_lt>-header-tdname
                  <ls_lt>-header-tdid     <ls_lt>-header-tdspras
             INTO ls_e071-obj_name SEPARATED BY ','.
      APPEND ls_e071 TO lt_e071.
    ENDLOOP.
    IF lt_e071 IS INITIAL.
      RETURN.
    ENDIF.

    " task of the user in the request (else the request itself)
    lv_target = mv_task.
    IF lv_target IS INITIAL.
      lv_target = mv_order.
    ENDIF.
    CALL FUNCTION 'TR_APPEND_TO_COMM_OBJS_KEYS'
      EXPORTING
        wi_trkorr = lv_target
      TABLES
        wt_e071   = lt_e071
        wt_e071k  = lt_e071k
      EXCEPTIONS
        OTHERS    = 1.
    IF sy-subrc <> 0.
      mo_log->add_sy( iv_msgty = 'E' iv_object = lv_target ).
      err( iv_object = lv_target iv_text = |The changes cannot be recorded in request { lv_target }| ).
      rv_ok = abap_false.
      RETURN.
    ENDIF.
    mo_log->add( iv_msgty  = 'S'
                 iv_object = lv_target
                 iv_text   = |Recorded in customizing request { mv_order } (task { lv_target }): { lines( lt_e071k ) } table keys, { lines( mt_ltplan ) } long texts| ).
  ENDMETHOD.

  METHOD transport_needed.
    LOOP AT mt_plan TRANSPORTING NO FIELDS WHERE tabname <> gc_tab_partner AND action <> '-'.
      rv_needed = abap_true.
      RETURN.
    ENDLOOP.
    IF mt_ltplan IS NOT INITIAL.
      rv_needed = abap_true.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Helpers
*----------------------------------------------------------------------*
  METHOD add_plan.
    DATA: ls_plan TYPE ty_plan,
          ls_idx  TYPE ty_plan_idx,
          lv_text TYPE string.
    FIELD-SYMBOLS: <ls_plan> TYPE ty_plan,
                   <ls_idx>  TYPE ty_plan_idx,
                   <ls_data> TYPE any.

    ls_idx-key = |{ iv_tabname }:{ build_tabkey( iv_tabname = iv_tabname is_data = is_data ) }|.
    READ TABLE mt_plan_idx ASSIGNING <ls_idx> WITH TABLE KEY key = ls_idx-key.
    IF sy-subrc = 0.
      " same key already planned in this run: one database operation only
      READ TABLE mt_plan ASSIGNING <ls_plan> INDEX <ls_idx>-index.
      ASSIGN <ls_plan>-data->* TO <ls_data>.
      <ls_data> = is_data.
      IF iv_action = 'D'.
        IF <ls_plan>-action = 'I'.
          <ls_plan>-action = '-'.
        ELSE.
          <ls_plan>-action = 'D'.
        ENDIF.
      ELSEIF <ls_plan>-action = 'D'.
        <ls_plan>-action = 'U'.
      ELSEIF <ls_plan>-action = '-'.
        <ls_plan>-action = 'I'.
      ENDIF.
      RETURN.
    ENDIF.

    ls_plan-tabname = iv_tabname.
    ls_plan-action  = iv_action.
    ls_plan-sheet   = iv_sheet.
    ls_plan-row     = iv_row.
    ls_plan-object  = iv_object.
    CREATE DATA ls_plan-data LIKE is_data.
    ASSIGN ls_plan-data->* TO <ls_data>.
    <ls_data> = is_data.
    APPEND ls_plan TO mt_plan.
    ls_idx-index = lines( mt_plan ).
    INSERT ls_idx INTO TABLE mt_plan_idx.

    CASE iv_action.
      WHEN 'I'.
        lv_text = |New entry in { iv_tabname }|.
      WHEN 'U'.
        lv_text = |Change of entry in { iv_tabname }|.
      WHEN OTHERS.
        lv_text = |Deletion of entry in { iv_tabname }|.
    ENDCASE.
    mo_log->add( iv_msgty  = 'S'
                 iv_text   = lv_text
                 iv_sheet  = iv_sheet
                 iv_row    = iv_row
                 iv_object = iv_object ).
  ENDMETHOD.

  METHOD add_ltplan.
    DATA ls_lt TYPE ty_ltplan.

    ls_lt-action = iv_action.
    ls_lt-sheet  = iv_sheet.
    ls_lt-row    = iv_row.
    ls_lt-header = is_header.
    ls_lt-lines  = it_lines.
    APPEND ls_lt TO mt_ltplan.
    IF iv_action = 'D'.
      mo_log->add( iv_msgty = 'S' iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object
                   iv_text  = |Long text { is_header-tdobject } { is_header-tdname } is deleted| ).
    ELSE.
      mo_log->add( iv_msgty = 'S' iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object
                   iv_text  = |Long text { is_header-tdobject } { is_header-tdname } is saved ({ lines( it_lines ) } lines)| ).
    ENDIF.
  ENDMETHOD.

  METHOD is_planned.
    DATA lv_key TYPE string.

    lv_key = |{ iv_tabname }:{ build_tabkey( iv_tabname = iv_tabname is_data = is_data ) }|.
    rv_planned = xsdbool( line_exists( mt_plan_idx[ key = lv_key ] ) ).
  ENDMETHOD.

  METHOD build_tabkey.
    " key of the table entry as in E071K-TABKEY (key fields with full length)
    DATA: lt_fields TYPE ddfields,
          ls_field  TYPE dfies,
          lv_value  TYPE c LENGTH 120,
          lv_off    TYPE i,
          lv_len    TYPE i.
    FIELD-SYMBOLS <lv_value> TYPE any.

    lt_fields = get_key_fields( iv_tabname ).
    LOOP AT lt_fields INTO ls_field.
      ASSIGN COMPONENT ls_field-fieldname OF STRUCTURE is_data TO <lv_value>.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_len = ls_field-leng.
      IF lv_len <= 0 OR lv_off + lv_len > 120.
        EXIT.
      ENDIF.
      lv_value = <lv_value>.
      rv_key+lv_off(lv_len) = lv_value.
      lv_off = lv_off + lv_len.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_key_fields.
    DATA: ls_buf    TYPE ty_keybuf,
          lo_descr  TYPE REF TO cl_abap_typedescr,
          lo_struct TYPE REF TO cl_abap_structdescr,
          lt_all    TYPE ddfields,
          ls_field  TYPE dfies.

    READ TABLE mt_keybuf INTO ls_buf WITH TABLE KEY tabname = iv_tabname.
    IF sy-subrc <> 0.
      ls_buf-tabname = iv_tabname.
      cl_abap_typedescr=>describe_by_name( EXPORTING  p_name         = iv_tabname
                                           RECEIVING  p_descr_ref    = lo_descr
                                           EXCEPTIONS type_not_found = 1
                                                      OTHERS         = 2 ).
      IF sy-subrc = 0 AND lo_descr->kind = cl_abap_typedescr=>kind_struct.
        lo_struct ?= lo_descr.
        lo_struct->get_ddic_field_list( RECEIVING  p_field_list = lt_all
                                        EXCEPTIONS OTHERS       = 1 ).
        IF sy-subrc = 0.
          LOOP AT lt_all INTO ls_field WHERE keyflag = abap_true.
            APPEND ls_field TO ls_buf-fields.
          ENDLOOP.
        ENDIF.
      ENDIF.
      INSERT ls_buf INTO TABLE mt_keybuf.
    ENDIF.
    rt_fields = ls_buf-fields.
  ENDMETHOD.

  METHOD longtext_header.
    " SAPLVIEWS / LCL_V_ACTIVTYP: key via /IAM/CL_LONGTEXT (IAMACTTMPL, ST, <application><template>)
    DATA ls_key TYPE /iam/s_longtext_key.

    ls_key = /iam/cl_longtext=>get_instance( )->create_longtext_key_iss_act(
               iv_application  = iv_appl
               iv_langu        = iv_langu
               iv_act_template = iv_tmpl ).
    rs_header-tdobject   = ls_key-object.
    rs_header-tdname     = ls_key-name.
    rs_header-tdid       = ls_key-id.
    rs_header-tdspras    = ls_key-language.
    rs_header-tdlinesize = 132.
  ENDMETHOD.

  METHOD longtext_exists.
    DATA lv_name TYPE stxh-tdname.

    SELECT SINGLE tdname FROM stxh INTO lv_name
      WHERE tdobject = is_header-tdobject
        AND tdname   = is_header-tdname
        AND tdid     = is_header-tdid
        AND tdspras  = is_header-tdspras.
    rv_exists = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD read_longtext.
    CALL FUNCTION 'READ_TEXT'
      EXPORTING
        id       = is_header-tdid
        language = is_header-tdspras
        name     = is_header-tdname
        object   = is_header-tdobject
      TABLES
        lines    = rt_lines
      EXCEPTIONS
        OTHERS   = 1.
    IF sy-subrc <> 0.
      CLEAR rt_lines.
    ENDIF.
  ENDMETHOD.

  METHOD convert_longtext.
    " one Excel line = one paragraph (as /MOC/ follow-up actions: CONVERT_STREAM_TO_ITF_TEXT)
    DATA: lv_text   TYPE string,
          lv_cr     TYPE c LENGTH 1,
          lt_stream TYPE string_table.

    lv_cr   = cl_abap_char_utilities=>cr_lf.      " first character = CR
    lv_text = iv_text.
    REPLACE ALL OCCURRENCES OF `_x000D_` IN lv_text WITH ``.     " CR escaped by Excel
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_text WITH cl_abap_char_utilities=>newline.
    REPLACE ALL OCCURRENCES OF lv_cr IN lv_text WITH cl_abap_char_utilities=>newline.
    SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_stream.
    CALL FUNCTION 'CONVERT_STREAM_TO_ITF_TEXT'
      EXPORTING
        stream_lines = lt_stream
        language     = iv_langu
        lf           = abap_true
      TABLES
        itf_text     = rt_lines.
  ENDMETHOD.

  METHOD check_new_key.
    " SAPLVIEWS: LCL_VIEWS->CHECK_NEW_KEY (msg 001, 050, 051, 052)
    DATA: lv_key   TYPE string,
          lv_dummy TYPE string.

    rv_ok  = abap_true.
    lv_key = iv_key.
    IF lv_key IS INITIAL.
      MESSAGE e001(/iam/config) INTO lv_dummy.
      mo_log->add_sy( iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object ).
      rv_ok = abap_false.
      RETURN.
    ENDIF.
    IF lv_key CA '*+%@,'''.
      MESSAGE e050(/iam/config) WITH iv_key INTO lv_dummy.
      mo_log->add_sy( iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object ).
      rv_ok = abap_false.
    ENDIF.
    IF lv_key CS ` `.
      MESSAGE e051(/iam/config) WITH iv_key INTO lv_dummy.
      mo_log->add_sy( iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object ).
      rv_ok = abap_false.
    ENDIF.
    IF lv_key CO '0'.
      MESSAGE e052(/iam/config) INTO lv_dummy.
      mo_log->add_sy( iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object ).
      rv_ok = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD appl_ok.
    rv_ok = xsdbool( line_exists( mt_i_appl[ client = sy-mandt application = iv_appl ] ) ).
    IF rv_ok = abap_false.
      err( iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_appl
           iv_text  = |Application "{ iv_appl }" is not defined in Issue and Activity Management (/IAM/I_APPL)| ).
    ENDIF.
  ENDMETHOD.

  METHOD template_exists.
    rv_exists = xsdbool( line_exists( mt_activtyp[ client        = sy-mandt
                                                   application   = iv_appl
                                                   activity_type = iv_tmpl ] ) ).
  ENDMETHOD.

  METHOD check_child_template.
    rv_ok = appl_ok( iv_appl = iv_appl iv_sheet = iv_sheet iv_row = iv_row ).
    IF rv_ok = abap_false.
      RETURN.
    ENDIF.
    IF iv_tmpl IS INITIAL.
      err( iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object
           iv_text  = 'Activity template (ACTIVITY_TYPE) is mandatory' ).
      rv_ok = abap_false.
    ELSEIF template_exists( iv_appl = iv_appl iv_tmpl = iv_tmpl ) = abap_false.
      err( iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object
           iv_text  = |Template { iv_tmpl } does not exist (neither in the system nor in worksheet TEMPLATES)| ).
      rv_ok = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD describe.
    DATA: lv_field TYPE string,
          lv_value TYPE string,
          lv_idx   TYPE i.

    LOOP AT it_fields INTO lv_field.
      lv_idx   = sy-tabix.
      lv_value = lcl_util=>get_comp( is_data = is_data iv_name = lv_field ).
      CASE lv_idx.
        WHEN 1.
          rv_text = lv_value.
        WHEN 2.
          rv_text = |{ rv_text }/{ lv_value }|.
        WHEN OTHERS.
          rv_text = |{ rv_text } { lv_value }|.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD err.
    mo_log->add( iv_msgty = 'E' iv_text = iv_text iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object ).
  ENDMETHOD.

  METHOD warn.
    mo_log->add( iv_msgty = 'W' iv_text = iv_text iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object ).
  ENDMETHOD.

  METHOD info.
    mo_log->add( iv_msgty = 'I' iv_text = iv_text iv_sheet = iv_sheet iv_row = iv_row iv_object = iv_object ).
  ENDMETHOD.

ENDCLASS.
