CLASS zcl_ehsm_wf_teams_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      tt_item    TYPE STANDARD TABLE OF zehsm_s_wf_item WITH EMPTY KEY,
      tt_decopt  TYPE STANDARD TABLE OF zehsm_s_wf_decopt WITH EMPTY KEY,
      tt_object  TYPE STANDARD TABLE OF zehsm_s_wf_object WITH EMPTY KEY,
      tt_comment TYPE STANDARD TABLE OF zehsm_s_wf_comment WITH EMPTY KEY.

    METHODS resolve_user
      IMPORTING iv_user        TYPE xubname OPTIONAL
                iv_email       TYPE ad_smtpadr OPTIONAL
      RETURNING VALUE(rv_user) TYPE xubname
      RAISING   /iwbep/cx_mgw_busi_exception.

    METHODS get_items
      IMPORTING iv_user         TYPE xubname
                iv_email        TYPE ad_smtpadr OPTIONAL
                iv_include_sent TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rt_item)  TYPE tt_item.

    METHODS get_item
      IMPORTING iv_wi_id       TYPE sww_wiid
      RETURNING VALUE(rs_item) TYPE zehsm_s_wf_item
      RAISING   /iwbep/cx_mgw_busi_exception.

    METHODS get_decision_options
      IMPORTING iv_wi_id      TYPE sww_wiid
      RETURNING VALUE(rt_opt) TYPE tt_decopt.

    METHODS get_objects
      IMPORTING iv_wi_id      TYPE sww_wiid
      RETURNING VALUE(rt_obj) TYPE tt_object.

    METHODS get_comments
      IMPORTING iv_wi_id      TYPE sww_wiid
      RETURNING VALUE(rt_cmt) TYPE tt_comment.

    METHODS mark_sent
      IMPORTING iv_wi_id      TYPE sww_wiid
                iv_user       TYPE xubname
                iv_email      TYPE ad_smtpadr OPTIONAL
      RETURNING VALUE(rv_msg) TYPE bapi_msg
      RAISING   /iwbep/cx_mgw_busi_exception.

    METHODS execute_decision
      IMPORTING iv_wi_id        TYPE sww_wiid
                iv_user         TYPE xubname
                iv_decision_key TYPE swr_decikey
                iv_comment      TYPE string OPTIONAL
      RETURNING VALUE(rv_msg)   TYPE bapi_msg
      RAISING   /iwbep/cx_mgw_busi_exception.

  PRIVATE SECTION.
    TYPES tt_wihdr TYPE STANDARD TABLE OF swr_wihdr WITH EMPTY KEY.

    CONSTANTS:
      c_msgid   TYPE symsgid VALUE 'ZEHSM_WF_TEAMS',
      c_sent    TYPE c LENGTH 1 VALUE 'S',
      c_decided TYPE c LENGTH 1 VALUE 'D'.

    METHODS read_worklist
      IMPORTING iv_user      TYPE xubname
      RETURNING VALUE(rt_wl) TYPE tt_wihdr.

    METHODS check_in_inbox
      IMPORTING iv_wi_id      TYPE sww_wiid
                iv_user       TYPE xubname
      RETURNING VALUE(rs_hdr) TYPE swr_wihdr
      RAISING   /iwbep/cx_mgw_busi_exception.

    METHODS build_item
      IMPORTING is_hdr         TYPE swr_wihdr
      RETURNING VALUE(rs_item) TYPE zehsm_s_wf_item.

    METHODS raise_error
      IMPORTING iv_msgno TYPE symsgno
                iv_v1    TYPE clike OPTIONAL
                iv_v2    TYPE clike OPTIONAL
                iv_v3    TYPE clike OPTIONAL
                iv_wi_id TYPE sww_wiid OPTIONAL
      RAISING   /iwbep/cx_mgw_busi_exception.

    METHODS log
      IMPORTING iv_wi_id TYPE sww_wiid OPTIONAL.
ENDCLASS.


CLASS zcl_ehsm_wf_teams_api IMPLEMENTATION.

  METHOD resolve_user.
    IF iv_user IS NOT INITIAL.
      rv_user = to_upper( iv_user ).
      SELECT SINGLE bname FROM usr02 WHERE bname = @rv_user INTO @rv_user.
      IF sy-subrc <> 0.
        raise_error( iv_msgno = '001' iv_v1 = iv_user ).
      ENDIF.
      RETURN.
    ENDIF.

    IF iv_email IS INITIAL.
      raise_error( '004' ).
    ENDIF.

    DATA(lv_mail) = to_upper( condense( iv_email ) ).
    SELECT DISTINCT u~bname
      FROM usr21 AS u
      INNER JOIN adr6 AS a ON  a~addrnumber = u~addrnumber
                           AND a~persnumber = u~persnumber
      INNER JOIN usr02 AS s ON s~bname = u~bname
      WHERE upper( a~smtp_addr ) = @lv_mail
        AND s~uflag = 0
      INTO TABLE @DATA(lt_user).

    CASE lines( lt_user ).
      WHEN 0.
        raise_error( iv_msgno = '002' iv_v1 = iv_email ).
      WHEN 1.
        rv_user = lt_user[ 1 ]-bname.
      WHEN OTHERS.
        raise_error( iv_msgno = '003' iv_v1 = iv_email ).
    ENDCASE.
  ENDMETHOD.


  METHOD get_items.
    DATA(lt_wl) = read_worklist( iv_user ).
    IF lt_wl IS INITIAL.
      RETURN.
    ENDIF.

    SELECT wi_id FROM zehsm_wf_teams
      FOR ALL ENTRIES IN @lt_wl
      WHERE wi_id   = @lt_wl-wi_id
        AND user_id = @iv_user
      INTO TABLE @DATA(lt_sent).
    SORT lt_sent BY wi_id.

    LOOP AT lt_wl INTO DATA(ls_hdr).
      READ TABLE lt_sent TRANSPORTING NO FIELDS WITH KEY wi_id = ls_hdr-wi_id BINARY SEARCH.
      DATA(lv_sent) = xsdbool( sy-subrc = 0 ).
      IF lv_sent = abap_true AND iv_include_sent = abap_false.
        CONTINUE.
      ENDIF.
      DATA(ls_item) = build_item( ls_hdr ).
      ls_item-user_id      = iv_user.
      ls_item-email        = iv_email.
      ls_item-already_sent = lv_sent.
      APPEND ls_item TO rt_item.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_item.
    DATA(lo_wi) = NEW /iwwrk/cl_wf_read_workitem( iv_workitem_id = iv_wi_id ).
    lo_wi->get_wi_header( IMPORTING es_wi_header   = DATA(ls_hdr)
                                    ev_return_code = DATA(lv_rc) ).
    IF lv_rc <> 0 OR ls_hdr-wi_id IS INITIAL.
      raise_error( iv_msgno = '013' iv_v1 = iv_wi_id ).
    ENDIF.
    rs_item = build_item( ls_hdr ).
  ENDMETHOD.


  METHOD get_decision_options.
    DATA: ls_guid TYPE swf_stguid,
          lt_cfg  TYPE /iwwrk/tt_wf_decision_info.

    DATA(lo_wi) = NEW /iwwrk/cl_wf_read_workitem( iv_workitem_id = iv_wi_id ).
    lo_wi->get_wi_decision_options( IMPORTING et_wi_dec_options = DATA(lt_alt)
                                              ev_return_code    = DATA(lv_rc) ).
    IF lv_rc <> 0 OR lt_alt IS INITIAL.
      RETURN.
    ENDIF.

    lo_wi->get_wi_header( IMPORTING es_wi_header = DATA(ls_hdr) ).
    ls_guid = ls_hdr-def_guid.
    DATA(lv_wf_id) = /iwwrk/cl_wf_step_config=>get_step_config_version(
                       iv_wfd_id  = ls_guid-wfdkey-wfd_id
                       iv_version = ls_guid-wfdkey-version
                       iv_step_id = ls_guid-nodeid ).
    /iwwrk/cl_wf_step_config=>get_decision_keys_info(
      EXPORTING iv_wf_id         = lv_wf_id
                iv_wf_step_id    = ls_guid-nodeid
      IMPORTING et_decision_keys = lt_cfg ).

    LOOP AT lt_alt INTO DATA(ls_alt).
      DATA(ls_cfg) = VALUE #( lt_cfg[ altkey = ls_alt-altkey ] OPTIONAL ).
      APPEND VALUE #( wi_id             = iv_wi_id
                      decision_key      = ls_alt-altkey
                      decision_text     = ls_alt-alttext
                      comment_mandatory = ls_cfg-comment_mandat
                      nature            = ls_cfg-nature ) TO rt_opt.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_objects.
    DATA ls_lead TYPE swr_obj_2.

    CALL FUNCTION 'SAP_WAPI_GET_OBJECTS'
      EXPORTING
        workitem_id      = iv_wi_id
      IMPORTING
        leading_object_2 = ls_lead.
    IF ls_lead-instid IS NOT INITIAL.
      APPEND VALUE #( wi_id        = iv_wi_id
                      source_wi_id = iv_wi_id
                      catid        = ls_lead-catid
                      typeid       = ls_lead-typeid
                      instid       = ls_lead-instid
                      is_leading   = abap_true ) TO rt_obj.
    ENDIF.

    SELECT SINGLE top_wi_id FROM swwwihead WHERE wi_id = @iv_wi_id INTO @DATA(lv_top).
    SELECT wi_id, catid, typeid, instid, wi_reltype FROM sww_wi2obj
      WHERE ( wi_id = @iv_wi_id OR wi_id = @lv_top )
        AND removed = @space
      INTO TABLE @DATA(lt_rel).

    LOOP AT lt_rel INTO DATA(ls_rel).
      IF line_exists( rt_obj[ source_wi_id = ls_rel-wi_id catid = ls_rel-catid
                              typeid = ls_rel-typeid instid = ls_rel-instid ] ).
        CONTINUE.
      ENDIF.
      APPEND VALUE #( wi_id        = iv_wi_id
                      source_wi_id = ls_rel-wi_id
                      catid        = ls_rel-catid
                      typeid       = ls_rel-typeid
                      instid       = ls_rel-instid
                      wi_reltype   = ls_rel-wi_reltype ) TO rt_obj.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_comments.
    DATA(lo_wi) = NEW /iwwrk/cl_wf_read_workitem( iv_workitem_id = iv_wi_id ).
    lo_wi->get_wi_appr_comments( IMPORTING et_wi_appr_comm = DATA(lt_cmt) ).
    LOOP AT lt_cmt INTO DATA(ls_cmt).
      DATA(ls_out) = CORRESPONDING zehsm_s_wf_comment( ls_cmt ).
      ls_out-wi_id = iv_wi_id.
      APPEND ls_out TO rt_cmt.
    ENDLOOP.
  ENDMETHOD.


  METHOD mark_sent.
    DATA(ls_hdr) = check_in_inbox( iv_wi_id = iv_wi_id iv_user = iv_user ).

    SELECT SINGLE top_wi_id, top_task FROM swwwihead
      WHERE wi_id = @iv_wi_id INTO @DATA(ls_top).

    DATA(ls_row) = VALUE zehsm_wf_teams( wi_id      = iv_wi_id
                                         user_id    = iv_user
                                         email      = iv_email
                                         top_wi_id  = ls_top-top_wi_id
                                         top_task   = ls_top-top_task
                                         wi_rh_task = ls_hdr-wi_rh_task
                                         status     = c_sent ).
    GET TIME STAMP FIELD ls_row-sent_on.
    MODIFY zehsm_wf_teams FROM @ls_row.

    MESSAGE ID c_msgid TYPE 'S' NUMBER '012' WITH iv_wi_id iv_user INTO rv_msg.
    log( iv_wi_id ).
  ENDMETHOD.


  METHOD execute_decision.
    DATA: ls_att_head TYPE swr_att_header,
          ls_att_id   TYPE swr_att_id,
          ls_note     TYPE swrsobjid,
          lv_rc       TYPE sysubrc,
          lt_msg      TYPE STANDARD TABLE OF swr_mstruc.

    check_in_inbox( iv_wi_id = iv_wi_id iv_user = iv_user ).

    DATA(lo_wi) = NEW /iwwrk/cl_wf_read_workitem( iv_workitem_id = iv_wi_id ).
    IF lo_wi->is_user_decision_task( ) = abap_false.
      raise_error( iv_msgno = '006' iv_v1 = iv_wi_id iv_wi_id = iv_wi_id ).
    ENDIF.

    DATA(lt_opt) = get_decision_options( iv_wi_id ).
    READ TABLE lt_opt INTO DATA(ls_opt) WITH KEY decision_key = iv_decision_key.
    IF sy-subrc <> 0.
      raise_error( iv_msgno = '007' iv_v1 = iv_decision_key iv_v2 = iv_wi_id iv_wi_id = iv_wi_id ).
    ENDIF.

    IF ls_opt-comment_mandatory = abap_true AND iv_comment IS INITIAL.
      raise_error( iv_msgno = '008' iv_v1 = ls_opt-decision_text iv_wi_id = iv_wi_id ).
    ENDIF.

    IF iv_comment IS NOT INITIAL.
      ls_att_head = VALUE #( file_name      = 'User Comments'
                             file_extension = 'HTM'
                             file_type      = 'T' ).
      CALL FUNCTION 'SAP_WAPI_ATTACHMENT_ADD'
        EXPORTING
          workitem_id      = iv_wi_id
          att_header       = ls_att_head
          att_txt          = iv_comment
          document_owner   = iv_user
          language         = sy-langu
          do_commit        = abap_true
          comment_semantic = abap_true
        IMPORTING
          return_code      = lv_rc
          att_id           = ls_att_id.
      IF lv_rc <> 0.
        raise_error( iv_msgno = '009' iv_v1 = iv_wi_id iv_wi_id = iv_wi_id ).
      ENDIF.
      ls_note-object_id = VALUE swotobjid( objtype = 'SOFM' objkey = ls_att_id-doc_id ).
    ENDIF.

    CALL FUNCTION 'SAP_WAPI_DECISION_COMPLETE'
      EXPORTING
        workitem_id    = iv_wi_id
        user           = iv_user
        decision_key   = iv_decision_key
        do_commit      = abap_true
        decision_note  = ls_note
      IMPORTING
        return_code    = lv_rc
      TABLES
        message_struct = lt_msg.
    IF lv_rc <> 0.
      DATA(ls_msg) = VALUE #( lt_msg[ 1 ] OPTIONAL ).
      DATA lv_err TYPE bapi_msg.
      IF ls_msg-msgid IS NOT INITIAL.
        MESSAGE ID ls_msg-msgid TYPE 'E' NUMBER ls_msg-msgno
          WITH ls_msg-msgv1 ls_msg-msgv2 ls_msg-msgv3 ls_msg-msgv4 INTO lv_err.
      ENDIF.
      raise_error( iv_msgno = '010' iv_v1 = iv_wi_id iv_v2 = lv_err iv_wi_id = iv_wi_id ).
    ENDIF.

    SELECT SINGLE * FROM zehsm_wf_teams
      WHERE wi_id = @iv_wi_id AND user_id = @iv_user INTO @DATA(ls_row).
    IF sy-subrc <> 0.
      SELECT SINGLE top_wi_id, top_task, wi_rh_task FROM swwwihead
        WHERE wi_id = @iv_wi_id INTO CORRESPONDING FIELDS OF @ls_row.
      ls_row-wi_id   = iv_wi_id.
      ls_row-user_id = iv_user.
    ENDIF.
    ls_row-status         = c_decided.
    ls_row-decision_key   = iv_decision_key.
    ls_row-decision_text  = ls_opt-decision_text.
    ls_row-comment_doc_id = ls_att_id-doc_id.
    GET TIME STAMP FIELD ls_row-decided_on.
    MODIFY zehsm_wf_teams FROM @ls_row.

    MESSAGE ID c_msgid TYPE 'S' NUMBER '011' WITH iv_wi_id ls_opt-decision_text iv_user INTO rv_msg.
    log( iv_wi_id ).
  ENDMETHOD.


  METHOD read_worklist.
    DATA: lv_rc TYPE sysubrc,
          lt_wl TYPE STANDARD TABLE OF swr_wihdr.

    CALL FUNCTION 'SAP_WAPI_CREATE_WORKLIST'
      EXPORTING
        user              = iv_user
        language          = sy-langu
        translate_wi_text = abap_true
        read_task_text    = abap_true
      IMPORTING
        return_code       = lv_rc
      TABLES
        worklist          = lt_wl.

    DELETE lt_wl WHERE wi_type <> 'W'
                    OR ( wi_stat <> 'READY' AND wi_stat <> 'SELECTED' AND wi_stat <> 'STARTED' ).
    rt_wl = lt_wl.
  ENDMETHOD.


  METHOD check_in_inbox.
    DATA(lt_wl) = read_worklist( iv_user ).
    READ TABLE lt_wl INTO rs_hdr WITH KEY wi_id = iv_wi_id.
    IF sy-subrc <> 0.
      raise_error( iv_msgno = '005' iv_v1 = iv_wi_id iv_v2 = iv_user iv_wi_id = iv_wi_id ).
    ENDIF.
  ENDMETHOD.


  METHOD build_item.
    DATA ls_lead TYPE swr_obj_2.

    rs_item = CORRESPONDING #( is_hdr ).

    DATA(lo_wi) = NEW /iwwrk/cl_wf_read_workitem( iv_workitem_id = is_hdr-wi_id ).
    lo_wi->get_wi_description( IMPORTING et_wi_description = DATA(lt_desc) ).
    LOOP AT lt_desc INTO DATA(ls_desc).
      rs_item-description = COND #( WHEN sy-tabix = 1 THEN ls_desc-textline
                                    ELSE rs_item-description && cl_abap_char_utilities=>newline && ls_desc-textline ).
    ENDLOOP.

    SELECT SINGLE top_wi_id, top_task FROM swwwihead
      WHERE wi_id = @is_hdr-wi_id INTO (@rs_item-top_wi_id, @rs_item-top_task).
    IF rs_item-top_wi_id IS NOT INITIAL.
      SELECT SINGLE wi_text FROM swwwihead
        WHERE wi_id = @rs_item-top_wi_id INTO @rs_item-top_wi_text.
    ENDIF.

    CALL FUNCTION 'SAP_WAPI_GET_OBJECTS'
      EXPORTING
        workitem_id      = is_hdr-wi_id
      IMPORTING
        leading_object_2 = ls_lead.
    rs_item-lead_catid  = ls_lead-catid.
    rs_item-lead_typeid = ls_lead-typeid.
    rs_item-lead_instid = ls_lead-instid.

    rs_item-decision_supported = xsdbool( lo_wi->is_user_decision_task( ) = abap_true
                                          AND get_decision_options( is_hdr-wi_id ) IS NOT INITIAL ).
  ENDMETHOD.


  METHOD raise_error.
    DATA lv_text TYPE bapi_msg.
    MESSAGE ID c_msgid TYPE 'E' NUMBER iv_msgno WITH iv_v1 iv_v2 iv_v3 INTO lv_text.
    log( iv_wi_id ).
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid  = /iwbep/cx_mgw_busi_exception=>business_error
        message = lv_text.
  ENDMETHOD.


  METHOD log.
    DATA: ls_log    TYPE bal_s_log,
          ls_msg    TYPE bal_s_msg,
          lv_handle TYPE balloghndl,
          lt_handle TYPE bal_t_logh.

    ls_msg = VALUE #( msgty = sy-msgty msgid = sy-msgid msgno = sy-msgno
                      msgv1 = sy-msgv1 msgv2 = sy-msgv2 msgv3 = sy-msgv3 msgv4 = sy-msgv4 ).
    ls_log = VALUE #( object    = 'ZEHSM'
                      subobject = 'WF_TEAMS'
                      extnumber = iv_wi_id
                      aluser    = sy-uname
                      alprog    = sy-repid ).

    CALL FUNCTION 'BAL_LOG_CREATE'
      EXPORTING
        i_s_log      = ls_log
      IMPORTING
        e_log_handle = lv_handle
      EXCEPTIONS
        OTHERS       = 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAL_LOG_MSG_ADD'
      EXPORTING
        i_log_handle = lv_handle
        i_s_msg      = ls_msg
      EXCEPTIONS
        OTHERS       = 1.

    INSERT lv_handle INTO TABLE lt_handle.
    CALL FUNCTION 'BAL_DB_SAVE'
      EXPORTING
        i_t_log_handle       = lt_handle
        i_2th_connection     = abap_true
        i_2th_connect_commit = abap_true
      EXCEPTIONS
        OTHERS               = 1.
  ENDMETHOD.

ENDCLASS.
