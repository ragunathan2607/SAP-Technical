*&---------------------------------------------------------------------*
*& Report  ZOO_CLASS_EXTRACTOR
*&---------------------------------------------------------------------*
*& Class / Interface Extractor - dumps EVERYTHING about one or many
*& global classes / interfaces (SE24 objects):
*&
*&  1  METADATA      SEOCLASS / SEOCLASSDF (every property with its
*&                   fixed-value text), descriptions in all languages,
*&                   TADIR, package, superclass chain, subclasses /
*&                   implementers, all includes of the class pool,
*&                   component statistics
*&  2  RELATIONS     SEOMETAREL, interfaces (incl. nested / inherited),
*&                   friends, "friend of", type-pools / forward decl.
*&  3  ATTRIBUTES    as ABAP declaration: visibility, DATA / CLASS-DATA /
*&                   CONSTANTS, typing, READ-ONLY, VALUE, description,
*&                   created / changed, source snippet for complex types
*&  4  METHODS       full signature as ABAP declaration: IMPORTING /
*&                   EXPORTING / CHANGING / RETURNING, VALUE(), typing,
*&                   OPTIONAL, DEFAULT, PREFERRED PARAMETER, RAISING /
*&                   EXCEPTIONS, ABSTRACT, FINAL, FOR EVENT, aliases,
*&                   every description; redefinitions with the
*&                   signature taken from the defining class
*&  5  EVENTS        with parameters
*&  6  TYPES         class types incl. the source of complex types
*&  7  INHERITED     every non-private component of every superclass
*&                   and every component of every implemented interface
*&  8  RTTI          runtime view (resolved types, inherited, aliases)
*&  9  DDIC          every structure / table type used in signatures
*&                   expanded recursively (fields, data elements,
*&                   lengths, labels, keys, .INCLUDEs), every data
*&                   element with domain, conversion exit, fixed values
*& 10  VALUES        runtime values of constants / static attributes,
*&                   incl. T100 and OTR texts of exception classes
*& 11  DOCU          SE61 documentation of class and components,
*&                   text pool (text symbols)
*& 12  SOURCE        every include of the pool (CP, CU, CO, CI, CCDEF,
*&                   CCMAC, CCIMP, CCAU, CT, every method, IP / IU ...)
*&                   with line numbers
*& 13  LOCAL         local classes / interfaces of the class pool
*& 14  ENHANCEMENTS  ENHOBJ entries + enhancement implementation source
*& 15  TRANSPORTS    E071 / E070 / E07T, version history VRSD,
*&                   inactive objects DWINACTIV
*& 16  WHERE-USED    WBCROSSGT / CROSS (used by + uses)
*& 17  RAW           every field of every row of every SEO* table
*&
*& Input : class / interface name(s) - select-options, so single
*&         values, lists, ranges and patterns (ZCL_MY*) all work.
*& Output: list + one .txt file per class (desktop / SAP GUI work
*&         directory / C:\temp or the directory you choose).
*&
*& No text elements and no selection texts to maintain - everything is
*& set in INITIALIZATION.
*&
*& Release-safe by design: every field that is not part of a table key
*& is read dynamically (ASSIGN COMPONENT), and every optional table is
*& read with a dynamic SELECT inside TRY/CATCH. A field or table that
*& does not exist on your release is simply skipped - it cannot cause a
*& syntax error or a short dump.
*&
*& READ ONLY. No INSERT / UPDATE / MODIFY / DELETE, no COMMIT, no
*& ENQUEUE. Safe in any client including production.
*&---------------------------------------------------------------------*
REPORT zoo_class_extractor LINE-SIZE 1023 NO STANDARD PAGE HEADING.

TABLES sscrfields.

*&---------------------------------------------------------------------*
*& Global types
*&---------------------------------------------------------------------*
TYPES: BEGIN OF ty_s_opt,
         meta  TYPE abap_bool,
         rel   TYPE abap_bool,
         attr  TYPE abap_bool,
         meth  TYPE abap_bool,
         evt   TYPE abap_bool,
         typ   TYPE abap_bool,
         inh   TYPE abap_bool,
         rtti  TYPE abap_bool,
         ddic  TYPE abap_bool,
         cval  TYPE abap_bool,
         doc   TYPE abap_bool,
         src   TYPE abap_bool,
         loc   TYPE abap_bool,
         enh   TYPE abap_bool,
         tr    TYPE abap_bool,
         wu    TYPE abap_bool,
         raw   TYPE abap_bool,
         init  TYPE abap_bool,
         depth TYPE i,
         maxr  TYPE i,
       END OF ty_s_opt.

" One component (attribute / method / event / type / alias) of a
" class or interface, built from SEOCOMPO + SEOCOMPODF + SEOCOMPOTX.
" DF keeps the complete SEOCOMPODF row for the raw detail.
TYPES: BEGIN OF ty_s_comp,
         clsname    TYPE seoclsname,
         cmpname    TYPE seocmpname,
         cmptype    TYPE string,      " 0 attr 1 method 2 event 3 type
         mtdtype    TYPE string,
         exposure   TYPE string,      " 0 private 1 protected 2 public
         decl       TYPE string,      " instance / static / constant
         rdonly     TYPE string,
         attvalue   TYPE string,
         typtype    TYPE string,
         typename   TYPE string,
         tableof    TYPE string,
         isabstract TYPE string,
         isfinal    TYPE string,
         newexc     TYPE string,
         isalias    TYPE string,
         refcls     TYPE string,
         refint     TYPE string,
         refcmp     TYPE string,
         editorder  TYPE i,
         srcrow1    TYPE i,
         srcrow2    TYPE i,
         descr      TYPE string,
         df         TYPE seocompodf,
       END OF ty_s_comp,
       ty_t_comp TYPE STANDARD TABLE OF ty_s_comp WITH EMPTY KEY.

" One parameter / exception, built from SEOSUBCO + SEOSUBCODF +
" SEOSUBCOTX.
TYPES: BEGIN OF ty_s_sub,
         clsname    TYPE seoclsname,
         cmpname    TYPE seocmpname,
         sconame    TYPE seosconame,
         scotype    TYPE string,      " 0 parameter 1 exception
         decl       TYPE string,      " 0 imp 1 exp 2 chg 3 ret
         pass       TYPE string,      " 0 value 1 reference
         typtype    TYPE string,
         typename   TYPE string,
         tableof    TYPE string,
         isoptional TYPE string,
         defval     TYPE string,
         preferred  TYPE string,
         editorder  TYPE i,
         descr      TYPE string,
         df         TYPE seosubcodf,
       END OF ty_s_sub,
       ty_t_sub TYPE STANDARD TABLE OF ty_s_sub WITH EMPTY KEY.

TYPES: BEGIN OF ty_s_model,
         clsname TYPE seoclsname,
         found   TYPE abap_bool,
         isintf  TYPE abap_bool,
         comps   TYPE ty_t_comp,
         subs    TYPE ty_t_sub,
       END OF ty_s_model,
       ty_t_model TYPE HASHED TABLE OF ty_s_model WITH UNIQUE KEY clsname.

TYPES ty_t_clsname TYPE STANDARD TABLE OF seoclsname WITH EMPTY KEY.

*&---------------------------------------------------------------------*
*& Selection screen
*&---------------------------------------------------------------------*
DATA gv_clsname TYPE seoclsname.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE t_b1.
SELECT-OPTIONS s_cls FOR gv_clsname.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE t_b2.
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN PUSHBUTTON 1(20)  b_all  USER-COMMAND sall.
SELECTION-SCREEN PUSHBUTTON 23(20) b_none USER-COMMAND snone.
SELECTION-SCREEN END OF LINE.
PARAMETERS: p_meta AS CHECKBOX DEFAULT 'X',
            p_rel  AS CHECKBOX DEFAULT 'X',
            p_attr AS CHECKBOX DEFAULT 'X',
            p_meth AS CHECKBOX DEFAULT 'X',
            p_evt  AS CHECKBOX DEFAULT 'X',
            p_typ  AS CHECKBOX DEFAULT 'X',
            p_inh  AS CHECKBOX DEFAULT 'X',
            p_rtti AS CHECKBOX DEFAULT 'X',
            p_ddic AS CHECKBOX DEFAULT 'X',
            p_cval AS CHECKBOX DEFAULT 'X',
            p_doc  AS CHECKBOX DEFAULT 'X',
            p_src  AS CHECKBOX DEFAULT 'X',
            p_loc  AS CHECKBOX DEFAULT 'X',
            p_enh  AS CHECKBOX DEFAULT 'X',
            p_tr   AS CHECKBOX DEFAULT 'X',
            p_wu   AS CHECKBOX DEFAULT 'X',
            p_raw  AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE t_b3.
PARAMETERS: p_depth TYPE i DEFAULT 5,
            p_maxr  TYPE i DEFAULT 1000,
            p_init  AS CHECKBOX DEFAULT ' ',
            p_list  AS CHECKBOX DEFAULT 'X',
            p_down  AS CHECKBOX DEFAULT 'X',
            p_dir   TYPE c LENGTH 200 LOWER CASE.
SELECTION-SCREEN END OF BLOCK b3.

*&---------------------------------------------------------------------*
*& Output collector
*&---------------------------------------------------------------------*
CLASS lcl_out DEFINITION FINAL.

  PUBLIC SECTION.
    TYPES ty_t_line TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    " All parameters BY VALUE: char-like actual parameters are converted
    " implicitly, no "not type-compatible" syntax errors.
    METHODS add
      IMPORTING VALUE(iv_text) TYPE string OPTIONAL.

    METHODS head
      IMPORTING VALUE(iv_text) TYPE string.

    METHODS sub
      IMPORTING VALUE(iv_text) TYPE string.

    METHODS kv
      IMPORTING VALUE(iv_key)   TYPE string
                VALUE(iv_value) TYPE string.

    METHODS get
      RETURNING VALUE(rt_line) TYPE ty_t_line.

  PRIVATE SECTION.
    DATA mt_line TYPE ty_t_line.

ENDCLASS.

CLASS lcl_out IMPLEMENTATION.

  METHOD add.
    APPEND iv_text TO mt_line.
  ENDMETHOD.

  METHOD head.
    APPEND `` TO mt_line.
    APPEND repeat( val = `=` occ = 100 ) TO mt_line.
    APPEND |== { iv_text }| TO mt_line.
    APPEND repeat( val = `=` occ = 100 ) TO mt_line.
  ENDMETHOD.

  METHOD sub.
    APPEND `` TO mt_line.
    APPEND |-- { iv_text }| TO mt_line.
  ENDMETHOD.

  METHOD kv.
    APPEND |  { iv_key WIDTH = 28 } : { iv_value }| TO mt_line.
  ENDMETHOD.

  METHOD get.
    rt_line = mt_line.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Generic helpers: dynamic field access, fixed values, generic SELECT,
*& generic row dump, source cache, download
*&---------------------------------------------------------------------*
CLASS lcl_util DEFINITION FINAL.

  PUBLIC SECTION.
    TYPES ty_t_string TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    TYPES: BEGIN OF ty_s_dom,
             domname TYPE string,
             low     TYPE string,
             high    TYPE string,
             text    TYPE string,
           END OF ty_s_dom,
           ty_t_dom TYPE STANDARD TABLE OF ty_s_dom WITH EMPTY KEY.

    " value of a component of any structure - '' if it does not exist
    CLASS-METHODS fv
      IMPORTING is_row        TYPE any
                iv_field      TYPE csequence
      RETURNING VALUE(rv_val) TYPE string.

    " same, plus the fixed-value text of the domain, e.g. "2 (Public)"
    CLASS-METHODS fvt
      IMPORTING is_row        TYPE any
                iv_field      TYPE csequence
      RETURNING VALUE(rv_val) TYPE string.

    CLASS-METHODS to_text
      IMPORTING iv_val        TYPE any
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS val_text
      IMPORTING iv_val        TYPE any
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS dom_values
      IMPORTING iv_domain     TYPE csequence
      RETURNING VALUE(rt_val) TYPE ty_t_dom.

    CLASS-METHODS dom_text
      IMPORTING iv_domain     TYPE csequence
                iv_value      TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS to_int
      IMPORTING VALUE(iv_val) TYPE string
      RETURNING VALUE(rv_int) TYPE i.

    CLASS-METHODS vis
      IMPORTING iv_exposure   TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS quote
      IMPORTING iv_val        TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS like_escape
      IMPORTING iv_val        TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    " ZCL_X -> ZCL_X=========================  (30 chars)
    CLASS-METHODS pool_prefix
      IMPORTING iv_cls        TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    " ZCL_X -> 'ZCL_X                         %'  (LIMU METH objects)
    CLASS-METHODS limu_pattern
      IMPORTING iv_cls        TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS generic_select
      IMPORTING iv_table      TYPE csequence
                iv_where      TYPE csequence
                iv_max        TYPE i DEFAULT 0
      RETURNING VALUE(rr_tab) TYPE REF TO data.

    CLASS-METHODS dump_struct
      IMPORTING io_out     TYPE REF TO lcl_out
                is_row     TYPE any
                iv_indent  TYPE i
                iv_initial TYPE abap_bool.

    CLASS-METHODS dump_rows
      IMPORTING io_out          TYPE REF TO lcl_out
                ir_tab          TYPE REF TO data
                VALUE(iv_title) TYPE string
                iv_initial      TYPE abap_bool.

    CLASS-METHODS read_source
      IMPORTING iv_prog TYPE csequence
      EXPORTING et_src  TYPE ty_t_string
                ev_ok   TYPE abap_bool.

    CLASS-METHODS reset.

    CLASS-METHODS download
      IMPORTING it_line        TYPE lcl_out=>ty_t_line
                iv_name        TYPE csequence
                iv_dir         TYPE csequence
      RETURNING VALUE(rv_file) TYPE string.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_s_src,
             prog  TYPE progname,
             ok    TYPE abap_bool,
             lines TYPE ty_t_string,
           END OF ty_s_src.

    CLASS-DATA gt_dom        TYPE ty_t_dom.
    CLASS-DATA gt_dom_loaded TYPE ty_t_string.
    CLASS-DATA gt_src        TYPE HASHED TABLE OF ty_s_src WITH UNIQUE KEY prog.

ENDCLASS.

CLASS lcl_util IMPLEMENTATION.

*----------------------------------------------------------------------*
  METHOD fv.
    FIELD-SYMBOLS <lv_any> TYPE any.

    CLEAR rv_val.
    ASSIGN COMPONENT iv_field OF STRUCTURE is_row TO <lv_any>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    rv_val = to_text( <lv_any> ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD fvt.
    FIELD-SYMBOLS <lv_any> TYPE any.

    CLEAR rv_val.
    ASSIGN COMPONENT iv_field OF STRUCTURE is_row TO <lv_any>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    rv_val = val_text( <lv_any> ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD to_text.
    FIELD-SYMBOLS: <lv_date> TYPE d,
                   <lv_time> TYPE t.

    CLEAR rv_txt.
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( iv_val ).

    IF lo_type->kind <> cl_abap_typedescr=>kind_elem.
      rv_txt = SWITCH #( lo_type->kind
                 WHEN cl_abap_typedescr=>kind_struct THEN `(structure)`
                 WHEN cl_abap_typedescr=>kind_table  THEN `(table)`
                 WHEN cl_abap_typedescr=>kind_ref    THEN `(reference)`
                 ELSE `(complex)` ).
      RETURN.
    ENDIF.

    CASE lo_type->type_kind.
      WHEN cl_abap_typedescr=>typekind_date.
        ASSIGN iv_val TO <lv_date>.
        IF <lv_date> IS NOT INITIAL.
          rv_txt = |{ <lv_date> DATE = ISO }|.
        ENDIF.
      WHEN cl_abap_typedescr=>typekind_time.
        ASSIGN iv_val TO <lv_time>.
        rv_txt = |{ <lv_time> TIME = ISO }|.
      WHEN OTHERS.
        rv_txt = |{ iv_val }|.
    ENDCASE.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD val_text.
    DATA lo_elem  TYPE REF TO cl_abap_elemdescr.
    DATA ls_dfies TYPE dfies.

    rv_txt = to_text( iv_val ).
    IF rv_txt IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        lo_elem ?= cl_abap_typedescr=>describe_by_data( iv_val ).
      CATCH cx_sy_move_cast_error.
        RETURN.
    ENDTRY.

    IF lo_elem->is_ddic_type( ) = abap_false.
      RETURN.
    ENDIF.

    lo_elem->get_ddic_field(
      RECEIVING  p_flddescr = ls_dfies
      EXCEPTIONS OTHERS     = 1 ).
    IF sy-subrc <> 0 OR ls_dfies-domname IS INITIAL OR ls_dfies-valexi IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_text) = dom_text( iv_domain = ls_dfies-domname
                              iv_value  = rv_txt ).
    IF lv_text IS NOT INITIAL.
      rv_txt = |{ rv_txt } ({ lv_text })|.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD dom_values.
    DATA lv_dom TYPE domname.

    lv_dom = to_upper( iv_domain ).
    DATA(lv_key) = CONV string( lv_dom ).

    IF NOT line_exists( gt_dom_loaded[ table_line = lv_key ] ).
      APPEND lv_key TO gt_dom_loaded.

      SELECT domvalue_l, domvalue_h, ddtext, ddlanguage, valpos
        FROM dd07v
        WHERE domname = @lv_dom
        ORDER BY valpos
        INTO TABLE @DATA(lt_val).

      DATA(lv_lang) = sy-langu.
      IF NOT line_exists( lt_val[ ddlanguage = sy-langu ] ).
        lv_lang = 'E'.
      ENDIF.

      LOOP AT lt_val INTO DATA(ls_val)
           WHERE ddlanguage = lv_lang OR ddlanguage IS INITIAL.
        APPEND VALUE #( domname = lv_key
                        low     = ls_val-domvalue_l
                        high    = ls_val-domvalue_h
                        text    = ls_val-ddtext ) TO gt_dom.
      ENDLOOP.
    ENDIF.

    rt_val = VALUE #( FOR ls_dom IN gt_dom WHERE ( domname = lv_key ) ( ls_dom ) ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD dom_text.
    DATA(lt_val) = dom_values( iv_domain ).
    DATA(lv_val) = CONV string( iv_value ).
    READ TABLE lt_val INTO DATA(ls_val) WITH KEY low = lv_val.
    IF sy-subrc = 0.
      rv_txt = ls_val-text.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD to_int.
    TRY.
        rv_int = iv_val.
      CATCH cx_sy_conversion_error.
        rv_int = 0.
    ENDTRY.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD vis.
    rv_txt = SWITCH #( iv_exposure
               WHEN '0' THEN `PRIVATE`
               WHEN '1' THEN `PROTECTED`
               WHEN '2' THEN `PUBLIC`
               ELSE |EXPOSURE { iv_exposure }| ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD quote.
    rv_txt = cl_abap_dyn_prg=>quote( CONV string( iv_val ) ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD like_escape.
    " ESCAPE '#' - '_' and '%' are wildcards in LIKE, class names
    " are full of '_'
    rv_txt = iv_val.
    REPLACE ALL OCCURRENCES OF `#` IN rv_txt WITH `##`.
    REPLACE ALL OCCURRENCES OF `_` IN rv_txt WITH `#_`.
    REPLACE ALL OCCURRENCES OF `%` IN rv_txt WITH `#%`.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD pool_prefix.
    rv_txt = iv_cls.
    DATA(lv_len) = strlen( rv_txt ).
    IF lv_len < 30.
      rv_txt = rv_txt && repeat( val = `=` occ = 30 - lv_len ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD limu_pattern.
    DATA(lv_cls) = CONV string( iv_cls ).
    DATA(lv_len) = strlen( lv_cls ).
    rv_txt = like_escape( lv_cls ).
    IF lv_len < 30.
      rv_txt = rv_txt && repeat( val = ` ` occ = 30 - lv_len ).
    ENDIF.
    rv_txt = rv_txt && `%`.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD generic_select.
    " Dynamic table + dynamic WHERE inside TRY: a table or field that
    " does not exist on this release just yields "not available".
    FIELD-SYMBOLS <lt_tab> TYPE STANDARD TABLE.
    DATA lv_tab TYPE tabname.

    lv_tab = to_upper( iv_table ).
    TRY.
        CREATE DATA rr_tab TYPE STANDARD TABLE OF (lv_tab).
        ASSIGN rr_tab->* TO <lt_tab>.
        IF iv_max > 0.
          SELECT * FROM (lv_tab)
            WHERE (iv_where)
            INTO TABLE @<lt_tab>
            UP TO @iv_max ROWS.
        ELSE.
          SELECT * FROM (lv_tab)
            WHERE (iv_where)
            INTO TABLE @<lt_tab>.
        ENDIF.
      CATCH cx_root.
        CLEAR rr_tab.
    ENDTRY.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD dump_struct.
    " Every component with its DDIC label and fixed-value text.
    FIELD-SYMBOLS <lv_any> TYPE any.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    DATA lt_dfies  TYPE ddfields.

    DATA(lv_pad) = repeat( val = ` ` occ = iv_indent ).

    TRY.
        lo_struct ?= cl_abap_typedescr=>describe_by_data( is_row ).
      CATCH cx_sy_move_cast_error.
        io_out->add( |{ lv_pad }{ to_text( is_row ) }| ).
        RETURN.
    ENDTRY.

    lo_struct->get_ddic_field_list(
      RECEIVING  p_field_list = lt_dfies
      EXCEPTIONS OTHERS       = 1 ).
    IF sy-subrc <> 0.
      CLEAR lt_dfies.
    ENDIF.

    LOOP AT lo_struct->components INTO DATA(ls_comp).
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE is_row TO <lv_any>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF iv_initial = abap_false AND <lv_any> IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_label) = ``.
      READ TABLE lt_dfies INTO DATA(ls_dfies) WITH KEY fieldname = ls_comp-name.
      IF sy-subrc = 0.
        lv_label = COND #( WHEN ls_dfies-scrtext_l IS NOT INITIAL
                           THEN ls_dfies-scrtext_l
                           ELSE ls_dfies-fieldtext ).
      ENDIF.

      io_out->add( |{ lv_pad }{ ls_comp-name WIDTH = 30 } | &&
                   |{ lv_label WIDTH = 40 } : { val_text( <lv_any> ) }| ).
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD dump_rows.
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <ls_row> TYPE any.

    io_out->sub( iv_title ).

    IF ir_tab IS NOT BOUND.
      io_out->add( `     (table / field not available on this release or not readable)` ).
      RETURN.
    ENDIF.

    ASSIGN ir_tab->* TO <lt_tab>.
    IF <lt_tab> IS INITIAL.
      io_out->add( `     (no entries)` ).
      RETURN.
    ENDIF.

    DATA(lv_n) = 0.
    LOOP AT <lt_tab> ASSIGNING <ls_row>.
      lv_n = lv_n + 1.
      io_out->add( |     [{ lv_n }]| ).
      dump_struct( io_out     = io_out
                   is_row     = <ls_row>
                   iv_indent  = 7
                   iv_initial = iv_initial ).
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD read_source.
    " READ REPORT needs a flat character field (PROGNAME), never STRING.
    " If your release rejects a string table as target, change TY_S_SRC-
    " LINES to ABAPTXT255_TAB - nothing else depends on it.
    DATA lv_prog TYPE progname.
    DATA ls_src  TYPE ty_s_src.

    CLEAR: et_src, ev_ok.
    lv_prog = iv_prog.
    IF lv_prog IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE gt_src INTO ls_src WITH TABLE KEY prog = lv_prog.
    IF sy-subrc <> 0.
      CLEAR ls_src.
      ls_src-prog = lv_prog.
      READ REPORT lv_prog INTO ls_src-lines.
      ls_src-ok = xsdbool( sy-subrc = 0 ).
      IF ls_src-ok = abap_false.
        CLEAR ls_src-lines.
      ENDIF.
      INSERT ls_src INTO TABLE gt_src.
    ENDIF.

    et_src = ls_src-lines.
    ev_ok  = ls_src-ok.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD reset.
    CLEAR gt_src.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD download.
    DATA lv_dir  TYPE string.
    DATA lt_data TYPE lcl_out=>ty_t_line.

    " no frontend in background / batch input
    IF sy-batch = abap_true OR sy-binpt = abap_true.
      RETURN.
    ENDIF.

    lt_data = it_line.
    lv_dir  = iv_dir.

    TRY.
        IF lv_dir IS INITIAL.
          cl_gui_frontend_services=>get_desktop_directory(
            CHANGING   desktop_directory = lv_dir
            EXCEPTIONS OTHERS            = 1 ).
          cl_gui_cfw=>flush( ).
        ENDIF.

        IF lv_dir IS INITIAL.
          cl_gui_frontend_services=>get_sapgui_workdir(
            CHANGING   sapworkdir = lv_dir
            EXCEPTIONS OTHERS     = 1 ).
          cl_gui_cfw=>flush( ).
        ENDIF.

        IF lv_dir IS INITIAL.
          lv_dir = `C:\temp`.
        ENDIF.

        DATA(lv_name) = replace( val = CONV string( iv_name )
                                 sub = `/` with = `_` occ = 0 ).
        rv_file = |{ lv_dir }\\{ lv_name }_{ sy-datum }_{ sy-uzeit }.txt|.

        cl_gui_frontend_services=>gui_download(
          EXPORTING  filename = rv_file
                     filetype = 'ASC'
                     codepage = '4110'          " UTF-8
          CHANGING   data_tab = lt_data
          EXCEPTIONS OTHERS   = 1 ).

        IF sy-subrc <> 0.
          CLEAR rv_file.
        ENDIF.

      CATCH cx_root.
        CLEAR rv_file.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Extractor - one instance per class / interface
*&---------------------------------------------------------------------*
CLASS lcl_extractor DEFINITION FINAL.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_cls TYPE seoclsname
                is_opt TYPE ty_s_opt
                io_out TYPE REF TO lcl_out.

    METHODS run.

  PRIVATE SECTION.
    CONSTANTS gc_active TYPE c LENGTH 1 VALUE '1'.

    " Visibility typed from the RTTI structure itself - compatible
    " with ABAP_ATTRDESCR-VISIBILITY / ABAP_METHDESCR-VISIBILITY
    TYPES ty_visibility TYPE abap_attrdescr-visibility.

    TYPES: BEGIN OF ty_s_type,
             abs   TYPE string,
             name  TYPE string,
             usage TYPE string,
             ref   TYPE REF TO cl_abap_datadescr,
           END OF ty_s_type,
           ty_t_type TYPE STANDARD TABLE OF ty_s_type WITH EMPTY KEY.

    DATA mv_cls    TYPE seoclsname.
    DATA mv_isintf TYPE abap_bool.
    DATA mv_prefix TYPE string.
    DATA ms_opt    TYPE ty_s_opt.
    DATA mo_out    TYPE REF TO lcl_out.
    DATA mo_obj    TYPE REF TO cl_abap_objectdescr.
    DATA mt_chain  TYPE ty_t_clsname.
    DATA mt_model  TYPE ty_t_model.
    DATA mt_type   TYPE ty_t_type.
    DATA mt_elem   TYPE ty_t_type.
    DATA mt_redef  TYPE STANDARD TABLE OF seoredef WITH EMPTY KEY.

    METHODS resolve
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    METHODS read_chain.

    METHODS model
      IMPORTING VALUE(iv_cls)   TYPE seoclsname
      RETURNING VALUE(rr_model) TYPE REF TO ty_s_model.

    METHODS get_interfaces
      RETURNING VALUE(rt_intf) TYPE ty_t_clsname.

    " ---- sections (called dynamically from RUN) ----------------------
    METHODS sec_metadata.
    METHODS sec_relations.
    METHODS sec_attributes.
    METHODS sec_methods.
    METHODS sec_events.
    METHODS sec_types.
    METHODS sec_inherited.
    METHODS sec_rtti.
    METHODS sec_ddic.
    METHODS sec_values.
    METHODS sec_docu.
    METHODS sec_source.
    METHODS sec_local.
    METHODS sec_enhancements.
    METHODS sec_transports.
    METHODS sec_whereused.
    METHODS sec_raw.

    " ---- SEO model printers ------------------------------------------
    METHODS print_comps
      IMPORTING ir_model           TYPE REF TO ty_s_model
                VALUE(iv_cmptype)  TYPE string
                iv_skip_private    TYPE abap_bool
                VALUE(iv_title)    TYPE string.

    METHODS print_aliases
      IMPORTING ir_model        TYPE REF TO ty_s_model
                iv_skip_private TYPE abap_bool.

    METHODS print_attr
      IMPORTING ir_model TYPE REF TO ty_s_model
                is_comp  TYPE ty_s_comp.

    METHODS print_method
      IMPORTING ir_model       TYPE REF TO ty_s_model
                is_comp        TYPE ty_s_comp
                VALUE(iv_note) TYPE string OPTIONAL.

    METHODS print_event
      IMPORTING ir_model TYPE REF TO ty_s_model
                is_comp  TYPE ty_s_comp.

    METHODS print_type
      IMPORTING ir_model TYPE REF TO ty_s_model
                is_comp  TYPE ty_s_comp.

    METHODS print_params
      IMPORTING ir_model TYPE REF TO ty_s_model
                is_comp  TYPE ty_s_comp.

    METHODS print_snippet
      IMPORTING ir_model TYPE REF TO ty_s_model
                is_comp  TYPE ty_s_comp.

    METHODS print_audit
      IMPORTING is_comp TYPE ty_s_comp.

    METHODS typing
      IMPORTING VALUE(iv_typtype) TYPE string
                VALUE(iv_type)    TYPE string
                VALUE(iv_tableof) TYPE string
      RETURNING VALUE(rv_txt)     TYPE string.

    METHODS section_include
      IMPORTING ir_model         TYPE REF TO ty_s_model
                VALUE(iv_expo)   TYPE string
      RETURNING VALUE(rv_prog)   TYPE progname.

    " ---- RTTI ----------------------------------------------------------
    METHODS print_rtti
      IMPORTING io_obj          TYPE REF TO cl_abap_objectdescr
                VALUE(iv_title) TYPE string.

    METHODS collect_types.

    METHODS collect_type
      IMPORTING io_type         TYPE REF TO cl_abap_datadescr
                VALUE(iv_usage) TYPE string.

    METHODS expand_type
      IMPORTING io_type   TYPE REF TO cl_abap_datadescr
                iv_indent TYPE i
                iv_depth  TYPE i.

    METHODS type_label
      IMPORTING io_type       TYPE REF TO cl_abap_typedescr
      RETURNING VALUE(rv_txt) TYPE string.

    METHODS field_extra
      IMPORTING io_type       TYPE REF TO cl_abap_datadescr
      RETURNING VALUE(rv_txt) TYPE string.

    METHODS vis_text
      IMPORTING VALUE(iv_vis) TYPE ty_visibility
      RETURNING VALUE(rv_txt) TYPE string.

    METHODS parm_text
      IMPORTING VALUE(iv_kind) TYPE abap_parmkind
      RETURNING VALUE(rv_txt)  TYPE string.

    " ---- misc ----------------------------------------------------------
    METHODS print_value
      IMPORTING iv_val         TYPE any
                VALUE(iv_name) TYPE string
                iv_indent      TYPE i.

    METHODS print_include
      IMPORTING VALUE(iv_prog)  TYPE progname
                VALUE(iv_title) TYPE string
                iv_quiet        TYPE abap_bool DEFAULT abap_false.

ENDCLASS.

CLASS lcl_extractor IMPLEMENTATION.

*----------------------------------------------------------------------*
  METHOD constructor.
    mv_cls    = to_upper( iv_cls ).
    ms_opt    = is_opt.
    mo_out    = io_out.
    mv_prefix = lcl_util=>pool_prefix( mv_cls ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD run.

    TYPES: BEGIN OF ty_s_sec,
             flag TYPE abap_bool,
             name TYPE string,
           END OF ty_s_sec,
           ty_t_sec TYPE STANDARD TABLE OF ty_s_sec WITH EMPTY KEY.

    lcl_util=>reset( ).

    mo_out->add( repeat( val = `#` occ = 100 ) ).
    mo_out->add( |CLASS EXTRACTOR - { mv_cls }| ).
    mo_out->add( |Generated { sy-datum DATE = ISO } { sy-uzeit TIME = ISO } | &&
                 |by { sy-uname } on { sy-sysid }/{ sy-mandt } (release { sy-saprl })| ).
    mo_out->add( repeat( val = `#` occ = 100 ) ).

    SELECT SINGLE clstype FROM seoclass
      WHERE clsname = @mv_cls
      INTO @DATA(lv_clstype).
    IF sy-subrc <> 0.
      mo_out->add( |*** { mv_cls } does not exist in SEOCLASS - not a global class / interface| ).
      RETURN.
    ENDIF.

    mv_isintf = xsdbool( lv_clstype = '1' ).

    IF resolve( ) = abap_false.
      mo_out->add( |*** RTTI could not load { mv_cls } (inactive / syntax error?) - | &&
                   |RTTI based sections are skipped, repository based sections are complete| ).
    ENDIF.

    read_chain( ).

    IF mv_isintf = abap_false.
      SELECT * FROM seoredef
        WHERE clsname = @mv_cls
          AND version = @gc_active
        ORDER BY PRIMARY KEY
        INTO TABLE @mt_redef.
    ENDIF.

    DATA(lt_sec) = VALUE ty_t_sec(
      ( flag = ms_opt-meta name = `SEC_METADATA` )
      ( flag = ms_opt-rel  name = `SEC_RELATIONS` )
      ( flag = ms_opt-attr name = `SEC_ATTRIBUTES` )
      ( flag = ms_opt-meth name = `SEC_METHODS` )
      ( flag = ms_opt-evt  name = `SEC_EVENTS` )
      ( flag = ms_opt-typ  name = `SEC_TYPES` )
      ( flag = ms_opt-inh  name = `SEC_INHERITED` )
      ( flag = ms_opt-rtti name = `SEC_RTTI` )
      ( flag = ms_opt-ddic name = `SEC_DDIC` )
      ( flag = ms_opt-cval name = `SEC_VALUES` )
      ( flag = ms_opt-doc  name = `SEC_DOCU` )
      ( flag = ms_opt-src  name = `SEC_SOURCE` )
      ( flag = ms_opt-loc  name = `SEC_LOCAL` )
      ( flag = ms_opt-enh  name = `SEC_ENHANCEMENTS` )
      ( flag = ms_opt-tr   name = `SEC_TRANSPORTS` )
      ( flag = ms_opt-wu   name = `SEC_WHEREUSED` )
      ( flag = ms_opt-raw  name = `SEC_RAW` ) ).

    " every section isolated: one failing section never stops the rest
    LOOP AT lt_sec INTO DATA(ls_sec) WHERE flag = abap_true.
      TRY.
          CALL METHOD me->(ls_sec-name).
        CATCH cx_root INTO DATA(lx_err).
          mo_out->add( |*** section { ls_sec-name } aborted: { lx_err->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.

    mo_out->add( `` ).
    mo_out->add( |#### END OF { mv_cls }| ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD resolve.

    DATA lo_descr TYPE REF TO cl_abap_typedescr.

    rv_ok = abap_false.

    cl_abap_typedescr=>describe_by_name(
      EXPORTING  p_name         = mv_cls
      RECEIVING  p_descr_ref    = lo_descr
      EXCEPTIONS type_not_found = 1
                 OTHERS         = 2 ).
    IF sy-subrc <> 0 OR lo_descr IS NOT BOUND.
      RETURN.
    ENDIF.

    TRY.
        mo_obj ?= lo_descr.
      CATCH cx_sy_move_cast_error.
        RETURN.
    ENDTRY.

    rv_ok = abap_true.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD read_chain.

    " Superclass chain from SEOMETAREL, RELTYPE = '2' (inheritance).
    " NOTE: SEOCLASSDF-REFCLSNAME is NOT the superclass.
    CLEAR mt_chain.
    IF mv_isintf = abap_true.
      RETURN.
    ENDIF.

    DATA(lv_current) = mv_cls.
    DO 30 TIMES.
      SELECT SINGLE refclsname FROM seometarel
        WHERE clsname = @lv_current
          AND reltype = '2'
          AND version = @gc_active
        INTO @DATA(lv_super).
      IF sy-subrc <> 0 OR lv_super IS INITIAL.
        EXIT.
      ENDIF.
      APPEND lv_super TO mt_chain.
      lv_current = lv_super.
    ENDDO.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD model.

    " Complete repository model of one class / interface (cached).
    " Only key fields are accessed statically - everything else via
    " LCL_UTIL=>FV, so a field missing on your release is just empty.
    DATA ls_model TYPE ty_s_model.
    DATA ls_comp  TYPE ty_s_comp.
    DATA ls_sub   TYPE ty_s_sub.
    DATA lt_compo TYPE STANDARD TABLE OF seocompo   WITH EMPTY KEY.
    DATA lt_cdf   TYPE STANDARD TABLE OF seocompodf WITH EMPTY KEY.
    DATA lt_ctx   TYPE STANDARD TABLE OF seocompotx WITH EMPTY KEY.
    DATA lt_sco   TYPE STANDARD TABLE OF seosubco   WITH EMPTY KEY.
    DATA lt_sdf   TYPE STANDARD TABLE OF seosubcodf WITH EMPTY KEY.
    DATA lt_stx   TYPE STANDARD TABLE OF seosubcotx WITH EMPTY KEY.
    DATA lt_names TYPE STANDARD TABLE OF seocmpname WITH EMPTY KEY.

    READ TABLE mt_model REFERENCE INTO rr_model WITH TABLE KEY clsname = iv_cls.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    ls_model-clsname = iv_cls.

    SELECT SINGLE clstype FROM seoclass
      WHERE clsname = @iv_cls
      INTO @DATA(lv_clstype).
    ls_model-found  = xsdbool( sy-subrc = 0 ).
    ls_model-isintf = xsdbool( lv_clstype = '1' ).

    SELECT * FROM seocompo WHERE clsname = @iv_cls INTO TABLE @lt_compo.

    SELECT * FROM seocompodf
      WHERE clsname = @iv_cls AND version = @gc_active
      INTO TABLE @lt_cdf.
    IF lt_cdf IS INITIAL.
      SELECT * FROM seocompodf WHERE clsname = @iv_cls INTO TABLE @lt_cdf.
    ENDIF.

    SELECT * FROM seocompotx WHERE clsname = @iv_cls INTO TABLE @lt_ctx.
    SELECT * FROM seosubco   WHERE clsname = @iv_cls INTO TABLE @lt_sco.

    SELECT * FROM seosubcodf
      WHERE clsname = @iv_cls AND version = @gc_active
      INTO TABLE @lt_sdf.
    IF lt_sdf IS INITIAL.
      SELECT * FROM seosubcodf WHERE clsname = @iv_cls INTO TABLE @lt_sdf.
    ENDIF.

    SELECT * FROM seosubcotx WHERE clsname = @iv_cls INTO TABLE @lt_stx.

    " ---- components: SEOCOMPO plus any SEOCOMPODF row without one ----
    LOOP AT lt_compo INTO DATA(ls_compo).
      APPEND ls_compo-cmpname TO lt_names.
    ENDLOOP.
    LOOP AT lt_cdf INTO DATA(ls_cdf).
      IF NOT line_exists( lt_names[ table_line = ls_cdf-cmpname ] ).
        APPEND ls_cdf-cmpname TO lt_names.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_names INTO DATA(lv_cmpname).
      CLEAR ls_comp.
      ls_comp-clsname = iv_cls.
      ls_comp-cmpname = lv_cmpname.

      READ TABLE lt_compo INTO ls_compo WITH KEY cmpname = lv_cmpname.
      IF sy-subrc = 0.
        ls_comp-cmptype = lcl_util=>fv( is_row = ls_compo iv_field = 'CMPTYPE' ).
        ls_comp-mtdtype = lcl_util=>fv( is_row = ls_compo iv_field = 'MTDTYPE' ).
      ENDIF.

      READ TABLE lt_cdf INTO ls_comp-df WITH KEY cmpname = lv_cmpname.
      IF sy-subrc = 0.
        IF ls_comp-cmptype IS INITIAL.
          ls_comp-cmptype = lcl_util=>fv( is_row = ls_comp-df iv_field = 'CMPTYPE' ).
        ENDIF.
        ls_comp-exposure   = lcl_util=>fv( is_row = ls_comp-df iv_field = 'EXPOSURE' ).
        ls_comp-decl       = SWITCH #( ls_comp-cmptype
                               WHEN `0` THEN lcl_util=>fv( is_row = ls_comp-df iv_field = 'ATTDECLTYP' )
                               WHEN `1` THEN lcl_util=>fv( is_row = ls_comp-df iv_field = 'MTDDECLTYP' )
                               WHEN `2` THEN lcl_util=>fv( is_row = ls_comp-df iv_field = 'EVTDECLTYP' ) ).
        ls_comp-rdonly     = lcl_util=>fv( is_row = ls_comp-df iv_field = 'ATTRDONLY' ).
        ls_comp-attvalue   = lcl_util=>fv( is_row = ls_comp-df iv_field = 'ATTVALUE' ).
        ls_comp-typtype    = lcl_util=>fv( is_row = ls_comp-df iv_field = 'TYPTYPE' ).
        ls_comp-typename   = lcl_util=>fv( is_row = ls_comp-df iv_field = 'TYPE' ).
        ls_comp-tableof    = lcl_util=>fv( is_row = ls_comp-df iv_field = 'TABLEOF' ).
        ls_comp-isabstract = lcl_util=>fv( is_row = ls_comp-df iv_field = 'MTDABSTRCT' ).
        ls_comp-isfinal    = lcl_util=>fv( is_row = ls_comp-df iv_field = 'MTDFINAL' ).
        ls_comp-newexc     = lcl_util=>fv( is_row = ls_comp-df iv_field = 'MTDNEWEXC' ).
        ls_comp-isalias    = lcl_util=>fv( is_row = ls_comp-df iv_field = 'ALIAS' ).
        ls_comp-refcls     = lcl_util=>fv( is_row = ls_comp-df iv_field = 'REFCLSNAME' ).
        ls_comp-refint     = lcl_util=>fv( is_row = ls_comp-df iv_field = 'REFINTNAME' ).
        ls_comp-refcmp     = lcl_util=>fv( is_row = ls_comp-df iv_field = 'REFCMPNAME' ).
        ls_comp-editorder  = lcl_util=>to_int( lcl_util=>fv( is_row = ls_comp-df iv_field = 'EDITORDER' ) ).
        ls_comp-srcrow1    = lcl_util=>to_int( lcl_util=>fv( is_row = ls_comp-df iv_field = 'SRCROW1' ) ).
        ls_comp-srcrow2    = lcl_util=>to_int( lcl_util=>fv( is_row = ls_comp-df iv_field = 'SRCROW2' ) ).
      ENDIF.

      IF ls_model-isintf = abap_true AND ls_comp-exposure IS INITIAL.
        ls_comp-exposure = `2`.          " interface components are public
      ENDIF.

      READ TABLE lt_ctx INTO DATA(ls_ctx) WITH KEY cmpname = lv_cmpname langu = sy-langu.
      IF sy-subrc <> 0.
        READ TABLE lt_ctx INTO ls_ctx WITH KEY cmpname = lv_cmpname.
      ENDIF.
      IF sy-subrc = 0.
        ls_comp-descr = ls_ctx-descript.
      ENDIF.

      APPEND ls_comp TO ls_model-comps.
    ENDLOOP.

    " ---- parameters / exceptions --------------------------------------
    LOOP AT lt_sco INTO DATA(ls_sco).
      CLEAR ls_sub.
      ls_sub-clsname = iv_cls.
      ls_sub-cmpname = ls_sco-cmpname.
      ls_sub-sconame = ls_sco-sconame.
      ls_sub-scotype = lcl_util=>fv( is_row = ls_sco iv_field = 'SCOTYPE' ).

      READ TABLE lt_sdf INTO ls_sub-df
           WITH KEY cmpname = ls_sco-cmpname sconame = ls_sco-sconame.
      IF sy-subrc = 0.
        ls_sub-decl       = lcl_util=>fv( is_row = ls_sub-df iv_field = 'PARDECLTYP' ).
        ls_sub-pass       = lcl_util=>fv( is_row = ls_sub-df iv_field = 'PARPASSTYP' ).
        ls_sub-typtype    = lcl_util=>fv( is_row = ls_sub-df iv_field = 'TYPTYPE' ).
        ls_sub-typename   = lcl_util=>fv( is_row = ls_sub-df iv_field = 'TYPE' ).
        ls_sub-tableof    = lcl_util=>fv( is_row = ls_sub-df iv_field = 'TABLEOF' ).
        ls_sub-isoptional = lcl_util=>fv( is_row = ls_sub-df iv_field = 'PAROPTIONL' ).
        ls_sub-defval     = lcl_util=>fv( is_row = ls_sub-df iv_field = 'PARVALUE' ).
        ls_sub-preferred  = lcl_util=>fv( is_row = ls_sub-df iv_field = 'PARPREFERD' ).
        ls_sub-editorder  = lcl_util=>to_int( lcl_util=>fv( is_row = ls_sub-df iv_field = 'EDITORDER' ) ).
        IF ls_sub-scotype IS INITIAL.
          ls_sub-scotype = lcl_util=>fv( is_row = ls_sub-df iv_field = 'SCOTYPE' ).
        ENDIF.
      ENDIF.

      READ TABLE lt_stx INTO DATA(ls_stx)
           WITH KEY cmpname = ls_sco-cmpname sconame = ls_sco-sconame langu = sy-langu.
      IF sy-subrc <> 0.
        READ TABLE lt_stx INTO ls_stx
             WITH KEY cmpname = ls_sco-cmpname sconame = ls_sco-sconame.
      ENDIF.
      IF sy-subrc = 0.
        ls_sub-descr = ls_stx-descript.
      ENDIF.

      APPEND ls_sub TO ls_model-subs.
    ENDLOOP.

    SORT ls_model-comps BY cmptype editorder cmpname.
    SORT ls_model-subs  BY cmpname editorder sconame.

    INSERT ls_model INTO TABLE mt_model REFERENCE INTO rr_model.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD get_interfaces.

    IF mo_obj IS BOUND.
      LOOP AT mo_obj->interfaces INTO DATA(ls_intf).
        APPEND CONV seoclsname( ls_intf-name ) TO rt_intf.
      ENDLOOP.
    ELSE.
      SELECT refclsname FROM seometarel
        WHERE clsname = @mv_cls
          AND reltype = '1'
          AND version = @gc_active
        INTO TABLE @rt_intf.
    ENDIF.

    SORT rt_intf.
    DELETE ADJACENT DUPLICATES FROM rt_intf.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_metadata.

    DATA lt_trdir TYPE STANDARD TABLE OF trdir WITH EMPTY KEY.

    mo_out->head( `METADATA` ).

    mo_out->kv( iv_key = `Object`       iv_value = CONV string( mv_cls ) ).
    mo_out->kv( iv_key = `Kind`
                iv_value = COND string( WHEN mv_isintf = abap_true
                                        THEN `INTERFACE` ELSE `CLASS` ) ).
    mo_out->kv( iv_key = `Pool program`
                iv_value = mv_prefix && COND string( WHEN mv_isintf = abap_true
                                                     THEN `IP` ELSE `CP` ) ).
    IF mo_obj IS BOUND.
      mo_out->kv( iv_key = `Absolute name` iv_value = CONV string( mo_obj->absolute_name ) ).
    ENDIF.

    IF mv_isintf = abap_false.
      DATA(lv_chain) = ``.
      LOOP AT mt_chain INTO DATA(lv_super).
        lv_chain = COND #( WHEN lv_chain IS INITIAL THEN CONV string( lv_super )
                           ELSE |{ lv_chain } -> { lv_super }| ).
      ENDLOOP.
      mo_out->kv( iv_key   = `Superclass chain`
                  iv_value = COND #( WHEN lv_chain IS INITIAL THEN `(none)` ELSE lv_chain ) ).
    ENDIF.

    " ---- component statistics -----------------------------------------
    DATA(lr_model) = model( mv_cls ).
    mo_out->kv( iv_key = `Own attributes`
                iv_value = |{ REDUCE i( INIT n = 0 FOR c IN lr_model->comps
                                        WHERE ( cmptype = `0` ) NEXT n = n + 1 ) }| ).
    mo_out->kv( iv_key = `Own methods`
                iv_value = |{ REDUCE i( INIT n = 0 FOR c IN lr_model->comps
                                        WHERE ( cmptype = `1` ) NEXT n = n + 1 ) }| ).
    mo_out->kv( iv_key = `Own events`
                iv_value = |{ REDUCE i( INIT n = 0 FOR c IN lr_model->comps
                                        WHERE ( cmptype = `2` ) NEXT n = n + 1 ) }| ).
    mo_out->kv( iv_key = `Own types`
                iv_value = |{ REDUCE i( INIT n = 0 FOR c IN lr_model->comps
                                        WHERE ( cmptype = `3` ) NEXT n = n + 1 ) }| ).
    mo_out->kv( iv_key = `Parameters + exceptions` iv_value = |{ lines( lr_model->subs ) }| ).
    mo_out->kv( iv_key = `Redefinitions`           iv_value = |{ lines( mt_redef ) }| ).
    mo_out->kv( iv_key = `Interfaces (all)`        iv_value = |{ lines( get_interfaces( ) ) }| ).
    IF mo_obj IS BOUND.
      mo_out->kv( iv_key = `RTTI attributes (all)` iv_value = |{ lines( mo_obj->attributes ) }| ).
      mo_out->kv( iv_key = `RTTI methods (all)`    iv_value = |{ lines( mo_obj->methods ) }| ).
    ENDIF.

    " ---- SEOCLASS / SEOCLASSDF - every property ------------------------
    lcl_util=>dump_rows(
      io_out     = mo_out
      ir_tab     = lcl_util=>generic_select( iv_table = 'SEOCLASS'
                                             iv_where = |CLSNAME = { lcl_util=>quote( mv_cls ) }| )
      iv_title   = `Class header (SEOCLASS)`
      iv_initial = abap_true ).

    lcl_util=>dump_rows(
      io_out     = mo_out
      ir_tab     = lcl_util=>generic_select( iv_table = 'SEOCLASSDF'
                                             iv_where = |CLSNAME = { lcl_util=>quote( mv_cls ) }| )
      iv_title   = `Properties - every version (SEOCLASSDF: category, exposure, final, ` &&
                   `abstract, fixed point, unicode, message class, shared memory, ` &&
                   `unit tests, created / changed ...)`
      iv_initial = ms_opt-init ).

    " ---- descriptions in all languages ---------------------------------
    mo_out->sub( `Descriptions (SEOCLASSTX, all languages)` ).
    SELECT langu, descript FROM seoclasstx
      WHERE clsname = @mv_cls
      ORDER BY langu
      INTO TABLE @DATA(lt_txt).
    IF lt_txt IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_txt INTO DATA(ls_txt).
      mo_out->add( |     { ls_txt-langu } : { ls_txt-descript }| ).
    ENDLOOP.

    " ---- who points at this object -------------------------------------
    mo_out->sub( COND #( WHEN mv_isintf = abap_true
                         THEN `Implementing classes / including interfaces (SEOMETAREL)`
                         ELSE `Direct subclasses / other relations to this class (SEOMETAREL)` ) ).
    SELECT * FROM seometarel
      WHERE refclsname = @mv_cls
        AND version    = @gc_active
      ORDER BY clsname
      INTO TABLE @DATA(lt_rev)
      UP TO @ms_opt-maxr ROWS.
    IF lt_rev IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_rev INTO DATA(ls_rev).
      mo_out->add( |     { ls_rev-clsname WIDTH = 32 } relation { lcl_util=>fvt( is_row = ls_rev iv_field = 'RELTYPE' ) }| ).
    ENDLOOP.

    " ---- repository / package ------------------------------------------
    DATA(lr_tadir) = lcl_util=>generic_select(
      iv_table = 'TADIR'
      iv_where = |PGMID = 'R3TR' AND OBJECT = { COND string( WHEN mv_isintf = abap_true
                                                            THEN `'INTF'` ELSE `'CLAS'` ) } | &&
                 |AND OBJ_NAME = { lcl_util=>quote( mv_cls ) }| ).
    lcl_util=>dump_rows( io_out     = mo_out
                         ir_tab     = lr_tadir
                         iv_title   = `Repository object (TADIR)`
                         iv_initial = ms_opt-init ).

    FIELD-SYMBOLS <lt_tadir> TYPE STANDARD TABLE.
    IF lr_tadir IS BOUND.
      ASSIGN lr_tadir->* TO <lt_tadir>.
      LOOP AT <lt_tadir> ASSIGNING FIELD-SYMBOL(<ls_tadir>).
        DATA(lv_devclass) = lcl_util=>fv( is_row = <ls_tadir> iv_field = 'DEVCLASS' ).
        IF lv_devclass IS NOT INITIAL.
          lcl_util=>dump_rows(
            io_out     = mo_out
            ir_tab     = lcl_util=>generic_select( iv_table = 'TDEVC'
                                                   iv_where = |DEVCLASS = { lcl_util=>quote( lv_devclass ) }| )
            iv_title   = |Package { lv_devclass } (TDEVC)|
            iv_initial = ms_opt-init ).
          lcl_util=>dump_rows(
            io_out     = mo_out
            ir_tab     = lcl_util=>generic_select( iv_table = 'TDEVCT'
                                                   iv_where = |DEVCLASS = { lcl_util=>quote( lv_devclass ) }| )
            iv_title   = |Package { lv_devclass } texts (TDEVCT)|
            iv_initial = ms_opt-init ).
        ENDIF.
      ENDLOOP.
    ENDIF.

    " ---- all includes of the pool --------------------------------------
    mo_out->sub( `Programs / includes of the pool (TRDIR)` ).
    DATA(lv_pat) = |{ lcl_util=>like_escape( mv_prefix ) }%|.
    SELECT * FROM trdir
      WHERE name LIKE @lv_pat ESCAPE '#'
      ORDER BY name
      INTO TABLE @lt_trdir.
    IF lt_trdir IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_trdir INTO DATA(ls_trdir).
      mo_out->add( |     { ls_trdir-name WIDTH = 42 } | &&
                   |type { lcl_util=>fvt( is_row = ls_trdir iv_field = 'SUBC' ) WIDTH = 24 } | &&
                   |created { lcl_util=>fv( is_row = ls_trdir iv_field = 'CNAM' ) WIDTH = 12 } | &&
                   |{ lcl_util=>fv( is_row = ls_trdir iv_field = 'CDAT' ) WIDTH = 10 }  | &&
                   |changed { lcl_util=>fv( is_row = ls_trdir iv_field = 'UNAM' ) WIDTH = 12 } | &&
                   |{ lcl_util=>fv( is_row = ls_trdir iv_field = 'UDAT' ) }| ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_relations.

    mo_out->head( `RELATIONS` ).

    mo_out->sub( `This object -> others (SEOMETAREL)` ).
    SELECT * FROM seometarel
      WHERE clsname = @mv_cls
      ORDER BY refclsname
      INTO TABLE @DATA(lt_rel).
    IF lt_rel IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_rel INTO DATA(ls_rel).
      mo_out->add( |     { ls_rel-refclsname WIDTH = 32 } | &&
                   |relation { lcl_util=>fvt( is_row = ls_rel iv_field = 'RELTYPE' ) WIDTH = 30 } | &&
                   |version { lcl_util=>fv( is_row = ls_rel iv_field = 'VERSION' ) } | &&
                   |state { lcl_util=>fvt( is_row = ls_rel iv_field = 'STATE' ) }| ).
    ENDLOOP.

    mo_out->sub( `Interfaces - complete list incl. nested and inherited (RTTI)` ).
    IF mo_obj IS BOUND.
      IF mo_obj->interfaces IS INITIAL.
        mo_out->add( `     (none)` ).
      ENDIF.
      LOOP AT mo_obj->interfaces INTO DATA(ls_intf).
        mo_out->add( |     { ls_intf-name WIDTH = 32 } | &&
                     |{ COND string( WHEN lcl_util=>fv( is_row = ls_intf iv_field = 'IS_INHERITED' ) = abap_true
                                     THEN `inherited from superclass` ELSE `` ) }| ).
      ENDLOOP.
    ELSE.
      mo_out->add( `     (RTTI not available)` ).
    ENDIF.

    DATA(lv_w_cls) = |CLSNAME = { lcl_util=>quote( mv_cls ) }|.

    lcl_util=>dump_rows(
      io_out     = mo_out
      ir_tab     = lcl_util=>generic_select( iv_table = 'SEOFRIENDS' iv_where = lv_w_cls )
      iv_title   = `Friends - this class grants friendship to (SEOFRIENDS)`
      iv_initial = ms_opt-init ).

    lcl_util=>dump_rows(
      io_out     = mo_out
      ir_tab     = lcl_util=>generic_select( iv_table = 'SEOFRIENDS'
                                             iv_where = |REFCLSNAME = { lcl_util=>quote( mv_cls ) }|
                                             iv_max   = ms_opt-maxr )
      iv_title   = `Friend of - classes granting friendship to this object (SEOFRIENDS)`
      iv_initial = ms_opt-init ).

    lcl_util=>dump_rows(
      io_out     = mo_out
      ir_tab     = lcl_util=>generic_select( iv_table = 'SEOTYPEPLS' iv_where = lv_w_cls )
      iv_title   = `Type groups / forward declarations (SEOTYPEPLS)`
      iv_initial = ms_opt-init ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_attributes.

    mo_out->head( `ATTRIBUTES (own, as declared)` ).
    DATA(lr_model) = model( mv_cls ).
    print_comps( ir_model        = lr_model
                 iv_cmptype      = `0`
                 iv_skip_private = abap_false
                 iv_title        = |Attributes of { mv_cls }| ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_methods.

    DATA lv_intf TYPE seoclsname.
    DATA lv_cmp  TYPE seocmpname.

    mo_out->head( `METHODS AND SIGNATURES (own, as declared)` ).
    DATA(lr_model) = model( mv_cls ).

    print_comps( ir_model        = lr_model
                 iv_cmptype      = `1`
                 iv_skip_private = abap_false
                 iv_title        = |Methods of { mv_cls }| ).

    print_aliases( ir_model = lr_model iv_skip_private = abap_false ).

    " ---- redefinitions ---------------------------------------------------
    mo_out->sub( `REDEFINITIONS (SEOREDEF) - signature taken from the defining class` ).

    IF mv_isintf = abap_true.
      mo_out->add( `     (interface - not applicable)` ).
      RETURN.
    ENDIF.

    IF mt_redef IS INITIAL.
      mo_out->add( `     (none)` ).
      RETURN.
    ENDIF.

    LOOP AT mt_redef INTO DATA(ls_redef).

      DATA(lv_mtd) = CONV string( ls_redef-mtdname ).
      DATA lr_def TYPE REF TO ty_s_model.
      CLEAR lr_def.
      DATA ls_def TYPE ty_s_comp.
      CLEAR ls_def.

      IF lv_mtd CS '~'.
        SPLIT lv_mtd AT '~' INTO DATA(lv_i) DATA(lv_c).
        lv_intf = lv_i.
        lv_cmp  = lv_c.
        lr_def  = model( lv_intf ).
        READ TABLE lr_def->comps INTO ls_def WITH KEY cmpname = lv_cmp.
        IF sy-subrc <> 0.
          CLEAR lr_def.
        ENDIF.
      ELSE.
        lv_cmp = lv_mtd.
        LOOP AT mt_chain INTO DATA(lv_super).
          lr_def = model( lv_super ).
          READ TABLE lr_def->comps INTO ls_def WITH KEY cmpname = lv_cmp.
          IF sy-subrc = 0.
            EXIT.
          ENDIF.
          CLEAR lr_def.
        ENDLOOP.
      ENDIF.

      IF lr_def IS BOUND.
        print_method( ir_model = lr_def
                      is_comp  = ls_def
                      iv_note  = |   <<< REDEFINED in { mv_cls } (declared in { lr_def->clsname })| ).
      ELSE.
        mo_out->add( `` ).
        mo_out->add( |  REDEFINITION { ls_redef-mtdname } (from { ls_redef-refclsname }) | &&
                     |- defining class not found in repository| ).
      ENDIF.

      " every field of the SEOREDEF row (abstract / final / attribute
      " value redefinitions ...)
      lcl_util=>dump_struct( io_out     = mo_out
                             is_row     = ls_redef
                             iv_indent  = 8
                             iv_initial = ms_opt-init ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_events.

    mo_out->head( `EVENTS (own, as declared)` ).
    print_comps( ir_model        = model( mv_cls )
                 iv_cmptype      = `2`
                 iv_skip_private = abap_false
                 iv_title        = |Events of { mv_cls }| ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_types.

    mo_out->head( `TYPES (own, as declared)` ).
    print_comps( ir_model        = model( mv_cls )
                 iv_cmptype      = `3`
                 iv_skip_private = abap_false
                 iv_title        = |Types of { mv_cls }| ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_inherited.

    mo_out->head( `INHERITED COMPONENTS AND IMPLEMENTED INTERFACES (repository view)` ).

    " ---- superclasses: everything except PRIVATE -------------------------
    IF mv_isintf = abap_false.
      IF mt_chain IS INITIAL.
        mo_out->sub( `No superclass` ).
      ENDIF.

      DATA(lv_level) = 0.
      LOOP AT mt_chain INTO DATA(lv_super).
        lv_level = lv_level + 1.
        DATA(lr_sup) = model( lv_super ).
        mo_out->head( |SUPERCLASS level { lv_level }: { lv_super } (public + protected components)| ).
        print_comps( ir_model = lr_sup iv_cmptype = `0` iv_skip_private = abap_true
                     iv_title = |Attributes inherited from { lv_super }| ).
        print_comps( ir_model = lr_sup iv_cmptype = `1` iv_skip_private = abap_true
                     iv_title = |Methods inherited from { lv_super }| ).
        print_comps( ir_model = lr_sup iv_cmptype = `2` iv_skip_private = abap_true
                     iv_title = |Events inherited from { lv_super }| ).
        print_comps( ir_model = lr_sup iv_cmptype = `3` iv_skip_private = abap_true
                     iv_title = |Types inherited from { lv_super }| ).
        print_aliases( ir_model = lr_sup iv_skip_private = abap_true ).
      ENDLOOP.
    ENDIF.

    " ---- interfaces: everything ------------------------------------------
    LOOP AT get_interfaces( ) INTO DATA(lv_intf).
      DATA(lr_intf) = model( lv_intf ).
      mo_out->head( |INTERFACE { lv_intf }| ).
      IF lr_intf->found = abap_false.
        mo_out->add( `  (not found in SEOCLASS)` ).
        CONTINUE.
      ENDIF.
      print_comps( ir_model = lr_intf iv_cmptype = `0` iv_skip_private = abap_false
                   iv_title = |Attributes / constants of { lv_intf }| ).
      print_comps( ir_model = lr_intf iv_cmptype = `1` iv_skip_private = abap_false
                   iv_title = |Methods of { lv_intf }| ).
      print_comps( ir_model = lr_intf iv_cmptype = `2` iv_skip_private = abap_false
                   iv_title = |Events of { lv_intf }| ).
      print_comps( ir_model = lr_intf iv_cmptype = `3` iv_skip_private = abap_false
                   iv_title = |Types of { lv_intf }| ).
      print_aliases( ir_model = lr_intf iv_skip_private = abap_false ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_comps.

    DATA(lv_n) = 0.

    LOOP AT ir_model->comps INTO DATA(ls_comp) WHERE cmptype = iv_cmptype.

      IF ls_comp-isalias = abap_true.
        CONTINUE.                         " printed by PRINT_ALIASES
      ENDIF.
      IF iv_skip_private = abap_true AND ls_comp-exposure = `0`.
        CONTINUE.
      ENDIF.

      lv_n = lv_n + 1.
      IF lv_n = 1.
        mo_out->sub( iv_title ).
      ENDIF.

      CASE iv_cmptype.
        WHEN `0`. print_attr(   ir_model = ir_model is_comp = ls_comp ).
        WHEN `1`. print_method( ir_model = ir_model is_comp = ls_comp ).
        WHEN `2`. print_event(  ir_model = ir_model is_comp = ls_comp ).
        WHEN `3`. print_type(   ir_model = ir_model is_comp = ls_comp ).
      ENDCASE.
    ENDLOOP.

    IF lv_n = 0.
      mo_out->sub( |{ iv_title }: (none)| ).
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_aliases.

    DATA(lv_n) = 0.

    LOOP AT ir_model->comps INTO DATA(ls_comp) WHERE isalias = abap_true.
      IF iv_skip_private = abap_true AND ls_comp-exposure = `0`.
        CONTINUE.
      ENDIF.
      lv_n = lv_n + 1.
      IF lv_n = 1.
        mo_out->sub( |Aliases of { ir_model->clsname }| ).
      ENDIF.
      DATA(lv_intf) = COND string( WHEN ls_comp-refint IS NOT INITIAL
                                   THEN ls_comp-refint ELSE ls_comp-refcls ).
      mo_out->add( |  { lcl_util=>vis( ls_comp-exposure ) WIDTH = 9 } | &&
                   |ALIASES { ls_comp-cmpname } FOR { lv_intf }~{ ls_comp-refcmp }.| &&
                   |{ COND string( WHEN ls_comp-descr IS NOT INITIAL THEN |   " { ls_comp-descr }| ) }| ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_attr.

    DATA(lv_kw) = SWITCH string( is_comp-decl
                    WHEN `1` THEN `CLASS-DATA`
                    WHEN `2` THEN `CONSTANTS`
                    ELSE `DATA` ).

    DATA(lv_line) = |  { lcl_util=>vis( is_comp-exposure ) WIDTH = 9 } { lv_kw } { is_comp-cmpname } | &&
                    |{ typing( iv_typtype = is_comp-typtype
                               iv_type    = is_comp-typename
                               iv_tableof = is_comp-tableof ) }|.

    IF is_comp-rdonly = abap_true.
      lv_line = lv_line && ` READ-ONLY`.
    ENDIF.
    IF is_comp-attvalue IS NOT INITIAL.
      lv_line = |{ lv_line } VALUE { is_comp-attvalue }|.
    ENDIF.
    lv_line = lv_line && `.`.
    IF is_comp-descr IS NOT INITIAL.
      lv_line = |{ lv_line }   " { is_comp-descr }|.
    ENDIF.

    mo_out->add( lv_line ).
    print_audit( is_comp ).

    " complex typing (inline structure, table with key ...) or a
    " structured constant: show the declaring source rows
    DATA(lv_complex) = xsdbool( is_comp-typtype <> `0` AND
                                is_comp-typtype <> `1` AND
                                is_comp-typtype <> `3` ).
    IF lv_complex = abap_true OR ( is_comp-decl = `2` AND is_comp-attvalue IS INITIAL ).
      print_snippet( ir_model = ir_model is_comp = is_comp ).
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_method.

    DATA(lv_kw) = COND string( WHEN is_comp-decl = `1` THEN `CLASS-METHODS` ELSE `METHODS` ).
    DATA(lv_head) = |  { lcl_util=>vis( is_comp-exposure ) WIDTH = 9 } { lv_kw } { is_comp-cmpname }|.

    IF is_comp-isabstract = abap_true.
      lv_head = lv_head && ` ABSTRACT`.
    ENDIF.
    IF is_comp-isfinal = abap_true.
      lv_head = lv_head && ` FINAL`.
    ENDIF.
    IF is_comp-refcmp IS NOT INITIAL.
      lv_head = |{ lv_head } FOR EVENT { is_comp-refcmp } OF { is_comp-refcls }{ is_comp-refint }|.
    ENDIF.
    IF is_comp-mtdtype IS NOT INITIAL AND is_comp-mtdtype <> `0`.
      lv_head = |{ lv_head }   [method type { is_comp-mtdtype } | &&
                |{ lcl_util=>dom_text( iv_domain = 'SEOMTDTYPE' iv_value = is_comp-mtdtype ) }]|.
    ENDIF.

    " redefined further down in the inspected class?
    IF ir_model->clsname <> mv_cls AND
       ( line_exists( mt_redef[ mtdname = is_comp-cmpname ] ) OR
         line_exists( mt_redef[ mtdname = |{ ir_model->clsname }~{ is_comp-cmpname }| ] ) ).
      lv_head = |{ lv_head }   <<< REDEFINED in { mv_cls }|.
    ENDIF.

    mo_out->add( `` ).
    mo_out->add( lv_head && iv_note ).
    IF is_comp-descr IS NOT INITIAL.
      mo_out->add( |              " { is_comp-descr }| ).
    ENDIF.

    print_params( ir_model = ir_model is_comp = is_comp ).
    print_audit( is_comp ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_event.

    DATA(lv_kw) = COND string( WHEN is_comp-decl = `1` THEN `CLASS-EVENTS` ELSE `EVENTS` ).

    mo_out->add( `` ).
    mo_out->add( |  { lcl_util=>vis( is_comp-exposure ) WIDTH = 9 } { lv_kw } { is_comp-cmpname }| ).
    IF is_comp-descr IS NOT INITIAL.
      mo_out->add( |              " { is_comp-descr }| ).
    ENDIF.

    print_params( ir_model = ir_model is_comp = is_comp ).
    print_audit( is_comp ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_type.

    DATA(lv_line) = |  { lcl_util=>vis( is_comp-exposure ) WIDTH = 9 } TYPES { is_comp-cmpname } | &&
                    |{ typing( iv_typtype = is_comp-typtype
                               iv_type    = is_comp-typename
                               iv_tableof = is_comp-tableof ) }.|.
    IF is_comp-descr IS NOT INITIAL.
      lv_line = |{ lv_line }   " { is_comp-descr }|.
    ENDIF.

    mo_out->add( lv_line ).
    print_audit( is_comp ).
    print_snippet( ir_model = ir_model is_comp = is_comp ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_params.

    DATA lt_decl TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    DATA(lt_par) = VALUE ty_t_sub( FOR ls_s IN ir_model->subs
                                   WHERE ( cmpname = is_comp-cmpname ) ( ls_s ) ).
    SORT lt_par BY editorder sconame.

    LOOP AT lt_par INTO DATA(ls_par) WHERE scotype <> `1`.
      IF NOT line_exists( lt_decl[ table_line = ls_par-decl ] ).
        APPEND ls_par-decl TO lt_decl.
      ENDIF.
    ENDLOOP.
    SORT lt_decl.

    DATA(lv_pref) = ``.

    LOOP AT lt_decl INTO DATA(lv_decl).

      mo_out->add( |        { SWITCH string( lv_decl
                                 WHEN `0` THEN `IMPORTING`
                                 WHEN `1` THEN `EXPORTING`
                                 WHEN `2` THEN `CHANGING`
                                 WHEN `3` THEN `RETURNING`
                                 ELSE |PARDECLTYP { lv_decl }| ) }| ).

      LOOP AT lt_par INTO ls_par WHERE scotype <> `1` AND decl = lv_decl.

        DATA(lv_name) = COND string( WHEN ls_par-pass = `0` OR lv_decl = `3`
                                     THEN |VALUE({ ls_par-sconame })|
                                     ELSE |REFERENCE({ ls_par-sconame })| ).

        DATA(lv_line) = |          { lv_name WIDTH = 40 } | &&
                        |{ typing( iv_typtype = ls_par-typtype
                                   iv_type    = ls_par-typename
                                   iv_tableof = ls_par-tableof ) }|.

        IF ls_par-isoptional = abap_true.
          lv_line = lv_line && ` OPTIONAL`.
        ENDIF.
        IF ls_par-defval IS NOT INITIAL.
          lv_line = |{ lv_line } DEFAULT { ls_par-defval }|.
        ENDIF.
        IF ls_par-preferred = abap_true.
          lv_pref = ls_par-sconame.
        ENDIF.
        IF ls_par-descr IS NOT INITIAL.
          lv_line = |{ lv_line }   " { ls_par-descr }|.
        ENDIF.

        mo_out->add( lv_line ).
      ENDLOOP.

      IF lv_decl = `0` AND lv_pref IS NOT INITIAL.
        mo_out->add( |        PREFERRED PARAMETER { lv_pref }| ).
      ENDIF.

    ENDLOOP.

    " ---- exceptions -------------------------------------------------------
    DATA(lv_first) = abap_true.
    LOOP AT lt_par INTO ls_par WHERE scotype = `1`.
      IF lv_first = abap_true.
        lv_first = abap_false.
        mo_out->add( |        { COND string( WHEN is_comp-newexc = abap_true
                                             THEN `RAISING` ELSE `EXCEPTIONS` ) }| ).
      ENDIF.
      DATA(lv_exc) = |          { ls_par-sconame WIDTH = 40 }|.
      IF lcl_util=>fv( is_row = ls_par-df iv_field = 'IS_RESUMABLE' ) = abap_true.
        lv_exc = |          RESUMABLE({ ls_par-sconame })|.
      ENDIF.
      IF ls_par-descr IS NOT INITIAL.
        lv_exc = |{ lv_exc }   " { ls_par-descr }|.
      ENDIF.
      mo_out->add( lv_exc ).
    ENDLOOP.

    IF lt_par IS INITIAL.
      mo_out->add( `        (no parameters, no exceptions)` ).
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_snippet.

    DATA lt_src TYPE lcl_util=>ty_t_string.
    DATA lv_ok  TYPE abap_bool.

    IF is_comp-srcrow1 <= 0.
      RETURN.
    ENDIF.

    DATA(lv_prog) = section_include( ir_model = ir_model iv_expo = is_comp-exposure ).
    lcl_util=>read_source( EXPORTING iv_prog = lv_prog
                           IMPORTING et_src  = lt_src
                                     ev_ok   = lv_ok ).

    IF lv_ok = abap_false OR lines( lt_src ) < is_comp-srcrow1.
      mo_out->add( |              (declared in { lv_prog } rows { is_comp-srcrow1 }-{ is_comp-srcrow2 }, not readable)| ).
      RETURN.
    ENDIF.

    DATA(lv_to) = COND i( WHEN is_comp-srcrow2 >= is_comp-srcrow1
                          THEN is_comp-srcrow2 ELSE is_comp-srcrow1 ).
    IF lv_to > lines( lt_src ).
      lv_to = lines( lt_src ).
    ENDIF.

    mo_out->add( |              source { lv_prog } rows { is_comp-srcrow1 }-{ lv_to }:| ).
    LOOP AT lt_src INTO DATA(lv_src) FROM is_comp-srcrow1 TO lv_to.
      mo_out->add( |              \| { lv_src }| ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_audit.

    DATA(lv_txt) =
      |created { lcl_util=>fv( is_row = is_comp-df iv_field = 'AUTHOR' ) } | &&
      |{ lcl_util=>fv( is_row = is_comp-df iv_field = 'CREATEDON' ) }, | &&
      |changed { lcl_util=>fv( is_row = is_comp-df iv_field = 'CHANGEDBY' ) } | &&
      |{ lcl_util=>fv( is_row = is_comp-df iv_field = 'CHANGEDON' ) }, | &&
      |state { lcl_util=>fvt( is_row = is_comp-df iv_field = 'STATE' ) }, | &&
      |edit order { is_comp-editorder }|.

    DATA(lv_rel) = lcl_util=>fvt( is_row = is_comp-df iv_field = 'RELEASE' ).
    IF lv_rel IS NOT INITIAL.
      lv_txt = |{ lv_txt }, release { lv_rel }|.
    ENDIF.

    mo_out->add( |              [{ lv_txt }]| ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD typing.

    IF iv_type IS INITIAL AND ( iv_typtype = `0` OR iv_typtype = `1` OR iv_typtype IS INITIAL ).
      rv_txt = `(untyped / generic)`.
      RETURN.
    ENDIF.

    IF iv_tableof = abap_true.
      rv_txt = SWITCH #( iv_typtype
                 WHEN `0` THEN |LIKE STANDARD TABLE OF { iv_type }|
                 WHEN `3` THEN |TYPE STANDARD TABLE OF REF TO { iv_type }|
                 ELSE          |TYPE STANDARD TABLE OF { iv_type }| ).
      RETURN.
    ENDIF.

    rv_txt = SWITCH #( iv_typtype
               WHEN `0` THEN |LIKE { iv_type }|
               WHEN `1` THEN |TYPE { iv_type }|
               WHEN `3` THEN |TYPE REF TO { iv_type }| ).

    IF rv_txt IS INITIAL.
      " other typing kinds (e.g. defined directly in the source)
      DATA(lv_dt) = lcl_util=>dom_text( iv_domain = 'SEOTYPTYPE' iv_value = iv_typtype ).
      rv_txt = COND string( WHEN iv_type IS NOT INITIAL THEN |TYPE { iv_type } | ) &&
               |[typing kind { iv_typtype }| &&
               COND string( WHEN lv_dt IS NOT INITIAL THEN | { lv_dt }| ) &&
               `]`.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD section_include.

    DATA(lv_prefix) = lcl_util=>pool_prefix( ir_model->clsname ).

    IF ir_model->isintf = abap_true.
      rv_prog = lv_prefix && `IU`.
      RETURN.
    ENDIF.

    rv_prog = lv_prefix && SWITCH string( iv_expo
                             WHEN `2` THEN `CU`
                             WHEN `1` THEN `CO`
                             ELSE `CI` ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_rtti.

    IF mo_obj IS NOT BOUND.
      mo_out->head( `RUNTIME VIEW (RTTI)` ).
      mo_out->add( `(RTTI not available - class could not be loaded)` ).
      RETURN.
    ENDIF.

    print_rtti( io_obj   = mo_obj
                iv_title = `RUNTIME VIEW (RTTI) - every component incl. inherited, interface and alias` ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_rtti.

    DATA lo_cls TYPE REF TO cl_abap_classdescr.
    DATA lo_sup TYPE REF TO cl_abap_classdescr.
    DATA lo_typ TYPE REF TO cl_abap_datadescr.
    DATA lv_evt TYPE abap_attrname.
    DATA lv_par TYPE abap_parmname.

    FIELD-SYMBOLS: <lv_any>  TYPE any,
                   <lt_evt>  TYPE ANY TABLE,
                   <ls_evt>  TYPE any,
                   <lt_epar> TYPE ANY TABLE,
                   <ls_epar> TYPE any.

    mo_out->head( iv_title ).
    mo_out->kv( iv_key = `Absolute name` iv_value = CONV string( io_obj->absolute_name ) ).
    mo_out->kv( iv_key   = `Kind`
                iv_value = COND string( WHEN io_obj->kind = cl_abap_typedescr=>kind_intf
                                        THEN `INTERFACE` ELSE `CLASS` ) ).

    IF io_obj->kind = cl_abap_typedescr=>kind_class.
      lo_cls ?= io_obj.

      ASSIGN lo_cls->('CLASS_KIND') TO <lv_any>.
      IF sy-subrc = 0.
        mo_out->kv( iv_key = `Class kind (A/F/C)` iv_value = |{ <lv_any> }| ).
      ENDIF.
      ASSIGN lo_cls->('CREATE_VISIBILITY') TO <lv_any>.
      IF sy-subrc = 0.
        mo_out->kv( iv_key = `Create visibility` iv_value = |{ <lv_any> }| ).
      ENDIF.

      lo_cls->get_super_class_type(
        RECEIVING  p_descr_ref = lo_sup
        EXCEPTIONS OTHERS      = 1 ).
      IF sy-subrc = 0 AND lo_sup IS BOUND.
        mo_out->kv( iv_key = `Superclass` iv_value = CONV string( lo_sup->get_relative_name( ) ) ).
      ENDIF.
    ENDIF.

    " ---- interfaces -------------------------------------------------------
    mo_out->sub( `Interfaces` ).
    IF io_obj->interfaces IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT io_obj->interfaces INTO DATA(ls_intf).
      mo_out->add( |     { ls_intf-name WIDTH = 40 }| &&
                   |{ COND string( WHEN lcl_util=>fv( is_row = ls_intf iv_field = 'IS_INHERITED' ) = abap_true
                                   THEN `INHERITED` ELSE `` ) }| ).
    ENDLOOP.

    " ---- attributes -------------------------------------------------------
    mo_out->sub( `Attributes` ).
    IF io_obj->attributes IS INITIAL.
      mo_out->add( `     (none)` ).
    ELSE.
      mo_out->add( |     { 'NAME' WIDTH = 45 } { 'VIS' WIDTH = 10 } { 'FLAGS' WIDTH = 34 } TYPE| ).
    ENDIF.

    LOOP AT io_obj->attributes INTO DATA(ls_attr).

      DATA(lv_flags) = ``.
      IF ls_attr-is_class     = abap_true. lv_flags = lv_flags && `STATIC `. ENDIF.
      IF ls_attr-is_constant  = abap_true. lv_flags = lv_flags && `CONST `.  ENDIF.
      IF ls_attr-is_read_only = abap_true. lv_flags = lv_flags && `RDONLY `. ENDIF.
      IF ls_attr-is_interface = abap_true. lv_flags = lv_flags && `INTF `.   ENDIF.
      IF lcl_util=>fv( is_row = ls_attr iv_field = 'IS_INHERITED' ) = abap_true.
        lv_flags = lv_flags && `INHERITED `.
      ENDIF.
      IF lcl_util=>fv( is_row = ls_attr iv_field = 'IS_VIRTUAL' ) = abap_true.
        lv_flags = lv_flags && `VIRTUAL `.
      ENDIF.
      DATA(lv_alias) = lcl_util=>fv( is_row = ls_attr iv_field = 'ALIAS_FOR' ).

      CLEAR lo_typ.
      TRY.
          io_obj->get_attribute_type(
            EXPORTING  p_name      = ls_attr-name
            RECEIVING  p_descr_ref = lo_typ
            EXCEPTIONS OTHERS      = 1 ).
          IF sy-subrc <> 0.
            CLEAR lo_typ.
          ENDIF.
        CATCH cx_root.
          CLEAR lo_typ.
      ENDTRY.

      mo_out->add( |     { ls_attr-name WIDTH = 45 } | &&
                   |{ vis_text( ls_attr-visibility ) WIDTH = 10 } | &&
                   |{ lv_flags WIDTH = 34 } { type_label( lo_typ ) }| &&
                   |{ COND string( WHEN lv_alias IS NOT INITIAL THEN |   (alias for { lv_alias })| ) }| ).
    ENDLOOP.

    " ---- methods ----------------------------------------------------------
    mo_out->sub( `Methods and signatures` ).
    IF io_obj->methods IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.

    LOOP AT io_obj->methods INTO DATA(ls_meth).

      lv_flags = ``.
      IF ls_meth-is_class     = abap_true. lv_flags = lv_flags && `STATIC `. ENDIF.
      IF ls_meth-is_interface = abap_true. lv_flags = lv_flags && `INTF `.   ENDIF.
      IF lcl_util=>fv( is_row = ls_meth iv_field = 'IS_ABSTRACT' ) = abap_true.
        lv_flags = lv_flags && `ABSTRACT `.
      ENDIF.
      IF lcl_util=>fv( is_row = ls_meth iv_field = 'IS_FINAL' ) = abap_true.
        lv_flags = lv_flags && `FINAL `.
      ENDIF.
      IF lcl_util=>fv( is_row = ls_meth iv_field = 'IS_INHERITED' ) = abap_true.
        lv_flags = lv_flags && `INHERITED `.
      ENDIF.
      IF lcl_util=>fv( is_row = ls_meth iv_field = 'IS_REDEFINED' ) = abap_true.
        lv_flags = lv_flags && `REDEFINED `.
      ENDIF.
      IF lcl_util=>fv( is_row = ls_meth iv_field = 'IS_RAISING_EXCPS' ) = abap_true.
        lv_flags = lv_flags && `CLASS-BASED-EXC `.
      ENDIF.
      IF ls_meth-for_event IS NOT INITIAL.
        lv_flags = |{ lv_flags }EVTHDL FOR { ls_meth-for_event } OF | &&
                   |{ lcl_util=>fv( is_row = ls_meth iv_field = 'OF_CLASS' ) } |.
      ENDIF.
      lv_alias = lcl_util=>fv( is_row = ls_meth iv_field = 'ALIAS_FOR' ).
      IF lv_alias IS NOT INITIAL.
        lv_flags = |{ lv_flags }ALIAS FOR { lv_alias } |.
      ENDIF.

      mo_out->add( `` ).
      mo_out->add( |     { ls_meth-name } [ { vis_text( ls_meth-visibility ) } { lv_flags }]| ).

      IF ls_meth-parameters IS INITIAL.
        mo_out->add( `          (no parameters)` ).
      ENDIF.

      LOOP AT ls_meth-parameters INTO DATA(ls_parm).

        CLEAR lo_typ.
        TRY.
            io_obj->get_method_parameter_type(
              EXPORTING  p_method_name    = ls_meth-name
                         p_parameter_name = ls_parm-name
              RECEIVING  p_descr_ref      = lo_typ
              EXCEPTIONS OTHERS           = 1 ).
            IF sy-subrc <> 0.
              CLEAR lo_typ.
            ENDIF.
          CATCH cx_root.
            CLEAR lo_typ.
        ENDTRY.

        mo_out->add( |          { parm_text( ls_parm-parm_kind ) WIDTH = 10 } | &&
                     |{ COND string( WHEN lcl_util=>fv( is_row = ls_parm iv_field = 'BY_VALUE' ) = abap_true
                                     THEN `VALUE` ELSE `REF` ) WIDTH = 6 }| &&
                     |{ ls_parm-name WIDTH = 32 } | &&
                     |{ COND string( WHEN ls_parm-is_optional = abap_true
                                     THEN `OPTIONAL` ELSE `` ) WIDTH = 9 } | &&
                     |TYPE { type_label( lo_typ ) }| ).
      ENDLOOP.

      LOOP AT ls_meth-exceptions INTO DATA(ls_exc).
        mo_out->add( |          { 'RAISING' WIDTH = 16 }{ ls_exc-name }| &&
                     |{ COND string( WHEN lcl_util=>fv( is_row = ls_exc iv_field = 'IS_RESUMABLE' ) = abap_true
                                     THEN ` (RESUMABLE)` ELSE `` ) }| ).
      ENDLOOP.

    ENDLOOP.

    " ---- events (read dynamically - not every release has EVENTS) -------
    mo_out->sub( `Events` ).
    ASSIGN io_obj->('EVENTS') TO <lt_evt>.
    IF sy-subrc <> 0.
      mo_out->add( `     (none)` ).
    ELSEIF <lt_evt> IS INITIAL.
      mo_out->add( `     (none)` ).
    ELSE.
      LOOP AT <lt_evt> ASSIGNING <ls_evt>.
        lv_flags = ``.
        IF lcl_util=>fv( is_row = <ls_evt> iv_field = 'IS_CLASS' )     = abap_true. lv_flags = lv_flags && `STATIC `.    ENDIF.
        IF lcl_util=>fv( is_row = <ls_evt> iv_field = 'IS_INTERFACE' ) = abap_true. lv_flags = lv_flags && `INTF `.      ENDIF.
        IF lcl_util=>fv( is_row = <ls_evt> iv_field = 'IS_INHERITED' ) = abap_true. lv_flags = lv_flags && `INHERITED `. ENDIF.
        lv_alias = lcl_util=>fv( is_row = <ls_evt> iv_field = 'ALIAS_FOR' ).
        IF lv_alias IS NOT INITIAL.
          lv_flags = |{ lv_flags }ALIAS FOR { lv_alias } |.
        ENDIF.

        lv_evt = lcl_util=>fv( is_row = <ls_evt> iv_field = 'NAME' ).
        mo_out->add( `` ).
        mo_out->add( |     EVENT { lv_evt } [ visibility { lcl_util=>fv( is_row = <ls_evt> iv_field = 'VISIBILITY' ) } | &&
                     |{ lv_flags }]| ).

        ASSIGN COMPONENT 'PARAMETERS' OF STRUCTURE <ls_evt> TO <lt_epar>.
        IF sy-subrc = 0.
          LOOP AT <lt_epar> ASSIGNING <ls_epar>.
            lv_par = lcl_util=>fv( is_row = <ls_epar> iv_field = 'NAME' ).
            CLEAR lo_typ.
            TRY.
                CALL METHOD io_obj->('GET_EVENT_PARAMETER_TYPE')
                  EXPORTING
                    p_event_name     = lv_evt
                    p_parameter_name = lv_par
                  RECEIVING
                    p_descr_ref      = lo_typ
                  EXCEPTIONS
                    OTHERS           = 1.
                IF sy-subrc <> 0.
                  CLEAR lo_typ.
                ENDIF.
              CATCH cx_root.
                CLEAR lo_typ.
            ENDTRY.
            mo_out->add( |          EXPORTING  { lv_par WIDTH = 32 } | &&
                         |{ COND string( WHEN lcl_util=>fv( is_row = <ls_epar> iv_field = 'IS_OPTIONAL' ) = abap_true
                                         THEN `OPTIONAL` ELSE `` ) WIDTH = 9 } | &&
                         |TYPE { COND string( WHEN lo_typ IS BOUND THEN type_label( lo_typ )
                                              ELSE `(see repository view)` ) }| ).
          ENDLOOP.
        ENDIF.
      ENDLOOP.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_ddic.

    DATA lo_elem  TYPE REF TO cl_abap_elemdescr.
    DATA ls_dfies TYPE dfies.

    collect_types( ).

    mo_out->head( |DDIC / TYPE DETAILS (expansion depth { ms_opt-depth })| ).

    " ---- structures and table types ---------------------------------------
    mo_out->sub( `STRUCTURES AND TABLE TYPES used by attributes / parameters / types` ).
    IF mt_type IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.

    SORT mt_type BY name.

    LOOP AT mt_type INTO DATA(ls_type).
      mo_out->sub( |{ ls_type-name }   [{ COND string( WHEN ls_type-ref->is_ddic_type( ) = abap_true
                                                      THEN `DDIC` ELSE `local / class type` ) } | &&
                   |{ COND string( WHEN ls_type-ref->kind = cl_abap_typedescr=>kind_table
                                   THEN `table type` ELSE `structure` ) }]| ).
      mo_out->add( |     absolute name : { ls_type-abs }| ).
      mo_out->add( |     used by       : { ls_type-usage }| ).

      " DDIC header: table class, delivery class, enhancement category,
      " key definition of table types ...
      IF ls_type-ref->is_ddic_type( ) = abap_true.
        IF ls_type-ref->kind = cl_abap_typedescr=>kind_struct.
          lcl_util=>dump_rows(
            io_out     = mo_out
            ir_tab     = lcl_util=>generic_select(
                           iv_table = 'DD02V'
                           iv_where = |TABNAME = { lcl_util=>quote( ls_type-name ) } | &&
                                      |AND DDLANGUAGE = { lcl_util=>quote( CONV string( sy-langu ) ) }| )
            iv_title   = |{ ls_type-name } - DDIC header (DD02V)|
            iv_initial = ms_opt-init ).
        ELSE.
          lcl_util=>dump_rows(
            io_out     = mo_out
            ir_tab     = lcl_util=>generic_select(
                           iv_table = 'DD40V'
                           iv_where = |TYPENAME = { lcl_util=>quote( ls_type-name ) } | &&
                                      |AND DDLANGUAGE = { lcl_util=>quote( CONV string( sy-langu ) ) }| )
            iv_title   = |{ ls_type-name } - DDIC header (DD40V)|
            iv_initial = ms_opt-init ).
        ENDIF.
        mo_out->add( `` ).
      ENDIF.

      expand_type( io_type   = ls_type-ref
                   iv_indent = 5
                   iv_depth  = ms_opt-depth ).
    ENDLOOP.

    " ---- data elements ------------------------------------------------------
    mo_out->sub( `DATA ELEMENTS used directly by attributes / parameters` ).
    IF mt_elem IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.

    SORT mt_elem BY name.

    LOOP AT mt_elem INTO DATA(ls_elem).
      TRY.
          lo_elem ?= ls_elem-ref.
        CATCH cx_sy_move_cast_error.
          CONTINUE.
      ENDTRY.

      CLEAR ls_dfies.
      lo_elem->get_ddic_field(
        RECEIVING  p_flddescr = ls_dfies
        EXCEPTIONS OTHERS     = 1 ).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      mo_out->sub( |{ ls_elem-name }   used by: { ls_elem-usage }| ).
      lcl_util=>dump_struct( io_out     = mo_out
                             is_row     = ls_dfies
                             iv_indent  = 7
                             iv_initial = ms_opt-init ).

      IF ls_dfies-domname IS NOT INITIAL.
        DATA(lt_fix) = lcl_util=>dom_values( ls_dfies-domname ).
        IF lt_fix IS NOT INITIAL.
          mo_out->add( |       Fixed values of domain { ls_dfies-domname }:| ).
          LOOP AT lt_fix INTO DATA(ls_fix).
            mo_out->add( |         { ls_fix-low WIDTH = 12 }| &&
                         |{ COND string( WHEN ls_fix-high IS NOT INITIAL THEN |- { ls_fix-high } | ) }| &&
                         |{ ls_fix-text }| ).
          ENDLOOP.
        ENDIF.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD collect_types.

    DATA lo_typ   TYPE REF TO cl_abap_datadescr.
    DATA lo_descr TYPE REF TO cl_abap_typedescr.

    CLEAR: mt_type, mt_elem.

    " ---- RTTI: every attribute / parameter incl. inherited ones ---------
    IF mo_obj IS BOUND.

      LOOP AT mo_obj->attributes INTO DATA(ls_attr).
        CLEAR lo_typ.
        TRY.
            mo_obj->get_attribute_type(
              EXPORTING  p_name      = ls_attr-name
              RECEIVING  p_descr_ref = lo_typ
              EXCEPTIONS OTHERS      = 1 ).
            IF sy-subrc = 0.
              collect_type( io_type = lo_typ iv_usage = |attr { ls_attr-name }| ).
            ENDIF.
          CATCH cx_root.
        ENDTRY.
      ENDLOOP.

      LOOP AT mo_obj->methods INTO DATA(ls_meth).
        LOOP AT ls_meth-parameters INTO DATA(ls_parm).
          CLEAR lo_typ.
          TRY.
              mo_obj->get_method_parameter_type(
                EXPORTING  p_method_name    = ls_meth-name
                           p_parameter_name = ls_parm-name
                RECEIVING  p_descr_ref      = lo_typ
                EXCEPTIONS OTHERS           = 1 ).
              IF sy-subrc = 0.
                collect_type( io_type = lo_typ iv_usage = |{ ls_meth-name }-{ ls_parm-name }| ).
              ENDIF.
            CATCH cx_root.
          ENDTRY.
        ENDLOOP.
      ENDLOOP.

    ENDIF.

    " ---- repository: own types and event / other parameters --------------
    DATA(lr_model) = model( mv_cls ).

    LOOP AT lr_model->comps INTO DATA(ls_comp) WHERE cmptype = `3`.
      DATA(lv_abs) = COND string( WHEN mv_isintf = abap_true
                                  THEN |\\INTERFACE={ mv_cls }\\TYPE={ ls_comp-cmpname }|
                                  ELSE |\\CLASS={ mv_cls }\\TYPE={ ls_comp-cmpname }| ).
      CLEAR lo_descr.
      cl_abap_typedescr=>describe_by_name(
        EXPORTING  p_name      = lv_abs
        RECEIVING  p_descr_ref = lo_descr
        EXCEPTIONS OTHERS      = 1 ).
      IF sy-subrc = 0 AND lo_descr IS BOUND.
        TRY.
            lo_typ ?= lo_descr.
            collect_type( io_type = lo_typ iv_usage = |type { ls_comp-cmpname }| ).
          CATCH cx_sy_move_cast_error.
        ENDTRY.
      ENDIF.
    ENDLOOP.

    LOOP AT lr_model->subs INTO DATA(ls_sub)
         WHERE scotype <> `1` AND typename IS NOT INITIAL
           AND ( typtype = `1` OR typtype = `3` ).
      CLEAR lo_descr.
      cl_abap_typedescr=>describe_by_name(
        EXPORTING  p_name      = ls_sub-typename
        RECEIVING  p_descr_ref = lo_descr
        EXCEPTIONS OTHERS      = 1 ).
      IF sy-subrc = 0 AND lo_descr IS BOUND.
        TRY.
            lo_typ ?= lo_descr.
            collect_type( io_type = lo_typ iv_usage = |{ ls_sub-cmpname }-{ ls_sub-sconame }| ).
          CATCH cx_sy_move_cast_error.
        ENDTRY.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD collect_type.

    DATA lo_ref TYPE REF TO cl_abap_refdescr.
    DATA lo_to  TYPE REF TO cl_abap_datadescr.
    FIELD-SYMBOLS <ls_type> TYPE ty_s_type.

    IF io_type IS NOT BOUND.
      RETURN.
    ENDIF.

    " REF TO <data type> -> collect the referenced data type
    IF io_type->kind = cl_abap_typedescr=>kind_ref.
      TRY.
          lo_ref ?= io_type.
          lo_to  ?= lo_ref->get_referenced_type( ).
          IF lo_to->kind <> cl_abap_typedescr=>kind_ref.
            collect_type( io_type = lo_to iv_usage = |{ iv_usage } (REF TO)| ).
          ENDIF.
        CATCH cx_root.
      ENDTRY.
      RETURN.
    ENDIF.

    DATA(lv_abs) = CONV string( io_type->absolute_name ).
    DATA(lv_name) = CONV string( io_type->get_relative_name( ) ).
    IF lv_name IS INITIAL.
      lv_name = lv_abs.
    ENDIF.

    CASE io_type->kind.
      WHEN cl_abap_typedescr=>kind_struct OR cl_abap_typedescr=>kind_table.
        ASSIGN mt_type[ abs = lv_abs ] TO <ls_type>.
        IF sy-subrc <> 0.
          APPEND VALUE #( abs = lv_abs name = lv_name usage = iv_usage ref = io_type ) TO mt_type.
          RETURN.
        ENDIF.
      WHEN cl_abap_typedescr=>kind_elem.
        IF io_type->is_ddic_type( ) = abap_false.
          RETURN.
        ENDIF.
        ASSIGN mt_elem[ abs = lv_abs ] TO <ls_type>.
        IF sy-subrc <> 0.
          APPEND VALUE #( abs = lv_abs name = lv_name usage = iv_usage ref = io_type ) TO mt_elem.
          RETURN.
        ENDIF.
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    IF strlen( <ls_type>-usage ) < 600.
      <ls_type>-usage = |{ <ls_type>-usage }, { iv_usage }|.
    ELSEIF <ls_type>-usage NP '*...'.
      <ls_type>-usage = <ls_type>-usage && `, ...`.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD expand_type.

    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    DATA lo_table  TYPE REF TO cl_abap_tabledescr.

    IF io_type IS NOT BOUND OR iv_depth <= 0.
      RETURN.
    ENDIF.

    DATA(lv_pad) = repeat( val = ` ` occ = iv_indent ).

    CASE io_type->kind.

      WHEN cl_abap_typedescr=>kind_table.
        TRY.
            lo_table ?= io_type.
            DATA(lo_line) = lo_table->get_table_line_type( ).

            DATA(lv_kind) = SWITCH string( lo_table->table_kind
                              WHEN cl_abap_tabledescr=>tablekind_std    THEN `STANDARD`
                              WHEN cl_abap_tabledescr=>tablekind_sorted THEN `SORTED`
                              WHEN cl_abap_tabledescr=>tablekind_hashed THEN `HASHED`
                              WHEN cl_abap_tabledescr=>tablekind_index  THEN `INDEX`
                              ELSE `ANY` ).

            DATA(lv_keys) = ``.
            LOOP AT lo_table->key INTO DATA(ls_key).
              lv_keys = |{ lv_keys } { ls_key-name }|.
            ENDLOOP.

            DATA(lv_keydef) = SWITCH string( lo_table->key_defkind
                                WHEN cl_abap_tabledescr=>keydefkind_default   THEN `DEFAULT KEY`
                                WHEN cl_abap_tabledescr=>keydefkind_tableline THEN `KEY TABLE_LINE`
                                ELSE COND string( WHEN lv_keys IS INITIAL THEN `EMPTY KEY`
                                                  ELSE |KEY{ lv_keys }| ) ).

            mo_out->add( |{ lv_pad }{ lv_kind } TABLE OF { type_label( lo_line ) } WITH | &&
                         |{ COND string( WHEN lo_table->has_unique_key = abap_true
                                         THEN `UNIQUE` ELSE `NON-UNIQUE` ) } { lv_keydef }| ).

            IF lo_line->kind = cl_abap_typedescr=>kind_elem.
              mo_out->add( |{ lv_pad }  line: { field_extra( lo_line ) }| ).
            ENDIF.

            expand_type( io_type   = lo_line
                         iv_indent = iv_indent + 2
                         iv_depth  = iv_depth - 1 ).
          CATCH cx_root.
            mo_out->add( |{ lv_pad }(table line type not resolvable)| ).
        ENDTRY.

      WHEN cl_abap_typedescr=>kind_struct.
        TRY.
            lo_struct ?= io_type.
            LOOP AT lo_struct->get_components( ) INTO DATA(ls_comp).

              IF ls_comp-as_include = abap_true.
                mo_out->add( |{ lv_pad }.INCLUDE { type_label( ls_comp-type ) }| &&
                             |{ COND string( WHEN ls_comp-suffix IS NOT INITIAL
                                             THEN | RENAMING WITH SUFFIX { ls_comp-suffix }| ) }| ).
                expand_type( io_type   = ls_comp-type
                             iv_indent = iv_indent + 2
                             iv_depth  = iv_depth ).
                CONTINUE.
              ENDIF.

              mo_out->add( |{ lv_pad }{ ls_comp-name WIDTH = 32 } | &&
                           |{ type_label( ls_comp-type ) WIDTH = 34 } | &&
                           |{ field_extra( ls_comp-type ) }| ).

              IF ls_comp-type IS BOUND AND
                 ( ls_comp-type->kind = cl_abap_typedescr=>kind_struct OR
                   ls_comp-type->kind = cl_abap_typedescr=>kind_table ).
                expand_type( io_type   = ls_comp-type
                             iv_indent = iv_indent + 2
                             iv_depth  = iv_depth - 1 ).
              ENDIF.
            ENDLOOP.
          CATCH cx_root.
            mo_out->add( |{ lv_pad }(components not resolvable)| ).
        ENDTRY.

      WHEN OTHERS.
        mo_out->add( |{ lv_pad }{ type_label( io_type ) } { field_extra( io_type ) }| ).

    ENDCASE.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD field_extra.

    DATA lo_elem  TYPE REF TO cl_abap_elemdescr.
    DATA ls_dfies TYPE dfies.

    IF io_type IS NOT BOUND OR io_type->kind <> cl_abap_typedescr=>kind_elem.
      RETURN.
    ENDIF.

    lo_elem ?= io_type.

    IF lo_elem->is_ddic_type( ) = abap_true.
      lo_elem->get_ddic_field(
        RECEIVING  p_flddescr = ls_dfies
        EXCEPTIONS OTHERS     = 1 ).
      IF sy-subrc = 0.
        rv_txt = |{ ls_dfies-datatype }({ CONV i( ls_dfies-leng ) }| &&
                 |{ COND string( WHEN ls_dfies-decimals IS NOT INITIAL
                                 THEN |,{ CONV i( ls_dfies-decimals ) }| ) }) | &&
                 |{ ls_dfies-fieldtext }|.
        IF ls_dfies-domname IS NOT INITIAL.
          rv_txt = |{ rv_txt }  [domain { ls_dfies-domname }| &&
                   |{ COND string( WHEN ls_dfies-valexi IS NOT INITIAL THEN `, fixed values` ) }| &&
                   |{ COND string( WHEN ls_dfies-convexit IS NOT INITIAL
                                   THEN |, conv.exit { ls_dfies-convexit }| ) }]|.
        ENDIF.
        RETURN.
      ENDIF.
    ENDIF.

    rv_txt = |kind { lo_elem->type_kind } len { lo_elem->output_length } dec { lo_elem->decimals }|.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD type_label.

    DATA lo_ref  TYPE REF TO cl_abap_refdescr.
    DATA lo_elem TYPE REF TO cl_abap_elemdescr.

    IF io_type IS NOT BOUND.
      rv_txt = `(type not resolvable - see repository view / source)`.
      RETURN.
    ENDIF.

    rv_txt = io_type->get_relative_name( ).

    IF io_type->kind = cl_abap_typedescr=>kind_ref.
      TRY.
          lo_ref ?= io_type.
          DATA(lo_ref_to) = lo_ref->get_referenced_type( ).
          rv_txt = |REF TO { lo_ref_to->get_relative_name( ) }|.
        CATCH cx_root.
          rv_txt = `REF TO (not resolvable)`.
      ENDTRY.
      RETURN.
    ENDIF.

    IF rv_txt IS INITIAL.
      IF io_type->kind = cl_abap_typedescr=>kind_elem.
        lo_elem ?= io_type.
        rv_txt = |(kind { lo_elem->type_kind } len { lo_elem->output_length } dec { lo_elem->decimals })|.
      ELSE.
        rv_txt = |{ io_type->absolute_name } (kind { io_type->kind } type { io_type->type_kind })|.
      ENDIF.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD vis_text.

    rv_txt = SWITCH string( iv_vis
               WHEN cl_abap_objectdescr=>public    THEN `PUBLIC`
               WHEN cl_abap_objectdescr=>protected THEN `PROTECTED`
               WHEN cl_abap_objectdescr=>private   THEN `PRIVATE`
               ELSE `UNKNOWN` ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD parm_text.

    rv_txt = SWITCH string( iv_kind
               WHEN cl_abap_objectdescr=>importing THEN `IMPORTING`
               WHEN cl_abap_objectdescr=>exporting THEN `EXPORTING`
               WHEN cl_abap_objectdescr=>changing  THEN `CHANGING`
               WHEN cl_abap_objectdescr=>returning THEN `RETURNING`
               ELSE `?` ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_values.

    " Runtime values of constants and static attributes. Structured
    " constants (e.g. T100 keys of exception classes) are expanded, T100
    " message texts and OTR texts are looked up.
    FIELD-SYMBOLS <lv_val> TYPE any.

    mo_out->head( `CONSTANT / STATIC ATTRIBUTE VALUES (runtime)` ).

    IF mo_obj IS NOT BOUND.
      mo_out->add( `(RTTI not available - see attribute VALUE / source in the ATTRIBUTES section)` ).
      RETURN.
    ENDIF.

    DATA(lv_n) = 0.
    LOOP AT mo_obj->attributes INTO DATA(ls_attr)
         WHERE is_constant = abap_true OR is_class = abap_true.

      lv_n = lv_n + 1.
      DATA(lv_name) = |{ mv_cls }=>{ ls_attr-name }|.
      UNASSIGN <lv_val>.
      TRY.
          ASSIGN (lv_name) TO <lv_val>.
        CATCH cx_root.
          UNASSIGN <lv_val>.
      ENDTRY.

      IF <lv_val> IS NOT ASSIGNED.
        mo_out->add( |  { ls_attr-name WIDTH = 45 } (not accessible from outside - | &&
                     |{ vis_text( ls_attr-visibility ) }; see VALUE / source in ATTRIBUTES)| ).
        CONTINUE.
      ENDIF.

      print_value( iv_val    = <lv_val>
                   iv_name   = CONV string( ls_attr-name )
                   iv_indent = 2 ).
    ENDLOOP.

    IF lv_n = 0.
      mo_out->add( `(no constants / static attributes)` ).
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_value.

    DATA lv_msgid TYPE arbgb.
    DATA lv_msgno TYPE msgnr.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    FIELD-SYMBOLS: <lv_comp> TYPE any,
                   <lt_tab>  TYPE ANY TABLE,
                   <lv_line> TYPE any.

    DATA(lv_pad)  = repeat( val = ` ` occ = iv_indent ).
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( iv_val ).

    CASE lo_type->kind.

      WHEN cl_abap_typedescr=>kind_elem.
        DATA(lv_txt) = lcl_util=>to_text( iv_val ).
        mo_out->add( |{ lv_pad }{ iv_name WIDTH = 45 } = '{ lv_txt }'| ).

        " OTR concept (exception texts of old exception classes)
        IF matches( val = lv_txt regex = `^[0-9A-Fa-f]{32}$` ).
          DATA(lr_otr) = lcl_util=>generic_select(
                           iv_table = 'SOTR_TEXT'
                           iv_where = |CONCEPT = { lcl_util=>quote( to_upper( lv_txt ) ) }| ).
          IF lr_otr IS BOUND.
            ASSIGN lr_otr->* TO <lt_tab>.
            LOOP AT <lt_tab> ASSIGNING <lv_line>.
              DATA(lv_lang) = lcl_util=>fv( is_row = <lv_line> iv_field = 'LANGU' ).
              IF lv_lang = sy-langu OR lv_lang = 'E'.
                mo_out->add( |{ lv_pad }    OTR text [{ lv_lang }]: | &&
                             |{ lcl_util=>fv( is_row = <lv_line> iv_field = 'TEXT' ) }| ).
              ENDIF.
            ENDLOOP.
          ENDIF.
        ENDIF.

      WHEN cl_abap_typedescr=>kind_struct.
        mo_out->add( |{ lv_pad }{ iv_name WIDTH = 45 } (structure { lo_type->get_relative_name( ) })| ).
        lo_struct ?= lo_type.
        LOOP AT lo_struct->components INTO DATA(ls_comp).
          ASSIGN COMPONENT ls_comp-name OF STRUCTURE iv_val TO <lv_comp>.
          IF sy-subrc = 0.
            print_value( iv_val    = <lv_comp>
                         iv_name   = |{ iv_name }-{ ls_comp-name }|
                         iv_indent = iv_indent + 2 ).
          ENDIF.
        ENDLOOP.

        " T100 key (IF_T100_MESSAGE / SCX_T100KEY) -> message text
        ASSIGN COMPONENT 'MSGID' OF STRUCTURE iv_val TO <lv_comp>.
        IF sy-subrc = 0.
          lv_msgid = <lv_comp>.
          ASSIGN COMPONENT 'MSGNO' OF STRUCTURE iv_val TO <lv_comp>.
          IF sy-subrc = 0.
            lv_msgno = <lv_comp>.
            SELECT SINGLE text FROM t100
              WHERE sprsl = @sy-langu AND arbgb = @lv_msgid AND msgnr = @lv_msgno
              INTO @DATA(lv_t100).
            IF sy-subrc <> 0.
              SELECT SINGLE text FROM t100
                WHERE sprsl = 'E' AND arbgb = @lv_msgid AND msgnr = @lv_msgno
                INTO @lv_t100.
            ENDIF.
            IF sy-subrc = 0.
              mo_out->add( |{ lv_pad }    T100 { lv_msgid }/{ lv_msgno }: { lv_t100 }| ).
            ENDIF.
          ENDIF.
        ENDIF.

      WHEN cl_abap_typedescr=>kind_table.
        ASSIGN iv_val TO <lt_tab>.
        mo_out->add( |{ lv_pad }{ iv_name WIDTH = 45 } (table, { lines( <lt_tab> ) } lines)| ).
        DATA(lv_idx) = 0.
        LOOP AT <lt_tab> ASSIGNING <lv_line>.
          lv_idx = lv_idx + 1.
          IF lv_idx > 100.
            mo_out->add( |{ lv_pad }  ... (first 100 lines shown)| ).
            EXIT.
          ENDIF.
          print_value( iv_val    = <lv_line>
                       iv_name   = |{ iv_name }[{ lv_idx }]|
                       iv_indent = iv_indent + 2 ).
        ENDLOOP.

      WHEN cl_abap_typedescr=>kind_ref.
        mo_out->add( |{ lv_pad }{ iv_name WIDTH = 45 } = (reference, | &&
                     |{ COND string( WHEN iv_val IS INITIAL THEN `initial` ELSE `bound` ) })| ).

      WHEN OTHERS.
        mo_out->add( |{ lv_pad }{ iv_name WIDTH = 45 } = (kind { lo_type->kind })| ).

    ENDCASE.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_docu.

    DATA lt_line TYPE STANDARD TABLE OF tline WITH EMPTY KEY.
    DATA lt_tp   TYPE STANDARD TABLE OF textpool WITH EMPTY KEY.
    DATA lv_pool TYPE progname.

    mo_out->head( `DOCUMENTATION AND TEXTS` ).

    " ---- SE61 documentation: class (CL) and components (CO) --------------
    DATA(lv_obj) = CONV doku_obj( mv_cls ).
    DATA(lv_pat) = lcl_util=>limu_pattern( mv_cls ).

    SELECT DISTINCT id, object, langu FROM dokhl
      WHERE object = @lv_obj
         OR object LIKE @lv_pat ESCAPE '#'
      ORDER BY id, object, langu
      INTO TABLE @DATA(lt_dok)
      UP TO @ms_opt-maxr ROWS.

    IF lt_dok IS INITIAL.
      mo_out->sub( `SE61 documentation: (none)` ).
    ENDIF.

    LOOP AT lt_dok INTO DATA(ls_dok).
      " show the logon language, or English if no logon-language version
      IF ls_dok-langu <> sy-langu AND
         line_exists( lt_dok[ id = ls_dok-id object = ls_dok-object langu = sy-langu ] ).
        CONTINUE.
      ENDIF.
      IF ls_dok-langu <> sy-langu AND ls_dok-langu <> 'E' AND
         line_exists( lt_dok[ id = ls_dok-id object = ls_dok-object langu = 'E' ] ).
        CONTINUE.
      ENDIF.

      CLEAR lt_line.
      CALL FUNCTION 'DOCU_GET'
        EXPORTING
          id     = ls_dok-id
          langu  = ls_dok-langu
          object = ls_dok-object
        TABLES
          line   = lt_line
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      mo_out->sub( |DOCUMENTATION { ls_dok-id } { condense( CONV string( ls_dok-object ) ) } [{ ls_dok-langu }]| ).
      LOOP AT lt_line INTO DATA(ls_line).
        mo_out->add( |     { ls_line-tdformat WIDTH = 3 } { ls_line-tdline }| ).
      ENDLOOP.
    ENDLOOP.

    " ---- text pool --------------------------------------------------------
    lv_pool = mv_prefix && COND string( WHEN mv_isintf = abap_true THEN `IP` ELSE `CP` ).
    READ TEXTPOOL lv_pool INTO lt_tp LANGUAGE sy-langu.
    IF lt_tp IS INITIAL.
      READ TEXTPOOL lv_pool INTO lt_tp LANGUAGE 'E'.
    ENDIF.

    mo_out->sub( |TEXT POOL of { lv_pool } (text symbols)| ).
    IF lt_tp IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_tp INTO DATA(ls_tp).
      mo_out->add( |     { ls_tp-id } { ls_tp-key WIDTH = 10 } { ls_tp-entry } (max len { ls_tp-length })| ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_source.

    TYPES: BEGIN OF ty_s_inc,
             rank    TYPE i,
             sortkey TYPE string,
             prog  TYPE progname,
             title TYPE string,
           END OF ty_s_inc.

    DATA lt_inc   TYPE STANDARD TABLE OF ty_s_inc WITH EMPTY KEY.
    DATA lt_meth  TYPE seop_methods_w_include.
    DATA lt_trdir TYPE STANDARD TABLE OF trdir WITH EMPTY KEY.

    mo_out->head( `SOURCE CODE - every include of the pool` ).

    " method include -> method name (incl. IF_XXX~METHOD, aliases)
    IF mv_isintf = abap_false.
      TRY.
          lt_meth = cl_oo_classname_service=>get_all_method_includes( mv_cls ).
        CATCH cx_root.
          CLEAR lt_meth.
      ENDTRY.
    ENDIF.

    " every include that belongs to the pool, whatever its suffix
    DATA(lv_pat) = |{ lcl_util=>like_escape( mv_prefix ) }%|.
    SELECT * FROM trdir
      WHERE name LIKE @lv_pat ESCAPE '#'
      INTO TABLE @lt_trdir.

    LOOP AT lt_trdir INTO DATA(ls_trdir).
      DATA(lv_prog) = ls_trdir-name.
      DATA(lv_suffix) = CONV string( lv_prog+30 ).
      DATA(ls_inc) = VALUE ty_s_inc( prog = lv_prog sortkey = lv_prog ).

      CASE lv_suffix.
        WHEN `CP`.    ls_inc-rank = 1.  ls_inc-title = `CLASS POOL (main program)`.
        WHEN `CU`.    ls_inc-rank = 2.  ls_inc-title = `PUBLIC SECTION`.
        WHEN `CO`.    ls_inc-rank = 3.  ls_inc-title = `PROTECTED SECTION`.
        WHEN `CI`.    ls_inc-rank = 4.  ls_inc-title = `PRIVATE SECTION`.
        WHEN `CCDEF`. ls_inc-rank = 5.  ls_inc-title = `CLASS-RELEVANT LOCAL TYPES (CCDEF)`.
        WHEN `CCMAC`. ls_inc-rank = 6.  ls_inc-title = `MACROS (CCMAC)`.
        WHEN `CCIMP`. ls_inc-rank = 7.  ls_inc-title = `LOCAL TYPES / CLASSES (CCIMP)`.
        WHEN `CCAU`.  ls_inc-rank = 8.  ls_inc-title = `TEST CLASSES (CCAU)`.
        WHEN `CT`.    ls_inc-rank = 9.  ls_inc-title = `LOCAL TYPES (CT)`.
        WHEN `IP`.    ls_inc-rank = 1.  ls_inc-title = `INTERFACE POOL (main program)`.
        WHEN `IU`.    ls_inc-rank = 2.  ls_inc-title = `INTERFACE DECLARATION (IU - incl. constant values)`.
        WHEN OTHERS.
          READ TABLE lt_meth INTO DATA(ls_meth) WITH KEY incname = lv_prog.
          IF sy-subrc = 0.
            ls_inc-rank  = 50.
            ls_inc-sortkey = ls_meth-cpdkey-cpdname.
            ls_inc-title = |METHOD { ls_meth-cpdkey-cpdname }|.
          ELSEIF lv_suffix CP 'CM*'.
            ls_inc-rank  = 60.
            ls_inc-title = `METHOD INCLUDE (method name not resolved)`.
          ELSE.
            ls_inc-rank  = 90.
            ls_inc-title = |INCLUDE (suffix { lv_suffix })|.
          ENDIF.
      ENDCASE.

      ls_inc-title = |{ ls_inc-title } - { lv_prog } - | &&
                     |changed { lcl_util=>fv( is_row = ls_trdir iv_field = 'UNAM' ) } | &&
                     |{ lcl_util=>fv( is_row = ls_trdir iv_field = 'UDAT' ) }|.
      APPEND ls_inc TO lt_inc.
    ENDLOOP.

    " method includes the service knows but TRDIR does not list
    LOOP AT lt_meth INTO ls_meth.
      IF ls_meth-incname IS NOT INITIAL AND
         NOT line_exists( lt_inc[ prog = ls_meth-incname ] ).
        APPEND VALUE #( rank    = 50
                        sortkey = ls_meth-cpdkey-cpdname
                        prog  = ls_meth-incname
                        title = |METHOD { ls_meth-cpdkey-cpdname } - { ls_meth-incname }| ) TO lt_inc.
      ENDIF.
    ENDLOOP.

    IF lt_inc IS INITIAL.
      mo_out->add( `(no includes found in TRDIR)` ).
      RETURN.
    ENDIF.

    SORT lt_inc BY rank sortkey.

    LOOP AT lt_inc INTO ls_inc.
      print_include( iv_prog = ls_inc-prog iv_title = ls_inc-title ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD print_include.

    DATA lt_src TYPE lcl_util=>ty_t_string.
    DATA lv_ok  TYPE abap_bool.

    lcl_util=>read_source( EXPORTING iv_prog = iv_prog
                           IMPORTING et_src  = lt_src
                                     ev_ok   = lv_ok ).
    IF lv_ok = abap_false.
      IF iv_quiet = abap_false.
        mo_out->sub( |{ iv_title } - include does not exist / not readable| ).
      ENDIF.
      RETURN.
    ENDIF.

    mo_out->sub( |{ iv_title } ({ lines( lt_src ) } lines)| ).
    DATA(lv_no) = 0.
    LOOP AT lt_src INTO DATA(lv_src).
      lv_no = lv_no + 1.
      mo_out->add( |{ lv_no WIDTH = 6 ALIGN = RIGHT } \| { lv_src }| ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_local.

    DATA lt_src  TYPE lcl_util=>ty_t_string.
    DATA lv_ok   TYPE abap_bool.
    DATA lv_kind TYPE string.
    DATA lv_name TYPE string.
    DATA lt_done TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA lo_descr TYPE REF TO cl_abap_typedescr.
    DATA lo_obj   TYPE REF TO cl_abap_objectdescr.

    mo_out->head( `LOCAL CLASSES / INTERFACES OF THE CLASS POOL` ).

    IF mv_isintf = abap_true.
      mo_out->add( `(interface - not applicable)` ).
      RETURN.
    ENDIF.

    LOOP AT VALUE lcl_util=>ty_t_string( ( `CCDEF` ) ( `CCIMP` ) ( `CCAU` ) ( `CT` ) )
         INTO DATA(lv_suffix).

      DATA(lv_prog) = CONV progname( mv_prefix && lv_suffix ).
      lcl_util=>read_source( EXPORTING iv_prog = lv_prog
                             IMPORTING et_src  = lt_src
                                       ev_ok   = lv_ok ).
      IF lv_ok = abap_false.
        CONTINUE.
      ENDIF.

      LOOP AT lt_src INTO DATA(lv_line).
        CLEAR: lv_kind, lv_name.

        FIND FIRST OCCURRENCE OF REGEX `^\s*(CLASS)\s+([A-Za-z0-9_/]+)\s+DEFINITION`
             IN lv_line IGNORING CASE SUBMATCHES lv_kind lv_name.
        IF sy-subrc <> 0.
          FIND FIRST OCCURRENCE OF REGEX `^\s*(INTERFACE)\s+([A-Za-z0-9_/]+)`
               IN lv_line IGNORING CASE SUBMATCHES lv_kind lv_name.
          IF sy-subrc <> 0.
            CONTINUE.
          ENDIF.
        ENDIF.

        FIND FIRST OCCURRENCE OF REGEX `\<(DEFERRED|LOAD)\>` IN lv_line IGNORING CASE.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.

        lv_kind = to_upper( lv_kind ).
        lv_name = to_upper( lv_name ).
        IF line_exists( lt_done[ table_line = |{ lv_kind } { lv_name }| ] ).
          CONTINUE.
        ENDIF.
        APPEND |{ lv_kind } { lv_name }| TO lt_done.

        DATA(lv_abs) = |\\CLASS-POOL={ mv_cls }\\{ lv_kind }={ lv_name }|.
        CLEAR lo_descr.
        cl_abap_typedescr=>describe_by_name(
          EXPORTING  p_name      = lv_abs
          RECEIVING  p_descr_ref = lo_descr
          EXCEPTIONS OTHERS      = 1 ).

        IF sy-subrc = 0 AND lo_descr IS BOUND.
          TRY.
              lo_obj ?= lo_descr.
              print_rtti( io_obj   = lo_obj
                          iv_title = |LOCAL { lv_kind } { lv_name } (declared in { lv_prog })| ).
              CONTINUE.
            CATCH cx_sy_move_cast_error.
          ENDTRY.
        ENDIF.

        mo_out->sub( |LOCAL { lv_kind } { lv_name } (declared in { lv_prog }) - | &&
                     |RTTI not available, see SOURCE CODE section| ).
      ENDLOOP.
    ENDLOOP.

    IF lt_done IS INITIAL.
      mo_out->add( `(no local classes / interfaces)` ).
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_enhancements.

    DATA lt_enh TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    FIELD-SYMBOLS <lt_tab> TYPE STANDARD TABLE.

    mo_out->head( `ENHANCEMENTS` ).

    DATA(lr_enh) = lcl_util=>generic_select(
                     iv_table = 'ENHOBJ'
                     iv_where = |MAIN_NAME = { lcl_util=>quote( mv_cls ) } | &&
                                |OR OBJ_NAME = { lcl_util=>quote( mv_cls ) }|
                     iv_max   = ms_opt-maxr ).

    lcl_util=>dump_rows( io_out     = mo_out
                         ir_tab     = lr_enh
                         iv_title   = `Enhancement implementations on this object (ENHOBJ)`
                         iv_initial = ms_opt-init ).

    IF lr_enh IS NOT BOUND.
      RETURN.
    ENDIF.

    ASSIGN lr_enh->* TO <lt_tab>.
    LOOP AT <lt_tab> ASSIGNING FIELD-SYMBOL(<ls_row>).
      DATA(lv_enhname) = lcl_util=>fv( is_row = <ls_row> iv_field = 'ENHNAME' ).
      IF lv_enhname IS NOT INITIAL AND NOT line_exists( lt_enh[ table_line = lv_enhname ] ).
        APPEND lv_enhname TO lt_enh.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_enh INTO lv_enhname.
      lcl_util=>dump_rows(
        io_out     = mo_out
        ir_tab     = lcl_util=>generic_select( iv_table = 'ENHHEADER'
                                               iv_where = |ENHNAME = { lcl_util=>quote( lv_enhname ) }| )
        iv_title   = |Enhancement { lv_enhname } header (ENHHEADER)|
        iv_initial = ms_opt-init ).

      " enhancement implementation include <ENHNAME>====...E
      print_include( iv_prog  = CONV progname( lcl_util=>pool_prefix( lv_enhname ) && `E` )
                     iv_title = |ENHANCEMENT IMPLEMENTATION SOURCE { lv_enhname }|
                     iv_quiet = abap_true ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_transports.

    DATA lt_e070 TYPE STANDARD TABLE OF e070 WITH EMPTY KEY.

    mo_out->head( `TRANSPORTS, VERSIONS, INACTIVE OBJECTS` ).

    DATA(lv_objname) = CONV trobj_name( mv_cls ).
    DATA(lv_pat)     = lcl_util=>limu_pattern( mv_cls ).

    " ---- transport requests -------------------------------------------------
    SELECT trkorr, as4pos, pgmid, object, obj_name
      FROM e071
      WHERE obj_name = @lv_objname
         OR obj_name LIKE @lv_pat ESCAPE '#'
      ORDER BY trkorr, as4pos
      INTO TABLE @DATA(lt_e071)
      UP TO @ms_opt-maxr ROWS.

    mo_out->sub( `Transport requests / tasks containing the object (E071 / E070 / E07T)` ).

    IF lt_e071 IS INITIAL.
      mo_out->add( `     (none)` ).
    ELSE.
      SELECT * FROM e070
        FOR ALL ENTRIES IN @lt_e071
        WHERE trkorr = @lt_e071-trkorr
        INTO TABLE @lt_e070.

      SELECT trkorr, as4text FROM e07t
        FOR ALL ENTRIES IN @lt_e071
        WHERE trkorr = @lt_e071-trkorr
          AND langu  = @sy-langu
        INTO TABLE @DATA(lt_e07t).

      SORT lt_e070 BY as4date DESCENDING as4time DESCENDING trkorr.

      LOOP AT lt_e070 INTO DATA(ls_e070).
        READ TABLE lt_e07t INTO DATA(ls_e07t) WITH KEY trkorr = ls_e070-trkorr.
        IF sy-subrc <> 0.
          CLEAR ls_e07t.
        ENDIF.
        mo_out->add( `` ).
        mo_out->add( |     { ls_e070-trkorr } { ls_e070-as4date DATE = ISO } { ls_e070-as4time TIME = ISO } | &&
                     |{ ls_e070-as4user WIDTH = 12 } | &&
                     |status { lcl_util=>val_text( ls_e070-trstatus ) WIDTH = 28 } | &&
                     |type { lcl_util=>val_text( ls_e070-trfunction ) WIDTH = 30 } | &&
                     |{ COND string( WHEN ls_e070-strkorr IS NOT INITIAL THEN |parent { ls_e070-strkorr } | ) }| &&
                     |"{ ls_e07t-as4text }"| ).
        LOOP AT lt_e071 INTO DATA(ls_e071) WHERE trkorr = ls_e070-trkorr.
          mo_out->add( |          { ls_e071-pgmid } { ls_e071-object } { ls_e071-obj_name }| ).
        ENDLOOP.
      ENDLOOP.
    ENDIF.

    " ---- version history ------------------------------------------------------
    SELECT objtype, objname, versno, korrnum, author, datum, zeit
      FROM vrsd
      WHERE objname = @lv_objname
         OR objname LIKE @lv_pat ESCAPE '#'
      ORDER BY objtype, objname, versno
      INTO TABLE @DATA(lt_vrsd)
      UP TO @ms_opt-maxr ROWS.

    mo_out->sub( `Version history (VRSD)` ).
    IF lt_vrsd IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_vrsd INTO DATA(ls_vrsd).
      mo_out->add( |     { ls_vrsd-objtype } { condense( CONV string( ls_vrsd-objname ) ) WIDTH = 70 } | &&
                   |v{ ls_vrsd-versno } { ls_vrsd-korrnum WIDTH = 12 } { ls_vrsd-author WIDTH = 12 } | &&
                   |{ ls_vrsd-datum DATE = ISO } { ls_vrsd-zeit TIME = ISO }| ).
    ENDLOOP.

    " ---- inactive objects -------------------------------------------------------
    lcl_util=>dump_rows(
      io_out     = mo_out
      ir_tab     = lcl_util=>generic_select(
                     iv_table = 'DWINACTIV'
                     iv_where = |OBJ_NAME = { lcl_util=>quote( mv_cls ) } | &&
                                |OR OBJ_NAME LIKE { lcl_util=>quote( lv_pat ) } ESCAPE '#'|
                     iv_max   = ms_opt-maxr )
      iv_title   = `Inactive objects (DWINACTIV)`
      iv_initial = ms_opt-init ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_whereused.

    TYPES: BEGIN OF ty_s_cnt,
             objkey TYPE string,
             cnt    TYPE i,
           END OF ty_s_cnt.

    DATA lt_cnt TYPE SORTED TABLE OF ty_s_cnt WITH UNIQUE KEY objkey.
    DATA lt_seen TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <ls_cnt> TYPE ty_s_cnt.

    mo_out->head( `WHERE-USED AND USED OBJECTS (cross-reference index WBCROSSGT / CROSS)` ).
    mo_out->add( `Note: the result is only as current as the where-used index of the system.` ).

    " ---- who uses this class / interface ---------------------------------------
    mo_out->sub( |Includes referencing { mv_cls } (WBCROSSGT, OTYPE TY, max { ms_opt-maxr })| ).
    DATA(lr_wu) = lcl_util=>generic_select(
                    iv_table = 'WBCROSSGT'
                    iv_where = |OTYPE = 'TY' AND NAME = { lcl_util=>quote( mv_cls ) }|
                    iv_max   = ms_opt-maxr ).
    IF lr_wu IS NOT BOUND.
      mo_out->add( `     (WBCROSSGT not readable)` ).
    ELSE.
      ASSIGN lr_wu->* TO <lt_tab>.
      IF <lt_tab> IS INITIAL.
        mo_out->add( `     (none)` ).
      ENDIF.
      LOOP AT <lt_tab> ASSIGNING FIELD-SYMBOL(<ls_row>).
        DATA(lv_inc) = lcl_util=>fv( is_row = <ls_row> iv_field = 'INCLUDE' ).
        INSERT lv_inc INTO TABLE lt_seen.
      ENDLOOP.
      LOOP AT lt_seen INTO lv_inc.
        " class pool include -> owning class
        DATA(lv_owner) = lv_inc.
        FIND FIRST OCCURRENCE OF '=' IN lv_inc MATCH OFFSET DATA(lv_off).
        IF sy-subrc = 0 AND lv_off > 0.
          lv_owner = |class/interface { lv_inc(lv_off) }|.
        ENDIF.
        mo_out->add( |     { lv_inc WIDTH = 45 } { lv_owner }| ).
      ENDLOOP.
    ENDIF.

    " ---- usage per component ------------------------------------------------------
    mo_out->sub( |Usage per component of { mv_cls } (WBCROSSGT)| ).
    DATA(lv_cpat) = |{ lcl_util=>like_escape( mv_cls ) }\\%|.
    DATA(lr_cu) = lcl_util=>generic_select(
                    iv_table = 'WBCROSSGT'
                    iv_where = |NAME LIKE { lcl_util=>quote( lv_cpat ) } ESCAPE '#'|
                    iv_max   = 50000 ).
    IF lr_cu IS BOUND.
      ASSIGN lr_cu->* TO <lt_tab>.
      LOOP AT <lt_tab> ASSIGNING <ls_row>.
        DATA(lv_key) = |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'OTYPE' ) } | &&
                       |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'NAME' ) }|.
        READ TABLE lt_cnt ASSIGNING <ls_cnt> WITH TABLE KEY objkey = lv_key.
        IF sy-subrc = 0.
          <ls_cnt>-cnt = <ls_cnt>-cnt + 1.
        ELSE.
          INSERT VALUE #( objkey = lv_key cnt = 1 ) INTO TABLE lt_cnt.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF lt_cnt IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_cnt INTO DATA(ls_cnt).
      mo_out->add( |     { ls_cnt-objkey WIDTH = 80 } used in { ls_cnt-cnt } include(s)| ).
    ENDLOOP.

    " ---- what this class uses ---------------------------------------------------------
    DATA(lv_ipat) = |{ lcl_util=>like_escape( mv_prefix ) }%|.

    CLEAR lt_seen.
    mo_out->sub( `Objects used by the class pool - types, classes, methods, data (WBCROSSGT)` ).
    DATA(lr_us) = lcl_util=>generic_select(
                    iv_table = 'WBCROSSGT'
                    iv_where = |INCLUDE LIKE { lcl_util=>quote( lv_ipat ) } ESCAPE '#'|
                    iv_max   = 50000 ).
    IF lr_us IS BOUND.
      ASSIGN lr_us->* TO <lt_tab>.
      LOOP AT <lt_tab> ASSIGNING <ls_row>.
        DATA(lv_entry) = |{ lcl_util=>fvt( is_row = <ls_row> iv_field = 'OTYPE' ) WIDTH = 24 } | &&
                         |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'NAME' ) }|.
        INSERT lv_entry INTO TABLE lt_seen.
      ENDLOOP.
    ENDIF.
    IF lt_seen IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_seen INTO DATA(lv_seen).
      mo_out->add( |     { lv_seen }| ).
    ENDLOOP.

    CLEAR lt_seen.
    mo_out->sub( `Objects used by the class pool - function modules, messages, programs ... (CROSS)` ).
    DATA(lr_cr) = lcl_util=>generic_select(
                    iv_table = 'CROSS'
                    iv_where = |INCLUDE LIKE { lcl_util=>quote( lv_ipat ) } ESCAPE '#'|
                    iv_max   = 50000 ).
    IF lr_cr IS BOUND.
      ASSIGN lr_cr->* TO <lt_tab>.
      LOOP AT <lt_tab> ASSIGNING <ls_row>.
        lv_entry = |{ lcl_util=>fvt( is_row = <ls_row> iv_field = 'TYPE' ) WIDTH = 24 } | &&
                   |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'NAME' ) }|.
        INSERT lv_entry INTO TABLE lt_seen.
      ENDLOOP.
    ENDIF.
    IF lt_seen IS INITIAL.
      mo_out->add( `     (none)` ).
    ENDIF.
    LOOP AT lt_seen INTO lv_seen.
      mo_out->add( |     { lv_seen }| ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD sec_raw.

    " Every field of every row of every repository table of the object.
    " Tables that do not exist on your release are reported, not dumped.
    mo_out->head( |RAW REPOSITORY DUMP - every field of every row| &&
                  |{ COND string( WHEN ms_opt-init = abap_false THEN ` (initial fields omitted)` ) }| ).

    DATA(lv_w)  = |CLSNAME = { lcl_util=>quote( mv_cls ) }|.
    DATA(lv_wr) = |REFCLSNAME = { lcl_util=>quote( mv_cls ) }|.

    DATA(lt_tab) = VALUE lcl_util=>ty_t_string(
      ( `SEOCLASS` )   ( `SEOCLASSDF` ) ( `SEOCLASSTX` ) ( `SEOCLASSEX` )
      ( `SEOMETAREL` ) ( `SEOCOMPO` )   ( `SEOCOMPODF` ) ( `SEOCOMPOTX` )
      ( `SEOCOMPOEX` ) ( `SEOSUBCO` )   ( `SEOSUBCODF` ) ( `SEOSUBCOTX` )
      ( `SEOSUBCOEX` ) ( `SEOREDEF` )   ( `SEOFRIENDS` ) ( `SEOTYPEPLS` ) ).

    LOOP AT lt_tab INTO DATA(lv_tab).
      lcl_util=>dump_rows( io_out     = mo_out
                           ir_tab     = lcl_util=>generic_select( iv_table = lv_tab iv_where = lv_w )
                           iv_title   = |{ lv_tab } WHERE { lv_w }|
                           iv_initial = ms_opt-init ).
    ENDLOOP.

    lcl_util=>dump_rows( io_out     = mo_out
                         ir_tab     = lcl_util=>generic_select( iv_table = 'SEOMETAREL'
                                                                iv_where = lv_wr
                                                                iv_max   = ms_opt-maxr )
                         iv_title   = |SEOMETAREL WHERE { lv_wr }|
                         iv_initial = ms_opt-init ).

    lcl_util=>dump_rows(
      io_out     = mo_out
      ir_tab     = lcl_util=>generic_select(
                     iv_table = 'TRDIR'
                     iv_where = |NAME LIKE { lcl_util=>quote( |{ lcl_util=>like_escape( mv_prefix ) }%| ) } ESCAPE '#'| )
      iv_title   = |TRDIR WHERE NAME LIKE { mv_prefix }%|
      iv_initial = ms_opt-init ).

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
INITIALIZATION.
  " selection texts without maintaining text elements
  t_b1 = 'Objects'.
  t_b2 = 'Sections to extract'.
  t_b3 = 'Options'.
  b_all  = 'Select all'.
  b_none = 'Deselect all'.

  %_s_cls_%_app_%-text  = 'Class / Interface name(s)'.
  %_p_meta_%_app_%-text = 'Metadata, properties, package'.
  %_p_rel_%_app_%-text  = 'Relations, interfaces, friends'.
  %_p_attr_%_app_%-text = 'Attributes and constants'.
  %_p_meth_%_app_%-text = 'Methods, signatures, redefin.'.
  %_p_evt_%_app_%-text  = 'Events'.
  %_p_typ_%_app_%-text  = 'Types'.
  %_p_inh_%_app_%-text  = 'Inherited + interface comps'.
  %_p_rtti_%_app_%-text = 'Runtime view (RTTI)'.
  %_p_ddic_%_app_%-text = 'Structures / data elements'.
  %_p_cval_%_app_%-text = 'Constant values (runtime)'.
  %_p_doc_%_app_%-text  = 'Documentation, text pool'.
  %_p_src_%_app_%-text  = 'Source code (all includes)'.
  %_p_loc_%_app_%-text  = 'Local classes / interfaces'.
  %_p_enh_%_app_%-text  = 'Enhancements'.
  %_p_tr_%_app_%-text   = 'Transports and versions'.
  %_p_wu_%_app_%-text   = 'Where-used / used objects'.
  %_p_raw_%_app_%-text  = 'Raw SEO* table dump'.
  %_p_depth_%_app_%-text = 'Type expansion depth'.
  %_p_maxr_%_app_%-text  = 'Max rows (lists)'.
  %_p_init_%_app_%-text  = 'Show initial fields too'.
  %_p_list_%_app_%-text  = 'Display list'.
  %_p_down_%_app_%-text  = 'Download .txt per object'.
  %_p_dir_%_app_%-text   = 'Download directory'.

*&---------------------------------------------------------------------*
AT SELECTION-SCREEN.
  CASE sscrfields-ucomm.
    WHEN 'SALL' OR 'SNONE'.
      DATA(gv_flag) = COND abap_bool( WHEN sscrfields-ucomm = 'SALL' THEN abap_true ELSE abap_false ).
      p_meta = p_rel = p_attr = p_meth = p_evt = p_typ = p_inh = p_rtti = gv_flag.
      p_ddic = p_cval = p_doc = p_src = p_loc = p_enh = p_tr = p_wu = p_raw = gv_flag.
  ENDCASE.

*&---------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_dir.
  DATA gv_folder TYPE string.
  cl_gui_frontend_services=>directory_browse(
    CHANGING   selected_folder = gv_folder
    EXCEPTIONS OTHERS          = 1 ).
  cl_gui_cfw=>flush( ).
  IF gv_folder IS NOT INITIAL.
    p_dir = gv_folder.
  ENDIF.

*&---------------------------------------------------------------------*
START-OF-SELECTION.

  IF s_cls[] IS INITIAL.
    MESSAGE 'Enter at least one class / interface name' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  DATA(gs_opt) = VALUE ty_s_opt(
    meta  = p_meta  rel  = p_rel  attr = p_attr meth = p_meth
    evt   = p_evt   typ  = p_typ  inh  = p_inh  rtti = p_rtti
    ddic  = p_ddic  cval = p_cval doc  = p_doc  src  = p_src
    loc   = p_loc   enh  = p_enh  tr   = p_tr   wu   = p_wu
    raw   = p_raw   init = p_init
    depth = COND #( WHEN p_depth > 0 THEN p_depth ELSE 1 )
    maxr  = COND #( WHEN p_maxr  > 0 THEN p_maxr  ELSE 1000 ) ).

  SELECT clsname FROM seoclass
    WHERE clsname IN @s_cls
    ORDER BY clsname
    INTO TABLE @DATA(gt_cls).

  IF gt_cls IS INITIAL.
    MESSAGE 'No class / interface matches the selection' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  DATA gt_all   TYPE lcl_out=>ty_t_line.
  DATA gt_files TYPE lcl_out=>ty_t_line.

  DATA gv_idx     TYPE i.
  DATA gv_percent TYPE i.
  DATA gv_ptext   TYPE string.

  LOOP AT gt_cls INTO DATA(gs_cls).

    gv_idx     = sy-tabix.
    gv_percent = ( gv_idx * 100 ) / lines( gt_cls ).
    gv_ptext   = |Extracting { gs_cls-clsname } ({ gv_idx }/{ lines( gt_cls ) })|.
    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = gv_percent
        text       = gv_ptext.

    DATA(go_out) = NEW lcl_out( ).
    DATA(go_ext) = NEW lcl_extractor( iv_cls = gs_cls-clsname
                                      is_opt = gs_opt
                                      io_out = go_out ).
    go_ext->run( ).

    DATA(gt_lines) = go_out->get( ).

    IF p_down = abap_true.
      DATA(gv_file) = lcl_util=>download( it_line = gt_lines
                                          iv_name = gs_cls-clsname
                                          iv_dir  = p_dir ).
      APPEND COND string( WHEN gv_file IS NOT INITIAL
                          THEN |{ gs_cls-clsname WIDTH = 32 } -> { gv_file }|
                          ELSE |{ gs_cls-clsname WIDTH = 32 } -> download failed / not possible| )
        TO gt_files.
    ENDIF.

    IF p_list = abap_true.
      APPEND LINES OF gt_lines TO gt_all.
      APPEND `` TO gt_all.
    ENDIF.

  ENDLOOP.

  IF gt_files IS NOT INITIAL.
    WRITE / 'Downloaded files:'.
    LOOP AT gt_files INTO DATA(gv_fline).
      WRITE / gv_fline.
    ENDLOOP.
    ULINE.
    MESSAGE |{ lines( gt_cls ) } object(s) extracted| TYPE 'S'.
  ENDIF.

  LOOP AT gt_all INTO DATA(gv_line).
    WRITE / gv_line.
  ENDLOOP.
