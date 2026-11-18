CLASS zcl_zehsm_wf_teams_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zehsm_wf_teams_dpc
  CREATE PUBLIC.

  PROTECTED SECTION.
    METHODS workitemset_get_entityset REDEFINITION.
    METHODS workitemset_get_entity    REDEFINITION.
    METHODS decoptionset_get_entityset REDEFINITION.
    METHODS objectset_get_entityset   REDEFINITION.
    METHODS commentset_get_entityset  REDEFINITION.
    METHODS decisionset_create_entity REDEFINITION.
    METHODS sentackset_create_entity  REDEFINITION.

  PRIVATE SECTION.
    DATA mo_api TYPE REF TO zcl_ehsm_wf_teams_api.

    METHODS api
      RETURNING VALUE(ro_api) TYPE REF TO zcl_ehsm_wf_teams_api.

    METHODS filter_value
      IMPORTING io_ctx      TYPE REF TO /iwbep/if_mgw_req_entityset
                iv_prop     TYPE string
      RETURNING VALUE(rv_v) TYPE string.

    METHODS source_wi_id
      IMPORTING it_key_tab      TYPE /iwbep/t_mgw_name_value_pair
                io_ctx          TYPE REF TO /iwbep/if_mgw_req_entityset
      RETURNING VALUE(rv_wi_id) TYPE sww_wiid
      RAISING   /iwbep/cx_mgw_busi_exception.
ENDCLASS.


CLASS zcl_zehsm_wf_teams_dpc_ext IMPLEMENTATION.

  METHOD api.
    IF mo_api IS NOT BOUND.
      mo_api = NEW #( ).
    ENDIF.
    ro_api = mo_api.
  ENDMETHOD.


  METHOD filter_value.
    DATA(lt_so) = io_ctx->get_filter( )->get_filter_select_options( ).
    READ TABLE lt_so INTO DATA(ls_so) WITH KEY property = iv_prop.
    IF sy-subrc = 0 AND ls_so-select_options IS NOT INITIAL.
      rv_v = ls_so-select_options[ 1 ]-low.
    ENDIF.
  ENDMETHOD.


  METHOD source_wi_id.
    READ TABLE it_key_tab INTO DATA(ls_key) WITH KEY name = 'WiId'.
    IF sy-subrc = 0.
      rv_wi_id = ls_key-value.
    ELSE.
      rv_wi_id = filter_value( io_ctx = io_ctx iv_prop = 'WI_ID' ).
    ENDIF.
    IF rv_wi_id IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid  = /iwbep/cx_mgw_busi_exception=>business_error
          message = 'Provide WiId'.
    ENDIF.
  ENDMETHOD.


  METHOD workitemset_get_entityset.
    DATA(lv_email) = CONV ad_smtpadr( filter_value( io_ctx = io_tech_request_context iv_prop = 'EMAIL' ) ).
    DATA(lv_user)  = api( )->resolve_user(
                       iv_user  = CONV #( filter_value( io_ctx = io_tech_request_context iv_prop = 'USER_ID' ) )
                       iv_email = lv_email ).
    DATA(lv_incl)  = xsdbool( filter_value( io_ctx = io_tech_request_context iv_prop = 'INCLUDE_SENT' ) = abap_true ).

    et_entityset = api( )->get_items( iv_user         = lv_user
                                      iv_email        = lv_email
                                      iv_include_sent = lv_incl ).
  ENDMETHOD.


  METHOD workitemset_get_entity.
    READ TABLE it_key_tab INTO DATA(ls_key) WITH KEY name = 'WiId'.
    er_entity = api( )->get_item( CONV #( ls_key-value ) ).
  ENDMETHOD.


  METHOD decoptionset_get_entityset.
    et_entityset = api( )->get_decision_options(
                     source_wi_id( it_key_tab = it_key_tab io_ctx = io_tech_request_context ) ).
  ENDMETHOD.


  METHOD objectset_get_entityset.
    et_entityset = api( )->get_objects(
                     source_wi_id( it_key_tab = it_key_tab io_ctx = io_tech_request_context ) ).
  ENDMETHOD.


  METHOD commentset_get_entityset.
    et_entityset = api( )->get_comments(
                     source_wi_id( it_key_tab = it_key_tab io_ctx = io_tech_request_context ) ).
  ENDMETHOD.


  METHOD decisionset_create_entity.
    io_data_provider->read_entry_data( IMPORTING es_data = er_entity ).

    DATA(lv_user) = api( )->resolve_user( iv_user = er_entity-user_id iv_email = er_entity-email ).
    er_entity-message = api( )->execute_decision( iv_wi_id        = er_entity-wi_id
                                                  iv_user         = lv_user
                                                  iv_decision_key = er_entity-decision_key
                                                  iv_comment      = er_entity-comment_text ).
    er_entity-user_id = lv_user.
    er_entity-status  = 'S'.
  ENDMETHOD.


  METHOD sentackset_create_entity.
    io_data_provider->read_entry_data( IMPORTING es_data = er_entity ).

    DATA(lv_user) = api( )->resolve_user( iv_user = er_entity-user_id iv_email = er_entity-email ).
    er_entity-message = api( )->mark_sent( iv_wi_id = er_entity-wi_id
                                           iv_user  = lv_user
                                           iv_email = er_entity-email ).
    er_entity-user_id = lv_user.
    er_entity-status  = 'S'.
  ENDMETHOD.

ENDCLASS.
