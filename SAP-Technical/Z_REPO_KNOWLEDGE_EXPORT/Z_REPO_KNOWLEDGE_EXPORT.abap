*&---------------------------------------------------------------------*
*& Report  Z_REPO_KNOWLEDGE_EXPORT
*&---------------------------------------------------------------------*
*& Repository / package knowledge exporter (Markdown + ZIP)
*&
*& Target: SAP S/4HANA 2023 (works on 7.50+ with strict Open SQL)
*&
*& Extracts EVERYTHING that is stored in one or more development
*& packages - optionally the complete hierarchy (super packages up to
*& the top and all sub packages recursively) - and writes it as
*& Markdown documentation packed into ZIP files. The result is a
*& self-contained, searchable knowledge base of the package that can be
*& read by people or by any Markdown-aware documentation / search tool:
*&
*&   * Documentation ZIP : a folder of Markdown files with an index
*&   * Plugin ZIP        : the same content in a plugin folder layout
*&
*& Every Markdown file is kept below a configurable number of lines
*& (default 1800, so each file fits in a single read window). Large
*& objects are split into _part-NNN.md files at line boundaries, code
*& fences are closed and reopened correctly. Each ZIP ("volume") is
*& kept below a configurable size, so packages with crores of lines
*& are written as several volumes plus one index volume that maps every
*& object to its volume. Nothing is held in memory longer than one
*& volume.
*&
*& WHAT IS EXTRACTED
*&   Packages      hierarchy, attributes, texts, object counts
*&   PROG          attributes, texts, text pool, full source, screens
*&                 (header, fields, flow logic), GUI texts, variants
*&   CLAS / INTF   properties, relations, friends, every component as
*&                 ABAP declaration incl. SE24 descriptions (types,
*&                 attributes, constants + values, events, methods with
*&                 complete signatures and exceptions, aliases),
*&                 redefinitions, text pool, source of EVERY include
*&                 (sections, local types, macros, local classes, test
*&                 classes, every method)
*&   FUGR / FUNC   group texts, every include, text pool, screens; one
*&                 file per function module with signature, parameter
*&                 texts, RFC / update attributes and source
*&   DDIC          tables / structures (fields, keys, data elements,
*&                 texts, technical settings, foreign keys, indexes,
*&                 search help assignments, maintenance dialog),
*&                 CONTENTS of customizing / control / system tables
*&                 (configuration values), views, data elements, domains
*&                 + fixed values, table types + keys, search helps,
*&                 lock objects, type pools
*&   CDS / RAP     DDLS, DCLS and every other source-based ADT object
*&                 (DDLX, BDEF, SRVD, ...): source is located by probing
*&                 the repository source tables - no release-specific
*&                 API needed
*&   BOPF          for every business object (TADIR BOBF or found via a
*&                 constants interface): every /BOBF/ repository row of
*&                 the BO key (nodes, associations, actions,
*&                 determinations, validations, queries, alternative
*&                 keys, status, authorization ...), the complete
*&                 runtime configuration (every GET method and public
*&                 attribute of /BOBF/IF_FRW_CONFIGURATION), all
*&                 implementing classes / constants interfaces - also
*&                 the ones OUTSIDE the package, fully extracted
*&   MSAG          every message in every language, long texts
*&   TRAN          transaction definition, texts, parameters, auth.
*&   Framework     Web Dynpro components / applications /
*&                 configurations, BOR objects (+ program source),
*&                 workflow tasks / templates, Gateway projects /
*&                 models / services, enhancement spots /
*&                 implementations (+ source), classic BAdIs, number
*&                 range objects, authorization objects, package
*&                 interfaces: every repository table of the framework
*&                 that has the object key is discovered via DD03L and
*&                 dumped - no hard-coded table layouts
*&   BSP / UI5     WAPA: every O2* row, page / view / controller layout
*&                 and event handler code, and EVERY text file of the
*&                 application from the MIME repository (UI5 / Fiori:
*&                 Component.js, manifest.json, controllers, views,
*&                 fragments, i18n, css ...) - one document per file
*&   Workflow      tasks (HRS1*: texts, method binding, container) and
*&                 workflow templates: latest definition version, step
*&                 list and a Mermaid flow diagram, workflow classes /
*&                 BOR objects used by the steps (also outside package)
*&   Forms         Smart Forms / Adobe forms: generated function group
*&                 = every code node, program line, initialization
*&   Exits         CMOD projects / SMOD enhancements (exit includes
*&                 ZX* are extracted as programs)
*&   Outside the   EVERY object the package uses - classes, interfaces,
*&   package       function modules, programs, transactions, DDIC types
*&   (also         (from signatures, relations and the where-used index)
*&   standard SAP) and classes / BOR objects named by BOPF,
*&                 workflow, Gateway (DPC / MPC), BAdI, BSP ... - incl.
*&                 standard SAP objects (option), up to a configurable
*&                 reference depth and maximum number of objects
*&   Any object    TADIR data, SE61 documentation, used objects from
*&                 the where-used index (WBCROSSGT / CROSS)
*&   Errors        every failed read is logged in ERRORS.md, the
*&                 extraction always continues
*&
*& READ ONLY - no INSERT / UPDATE / MODIFY / DELETE, no COMMIT.
*& For big packages run it in BACKGROUND with output to the application
*& server (frontend download is not possible in background and dialog
*& work processes have a runtime limit).
*&---------------------------------------------------------------------*
REPORT z_repo_knowledge_export LINE-SIZE 255 NO STANDARD PAGE HEADING.

TABLES: tdevc, tadir.

*&---------------------------------------------------------------------*
*& Global types
*&---------------------------------------------------------------------*
TYPES: BEGIN OF ty_s_opt,
         sub    TYPE abap_bool,
         up     TYPE abap_bool,
         src    TYPE abap_bool,
         sig    TYPE abap_bool,
         ddic   TYPE abap_bool,
         cont   TYPE abap_bool,
         bopf   TYPE abap_bool,
         ext    TYPE abap_bool,
         extd   TYPE abap_bool,
         std    TYPE abap_bool,
         ldepth TYPE i,
         extmax TYPE i,
         dyn    TYPE abap_bool,
         docu   TYPE abap_bool,
         xref   TYPE abap_bool,
         frm    TYPE abap_bool,
         contr  TYPE i,
         maxr   TYPE i,
         maxl   TYPE i,
         volmb  TYPE i,
         maxf   TYPE i,
         plugin TYPE abap_bool,
         appl   TYPE abap_bool,
         test   TYPE abap_bool,
         dir    TYPE string,
         sname  TYPE string,
       END OF ty_s_opt.

*&---------------------------------------------------------------------*
*& Selection screen
*&---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE t_b1.
SELECT-OPTIONS: s_pack FOR tdevc-devclass OBLIGATORY,
                s_type FOR tadir-object,
                s_name FOR tadir-obj_name.
PARAMETERS: p_sub AS CHECKBOX DEFAULT 'X',
            p_up  AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE t_b2.
PARAMETERS: p_src   AS CHECKBOX DEFAULT 'X',
            p_sig   AS CHECKBOX DEFAULT 'X',
            p_ddic  AS CHECKBOX DEFAULT 'X',
            p_cont  AS CHECKBOX DEFAULT 'X',
            p_contr TYPE i DEFAULT 5000,
            p_bopf  AS CHECKBOX DEFAULT 'X',
            p_ext   AS CHECKBOX DEFAULT 'X',
            p_extd  AS CHECKBOX DEFAULT 'X',
            p_std   AS CHECKBOX DEFAULT 'X',
            p_ldep  TYPE i DEFAULT 1,
            p_extmx TYPE i DEFAULT 5000,
            p_dyn   AS CHECKBOX DEFAULT 'X',
            p_docu  AS CHECKBOX DEFAULT 'X',
            p_xref  AS CHECKBOX DEFAULT 'X',
            p_frm   AS CHECKBOX DEFAULT 'X',
            p_maxr  TYPE i DEFAULT 2000.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE t_b3.
PARAMETERS: r_skill RADIOBUTTON GROUP fmt DEFAULT 'X',
            r_plug  RADIOBUTTON GROUP fmt,
            p_sname TYPE c LENGTH 40 LOWER CASE,
            p_maxl  TYPE i DEFAULT 1800,
            p_volmb TYPE i DEFAULT 20,
            p_maxf  TYPE i DEFAULT 190,
            r_front RADIOBUTTON GROUP tgt DEFAULT 'X',
            r_appl  RADIOBUTTON GROUP tgt,
            p_dir   TYPE c LENGTH 200 LOWER CASE,
            p_test  AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b3.

*&---------------------------------------------------------------------*
*& Helpers
*&---------------------------------------------------------------------*
CLASS lcl_util DEFINITION FINAL.

  PUBLIC SECTION.
    TYPES ty_t_string TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    CLASS-DATA gv_nl   TYPE string READ-ONLY.
    CLASS-DATA gv_maxr TYPE i.

    CLASS-METHODS class_constructor.

    " component value of any structure - '' if it does not exist
    CLASS-METHODS fv
      IMPORTING is_row        TYPE any
                iv_field      TYPE csequence
      RETURNING VALUE(rv_val) TYPE string.

    CLASS-METHODS to_text
      IMPORTING iv_val        TYPE any
      RETURNING VALUE(rv_txt) TYPE string.

    " single line, Markdown-table safe, truncated
    CLASS-METHODS oneline
      IMPORTING VALUE(iv_txt) TYPE string
                iv_max        TYPE i DEFAULT 300
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS quote
      IMPORTING iv_val        TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS like_escape
      IMPORTING iv_val        TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    " ZCL_X -> ZCL_X=========================
    CLASS-METHODS pool_prefix
      IMPORTING iv_cls        TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

    " LIKE pattern: name padded with blanks to iv_len, then %
    CLASS-METHODS pad_pattern
      IMPORTING iv_val        TYPE csequence
                iv_len        TYPE i
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS generic_select
      IMPORTING iv_table      TYPE csequence
                iv_where      TYPE csequence
                iv_max        TYPE i DEFAULT 0
      RETURNING VALUE(rr_tab) TYPE REF TO data.

    " WHERE <field> = <value> with the value as host variable (works
    " for RAW keys such as BOPF keys)
    CLASS-METHODS select_by_field
      IMPORTING iv_table      TYPE csequence
                iv_field      TYPE csequence
                iv_value      TYPE any
                iv_max        TYPE i DEFAULT 0
                iv_ordered    TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rr_tab) TYPE REF TO data.

    CLASS-METHODS has_rows
      IMPORTING ir_tab     TYPE REF TO data
      RETURNING VALUE(rv)  TYPE abap_bool.

    CLASS-METHODS read_source
      IMPORTING iv_prog TYPE csequence
      EXPORTING et_src  TYPE ty_t_string
                ev_ok   TYPE abap_bool.

    CLASS-METHODS safe_file
      IMPORTING VALUE(iv_name) TYPE string
      RETURNING VALUE(rv_txt)  TYPE string.

    CLASS-METHODS kebab
      IMPORTING VALUE(iv_name) TYPE string
                iv_max         TYPE i
      RETURNING VALUE(rv_txt)  TYPE string.

    CLASS-METHODS typing
      IMPORTING VALUE(iv_typtype) TYPE string
                VALUE(iv_type)    TYPE string
                VALUE(iv_tableof) TYPE string
      RETURNING VALUE(rv_txt)     TYPE string.

    " text of an object from a text table, logon language -> EN -> any
    CLASS-METHODS text_of
      IMPORTING iv_table      TYPE csequence
                iv_keyfield   TYPE csequence
                iv_name       TYPE csequence
                iv_langfield  TYPE csequence
                iv_textfield  TYPE csequence
      RETURNING VALUE(rv_txt) TYPE string.

ENDCLASS.

CLASS lcl_util IMPLEMENTATION.

  METHOD class_constructor.
    gv_nl   = cl_abap_char_utilities=>newline.
    gv_maxr = 2000.
  ENDMETHOD.

  METHOD fv.
    FIELD-SYMBOLS <lv_any> TYPE any.
    CLEAR rv_val.
    ASSIGN COMPONENT iv_field OF STRUCTURE is_row TO <lv_any>.
    IF sy-subrc = 0.
      rv_val = to_text( <lv_any> ).
    ENDIF.
  ENDMETHOD.

  METHOD to_text.
    FIELD-SYMBOLS: <lv_date> TYPE d,
                   <lv_time> TYPE t.

    CLEAR rv_txt.
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( iv_val ).
    IF lo_type->kind <> cl_abap_typedescr=>kind_elem.
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

  METHOD oneline.
    rv_txt = iv_txt.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf          IN rv_txt WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline        IN rv_txt WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_txt WITH ` `.
    REPLACE ALL OCCURRENCES OF `|` IN rv_txt WITH `\|`.
    IF iv_max > 0 AND strlen( rv_txt ) > iv_max.
      rv_txt = |{ substring( val = rv_txt len = iv_max ) }... ({ strlen( rv_txt ) } chars)|.
    ENDIF.
  ENDMETHOD.

  METHOD quote.
    rv_txt = cl_abap_dyn_prg=>quote( CONV string( iv_val ) ).
  ENDMETHOD.

  METHOD like_escape.
    rv_txt = iv_val.
    REPLACE ALL OCCURRENCES OF `#` IN rv_txt WITH `##`.
    REPLACE ALL OCCURRENCES OF `_` IN rv_txt WITH `#_`.
    REPLACE ALL OCCURRENCES OF `%` IN rv_txt WITH `#%`.
  ENDMETHOD.

  METHOD pool_prefix.
    rv_txt = iv_cls.
    DATA(lv_len) = strlen( rv_txt ).
    IF lv_len < 30.
      rv_txt = rv_txt && repeat( val = `=` occ = 30 - lv_len ).
    ENDIF.
  ENDMETHOD.

  METHOD pad_pattern.
    DATA(lv_val) = CONV string( iv_val ).
    DATA(lv_len) = strlen( lv_val ).
    rv_txt = like_escape( lv_val ).
    IF lv_len < iv_len.
      rv_txt = rv_txt && repeat( val = ` ` occ = iv_len - lv_len ).
    ENDIF.
    rv_txt = rv_txt && `%`.
  ENDMETHOD.

  METHOD generic_select.
    " table / field missing on this release -> unbound, never a dump
    FIELD-SYMBOLS <lt_tab> TYPE STANDARD TABLE.
    DATA lv_tab TYPE tabname.

    lv_tab = to_upper( iv_table ).
    TRY.
        CREATE DATA rr_tab TYPE STANDARD TABLE OF (lv_tab).
        ASSIGN rr_tab->* TO <lt_tab>.
        IF iv_max > 0.
          SELECT * FROM (lv_tab) WHERE (iv_where) INTO TABLE @<lt_tab> UP TO @iv_max ROWS.
        ELSE.
          SELECT * FROM (lv_tab) WHERE (iv_where) INTO TABLE @<lt_tab>.
        ENDIF.
      CATCH cx_root.
        CLEAR rr_tab.
    ENDTRY.
  ENDMETHOD.

  METHOD select_by_field.
    FIELD-SYMBOLS <lt_tab> TYPE STANDARD TABLE.
    DATA lv_tab TYPE tabname.

    lv_tab = to_upper( iv_table ).
    DATA(lv_where) = |{ to_upper( iv_field ) } = @IV_VALUE|.
    TRY.
        CREATE DATA rr_tab TYPE STANDARD TABLE OF (lv_tab).
        ASSIGN rr_tab->* TO <lt_tab>.
        IF iv_ordered = abap_true.
          SELECT * FROM (lv_tab) WHERE (lv_where) ORDER BY PRIMARY KEY INTO TABLE @<lt_tab>.
        ELSEIF iv_max > 0.
          SELECT * FROM (lv_tab) WHERE (lv_where) INTO TABLE @<lt_tab> UP TO @iv_max ROWS.
        ELSE.
          SELECT * FROM (lv_tab) WHERE (lv_where) INTO TABLE @<lt_tab>.
        ENDIF.
      CATCH cx_root.
        CLEAR rr_tab.
    ENDTRY.
  ENDMETHOD.

  METHOD has_rows.
    FIELD-SYMBOLS <lt_tab> TYPE ANY TABLE.
    rv = abap_false.
    IF ir_tab IS BOUND.
      ASSIGN ir_tab->* TO <lt_tab>.
      rv = xsdbool( <lt_tab> IS NOT INITIAL ).
    ENDIF.
  ENDMETHOD.

  METHOD read_source.
    " READ REPORT needs a flat character field, never STRING
    DATA lv_prog TYPE progname.

    CLEAR: et_src, ev_ok.
    lv_prog = iv_prog.
    IF lv_prog IS INITIAL.
      RETURN.
    ENDIF.

    READ REPORT lv_prog INTO et_src STATE 'A'.
    IF sy-subrc <> 0.
      READ REPORT lv_prog INTO et_src.
    ENDIF.
    ev_ok = xsdbool( sy-subrc = 0 ).
    IF ev_ok = abap_false.
      CLEAR et_src.
    ENDIF.
  ENDMETHOD.

  METHOD safe_file.
    " /ABC/CL_X -> =ABC=CL_X ; anything not file-system safe -> _
    rv_txt = iv_name.
    REPLACE ALL OCCURRENCES OF `/` IN rv_txt WITH `=`.
    REPLACE ALL OCCURRENCES OF REGEX `[^A-Za-z0-9_=$.#-]` IN rv_txt WITH `_`.
    IF rv_txt IS INITIAL.
      rv_txt = `_`.
    ENDIF.
  ENDMETHOD.

  METHOD kebab.
    " folder / archive names: lowercase letters, digits, hyphens
    rv_txt = to_lower( iv_name ).
    REPLACE ALL OCCURRENCES OF REGEX `[^a-z0-9]+` IN rv_txt WITH `-`.
    REPLACE ALL OCCURRENCES OF REGEX `^-+|-+$` IN rv_txt WITH ``.
    IF strlen( rv_txt ) > iv_max.
      rv_txt = substring( val = rv_txt len = iv_max ).
      REPLACE ALL OCCURRENCES OF REGEX `-+$` IN rv_txt WITH ``.
    ENDIF.
    IF rv_txt IS INITIAL.
      rv_txt = `sap-package`.
    ENDIF.
  ENDMETHOD.

  METHOD typing.
    IF iv_type IS INITIAL AND ( iv_typtype = `0` OR iv_typtype = `1` OR iv_typtype IS INITIAL ).
      rv_txt = `(generic)`.
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
      rv_txt = COND string( WHEN iv_type IS NOT INITIAL THEN |TYPE { iv_type } | ) &&
               |[typing kind { iv_typtype } - see source section]|.
    ENDIF.
  ENDMETHOD.

  METHOD text_of.
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <ls_row> TYPE any.

    DATA(lv_key) = |{ iv_keyfield } = { quote( iv_name ) }|.
    DATA(lt_where) = VALUE ty_t_string(
      ( |{ lv_key } AND { iv_langfield } = { quote( CONV string( sy-langu ) ) }| )
      ( |{ lv_key } AND { iv_langfield } = 'E'| )
      ( lv_key ) ).

    LOOP AT lt_where INTO DATA(lv_where).
      DATA(lr_tab) = generic_select( iv_table = iv_table iv_where = lv_where iv_max = 1 ).
      IF has_rows( lr_tab ) = abap_true.
        ASSIGN lr_tab->* TO <lt_tab>.
        READ TABLE <lt_tab> ASSIGNING <ls_row> INDEX 1.
        rv_txt = fv( is_row = <ls_row> iv_field = iv_textfield ).
        IF rv_txt IS NOT INITIAL.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Markdown builder for one object
*&---------------------------------------------------------------------*
CLASS lcl_md DEFINITION FINAL.

  PUBLIC SECTION.
    DATA mt_line TYPE lcl_util=>ty_t_string READ-ONLY.

    METHODS add  IMPORTING VALUE(iv_text) TYPE string OPTIONAL.
    METHODS h1   IMPORTING VALUE(iv_text) TYPE string.
    METHODS h2   IMPORTING VALUE(iv_text) TYPE string.
    METHODS h3   IMPORTING VALUE(iv_text) TYPE string.

    " - **key:** value   (skipped when the value is empty)
    METHODS kv
      IMPORTING VALUE(iv_key) TYPE string
                VALUE(iv_val) TYPE string.

    METHODS code
      IMPORTING it_src          TYPE lcl_util=>ty_t_string
                VALUE(iv_lang)  TYPE string DEFAULT `abap`
                VALUE(iv_title) TYPE string OPTIONAL.

    METHODS code_string
      IMPORTING VALUE(iv_src)   TYPE string
                VALUE(iv_lang)  TYPE string DEFAULT `abap`
                VALUE(iv_title) TYPE string OPTIONAL.

    " every row as one line FIELD=value; ... (non-initial fields only),
    " long strings as code block, deep components recursively
    METHODS rows
      IMPORTING ir_tab          TYPE REF TO data
                VALUE(iv_title) TYPE string
                iv_always       TYPE abap_bool DEFAULT abap_false.

    " Markdown table (falls back to ROWS for very wide tables)
    METHODS table_md
      IMPORTING ir_tab          TYPE REF TO data
                VALUE(iv_title) TYPE string.

    " any data object (elementary / structure / table / reference)
    METHODS dump
      IMPORTING iv_data        TYPE any
                VALUE(iv_name) TYPE string
                iv_depth       TYPE i DEFAULT 0.

    METHODS count RETURNING VALUE(rv) TYPE i.

    " simple components of a structure as FIELD=value; ...
    METHODS inline
      IMPORTING is_row        TYPE any
      RETURNING VALUE(rv_txt) TYPE string.

  PRIVATE SECTION.
    METHODS emit_row
      IMPORTING is_row   TYPE any
                iv_pad   TYPE string
                iv_depth TYPE i.

ENDCLASS.

CLASS lcl_md IMPLEMENTATION.

  METHOD add.
    APPEND iv_text TO mt_line.
  ENDMETHOD.

  METHOD h1.
    APPEND |# { iv_text }| TO mt_line.
    APPEND `` TO mt_line.
  ENDMETHOD.

  METHOD h2.
    APPEND `` TO mt_line.
    APPEND |## { iv_text }| TO mt_line.
    APPEND `` TO mt_line.
  ENDMETHOD.

  METHOD h3.
    APPEND `` TO mt_line.
    APPEND |### { iv_text }| TO mt_line.
    APPEND `` TO mt_line.
  ENDMETHOD.

  METHOD kv.
    IF iv_val IS NOT INITIAL.
      APPEND |- **{ iv_key }:** { lcl_util=>oneline( iv_txt = iv_val iv_max = 1000 ) }| TO mt_line.
    ENDIF.
  ENDMETHOD.

  METHOD code.
    IF iv_title IS NOT INITIAL.
      h3( iv_title ).
    ENDIF.
    APPEND |```{ iv_lang }| TO mt_line.
    LOOP AT it_src INTO DATA(lv_line).
      " a source line starting with ``` would close the fence
      IF strlen( lv_line ) >= 3 AND substring( val = lv_line len = 3 ) = '```'.
        lv_line = ` ` && lv_line.
      ENDIF.
      APPEND lv_line TO mt_line.
    ENDLOOP.
    APPEND `` && '```' TO mt_line.
  ENDMETHOD.

  METHOD code_string.
    DATA lt_src TYPE lcl_util=>ty_t_string.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN iv_src WITH lcl_util=>gv_nl.
    SPLIT iv_src AT lcl_util=>gv_nl INTO TABLE lt_src.
    code( it_src = lt_src iv_lang = iv_lang iv_title = iv_title ).
  ENDMETHOD.

  METHOD rows.
    FIELD-SYMBOLS: <lt_tab> TYPE ANY TABLE,
                   <ls_row> TYPE any.

    IF ir_tab IS NOT BOUND.
      IF iv_always = abap_true.
        h3( iv_title ).
        add( `(not available on this system)` ).
      ENDIF.
      RETURN.
    ENDIF.

    ASSIGN ir_tab->* TO <lt_tab>.
    IF <lt_tab> IS INITIAL.
      IF iv_always = abap_true.
        h3( iv_title ).
        add( `(no entries)` ).
      ENDIF.
      RETURN.
    ENDIF.

    h3( |{ iv_title } ({ lines( <lt_tab> ) } rows)| ).
    DATA(lv_n) = 0.
    LOOP AT <lt_tab> ASSIGNING <ls_row>.
      lv_n = lv_n + 1.
      IF lv_n > lcl_util=>gv_maxr.
        add( |- ... { lines( <lt_tab> ) - lcl_util=>gv_maxr } more rows not shown (max rows option)| ).
        EXIT.
      ENDIF.
      emit_row( is_row = <ls_row> iv_pad = `` iv_depth = 0 ).
    ENDLOOP.
  ENDMETHOD.

  METHOD inline.
    " simple components of a structure as FIELD=value; ...
    FIELD-SYMBOLS <lv_val> TYPE any.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.

    TRY.
        lo_struct ?= cl_abap_typedescr=>describe_by_data( is_row ).
      CATCH cx_sy_move_cast_error.
        rv_txt = lcl_util=>oneline( lcl_util=>to_text( is_row ) ).
        RETURN.
    ENDTRY.

    LOOP AT lo_struct->components INTO DATA(ls_comp).
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE is_row TO <lv_val>.
      IF sy-subrc <> 0 OR <lv_val> IS INITIAL.
        CONTINUE.
      ENDIF.
      IF cl_abap_typedescr=>describe_by_data( <lv_val> )->kind <> cl_abap_typedescr=>kind_elem.
        CONTINUE.
      ENDIF.
      rv_txt = |{ rv_txt }{ ls_comp-name }={ lcl_util=>oneline( iv_txt = lcl_util=>to_text( <lv_val> ) iv_max = 200 ) }; |.
    ENDLOOP.
  ENDMETHOD.

  METHOD emit_row.
    FIELD-SYMBOLS <lv_val> TYPE any.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    DATA lt_long   TYPE lcl_util=>ty_t_string.
    DATA lt_deep   TYPE lcl_util=>ty_t_string.
    DATA lv_line   TYPE string.

    TRY.
        lo_struct ?= cl_abap_typedescr=>describe_by_data( is_row ).
      CATCH cx_sy_move_cast_error.
        add( |{ iv_pad }- { lcl_util=>oneline( lcl_util=>to_text( is_row ) ) }| ).
        RETURN.
    ENDTRY.

    LOOP AT lo_struct->components INTO DATA(ls_comp).
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE is_row TO <lv_val>.
      IF sy-subrc <> 0 OR <lv_val> IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(lo_type) = cl_abap_typedescr=>describe_by_data( <lv_val> ).
      IF lo_type->kind <> cl_abap_typedescr=>kind_elem.
        APPEND CONV string( ls_comp-name ) TO lt_deep.
        CONTINUE.
      ENDIF.
      DATA(lv_txt) = lcl_util=>to_text( <lv_val> ).
      IF ( lo_type->type_kind = cl_abap_typedescr=>typekind_string AND
           ( strlen( lv_txt ) > 200 OR lv_txt CS lcl_util=>gv_nl ) ).
        APPEND CONV string( ls_comp-name ) TO lt_long.
        CONTINUE.
      ENDIF.
      lv_line = |{ lv_line }{ ls_comp-name }={ lcl_util=>oneline( iv_txt = lv_txt iv_max = 300 ) }; |.
    ENDLOOP.

    add( |{ iv_pad }- { lv_line }| ).

    LOOP AT lt_long INTO DATA(lv_name).
      ASSIGN COMPONENT lv_name OF STRUCTURE is_row TO <lv_val>.
      add( |{ iv_pad }  { lv_name }:| ).
      code_string( iv_src = lcl_util=>to_text( <lv_val> ) iv_lang = `text` ).
    ENDLOOP.

    LOOP AT lt_deep INTO lv_name.
      ASSIGN COMPONENT lv_name OF STRUCTURE is_row TO <lv_val>.
      dump( iv_data = <lv_val> iv_name = lv_name iv_depth = iv_depth + 1 ).
    ENDLOOP.
  ENDMETHOD.

  METHOD table_md.
    FIELD-SYMBOLS: <lt_tab> TYPE ANY TABLE,
                   <ls_row> TYPE any,
                   <lv_val> TYPE any.
    DATA lo_table  TYPE REF TO cl_abap_tabledescr.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    DATA lt_cols   TYPE lcl_util=>ty_t_string.

    IF ir_tab IS NOT BOUND.
      RETURN.
    ENDIF.
    ASSIGN ir_tab->* TO <lt_tab>.
    IF <lt_tab> IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        lo_table  ?= cl_abap_typedescr=>describe_by_data( <lt_tab> ).
        lo_struct ?= lo_table->get_table_line_type( ).
      CATCH cx_sy_move_cast_error.
        rows( ir_tab = ir_tab iv_title = iv_title ).
        RETURN.
    ENDTRY.

    LOOP AT lo_struct->components INTO DATA(ls_comp)
         WHERE type_kind <> cl_abap_typedescr=>typekind_table
           AND type_kind <> cl_abap_typedescr=>typekind_struct1
           AND type_kind <> cl_abap_typedescr=>typekind_struct2.
      IF ls_comp-name = 'MANDT' OR ls_comp-name = 'CLIENT'.
        CONTINUE.
      ENDIF.
      APPEND CONV string( ls_comp-name ) TO lt_cols.
    ENDLOOP.

    IF lines( lt_cols ) > 25 OR lt_cols IS INITIAL.
      rows( ir_tab = ir_tab iv_title = iv_title ).
      RETURN.
    ENDIF.

    h3( |{ iv_title } ({ lines( <lt_tab> ) } rows)| ).

    DATA(lv_head) = `|`.
    DATA(lv_sep)  = `|`.
    LOOP AT lt_cols INTO DATA(lv_col).
      lv_head = |{ lv_head } { lv_col } \||.
      lv_sep  = lv_sep && ` --- |`.
    ENDLOOP.
    add( lv_head ).
    add( lv_sep ).

    DATA(lv_n) = 0.
    LOOP AT <lt_tab> ASSIGNING <ls_row>.
      lv_n = lv_n + 1.
      IF lv_n > lcl_util=>gv_maxr.
        add( `` ).
        add( |... { lines( <lt_tab> ) - lcl_util=>gv_maxr } more rows not shown (max rows option)| ).
        EXIT.
      ENDIF.
      DATA(lv_row) = `|`.
      LOOP AT lt_cols INTO lv_col.
        ASSIGN COMPONENT lv_col OF STRUCTURE <ls_row> TO <lv_val>.
        DATA(lv_cell) = COND string( WHEN sy-subrc = 0 THEN lcl_util=>oneline( iv_txt = lcl_util=>to_text( <lv_val> ) iv_max = 120 ) ).
        lv_row = |{ lv_row } { lv_cell } \||.
      ENDLOOP.
      add( lv_row ).
    ENDLOOP.
  ENDMETHOD.

  METHOD dump.
    FIELD-SYMBOLS: <lt_tab> TYPE ANY TABLE,
                   <ls_row> TYPE any,
                   <lv_val> TYPE any,
                   <lv_ref> TYPE any.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.

    IF iv_depth > 8.
      RETURN.
    ENDIF.

    DATA(lv_pad)  = repeat( val = `  ` occ = iv_depth ).
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( iv_data ).

    CASE lo_type->kind.

      WHEN cl_abap_typedescr=>kind_elem.
        DATA(lv_txt) = lcl_util=>to_text( iv_data ).
        IF strlen( lv_txt ) > 300 OR lv_txt CS lcl_util=>gv_nl.
          add( |{ lv_pad }- { iv_name }:| ).
          code_string( iv_src = lv_txt iv_lang = `text` ).
        ELSE.
          add( |{ lv_pad }- { iv_name } = { lcl_util=>oneline( lv_txt ) }| ).
        ENDIF.

      WHEN cl_abap_typedescr=>kind_struct.
        add( |{ lv_pad }- { iv_name }:| ).
        emit_row( is_row = iv_data iv_pad = lv_pad && `  ` iv_depth = iv_depth ).

      WHEN cl_abap_typedescr=>kind_table.
        ASSIGN iv_data TO <lt_tab>.
        add( |{ lv_pad }- { iv_name } ({ lines( <lt_tab> ) } rows):| ).
        DATA(lv_n) = 0.
        LOOP AT <lt_tab> ASSIGNING <ls_row>.
          lv_n = lv_n + 1.
          IF lv_n > lcl_util=>gv_maxr.
            add( |{ lv_pad }  - ... more rows not shown| ).
            EXIT.
          ENDIF.
          emit_row( is_row = <ls_row> iv_pad = lv_pad && `  ` iv_depth = iv_depth ).
        ENDLOOP.

      WHEN cl_abap_typedescr=>kind_ref.
        IF iv_data IS INITIAL.
          RETURN.
        ENDIF.
        IF lo_type->type_kind = cl_abap_typedescr=>typekind_dref.
          ASSIGN iv_data TO <lv_ref>.
          TRY.
              DATA lr_data TYPE REF TO data.
              lr_data = <lv_ref>.
              ASSIGN lr_data->* TO <lv_val>.
              IF sy-subrc = 0.
                dump( iv_data = <lv_val> iv_name = iv_name iv_depth = iv_depth ).
              ENDIF.
            CATCH cx_root.
          ENDTRY.
        ELSE.
          TRY.
              DATA lo_obj TYPE REF TO object.
              ASSIGN iv_data TO <lv_ref>.
              lo_obj = <lv_ref>.
              add( |{ lv_pad }- { iv_name } = (object { cl_abap_typedescr=>describe_by_object_ref( lo_obj )->get_relative_name( ) })| ).
            CATCH cx_root.
          ENDTRY.
        ENDIF.

    ENDCASE.
  ENDMETHOD.

  METHOD count.
    rv = lines( mt_line ).
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Writer: splits documents into files, files into ZIP volumes, writes
*& SKILL.md / index files / plugin manifests, saves the ZIPs
*&---------------------------------------------------------------------*
CLASS lcl_writer DEFINITION FINAL.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_s_idx,
             otype  TYPE string,
             name  TYPE string,
             descr TYPE string,
             lines TYPE i,
             vol   TYPE string,
             file  TYPE string,
           END OF ty_s_idx,
           ty_t_idx TYPE STANDARD TABLE OF ty_s_idx WITH EMPTY KEY.

    TYPES: BEGIN OF ty_s_file,
             path    TYPE string,
             content TYPE string,
           END OF ty_s_file,
           ty_t_file TYPE STANDARD TABLE OF ty_s_file WITH EMPTY KEY.

    TYPES: BEGIN OF ty_s_tt,
             otype TYPE string,
             text TYPE string,
           END OF ty_s_tt,
           ty_t_tt TYPE SORTED TABLE OF ty_s_tt WITH UNIQUE KEY otype.

    DATA mt_saved      TYPE lcl_util=>ty_t_string READ-ONLY.
    DATA mt_index      TYPE ty_t_idx READ-ONLY.
    DATA mv_lines      TYPE i READ-ONLY.
    DATA mv_files      TYPE i READ-ONLY.
    DATA mv_bytes_all  TYPE int8 READ-ONLY.

    METHODS constructor
      IMPORTING is_opt         TYPE ty_s_opt
                VALUE(iv_base) TYPE string
                VALUE(iv_title) TYPE string.

    METHODS set_type_texts IMPORTING it_tt TYPE ty_t_tt.

    METHODS add_common
      IMPORTING VALUE(iv_path)    TYPE string
                VALUE(iv_content) TYPE string.

    METHODS add_doc
      IMPORTING VALUE(iv_type)  TYPE string
                VALUE(iv_name)  TYPE string
                VALUE(iv_descr) TYPE string
                io_md           TYPE REF TO lcl_md.

    METHODS doc_path
      IMPORTING VALUE(iv_type) TYPE string
                VALUE(iv_name) TYPE string
      RETURNING VALUE(rv_path) TYPE string.

    METHODS finish
      IMPORTING it_final TYPE ty_t_file.

    METHODS type_text
      IMPORTING VALUE(iv_type) TYPE string
      RETURNING VALUE(rv_txt)  TYPE string.

  PRIVATE SECTION.
    DATA ms_opt    TYPE ty_s_opt.
    DATA mv_base   TYPE string.
    DATA mv_title  TYPE string.
    DATA mv_maxb   TYPE i.
    DATA mo_zip    TYPE REF TO cl_abap_zip.
    DATA mv_vol    TYPE i.
    DATA mv_bytes  TYPE i.
    DATA mv_open   TYPE abap_bool.
    DATA mv_skill  TYPE string.
    DATA mt_vidx   TYPE ty_t_idx.
    DATA mt_common TYPE ty_t_file.
    DATA mt_tt     TYPE ty_t_tt.
    DATA mt_vols   TYPE ty_t_idx.        " volume name + object count
    " many upload targets accept at most 200 files per ZIP: in docu mode
    " several objects are bundled into reference/part-NNNN.md files and
    " a volume is closed before it exceeds MV_MAXF files
    DATA mv_maxf        TYPE i.
    DATA mv_files_vol   TYPE i.
    DATA mv_bundles_vol TYPE i.
    DATA mv_bundle_no   TYPE i.
    DATA mv_bundle_file TYPE string.
    DATA mt_bundle      TYPE lcl_util=>ty_t_string.

    METHODS start_bundle.
    METHODS flush_bundle.

    METHODS vol_name
      IMPORTING iv_vol         TYPE i
      RETURNING VALUE(rv_name) TYPE string.

    METHODS open_volume
      IMPORTING VALUE(iv_skill) TYPE string.

    METHODS close_volume
      IMPORTING it_extra TYPE ty_t_file
                VALUE(iv_kind) TYPE string.

    METHODS put
      IMPORTING VALUE(iv_rel)     TYPE string
                VALUE(iv_content) TYPE string
                iv_force          TYPE abap_bool DEFAULT abap_false
                iv_absolute       TYPE abap_bool DEFAULT abap_false.

    METHODS skill_md
      IMPORTING it_idx         TYPE ty_t_idx
                it_files       TYPE ty_t_file
                VALUE(iv_kind) TYPE string
      RETURNING VALUE(rv_md)   TYPE string.

    METHODS index_files
      IMPORTING it_idx          TYPE ty_t_idx
                VALUE(iv_name)  TYPE string
      RETURNING VALUE(rt_files) TYPE ty_t_file.

    METHODS plugin_manifests.

    METHODS save
      IMPORTING iv_zip         TYPE xstring
                VALUE(iv_file) TYPE string.

ENDCLASS.

CLASS lcl_writer IMPLEMENTATION.

*----------------------------------------------------------------------*
  METHOD constructor.
    ms_opt   = is_opt.
    mv_base  = iv_base.
    mv_title = iv_title.
    mv_maxb  = COND i( WHEN is_opt-volmb > 0 THEN is_opt-volmb ELSE 20 ) * 1024 * 1024.
    " file limit only for documentation ZIPs (plugin layout has none)
    mv_maxf  = COND i( WHEN is_opt-plugin = abap_true OR is_opt-maxf <= 0 THEN 0
                       WHEN is_opt-maxf < 20 THEN 20
                       ELSE is_opt-maxf ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD set_type_texts.
    mt_tt = it_tt.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD type_text.
    READ TABLE mt_tt INTO DATA(ls_tt) WITH TABLE KEY otype = iv_type.
    IF sy-subrc = 0.
      rv_txt = ls_tt-text.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD add_common.
    APPEND VALUE #( path = iv_path content = iv_content ) TO mt_common.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD vol_name.
    rv_name = |{ mv_base }-vol-{ iv_vol WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD doc_path.
    IF mv_maxf > 0.
      " bundled: the index gives file and line of every object
      rv_path = |{ iv_type } { iv_name } - see INDEX|.
    ELSE.
      rv_path = |reference/{ lcl_util=>safe_file( iv_type ) }/{ lcl_util=>safe_file( iv_name ) }.md|.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD open_volume.
    mv_skill        = iv_skill.
    mv_bytes        = 0.
    mv_files_vol    = 0.
    mv_bundles_vol  = 0.
    mv_open         = abap_true.
    CLEAR mt_vidx.
    IF ms_opt-test = abap_false.
      mo_zip = NEW cl_abap_zip( ).
    ENDIF.

    IF ms_opt-plugin = abap_true.
      plugin_manifests( ).
    ENDIF.

    LOOP AT mt_common INTO DATA(ls_file).
      put( iv_rel = ls_file-path iv_content = ls_file-content iv_force = abap_true ).
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD plugin_manifests.
    " Only written for the optional plugin-layout output. The folder
    " name below ('.claude-plugin') is the fixed manifest path that the
    " plugin loader expects - it must stay exactly as is or the plugin
    " ZIP will not be recognised. The documentation ZIP (the default
    " output) does not contain it.
    DATA(lv_desc) = |Read-only extract of SAP package { mv_title } (system { sy-sysid })|.
    REPLACE ALL OCCURRENCES OF `"` IN lv_desc WITH `'`.

    DATA(lv_market) =
      |\{| && lcl_util=>gv_nl &&
      |  "name": "{ mv_base }-marketplace",| && lcl_util=>gv_nl &&
      |  "owner": \{ "name": "{ to_lower( sy-uname ) }" \},| && lcl_util=>gv_nl &&
      |  "plugins": [| && lcl_util=>gv_nl &&
      |    \{| && lcl_util=>gv_nl &&
      |      "name": "{ mv_base }",| && lcl_util=>gv_nl &&
      |      "source": "./plugins/{ mv_base }",| && lcl_util=>gv_nl &&
      |      "description": "{ lv_desc }"| && lcl_util=>gv_nl &&
      |    \}| && lcl_util=>gv_nl &&
      |  ]| && lcl_util=>gv_nl &&
      |\}| && lcl_util=>gv_nl.

    DATA(lv_plugin) =
      |\{| && lcl_util=>gv_nl &&
      |  "name": "{ mv_base }",| && lcl_util=>gv_nl &&
      |  "description": "{ lv_desc }",| && lcl_util=>gv_nl &&
      |  "version": "1.0.0"| && lcl_util=>gv_nl &&
      |\}| && lcl_util=>gv_nl.

    put( iv_rel      = |{ mv_base }-marketplace/.claude-plugin/marketplace.json|
         iv_content  = lv_market
         iv_force    = abap_true
         iv_absolute = abap_true ).
    put( iv_rel      = |{ mv_base }-marketplace/plugins/{ mv_base }/.claude-plugin/plugin.json|
         iv_content  = lv_plugin
         iv_force    = abap_true
         iv_absolute = abap_true ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD put.
    DATA lv_path TYPE string.

    IF iv_force = abap_false.
      DATA(lv_size) = strlen( iv_content ).
      IF mv_open = abap_true AND mt_vidx IS NOT INITIAL AND mv_bytes + lv_size > mv_maxb.
        close_volume( it_extra = VALUE #( ) iv_kind = `VOL` ).
      ENDIF.
      IF mv_open = abap_false.
        mv_vol = mv_vol + 1.
        open_volume( vol_name( mv_vol ) ).
      ENDIF.
    ENDIF.

    IF iv_absolute = abap_true.
      lv_path = iv_rel.
    ELSEIF ms_opt-plugin = abap_true.
      lv_path = |{ mv_base }-marketplace/plugins/{ mv_base }/skills/{ mv_skill }/{ iv_rel }|.
    ELSE.
      lv_path = |{ mv_skill }/{ iv_rel }|.
    ENDIF.

    DATA(lv_x) = cl_abap_codepage=>convert_to( source = iv_content ).
    mv_bytes     = mv_bytes + xstrlen( lv_x ).
    mv_bytes_all = mv_bytes_all + xstrlen( lv_x ).
    mv_files     = mv_files + 1.
    mv_files_vol = mv_files_vol + 1.

    IF ms_opt-test = abap_false.
      mo_zip->add( name = lv_path content = lv_x ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD add_doc.
    DATA lt_part  TYPE lcl_util=>ty_t_string.
    DATA lv_fence TYPE string.
    DATA lv_last  TYPE string.

    DATA(lv_maxl)   = COND i( WHEN ms_opt-maxl >= 200 THEN ms_opt-maxl ELSE 1800 ).
    DATA(lv_total)  = io_md->count( ).
    DATA(lv_bundle) = xsdbool( mv_maxf > 0 ).
    DATA(lv_parts)  = ( lv_total + lv_maxl - 1 ) DIV lv_maxl.
    IF lv_parts < 1.
      lv_parts = 1.
    ENDIF.

    DATA(lv_base) = |reference/{ lcl_util=>safe_file( iv_type ) }/{ lcl_util=>safe_file( iv_name ) }|.

    DATA(ls_idx) = VALUE ty_s_idx( otype  = iv_type
                                   name  = iv_name
                                   descr = lcl_util=>oneline( iv_txt = iv_descr iv_max = 120 )
                                   lines = lv_total ).

    " ---- skill mode: small objects share a bundle file ---------------------
    IF lv_bundle = abap_true AND lv_parts = 1.
      IF mt_bundle IS NOT INITIAL AND lines( mt_bundle ) + lv_total + 3 > lv_maxl.
        flush_bundle( ).
      ENDIF.
      IF mt_bundle IS INITIAL.
        start_bundle( ).
      ELSE.
        APPEND `` TO mt_bundle.
        APPEND `---` TO mt_bundle.
        APPEND `` TO mt_bundle.
      ENDIF.
      DATA(lv_start) = lines( mt_bundle ) + 1.
      APPEND LINES OF io_md->mt_line TO mt_bundle.

      ls_idx-vol  = mv_skill.
      ls_idx-file = |{ mv_bundle_file } line { lv_start }|.
      APPEND ls_idx TO mt_vidx.
      APPEND ls_idx TO mt_index.
      mv_lines = mv_lines + lv_total.
      RETURN.
    ENDIF.

    IF lv_bundle = abap_true.
      flush_bundle( ).                       " big object: own files
    ENDIF.

    DATA(lv_part) = 0.
    WHILE lv_part < lv_parts.
      lv_part = lv_part + 1.

      DATA(lv_from) = ( lv_part - 1 ) * lv_maxl + 1.
      DATA(lv_to)   = lv_part * lv_maxl.
      IF lv_to > lv_total.
        lv_to = lv_total.
      ENDIF.

      " file of this part and of the next part
      DATA(lv_rel) = COND string(
        WHEN lv_bundle = abap_true THEN |reference/part-{ mv_bundle_no + 1 WIDTH = 4 ALIGN = RIGHT PAD = '0' }.md|
        WHEN lv_parts = 1          THEN |{ lv_base }.md|
        ELSE |{ lv_base }_part-{ lv_part WIDTH = 3 ALIGN = RIGHT PAD = '0' }.md| ).
      DATA(lv_next) = COND string(
        WHEN lv_bundle = abap_true THEN |reference/part-{ mv_bundle_no + 2 WIDTH = 4 ALIGN = RIGHT PAD = '0' }.md|
        ELSE |{ lv_base }_part-{ lv_part + 1 WIDTH = 3 ALIGN = RIGHT PAD = '0' }.md| ).

      CLEAR lt_part.
      IF lv_part > 1.
        APPEND |# { iv_type } { iv_name } - part { lv_part } of { lv_parts }| TO lt_part.
        APPEND `` TO lt_part.
        IF lv_fence IS NOT INITIAL.
          APPEND lv_fence TO lt_part.        " reopen the code block
        ENDIF.
      ENDIF.

      LOOP AT io_md->mt_line INTO DATA(lv_line) FROM lv_from TO lv_to.
        APPEND lv_line TO lt_part.
        IF strlen( lv_line ) >= 3 AND substring( val = lv_line len = 3 ) = '```'.
          lv_fence = COND #( WHEN lv_fence IS INITIAL THEN lv_line ELSE `` ).
        ENDIF.
      ENDLOOP.

      IF lv_part < lv_parts.
        IF lv_fence IS NOT INITIAL.
          APPEND `` && '```' TO lt_part.     " close, reopened in next part
        ENDIF.
        APPEND `` TO lt_part.
        APPEND |_Continued in `{ lv_next }`{ COND string( WHEN lv_bundle = abap_true
                                                          THEN ` (possibly in the next volume - see the index)` ) }_| TO lt_part.
      ENDIF.

      IF lv_bundle = abap_true.
        start_bundle( ).
        mt_bundle = lt_part.
        flush_bundle( ).
      ELSE.
        put( iv_rel = lv_rel iv_content = concat_lines_of( table = lt_part sep = lcl_util=>gv_nl ) ).
      ENDIF.

      " index entry for every volume that holds a part of the object
      IF mv_skill <> lv_last.
        lv_last = mv_skill.
        DATA(ls_vidx) = ls_idx.
        ls_vidx-vol  = mv_skill.
        ls_vidx-file = COND #( WHEN lv_parts = 1 THEN lv_rel
                               ELSE |{ lv_rel } (part { lv_part } of { lv_parts })| ).
        APPEND ls_vidx TO mt_vidx.
        ls_idx-vol  = COND #( WHEN ls_idx-vol IS INITIAL THEN mv_skill ELSE |{ ls_idx-vol }, { mv_skill }| ).
        IF ls_idx-file IS INITIAL.
          ls_idx-file = COND #( WHEN lv_parts = 1 THEN lv_rel ELSE |{ lv_rel } (+{ lv_parts - 1 } parts)| ).
        ENDIF.
      ENDIF.
    ENDWHILE.

    APPEND ls_idx TO mt_index.
    mv_lines = mv_lines + lv_total.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD start_bundle.
    " a new bundle file; close the volume first when it would exceed the
    " file limit (room is kept for SKILL.md, index and common files)
    DATA(lv_maxl)    = COND i( WHEN ms_opt-maxl >= 200 THEN ms_opt-maxl ELSE 1800 ).
    DATA(lv_reserve) = 8 + ( lines( mt_vidx ) + lv_maxl ) DIV ( lv_maxl - 10 ).

    IF mv_open = abap_true AND mv_bundles_vol > 0 AND
       ( ( mv_maxf > 0 AND mv_files_vol + 1 + lv_reserve > mv_maxf ) OR mv_bytes >= mv_maxb ).
      close_volume( it_extra = VALUE #( ) iv_kind = `VOL` ).
    ENDIF.
    IF mv_open = abap_false.
      mv_vol = mv_vol + 1.
      open_volume( vol_name( mv_vol ) ).
    ENDIF.

    mv_bundle_no   = mv_bundle_no + 1.
    mv_bundles_vol = mv_bundles_vol + 1.
    mv_bundle_file = |reference/part-{ mv_bundle_no WIDTH = 4 ALIGN = RIGHT PAD = '0' }.md|.
    CLEAR mt_bundle.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD flush_bundle.
    IF mt_bundle IS INITIAL.
      RETURN.
    ENDIF.
    put( iv_rel     = mv_bundle_file
         iv_content = concat_lines_of( table = mt_bundle sep = lcl_util=>gv_nl )
         iv_force   = abap_true ).
    CLEAR mt_bundle.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD index_files.
    " INDEX.md, or INDEX_001.md, INDEX_002.md ... when it is too long
    DATA lt_lines TYPE lcl_util=>ty_t_string.

    DATA(lv_maxl) = COND i( WHEN ms_opt-maxl >= 200 THEN ms_opt-maxl ELSE 1800 ) - 10.
    DATA(lt_idx)  = it_idx.
    SORT lt_idx BY otype name.

    DATA(lv_count) = lines( lt_idx ).
    DATA(lv_parts) = ( lv_count + lv_maxl - 1 ) DIV lv_maxl.
    IF lv_parts < 1.
      lv_parts = 1.
    ENDIF.

    DATA(lv_part) = 0.
    WHILE lv_part < lv_parts.
      lv_part = lv_part + 1.
      CLEAR lt_lines.
      APPEND |# Object index{ COND string( WHEN lv_parts > 1 THEN | - part { lv_part } of { lv_parts }| ) }| TO lt_lines.
      APPEND `` TO lt_lines.
      APPEND `| Type | Object | Description | Lines | Volume (skill) | File |` TO lt_lines.
      APPEND `| --- | --- | --- | --- | --- | --- |` TO lt_lines.
      DATA(lv_from) = ( lv_part - 1 ) * lv_maxl + 1.
      DATA(lv_to)   = lv_part * lv_maxl.
      LOOP AT lt_idx INTO DATA(ls_idx) FROM lv_from TO lv_to.
        APPEND |\| { ls_idx-otype } \| { lcl_util=>oneline( ls_idx-name ) } \| { ls_idx-descr } \| | &&
               |{ ls_idx-lines } \| { ls_idx-vol } \| `{ ls_idx-file }` \|| TO lt_lines.
      ENDLOOP.
      APPEND VALUE #( path    = COND #( WHEN lv_parts = 1 THEN |reference/{ iv_name }.md|
                                        ELSE |reference/{ iv_name }_{ lv_part WIDTH = 3 ALIGN = RIGHT PAD = '0' }.md| )
                      content = concat_lines_of( table = lt_lines sep = lcl_util=>gv_nl ) ) TO rt_files.
    ENDWHILE.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD skill_md.
    TYPES: BEGIN OF ty_s_cnt,
             otype TYPE string,
             cnt  TYPE i,
           END OF ty_s_cnt.
    DATA lt_cnt   TYPE SORTED TABLE OF ty_s_cnt WITH UNIQUE KEY otype.
    DATA lt_lines TYPE lcl_util=>ty_t_string.
    DATA lv_examples TYPE string.

    LOOP AT it_idx INTO DATA(ls_idx).
      READ TABLE lt_cnt ASSIGNING FIELD-SYMBOL(<ls_cnt>) WITH TABLE KEY otype = ls_idx-otype.
      IF sy-subrc = 0.
        <ls_cnt>-cnt = <ls_cnt>-cnt + 1.
      ELSE.
        INSERT VALUE #( otype = ls_idx-otype cnt = 1 ) INTO TABLE lt_cnt.
      ENDIF.
    ENDLOOP.

    " example names for the description (helps a tool pick the volume)
    DATA(lv_ex) = 0.
    LOOP AT it_idx INTO ls_idx
         WHERE otype = `BOBF` OR otype = `CLAS` OR otype = `INTF` OR otype = `DDLS` OR otype = `PROG` OR otype = `FUGR`.
      lv_ex = lv_ex + 1.
      IF lv_ex > 25 OR strlen( lv_examples ) > 400.
        EXIT.
      ENDIF.
      lv_examples = COND #( WHEN lv_examples IS INITIAL THEN ls_idx-name ELSE |{ lv_examples }, { ls_idx-name }| ).
    ENDLOOP.

    DATA(lv_scope) = SWITCH string( iv_kind
                       WHEN `MASTER` THEN `master index of a multi-volume extract`
                       WHEN `SINGLE` THEN `complete extract`
                       ELSE |volume { mv_skill }| ).

    DATA(lv_desc) =
      |Read-only extract of SAP ABAP package { mv_title } (system { sy-sysid }, { sy-datum DATE = ISO }), | &&
      |{ lv_scope }. Contains complete source code, class and interface method signatures, function modules, | &&
      |DDIC tables, structures, data elements and domains, CDS and RAP sources, BOPF business objects with nodes, | &&
      |actions, determinations, validations, configuration values and implementing classes, customizing table | &&
      |contents, messages, transactions and framework objects. Use it when the user asks about these SAP objects| &&
      |{ COND string( WHEN lv_examples IS NOT INITIAL THEN |, for example { lv_examples }| ) }.|.
    REPLACE ALL OCCURRENCES OF `"` IN lv_desc WITH `'`.
    REPLACE ALL OCCURRENCES OF `<` IN lv_desc WITH `(`.
    REPLACE ALL OCCURRENCES OF `>` IN lv_desc WITH `)`.
    IF strlen( lv_desc ) > 1000.
      lv_desc = substring( val = lv_desc len = 996 ) && ` ...`.
    ENDIF.

    APPEND `---` TO lt_lines.
    APPEND |name: { mv_skill }| TO lt_lines.
    APPEND |description: "{ lv_desc }"| TO lt_lines.
    APPEND `---` TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND |# SAP package extract: { mv_title }| TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND |System { sy-sysid } client { sy-mandt }, extracted { sy-datum DATE = ISO } { sy-uzeit TIME = ISO } | &&
           |by { sy-uname }. This skill is the { lv_scope }.| TO lt_lines.
    APPEND `` TO lt_lines.

    IF iv_kind = `MASTER`.
      APPEND `## Volumes` TO lt_lines.
      APPEND `` TO lt_lines.
      APPEND `The extract was too large for one skill. Every volume below is a separate skill; ` &&
             `the object index of THIS skill tells you which volume (skill) holds which object.` TO lt_lines.
      APPEND `` TO lt_lines.
      LOOP AT mt_vols INTO DATA(ls_vol).
        APPEND |- `{ ls_vol-vol }` - { ls_vol-lines } objects| TO lt_lines.
      ENDLOOP.
      APPEND `` TO lt_lines.
    ENDIF.

    APPEND `## How to use this skill` TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND `1. Find the object in the index file(s) listed below: type, name, description, volume and file.` TO lt_lines.
    IF mv_maxf > 0.
      APPEND `2. Several objects share one file reference/part-NNNN.md. The index gives the file and the ` &&
             `line where the object starts; every object starts with a heading "# TYPE NAME" and ends ` &&
             `before the next "---" separator. Read the file from that line.` TO lt_lines.
      APPEND |   Objects longer than { ms_opt-maxl } lines continue in the following part file(s).| TO lt_lines.
      APPEND `3. To search across everything use grep on the reference folder, e.g. ` &&
             '`grep -n "^# CLAS ZCL_ORDER" reference/*.md`' && ` or ` &&
             '`grep -rn "ZCL_ORDER" reference/`' && `.` TO lt_lines.
    ELSE.
      APPEND |2. Open the file under `reference/`. Objects longer than { ms_opt-maxl } lines are split into | &&
             |`_part-NNN.md` files - read the parts in order.| TO lt_lines.
      APPEND `3. To search across everything use grep on the reference folder, e.g. ` &&
             '`grep -rn "ZCL_ORDER" reference/`' && `. Names with "/" are stored with "=" ` &&
             '(`/ABC/CL_X` -> `=ABC=CL_X.md`).' TO lt_lines.
    ENDIF.
    APPEND `4. Each object file has: header (package, author, description), metadata, signatures / ` &&
           `configuration, the complete source in fenced code blocks, documentation and used objects.` TO lt_lines.
    APPEND `5. Classes and interfaces: section "Declaration" lists every type, attribute, constant, event and ` &&
           `method with its full signature and SE24 description; section "Source" contains every include ` &&
           `(public / protected / private section, local types, macros, local and test classes, each method).` TO lt_lines.
    APPEND `6. BOPF business objects (reference/BOBF/): every /BOBF/ repository row of the BO key ` &&
           `(nodes, associations, actions, determinations, validations, queries, alternative keys, ...), ` &&
           `the runtime configuration from /BOBF/IF_FRW_CONFIGURATION and the implementing classes ` &&
           `(their full source is in the CLAS documents - also classes outside the package).` TO lt_lines.
    APPEND `6b. Objects OUTSIDE the package that the package uses (classes of BOPF / workflow / Gateway / ` &&
           `BAdI / BSP, BOR objects, DDIC types, incl. standard SAP) are extracted too; their header says why. ` &&
           `BSP / UI5 applications: type WAPA has one document per application file (controllers, views, ` &&
           `manifest, i18n ...). Workflows contain a Mermaid diagram of the steps.` TO lt_lines.
    APPEND `7. Customizing tables contain their table contents (configuration values) of client ` &&
           |{ sy-mandt }.| TO lt_lines.
    APPEND `8. Package hierarchy: reference/PACKAGES.md. Extraction problems: reference/ERRORS.md (index / ` &&
           `single volume). Statistics: reference/STATS.md.` TO lt_lines.
    APPEND `9. Answer only from these files, quote the file path, and say so when something is not in the ` &&
           `extract. If an object is missing here, it may be in another volume - check the skill ` &&
           |`{ mv_base }-index`.| TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `## Object types` TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND `| Type | Meaning | Objects |` TO lt_lines.
    APPEND `| --- | --- | --- |` TO lt_lines.
    LOOP AT lt_cnt INTO DATA(ls_cnt).
      APPEND |\| { ls_cnt-otype } \| { type_text( ls_cnt-otype ) } \| { ls_cnt-cnt } \|| TO lt_lines.
    ENDLOOP.
    APPEND `` TO lt_lines.

    APPEND `## Index files` TO lt_lines.
    APPEND `` TO lt_lines.
    LOOP AT it_files INTO DATA(ls_file).
      APPEND |- `{ ls_file-path }`| TO lt_lines.
    ENDLOOP.
    APPEND `- ` && '`reference/PACKAGES.md`' TO lt_lines.

    rv_md = concat_lines_of( table = lt_lines sep = lcl_util=>gv_nl ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD close_volume.
    IF mv_open = abap_false.
      RETURN.
    ENDIF.
    flush_bundle( ).

    LOOP AT it_extra INTO DATA(ls_file).
      put( iv_rel = ls_file-path iv_content = ls_file-content iv_force = abap_true ).
    ENDLOOP.

    DATA(lt_idx)   = COND ty_t_idx( WHEN iv_kind = `MASTER` THEN mt_index ELSE mt_vidx ).
    DATA(lt_files) = index_files( it_idx  = lt_idx
                                  iv_name = COND #( WHEN iv_kind = `MASTER` THEN `OBJECT_INDEX` ELSE `INDEX` ) ).
    LOOP AT lt_files INTO ls_file.
      put( iv_rel = ls_file-path iv_content = ls_file-content iv_force = abap_true ).
    ENDLOOP.

    put( iv_rel     = `SKILL.md`
         iv_content = skill_md( it_idx = lt_idx it_files = lt_files iv_kind = iv_kind )
         iv_force   = abap_true ).

    IF iv_kind <> `MASTER`.
      APPEND VALUE #( vol = mv_skill lines = lines( mt_vidx ) ) TO mt_vols.
    ENDIF.

    DATA(lv_file) = COND string( WHEN ms_opt-plugin = abap_true
                                 THEN |{ mv_skill }-plugin.zip|
                                 ELSE |{ mv_skill }.zip| ).
    IF ms_opt-test = abap_false.
      save( iv_zip = mo_zip->save( ) iv_file = lv_file ).
      FREE mo_zip.
    ELSE.
      APPEND |(test run - not written) { lv_file } ~{ mv_bytes DIV 1024 } KB uncompressed| TO mt_saved.
    ENDIF.

    mv_open = abap_false.
    CLEAR mt_vidx.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD finish.
    flush_bundle( ).
    IF mv_vol = 0.
      mv_vol = 1.
      open_volume( vol_name( 1 ) ).          " empty extract
    ENDIF.

    IF mv_vol = 1.
      " everything fitted into one volume: it gets the full picture
      close_volume( it_extra = it_final iv_kind = `SINGLE` ).
      RETURN.
    ENDIF.

    close_volume( it_extra = VALUE #( ) iv_kind = `VOL` ).

    " master index skill
    open_volume( |{ mv_base }-index| ).
    close_volume( it_extra = it_final iv_kind = `MASTER` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD save.
    DATA lv_dir  TYPE string.
    DATA lv_full TYPE string.

    lv_dir = ms_opt-dir.

    IF ms_opt-appl = abap_true.
      lv_full = |{ lv_dir }/{ iv_file }|.
      REPLACE ALL OCCURRENCES OF `//` IN lv_full WITH `/`.
      TRY.
          OPEN DATASET lv_full FOR OUTPUT IN BINARY MODE.
          IF sy-subrc <> 0.
            APPEND |FAILED (OPEN DATASET) { lv_full }| TO mt_saved.
            RETURN.
          ENDIF.
          TRANSFER iv_zip TO lv_full.
          CLOSE DATASET lv_full.
          APPEND lv_full TO mt_saved.
        CATCH cx_root INTO DATA(lx_file).
          APPEND |FAILED { lv_full }: { lx_file->get_text( ) }| TO mt_saved.
      ENDTRY.
      RETURN.
    ENDIF.

    TRY.
        IF lv_dir IS INITIAL.
          cl_gui_frontend_services=>get_desktop_directory(
            CHANGING   desktop_directory = lv_dir
            EXCEPTIONS OTHERS            = 1 ).
          cl_gui_cfw=>flush( ).
        ENDIF.
        IF lv_dir IS INITIAL.
          lv_dir = `C:\temp`.
        ENDIF.

        DATA(lv_sep) = COND string( WHEN lv_dir CS `/` THEN `/` ELSE `\` ).
        lv_full = |{ lv_dir }{ lv_sep }{ iv_file }|.

        DATA(lt_solix) = cl_bcs_convert=>xstring_to_solix( iv_xstring = iv_zip ).
        cl_gui_frontend_services=>gui_download(
          EXPORTING  bin_filesize = xstrlen( iv_zip )
                     filename     = lv_full
                     filetype     = 'BIN'
          CHANGING   data_tab     = lt_solix
          EXCEPTIONS OTHERS       = 1 ).
        IF sy-subrc = 0.
          APPEND lv_full TO mt_saved.
        ELSE.
          APPEND |FAILED (GUI_DOWNLOAD { sy-subrc }) { lv_full }| TO mt_saved.
        ENDIF.
      CATCH cx_root INTO DATA(lx_gui).
        APPEND |FAILED { iv_file }: { lx_gui->get_text( ) }| TO mt_saved.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Extractor
*&---------------------------------------------------------------------*
CLASS lcl_extractor DEFINITION FINAL.

  PUBLIC SECTION.
    METHODS constructor IMPORTING is_opt TYPE ty_s_opt.
    METHODS run.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_s_pack,
             devclass TYPE devclass,
             parent   TYPE devclass,
             level    TYPE i,
             descr    TYPE string,
             objects  TYPE i,
           END OF ty_s_pack,
           ty_t_pack TYPE STANDARD TABLE OF ty_s_pack WITH EMPTY KEY.

    TYPES: BEGIN OF ty_s_err,
             otype TYPE string,
             name TYPE string,
             area TYPE string,
             msg  TYPE string,
           END OF ty_s_err.

    TYPES: BEGIN OF ty_s_bo,
             name   TYPE string,
             bo_key TYPE /bobf/obm_bo_key,
             done   TYPE abap_bool,
           END OF ty_s_bo.

    TYPES: BEGIN OF ty_s_disc,
             dkey   TYPE string,
             tables TYPE lcl_util=>ty_t_string,
           END OF ty_s_disc.

    TYPES: BEGIN OF ty_s_probe,
             otype     TYPE string,
             found    TYPE abap_bool,
             ptable   TYPE string,
             keyfield TYPE string,
             srcfield TYPE string,
           END OF ty_s_probe.

    TYPES: BEGIN OF ty_s_spec,
             otype    TYPE string,
             pattern TYPE string,
             field   TYPE string,
           END OF ty_s_spec,
           ty_t_spec TYPE STANDARD TABLE OF ty_s_spec WITH EMPTY KEY.

    TYPES: BEGIN OF ty_s_comp,
             cmpname    TYPE seocmpname,
             cmptype    TYPE string,
             mtdtype    TYPE string,
             exposure   TYPE string,
             decl       TYPE string,
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
             descr      TYPE string,
           END OF ty_s_comp,
           ty_t_comp TYPE STANDARD TABLE OF ty_s_comp WITH EMPTY KEY.

    TYPES: BEGIN OF ty_s_sub,
             cmpname    TYPE seocmpname,
             sconame    TYPE seosconame,
             scotype    TYPE string,
             decl       TYPE string,
             pass       TYPE string,
             typtype    TYPE string,
             typename   TYPE string,
             tableof    TYPE string,
             isoptional TYPE string,
             defval     TYPE string,
             preferred  TYPE string,
             editorder  TYPE i,
             descr      TYPE string,
           END OF ty_s_sub,
           ty_t_sub TYPE STANDARD TABLE OF ty_s_sub WITH EMPTY KEY.

    DATA ms_opt     TYPE ty_s_opt.
    DATA mo_writer  TYPE REF TO lcl_writer.
    DATA mt_pack    TYPE ty_t_pack.
    DATA mt_tadir   TYPE STANDARD TABLE OF tadir WITH EMPTY KEY.
    DATA mt_err     TYPE STANDARD TABLE OF ty_s_err WITH EMPTY KEY.
    DATA mt_bo      TYPE STANDARD TABLE OF ty_s_bo WITH EMPTY KEY.
    DATA mt_disc    TYPE HASHED TABLE OF ty_s_disc WITH UNIQUE KEY dkey.
    DATA mt_probe   TYPE HASHED TABLE OF ty_s_probe WITH UNIQUE KEY otype.
    DATA mt_spec    TYPE ty_t_spec.
    TYPES: BEGIN OF ty_s_ext,
             otype  TYPE string,
             name   TYPE string,
             reason TYPE string,
             depth  TYPE i,
           END OF ty_s_ext.
    DATA mv_depth     TYPE i.             " reference depth of the current object
    DATA mv_ext_full  TYPE abap_bool.
    TYPES: BEGIN OF ty_s_reftab,
             tabname TYPE string,
             ref     TYPE REF TO data,
           END OF ty_s_reftab,
           ty_t_reftab TYPE STANDARD TABLE OF ty_s_reftab WITH EMPTY KEY.
    DATA mt_extq    TYPE STANDARD TABLE OF ty_s_ext WITH EMPTY KEY.
    DATA mt_extkey  TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    DATA mt_ns      TYPE lcl_util=>ty_t_string.
    DATA mt_inpack  TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    DATA mt_srctabs TYPE lcl_util=>ty_t_string.
    DATA mv_srctabs_read TYPE abap_bool.
    DATA mv_start   TYPE timestampl.

    " ---- framework ---------------------------------------------------
    METHODS collect_packages.
    METHODS collect_objects.
    METHODS type_texts.
    METHODS packages_md RETURNING VALUE(rv_md) TYPE string.
    METHODS errors_md   RETURNING VALUE(rv_md) TYPE string.
    METHODS stats_md    RETURNING VALUE(rv_md) TYPE string.
    METHODS write_list.

    METHODS err
      IMPORTING VALUE(iv_type) TYPE string
                VALUE(iv_name) TYPE string
                VALUE(iv_area) TYPE string
                VALUE(iv_msg)  TYPE string.

    METHODS extract_object
      IMPORTING is_tadir TYPE tadir.

    METHODS header
      IMPORTING is_tadir       TYPE tadir
                io_md          TYPE REF TO lcl_md
                VALUE(iv_descr) TYPE string.

    METHODS descr
      IMPORTING VALUE(iv_type) TYPE string
                VALUE(iv_name) TYPE string
      RETURNING VALUE(rv_txt)  TYPE string.

    " ---- object types ------------------------------------------------
    METHODS x_devc IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_prog IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_clas IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_fugr IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md is_tadir TYPE tadir.
    METHODS x_func
      IMPORTING VALUE(iv_fm)     TYPE string
                VALUE(iv_fugr)   TYPE string
                VALUE(iv_prefix) TYPE string
                is_tadir         TYPE tadir.
    METHODS x_tabl IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_view IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_dtel IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_doma IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_ttyp IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_shlp IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_type IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_msag IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_tran IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_sobj IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_wf   IMPORTING VALUE(iv_name) TYPE string VALUE(iv_type) TYPE string io_md TYPE REF TO lcl_md.
    METHODS x_enho IMPORTING VALUE(iv_name) TYPE string io_md TYPE REF TO lcl_md.

    METHODS x_bobf
      IMPORTING VALUE(iv_name) TYPE string
                iv_key         TYPE /bobf/obm_bo_key
                is_tadir       TYPE tadir.

    METHODS x_source_probe
      IMPORTING VALUE(iv_type) TYPE string
                VALUE(iv_name) TYPE string
                io_md          TYPE REF TO lcl_md
      RETURNING VALUE(rv_found) TYPE abap_bool.

    METHODS x_discovery
      IMPORTING VALUE(iv_type) TYPE string
                VALUE(iv_name) TYPE string
                io_md          TYPE REF TO lcl_md
      RETURNING VALUE(rv_found) TYPE abap_bool.

    " ---- building blocks ----------------------------------------------
    METHODS dump_tab
      IMPORTING io_md           TYPE REF TO lcl_md
                VALUE(iv_table) TYPE string
                VALUE(iv_where) TYPE string
                VALUE(iv_title) TYPE string OPTIONAL
                iv_as_table     TYPE abap_bool DEFAULT abap_false.

    METHODS discover
      IMPORTING VALUE(iv_pattern) TYPE string
                VALUE(iv_field)   TYPE string
      RETURNING VALUE(rt_tables)  TYPE lcl_util=>ty_t_string.

    METHODS source_block
      IMPORTING VALUE(iv_prog)  TYPE string
                VALUE(iv_title) TYPE string
                io_md           TYPE REF TO lcl_md
                iv_quiet        TYPE abap_bool DEFAULT abap_false.

    METHODS textpool
      IMPORTING VALUE(iv_prog) TYPE string
                io_md          TYPE REF TO lcl_md.

    METHODS dynpros
      IMPORTING VALUE(iv_prog) TYPE string
                io_md          TYPE REF TO lcl_md.

    METHODS docu
      IMPORTING VALUE(iv_name)    TYPE string
                VALUE(iv_pattern) TYPE string OPTIONAL
                io_md             TYPE REF TO lcl_md.

    METHODS xref
      IMPORTING VALUE(iv_include) TYPE string
                iv_like           TYPE abap_bool
                io_md             TYPE REF TO lcl_md.

    METHODS fugr_names
      IMPORTING VALUE(iv_fugr) TYPE string
      EXPORTING ev_main        TYPE string
                ev_prefix      TYPE string.

    METHODS class_declaration
      IMPORTING VALUE(iv_cls) TYPE seoclsname
                iv_isintf     TYPE abap_bool
                io_md         TYPE REF TO lcl_md.

    METHODS params_decl
      IMPORTING it_sub          TYPE ty_t_sub
                is_comp         TYPE ty_s_comp
                VALUE(iv_pad)   TYPE string
      CHANGING  ct_lines        TYPE lcl_util=>ty_t_string.

    METHODS bopf_collect.

    " ---- objects outside the package that the package uses -------------
    METHODS queue_ext
      IMPORTING VALUE(iv_type)   TYPE string
                VALUE(iv_name)   TYPE string
                VALUE(iv_reason) TYPE string.

    METHODS queue_refs
      IMPORTING it_names         TYPE lcl_util=>ty_t_string
                VALUE(iv_reason) TYPE string
                io_md            TYPE REF TO lcl_md OPTIONAL
                VALUE(iv_title)  TYPE string OPTIONAL.

    METHODS queue_ddic
      IMPORTING VALUE(iv_name)   TYPE string
                VALUE(iv_reason) TYPE string.

    " class / interface or DDIC type by name (where-used names such as
    " CL_X\ME:METHOD are reduced to the class)
    METHODS queue_name
      IMPORTING VALUE(iv_name)   TYPE string
                VALUE(iv_reason) TYPE string.

    METHODS allowed
      IMPORTING VALUE(iv_name) TYPE string
      RETURNING VALUE(rv)      TYPE abap_bool.

    METHODS is_customer
      IMPORTING VALUE(iv_name) TYPE string
      RETURNING VALUE(rv)      TYPE abap_bool.

    METHODS keep_latest
      IMPORTING ir_tab TYPE REF TO data.

    METHODS x_wapa
      IMPORTING VALUE(iv_name) TYPE string
                io_md          TYPE REF TO lcl_md
                is_tadir       TYPE tadir.

    METHODS x_wdyn
      IMPORTING VALUE(iv_name) TYPE string
                io_md          TYPE REF TO lcl_md.

    METHODS render_code_fields
      IMPORTING VALUE(iv_table) TYPE string
                VALUE(iv_where) TYPE string
                io_md           TYPE REF TO lcl_md.

    METHODS x_form
      IMPORTING VALUE(iv_name) TYPE string
                VALUE(iv_type) TYPE string
                io_md          TYPE REF TO lcl_md.

    METHODS wf_diagram
      IMPORTING it_tabs TYPE ty_t_reftab
                io_md   TYPE REF TO lcl_md.

    METHODS lang_of
      IMPORTING VALUE(iv_file) TYPE string
      RETURNING VALUE(rv)      TYPE string.

    METHODS scan_names
      IMPORTING iv_data   TYPE any
                iv_depth  TYPE i DEFAULT 0
      CHANGING  ct_names  TYPE lcl_util=>ty_t_string.

ENDCLASS.

CLASS lcl_extractor IMPLEMENTATION.

*----------------------------------------------------------------------*
  METHOD constructor.
    ms_opt = is_opt.
    lcl_util=>gv_maxr = COND #( WHEN is_opt-maxr > 0 THEN is_opt-maxr ELSE 2000 ).

    " Framework objects: every repository table matching PATTERN that
    " has FIELD is read with FIELD = object name. Patterns are LIKE
    " patterns with ESCAPE '#'.
    mt_spec = VALUE #(
      ( otype = `WDYN` pattern = `WDY%`       field = `COMPONENT_NAME` )
      ( otype = `WDYA` pattern = `WDY%`       field = `APPLICATION_NAME` )
      ( otype = `WDCC` pattern = `WDY%`       field = `CONFIG_ID` )
      ( otype = `WDCA` pattern = `WDY%`       field = `CONFIG_ID` )
      ( otype = `SOBJ` pattern = `SWOT%`      field = `LOBJTYPE` )
      ( otype = `SOBJ` pattern = `TOJ%`       field = `NAME` )
      ( otype = `IWPR` pattern = `/IWBEP/%`   field = `PROJECT` )
      ( otype = `IWPR` pattern = `/IWBEP/%`   field = `PROJECT_NAME` )
      ( otype = `IWMO` pattern = `/IWBEP/%`   field = `TECHNICAL_NAME` )
      ( otype = `IWSV` pattern = `/IWBEP/%`   field = `TECHNICAL_NAME` )
      ( otype = `IWSV` pattern = `/IWFND/%`   field = `SERVICE_NAME` )
      ( otype = `IWSG` pattern = `/IWFND/%`   field = `SRV_IDENTIFIER` )
      ( otype = `ENHO` pattern = `ENH%`       field = `ENHNAME` )
      ( otype = `ENHS` pattern = `ENH%`       field = `ENHSPOT` )
      ( otype = `ENHS` pattern = `BADI%`      field = `ENHSPOT` )
      ( otype = `ENHC` pattern = `ENH%`       field = `ENHCOMPOSITE` )
      ( otype = `ENSC` pattern = `ENH%`       field = `ENHSPOTCOMPOSITE` )
      ( otype = `SXSD` pattern = `SXS%`       field = `EXIT_NAME` )
      ( otype = `SXCI` pattern = `SXC%`       field = `IMP_NAME` )
      ( otype = `NROB` pattern = `NRIV`       field = `OBJECT` )
      ( otype = `NROB` pattern = `TNRO%`      field = `OBJECT` )
      ( otype = `SUSO` pattern = `TOBJ%`      field = `OBJCT` )
      ( otype = `SUSO` pattern = `TACTZ`      field = `BROBJ` )
      ( otype = `SUSO` pattern = `AUTHX`      field = `FIELDNAME` )
      ( otype = `PINF` pattern = `INTF%`      field = `INTF_NAME` )
      ( otype = `ACGR` pattern = `AGR#_%`     field = `AGR_NAME` )
      ( otype = `DDLS` pattern = `DDLDEP%`    field = `DDLNAME` )
      ( otype = `DDLS` pattern = `DDDDLSRC%T` field = `DDLNAME` )
      ( otype = `SICF` pattern = `ICFSERVICE` field = `ICF_NAME` )
      ( otype = `XSLT` pattern = `O2XSLT%`    field = `XSLTDESC` )
      ( otype = `SMIM` pattern = `SMIM%`      field = `LOIO_ID` )
      ( otype = `SHI3` pattern = `TTREE%`     field = `ID` )
      ( otype = `CUS0` pattern = `CUS_IMG%`   field = `ACTIVITY` )
      ( otype = `TOBJ` pattern = `OBJH`       field = `OBJECTNAME` )
      ( otype = `TOBJ` pattern = `OBJS`       field = `OBJECTNAME` )
      ( otype = `TOBJ` pattern = `OBJT`       field = `OBJECTNAME` )
      ( otype = `VCLS` pattern = `VCL%`       field = `VCLNAME` )
      ( otype = `FDT0` pattern = `FDT#_%`     field = `APPLICATION_ID` )
      ( otype = `SPRX` pattern = `SPROX%`     field = `OBJ_NAME` )
      ( otype = `UDMO` pattern = `DM%`        field = `DMOD` )
      ( otype = `UENO` pattern = `DM%`        field = `ENTID` )
      ( otype = `CMOD` pattern = `MOD%`       field = `NAME` )
      ( otype = `SMOD` pattern = `MOD%`       field = `NAME` )
      ( otype = `ENHO` pattern = `BADI%`      field = `ENHNAME` )
      ( otype = `SSFO` pattern = `STXF%`      field = `FORMNAME` )
      ( otype = `SFPF` pattern = `FP%`        field = `NAME` )
      ( otype = `SFPI` pattern = `FP%`        field = `NAME` )
      ( otype = `WAPA` pattern = `BSP%`       field = `APPLNAME` ) ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD run.

    GET TIME STAMP FIELD mv_start.

    collect_packages( ).
    IF mt_pack IS INITIAL.
      MESSAGE 'No package matches the selection' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    collect_objects( ).

    " skill base name from the root package(s) unless given
    DATA(lv_roots) = ``.
    LOOP AT mt_pack INTO DATA(ls_pack) WHERE level = 0.
      lv_roots = COND #( WHEN lv_roots IS INITIAL THEN CONV string( ls_pack-devclass )
                         ELSE |{ lv_roots }, { ls_pack-devclass }| ).
    ENDLOOP.
    DATA(lv_base) = COND string( WHEN ms_opt-sname IS NOT INITIAL THEN ms_opt-sname
                                 ELSE |sap-pkg-{ lv_roots }| ).
    lv_base = lcl_util=>kebab( iv_name = lv_base iv_max = 50 ).
    IF strlen( lv_roots ) > 200.
      lv_roots = substring( val = lv_roots len = 200 ) && ` ...`.
    ENDIF.

    mo_writer = NEW lcl_writer( is_opt = ms_opt iv_base = lv_base iv_title = lv_roots ).
    type_texts( ).
    mo_writer->add_common( iv_path = `reference/PACKAGES.md` iv_content = packages_md( ) ).

    IF ms_opt-bopf = abap_true.
      bopf_collect( ).
    ENDIF.

    " ---- every object ------------------------------------------------
    DATA(lv_total) = lines( mt_tadir ).
    DATA(lv_idx)   = 0.
    LOOP AT mt_tadir INTO DATA(ls_tadir).
      lv_idx = lv_idx + 1.
      IF lv_idx MOD 25 = 1 AND sy-batch = abap_false.
        DATA lv_text TYPE c LENGTH 120.
        DATA(lv_pct)  = lv_idx * 100 / lv_total.
        lv_text = |{ lv_idx }/{ lv_total } { ls_tadir-object } { ls_tadir-obj_name }|.
        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING
            percentage = lv_pct
            text       = lv_text.
      ENDIF.

      TRY.
          extract_object( ls_tadir ).
        CATCH cx_root INTO DATA(lx_obj).
          err( iv_type = CONV #( ls_tadir-object ) iv_name = CONV #( ls_tadir-obj_name )
               iv_area = `OBJECT` iv_msg = lx_obj->get_text( ) ).
      ENDTRY.
    ENDLOOP.

    " ---- BOPF business objects found only via constants interfaces ----
    LOOP AT mt_bo ASSIGNING FIELD-SYMBOL(<ls_bo>) WHERE done = abap_false.
      <ls_bo>-done = abap_true.
      TRY.
          x_bobf( iv_name = <ls_bo>-name iv_key = <ls_bo>-bo_key is_tadir = VALUE #( pgmid = 'R3TR' object = 'BOBF' ) ).
        CATCH cx_root INTO DATA(lx_bo).
          err( iv_type = `BOBF` iv_name = <ls_bo>-name iv_area = `BOPF` iv_msg = lx_bo->get_text( ) ).
      ENDTRY.
    ENDLOOP.

    " ---- objects outside the package that the package uses --------------
    " (BOPF / workflow / Gateway / BAdI / BSP classes, BOR objects,
    "  customer DDIC types). The queue can grow while it is processed.
    DATA ls_ext TYPE tadir.
    DATA(lv_ext_i) = 0.
    WHILE lv_ext_i < lines( mt_extq ).
      lv_ext_i = lv_ext_i + 1.
      READ TABLE mt_extq INTO DATA(ls_eq) INDEX lv_ext_i.
      mv_depth = ls_eq-depth.
      IF sy-batch = abap_false AND lv_ext_i MOD 25 = 1.
        DATA lv_etext TYPE c LENGTH 120.
        lv_etext = |Used objects outside the package: { lv_ext_i }/{ lines( mt_extq ) } { ls_eq-otype } { ls_eq-name }|.
        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING
            percentage = 99
            text       = lv_etext.
      ENDIF.
      CLEAR ls_ext.
      SELECT SINGLE * FROM tadir
        WHERE pgmid = 'R3TR' AND object = @ls_eq-otype AND obj_name = @ls_eq-name
        INTO @ls_ext.
      IF sy-subrc <> 0.
        ls_ext-pgmid    = 'R3TR'.
        ls_ext-object   = ls_eq-otype.
        ls_ext-obj_name = ls_eq-name.
      ENDIF.
      TRY.
          extract_object( ls_ext ).
        CATCH cx_root INTO DATA(lx_ext).
          err( iv_type = ls_eq-otype iv_name = ls_eq-name iv_area = `EXTERNAL` iv_msg = lx_ext->get_text( ) ).
      ENDTRY.
    ENDWHILE.

    mo_writer->finish( VALUE #( ( path = `reference/ERRORS.md` content = errors_md( ) )
                                ( path = `reference/STATS.md`  content = stats_md( ) ) ) ).

    write_list( ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD collect_packages.

    DATA lt_queue TYPE STANDARD TABLE OF ty_s_pack WITH EMPTY KEY.

    SELECT devclass, parentcl FROM tdevc
      WHERE devclass IN @s_pack
      INTO TABLE @DATA(lt_roots).

    LOOP AT lt_roots INTO DATA(ls_root).
      DATA(lv_top) = ls_root-devclass.

      " walk up to the top-most super package
      IF ms_opt-up = abap_true.
        DATA(lv_parent) = ls_root-parentcl.
        DATA lv_next TYPE devclass.
        DO 30 TIMES.
          IF lv_parent IS INITIAL.
            EXIT.
          ENDIF.
          lv_top = lv_parent.
          CLEAR lv_next.
          SELECT SINGLE parentcl FROM tdevc WHERE devclass = @lv_parent INTO @lv_next.
          IF sy-subrc <> 0.
            EXIT.
          ENDIF.
          lv_parent = lv_next.
        ENDDO.
      ENDIF.

      IF NOT line_exists( mt_pack[ devclass = lv_top ] ).
        DATA lv_top_parent TYPE devclass.
        CLEAR lv_top_parent.
        SELECT SINGLE parentcl FROM tdevc WHERE devclass = @lv_top INTO @lv_top_parent.
        APPEND VALUE #( devclass = lv_top parent = lv_top_parent level = 0 ) TO mt_pack.
        APPEND VALUE #( devclass = lv_top level = 0 ) TO lt_queue.
      ENDIF.
    ENDLOOP.

    " all sub packages, breadth first
    IF ms_opt-sub = abap_true OR ms_opt-up = abap_true.
      WHILE lt_queue IS NOT INITIAL.
        READ TABLE lt_queue INTO DATA(ls_q) INDEX 1.
        DELETE lt_queue INDEX 1.

        SELECT devclass FROM tdevc
          WHERE parentcl = @ls_q-devclass
          ORDER BY devclass
          INTO TABLE @DATA(lt_child).

        LOOP AT lt_child INTO DATA(ls_child).
          IF line_exists( mt_pack[ devclass = ls_child-devclass ] ).
            CONTINUE.
          ENDIF.
          APPEND VALUE #( devclass = ls_child-devclass parent = ls_q-devclass level = ls_q-level + 1 ) TO mt_pack.
          APPEND VALUE #( devclass = ls_child-devclass level = ls_q-level + 1 ) TO lt_queue.
        ENDLOOP.
      ENDWHILE.
    ENDIF.

    LOOP AT mt_pack ASSIGNING FIELD-SYMBOL(<ls_pack>).
      <ls_pack>-descr = lcl_util=>text_of( iv_table = 'TDEVCT' iv_keyfield = 'DEVCLASS'
                                           iv_name = <ls_pack>-devclass
                                           iv_langfield = 'SPRAS' iv_textfield = 'CTEXT' ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD collect_objects.

    IF mt_pack IS INITIAL.
      RETURN.
    ENDIF.

    SELECT * FROM tadir
      FOR ALL ENTRIES IN @mt_pack
      WHERE pgmid    = 'R3TR'
        AND devclass = @mt_pack-devclass
      INTO TABLE @mt_tadir.

    DELETE mt_tadir WHERE delflag = abap_true.
    DELETE mt_tadir WHERE NOT ( object IN s_type AND obj_name IN s_name ).
    SORT mt_tadir BY object obj_name.
    DELETE ADJACENT DUPLICATES FROM mt_tadir COMPARING object obj_name.

    LOOP AT mt_tadir INTO DATA(ls_tadir).
      DATA(lv_inpack) = |{ ls_tadir-object } { ls_tadir-obj_name }|.
      INSERT lv_inpack INTO TABLE mt_inpack.
      IF ls_tadir-object = 'FUGR'.
        DATA lv_fg_main   TYPE string.
        DATA lv_fg_prefix TYPE string.
        DATA lv_fg_pname  TYPE tfdir-pname.
        fugr_names( EXPORTING iv_fugr = CONV #( ls_tadir-obj_name ) IMPORTING ev_main = lv_fg_main ev_prefix = lv_fg_prefix ).
        lv_fg_pname = lv_fg_main.
        SELECT funcname FROM tfdir WHERE pname = @lv_fg_pname INTO TABLE @DATA(lt_fg_fm).
        LOOP AT lt_fg_fm INTO DATA(ls_fg_fm).
          DATA(lv_fm_key) = |FUNC { ls_fg_fm-funcname }|.
          INSERT lv_fm_key INTO TABLE mt_inpack.
        ENDLOOP.
      ENDIF.
      " namespaces (/ABC/) used by the package - customer DDIC detection
      IF ls_tadir-obj_name(1) = '/'.
        DATA lv_nsoff TYPE i.
        FIND FIRST OCCURRENCE OF '/' IN SECTION OFFSET 1 OF ls_tadir-obj_name MATCH OFFSET lv_nsoff.
        IF sy-subrc = 0.
          DATA(lv_ns) = CONV string( ls_tadir-obj_name(lv_nsoff) ) && `/`.
          IF NOT line_exists( mt_ns[ table_line = lv_ns ] ).
            APPEND lv_ns TO mt_ns.
          ENDIF.
        ENDIF.
      ENDIF.
      READ TABLE mt_pack ASSIGNING FIELD-SYMBOL(<ls_pack>) WITH KEY devclass = ls_tadir-devclass.
      IF sy-subrc = 0.
        <ls_pack>-objects = <ls_pack>-objects + 1.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD type_texts.

    " object type texts from the system (KO100), own texts as fallback
    DATA lt_tt TYPE lcl_writer=>ty_t_tt.
    FIELD-SYMBOLS <lt_tab> TYPE STANDARD TABLE.

    DATA(lr_ko) = lcl_util=>generic_select(
                    iv_table = 'KO100'
                    iv_where = |PGMID = 'R3TR' AND SPRAS = { lcl_util=>quote( CONV string( sy-langu ) ) }| ).
    IF lcl_util=>has_rows( lr_ko ) = abap_false.
      lr_ko = lcl_util=>generic_select( iv_table = 'KO100' iv_where = `PGMID = 'R3TR' AND SPRAS = 'E'` ).
    ENDIF.
    IF lcl_util=>has_rows( lr_ko ) = abap_false.
      lr_ko = lcl_util=>generic_select( iv_table = 'KO100' iv_where = `PGMID = 'R3TR'` ).
    ENDIF.
    IF lr_ko IS BOUND.
      ASSIGN lr_ko->* TO <lt_tab>.
      LOOP AT <lt_tab> ASSIGNING FIELD-SYMBOL(<ls_ko>).
        INSERT VALUE #( otype = lcl_util=>fv( is_row = <ls_ko> iv_field = 'OBJECT' )
                        text = lcl_util=>fv( is_row = <ls_ko> iv_field = 'TEXT' ) ) INTO TABLE lt_tt.
      ENDLOOP.
    ENDIF.

    DATA(lt_own) = VALUE lcl_writer=>ty_t_tt(
      ( otype = `BOBF` text = `BOPF business object` )
      ( otype = `CLAS` text = `Class` )
      ( otype = `DDLS` text = `CDS data definition` )
      ( otype = `DEVC` text = `Package` )
      ( otype = `FUGR` text = `Function group` )
      ( otype = `FUNC` text = `Function module` )
      ( otype = `INTF` text = `Interface` )
      ( otype = `PROG` text = `Program / include` )
      ( otype = `TABL` text = `Table / structure` ) ).
    LOOP AT lt_own INTO DATA(ls_own).
      INSERT ls_own INTO TABLE lt_tt.         " ignored when KO100 has it
    ENDLOOP.

    mo_writer->set_type_texts( lt_tt ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD packages_md.

    DATA lt_lines TYPE lcl_util=>ty_t_string.

    APPEND `# Package hierarchy` TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND |Extracted { lines( mt_pack ) } package(s), { lines( mt_tadir ) } repository object(s). | &&
           |Sub packages: { COND string( WHEN ms_opt-sub = abap_true THEN `yes` ELSE `no` ) }, | &&
           |from top super package: { COND string( WHEN ms_opt-up = abap_true THEN `yes` ELSE `no` ) }.| TO lt_lines.
    APPEND `` TO lt_lines.

    " depth-first tree
    DATA lt_stack TYPE STANDARD TABLE OF devclass WITH EMPTY KEY.
    LOOP AT mt_pack INTO DATA(ls_root) WHERE level = 0.
      APPEND ls_root-devclass TO lt_stack.
      WHILE lt_stack IS NOT INITIAL.
        DATA(lv_last) = lines( lt_stack ).
        READ TABLE lt_stack INTO DATA(lv_pack) INDEX lv_last.
        DELETE lt_stack INDEX lv_last.
        READ TABLE mt_pack INTO DATA(ls_pack) WITH KEY devclass = lv_pack.
        APPEND |{ repeat( val = `  ` occ = ls_pack-level ) }- **{ ls_pack-devclass }** - { ls_pack-descr } | &&
               |({ ls_pack-objects } objects{ COND string( WHEN ls_pack-level = 0 AND ls_pack-parent IS NOT INITIAL
                                                           THEN |, super package { ls_pack-parent }| ) })| TO lt_lines.
        " children in reverse order so they come out sorted
        DATA(lt_children) = VALUE ty_t_pack( FOR ls_c IN mt_pack WHERE ( parent = lv_pack AND level > 0 ) ( ls_c ) ).
        SORT lt_children BY devclass DESCENDING.
        LOOP AT lt_children INTO DATA(ls_child).
          APPEND ls_child-devclass TO lt_stack.
        ENDLOOP.
      ENDWHILE.
    ENDLOOP.

    rv_md = concat_lines_of( table = lt_lines sep = lcl_util=>gv_nl ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD errors_md.

    DATA lt_lines TYPE lcl_util=>ty_t_string.
    APPEND `# Extraction errors and limitations` TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND |{ lines( mt_err ) } entries. The extraction continued after every error.| TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND `| Type | Object | Area | Message |` TO lt_lines.
    APPEND `| --- | --- | --- | --- |` TO lt_lines.
    LOOP AT mt_err INTO DATA(ls_err).
      APPEND |\| { ls_err-otype } \| { lcl_util=>oneline( ls_err-name ) } \| { ls_err-area } \| | &&
             |{ lcl_util=>oneline( iv_txt = ls_err-msg iv_max = 400 ) } \|| TO lt_lines.
    ENDLOOP.
    rv_md = concat_lines_of( table = lt_lines sep = lcl_util=>gv_nl ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD stats_md.

    TYPES: BEGIN OF ty_s_cnt,
             otype TYPE string,
             cnt  TYPE i,
           END OF ty_s_cnt.
    DATA lt_cnt   TYPE SORTED TABLE OF ty_s_cnt WITH UNIQUE KEY otype.
    DATA lt_lines TYPE lcl_util=>ty_t_string.
    DATA lv_end   TYPE timestampl.

    LOOP AT mo_writer->mt_index INTO DATA(ls_idx).
      READ TABLE lt_cnt ASSIGNING FIELD-SYMBOL(<ls_cnt>) WITH TABLE KEY otype = ls_idx-otype.
      IF sy-subrc = 0.
        <ls_cnt>-cnt = <ls_cnt>-cnt + 1.
      ELSE.
        INSERT VALUE #( otype = ls_idx-otype cnt = 1 ) INTO TABLE lt_cnt.
      ENDIF.
    ENDLOOP.

    GET TIME STAMP FIELD lv_end.
    DATA(lv_secs) = cl_abap_tstmp=>subtract( tstmp1 = lv_end tstmp2 = mv_start ).

    APPEND `# Extraction statistics` TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND |- System: { sy-sysid } / client { sy-mandt } / release { sy-saprl }| TO lt_lines.
    APPEND |- Date: { sy-datum DATE = ISO } { sy-uzeit TIME = ISO }, user { sy-uname }| TO lt_lines.
    APPEND |- Packages: { lines( mt_pack ) }| TO lt_lines.
    APPEND |- Repository objects (TADIR): { lines( mt_tadir ) }| TO lt_lines.
    APPEND |- Documents written: { lines( mo_writer->mt_index ) }| TO lt_lines.
    APPEND |- Markdown lines: { mo_writer->mv_lines }| TO lt_lines.
    APPEND |- Errors / limitations: { lines( mt_err ) }| TO lt_lines.
    APPEND |- Runtime: { lv_secs DECIMALS = 0 } s| TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND `| Type | Documents |` TO lt_lines.
    APPEND `| --- | --- |` TO lt_lines.
    LOOP AT lt_cnt INTO DATA(ls_cnt).
      APPEND |\| { ls_cnt-otype } \| { ls_cnt-cnt } \|| TO lt_lines.
    ENDLOOP.
    rv_md = concat_lines_of( table = lt_lines sep = lcl_util=>gv_nl ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD write_list.

    DATA(lv_packs) = lines( mt_pack ).
    DATA(lv_objs)  = lines( mt_tadir ).
    DATA(lv_docs)  = lines( mo_writer->mt_index ).
    DATA(lv_lines) = mo_writer->mv_lines.
    DATA(lv_files) = mo_writer->mv_files.
    DATA(lv_bytes) = mo_writer->mv_bytes_all.
    DATA(lv_errs)  = lines( mt_err ).

    WRITE: / 'Package extract finished' COLOR COL_HEADING.
    SKIP.
    WRITE: / 'Packages          :', lv_packs.
    WRITE: / 'Objects (TADIR)   :', lv_objs.
    WRITE: / 'Documents         :', lv_docs.
    WRITE: / 'Markdown lines    :', lv_lines.
    WRITE: / 'Files in ZIPs     :', lv_files.
    WRITE: / 'Bytes uncompressed:', lv_bytes.
    WRITE: / 'Errors/limitations:', lv_errs.
    SKIP.
    WRITE: / 'Written:' COLOR COL_GROUP.
    LOOP AT mo_writer->mt_saved INTO DATA(lv_saved).
      WRITE: / lv_saved.
    ENDLOOP.
    SKIP.
    WRITE: / 'Packages:' COLOR COL_GROUP.
    LOOP AT mt_pack INTO DATA(ls_pack).
      WRITE: / ls_pack-devclass, ls_pack-objects, ls_pack-descr.
    ENDLOOP.
    IF mt_err IS NOT INITIAL.
      SKIP.
      WRITE: / 'Errors / limitations (also in reference/ERRORS.md):' COLOR COL_NEGATIVE.
      LOOP AT mt_err INTO DATA(ls_err).
        WRITE: / ls_err-otype, ls_err-name, ls_err-area, ls_err-msg.
      ENDLOOP.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD err.
    APPEND VALUE #( otype = iv_type name = iv_name area = iv_area msg = iv_msg ) TO mt_err.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD extract_object.

    DATA(lv_type) = CONV string( is_tadir-object ).
    DATA(lv_name) = CONV string( is_tadir-obj_name ).

    " BOPF objects write their own document (key based)
    IF lv_type = `BOBF`.
      IF ms_opt-bopf = abap_true.
        READ TABLE mt_bo ASSIGNING FIELD-SYMBOL(<ls_bo>) WITH KEY name = lv_name.
        IF sy-subrc = 0.
          <ls_bo>-done = abap_true.
          x_bobf( iv_name = lv_name iv_key = <ls_bo>-bo_key is_tadir = is_tadir ).
          RETURN.
        ENDIF.
        err( iv_type = lv_type iv_name = lv_name iv_area = `BOPF`
             iv_msg = `BO key not found (/BOBF/OBM_OBJ) - metadata only` ).
      ENDIF.
    ENDIF.

    DATA(lv_descr) = descr( iv_type = lv_type iv_name = lv_name ).
    DATA(lo_md) = NEW lcl_md( ).
    header( is_tadir = is_tadir io_md = lo_md iv_descr = lv_descr ).

    DATA(lv_handled) = abap_true.

    CASE lv_type.
      WHEN `DEVC`.
        x_devc( iv_name = lv_name io_md = lo_md ).
      WHEN `PROG`.
        x_prog( iv_name = lv_name io_md = lo_md ).
      WHEN `CLAS` OR `INTF`.
        x_clas( iv_name = lv_name io_md = lo_md ).
      WHEN `FUGR` OR `FUGS` OR `FUGX`.
        x_fugr( iv_name = lv_name io_md = lo_md is_tadir = is_tadir ).
      WHEN `TABL`.
        IF ms_opt-ddic = abap_true. x_tabl( iv_name = lv_name io_md = lo_md ). ENDIF.
      WHEN `VIEW` OR `ENQU`.
        IF ms_opt-ddic = abap_true. x_view( iv_name = lv_name io_md = lo_md ). ENDIF.
      WHEN `DTEL`.
        IF ms_opt-ddic = abap_true. x_dtel( iv_name = lv_name io_md = lo_md ). ENDIF.
      WHEN `DOMA`.
        IF ms_opt-ddic = abap_true. x_doma( iv_name = lv_name io_md = lo_md ). ENDIF.
      WHEN `TTYP`.
        IF ms_opt-ddic = abap_true. x_ttyp( iv_name = lv_name io_md = lo_md ). ENDIF.
      WHEN `SHLP`.
        IF ms_opt-ddic = abap_true. x_shlp( iv_name = lv_name io_md = lo_md ). ENDIF.
      WHEN `TYPE`.
        x_type( iv_name = lv_name io_md = lo_md ).
      WHEN `MSAG`.
        x_msag( iv_name = lv_name io_md = lo_md ).
      WHEN `TRAN`.
        x_tran( iv_name = lv_name io_md = lo_md ).
      WHEN `SOBJ`.
        x_sobj( iv_name = lv_name io_md = lo_md ).
      WHEN `PDTS` OR `PDWS`.
        IF ms_opt-frm = abap_true. x_wf( iv_name = lv_name iv_type = lv_type io_md = lo_md ). ENDIF.
      WHEN `ENHO`.
        x_enho( iv_name = lv_name io_md = lo_md ).
      WHEN `WAPA`.
        x_wapa( iv_name = lv_name io_md = lo_md is_tadir = is_tadir ).
      WHEN `WDYN`.
        x_wdyn( iv_name = lv_name io_md = lo_md ).   " + generic WDY* dump below
      WHEN `SSFO` OR `SFPF`.
        x_form( iv_name = lv_name iv_type = lv_type io_md = lo_md ).
      WHEN `FUNC`.
        " a single function module used by the package (not its group)
        DATA lv_fm_name TYPE rs38l_fnam.
        lv_fm_name = lv_name.
        SELECT SINGLE area FROM enlfdir WHERE funcname = @lv_fm_name INTO @DATA(lv_area).
        IF sy-subrc = 0.
          DATA lv_fx_main   TYPE string.
          DATA lv_fx_prefix TYPE string.
          fugr_names( EXPORTING iv_fugr = CONV #( lv_area ) IMPORTING ev_main = lv_fx_main ev_prefix = lv_fx_prefix ).
          DATA(ls_fugr_tadir) = is_tadir.
          SELECT SINGLE devclass FROM tadir
            WHERE pgmid = 'R3TR' AND object = 'FUGR' AND obj_name = @lv_area
            INTO @ls_fugr_tadir-devclass.
          x_func( iv_fm = lv_name iv_fugr = CONV #( lv_area ) iv_prefix = lv_fx_prefix is_tadir = ls_fugr_tadir ).
          RETURN.
        ENDIF.
        lv_handled = abap_false.
      WHEN OTHERS.
        lv_handled = abap_false.
    ENDCASE.

    " repository tables of framework objects
    IF ms_opt-frm = abap_true AND line_exists( mt_spec[ otype = lv_type ] ).
      IF x_discovery( iv_type = lv_type iv_name = lv_name io_md = lo_md ) = abap_true.
        lv_handled = abap_true.
      ENDIF.
    ENDIF.

    " source based objects (CDS, RAP, ...) and everything unknown
    IF lv_type = `DDLS` OR lv_type = `DCLS` OR lv_handled = abap_false.
      IF x_source_probe( iv_type = lv_type iv_name = lv_name io_md = lo_md ) = abap_true.
        lv_handled = abap_true.
      ENDIF.
    ENDIF.

    IF lv_handled = abap_false.
      lo_md->h2( `Content` ).
      lo_md->add( `No generic reader for this object type: TADIR data, documentation and ` &&
                  `where-used information only.` ).
      err( iv_type = lv_type iv_name = lv_name iv_area = `TYPE`
           iv_msg = `No reader for this object type - metadata only` ).
    ENDIF.

    IF ms_opt-docu = abap_true AND lv_type <> `MSAG`.
      docu( iv_name = lv_name io_md = lo_md ).
    ENDIF.

    mo_writer->add_doc( iv_type = lv_type iv_name = lv_name iv_descr = lv_descr io_md = lo_md ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD header.

    io_md->h1( |{ is_tadir-object } { is_tadir-obj_name }| ).
    io_md->kv( iv_key = `Object type` iv_val = |{ is_tadir-object } - { mo_writer->type_text( CONV #( is_tadir-object ) ) }| ).
    io_md->kv( iv_key = `Description` iv_val = iv_descr ).
    io_md->kv( iv_key = `Package` iv_val = COND string( WHEN is_tadir-devclass IS NOT INITIAL
                                                         THEN CONV string( is_tadir-devclass )
                                                         ELSE `(outside the extracted packages)` ) ).
    READ TABLE mt_extq INTO DATA(ls_eq) WITH KEY otype = CONV string( is_tadir-object )
                                                 name  = CONV string( is_tadir-obj_name ).
    IF sy-subrc = 0.
      io_md->kv( iv_key = `Note` iv_val = |object is OUTSIDE the extracted packages - extracted because it is { ls_eq-reason }| ).
    ENDIF.
    io_md->kv( iv_key = `Author`          iv_val = lcl_util=>fv( is_row = is_tadir iv_field = 'AUTHOR' ) ).
    io_md->kv( iv_key = `Created on`      iv_val = lcl_util=>fv( is_row = is_tadir iv_field = 'CREATED_ON' ) ).
    io_md->kv( iv_key = `Original system` iv_val = lcl_util=>fv( is_row = is_tadir iv_field = 'SRCSYSTEM' ) ).
    io_md->kv( iv_key = `Master language` iv_val = lcl_util=>fv( is_row = is_tadir iv_field = 'MASTERLANG' ) ).
    io_md->kv( iv_key = `Generated`       iv_val = lcl_util=>fv( is_row = is_tadir iv_field = 'GENFLAG' ) ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD descr.

    CASE iv_type.
      WHEN `CLAS` OR `INTF`.
        rv_txt = lcl_util=>text_of( iv_table = 'SEOCLASSTX' iv_keyfield = 'CLSNAME' iv_name = iv_name
                                    iv_langfield = 'LANGU' iv_textfield = 'DESCRIPT' ).
      WHEN `PROG`.
        rv_txt = lcl_util=>text_of( iv_table = 'TRDIRT' iv_keyfield = 'NAME' iv_name = iv_name
                                    iv_langfield = 'SPRSL' iv_textfield = 'TEXT' ).
      WHEN `FUGR`.
        rv_txt = lcl_util=>text_of( iv_table = 'TLIBT' iv_keyfield = 'AREA' iv_name = iv_name
                                    iv_langfield = 'SPRAS' iv_textfield = 'AREAT' ).
      WHEN `TABL`.
        rv_txt = lcl_util=>text_of( iv_table = 'DD02T' iv_keyfield = 'TABNAME' iv_name = iv_name
                                    iv_langfield = 'DDLANGUAGE' iv_textfield = 'DDTEXT' ).
      WHEN `VIEW` OR `ENQU`.
        rv_txt = lcl_util=>text_of( iv_table = 'DD25T' iv_keyfield = 'VIEWNAME' iv_name = iv_name
                                    iv_langfield = 'DDLANGUAGE' iv_textfield = 'DDTEXT' ).
      WHEN `DTEL`.
        rv_txt = lcl_util=>text_of( iv_table = 'DD04T' iv_keyfield = 'ROLLNAME' iv_name = iv_name
                                    iv_langfield = 'DDLANGUAGE' iv_textfield = 'DDTEXT' ).
      WHEN `DOMA`.
        rv_txt = lcl_util=>text_of( iv_table = 'DD01T' iv_keyfield = 'DOMNAME' iv_name = iv_name
                                    iv_langfield = 'DDLANGUAGE' iv_textfield = 'DDTEXT' ).
      WHEN `TTYP`.
        rv_txt = lcl_util=>text_of( iv_table = 'DD40T' iv_keyfield = 'TYPENAME' iv_name = iv_name
                                    iv_langfield = 'DDLANGUAGE' iv_textfield = 'DDTEXT' ).
      WHEN `SHLP`.
        rv_txt = lcl_util=>text_of( iv_table = 'DD30T' iv_keyfield = 'SHLPNAME' iv_name = iv_name
                                    iv_langfield = 'DDLANGUAGE' iv_textfield = 'DDTEXT' ).
      WHEN `MSAG`.
        rv_txt = lcl_util=>text_of( iv_table = 'T100T' iv_keyfield = 'ARBGB' iv_name = iv_name
                                    iv_langfield = 'SPRSL' iv_textfield = 'STEXT' ).
      WHEN `TRAN`.
        rv_txt = lcl_util=>text_of( iv_table = 'TSTCT' iv_keyfield = 'TCODE' iv_name = iv_name
                                    iv_langfield = 'SPRSL' iv_textfield = 'TTEXT' ).
      WHEN `DEVC`.
        rv_txt = lcl_util=>text_of( iv_table = 'TDEVCT' iv_keyfield = 'DEVCLASS' iv_name = iv_name
                                    iv_langfield = 'SPRAS' iv_textfield = 'CTEXT' ).
      WHEN `DDLS`.
        rv_txt = lcl_util=>text_of( iv_table = 'DDDDLSRCT' iv_keyfield = 'DDLNAME' iv_name = iv_name
                                    iv_langfield = 'DDLANGUAGE' iv_textfield = 'DDTEXT' ).
      WHEN `TYPE`.
        rv_txt = lcl_util=>text_of( iv_table = 'DDTYPET' iv_keyfield = 'TYPEGROUP' iv_name = iv_name
                                    iv_langfield = 'DDLANGUAGE' iv_textfield = 'DDTEXT' ).
    ENDCASE.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD dump_tab.
    DATA(lr_tab) = lcl_util=>generic_select( iv_table = iv_table iv_where = iv_where ).
    DATA(lv_title) = COND string( WHEN iv_title IS NOT INITIAL THEN iv_title ELSE iv_table ).
    IF iv_as_table = abap_true.
      io_md->table_md( ir_tab = lr_tab iv_title = lv_title ).
    ELSE.
      io_md->rows( ir_tab = lr_tab iv_title = lv_title ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD discover.
    " every transparent table matching the pattern that has the field
    DATA lv_pattern TYPE string.
    DATA lv_field   TYPE fieldname.

    DATA(lv_key) = |{ iv_pattern }\|{ iv_field }|.
    READ TABLE mt_disc INTO DATA(ls_disc) WITH TABLE KEY dkey = lv_key.
    IF sy-subrc = 0.
      rt_tables = ls_disc-tables.
      RETURN.
    ENDIF.

    lv_pattern = iv_pattern.
    lv_field   = iv_field.

    SELECT DISTINCT d3~tabname
      FROM dd03l AS d3
      INNER JOIN dd02l AS d2
        ON  d2~tabname  = d3~tabname
        AND d2~as4local = d3~as4local
        AND d2~as4vers  = d3~as4vers
      WHERE d3~tabname   LIKE @lv_pattern ESCAPE '#'
        AND d3~fieldname = @lv_field
        AND d3~as4local  = 'A'
        AND d2~tabclass  IN ('TRANSP','CLUSTER','POOL')
      ORDER BY d3~tabname
      INTO TABLE @DATA(lt_tab).

    LOOP AT lt_tab INTO DATA(ls_tab).
      APPEND CONV string( ls_tab-tabname ) TO rt_tables.
    ENDLOOP.

    INSERT VALUE #( dkey = lv_key tables = rt_tables ) INTO TABLE mt_disc.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_discovery.

    DATA lt_names TYPE lcl_util=>ty_t_string.
    FIELD-SYMBOLS <lt_found> TYPE ANY TABLE.

    rv_found = abap_false.

    LOOP AT mt_spec INTO DATA(ls_spec) WHERE otype = iv_type.
      LOOP AT discover( iv_pattern = ls_spec-pattern iv_field = ls_spec-field ) INTO DATA(lv_table).
        DATA(lr_tab) = lcl_util=>select_by_field( iv_table = lv_table
                                                  iv_field = ls_spec-field
                                                  iv_value = iv_name
                                                  iv_max   = ms_opt-maxr ).
        IF lcl_util=>has_rows( lr_tab ) = abap_true.
          IF rv_found = abap_false.
            io_md->h2( `Repository tables of the framework object` ).
            rv_found = abap_true.
          ENDIF.
          io_md->rows( ir_tab = lr_tab iv_title = |{ lv_table } ({ ls_spec-field } = { iv_name })| ).
          ASSIGN lr_tab->* TO <lt_found>.
          scan_names( EXPORTING iv_data = <lt_found> CHANGING ct_names = lt_names ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " classes / interfaces / BOR objects named in these tables
    " (DPC / MPC classes, BAdI implementations, controllers ...)
    queue_refs( it_names  = lt_names
                iv_reason = |used by { iv_type } { iv_name }|
                io_md     = io_md
                iv_title  = `Referenced classes, interfaces and BOR objects` ).

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_source_probe.
    " Source-based ADT objects (DDLS, DCLS, DDLX, BDEF, SRVD, ...):
    " find the repository table that holds the source - a transparent
    " table with a STRING field SOURCE / SOURCE_CODE / CONTENT whose
    " first key field (after the client) contains the object name.
    " The mapping is probed once per object type and cached.
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <ls_row> TYPE any.

    rv_found = abap_false.

    READ TABLE mt_probe INTO DATA(ls_probe) WITH TABLE KEY otype = iv_type.
    IF sy-subrc <> 0.
      ls_probe-otype = iv_type.

      " known locations first
      CASE iv_type.
        WHEN `DDLS`.
          ls_probe = VALUE #( otype = iv_type found = abap_true ptable = `DDDDLSRC` keyfield = `DDLNAME` srcfield = `SOURCE` ).
        WHEN `DCLS`.
          ls_probe = VALUE #( otype = iv_type found = abap_true ptable = `ACMDCLSRC` keyfield = `DCLNAME` srcfield = `SOURCE` ).
      ENDCASE.

      IF ls_probe-found = abap_false.
        IF mv_srctabs_read = abap_false.
          mv_srctabs_read = abap_true.
          SELECT DISTINCT d3~tabname, d3~fieldname
            FROM dd03l AS d3
            INNER JOIN dd02l AS d2
              ON  d2~tabname  = d3~tabname
              AND d2~as4local = d3~as4local
              AND d2~as4vers  = d3~as4vers
            WHERE d3~as4local = 'A'
              AND d3~datatype = 'STRG'
              AND d3~fieldname IN ('SOURCE','SOURCE_CODE','CONTENT')
              AND d2~tabclass = 'TRANSP'
            INTO TABLE @DATA(lt_src).
          LOOP AT lt_src INTO DATA(ls_src).
            APPEND |{ ls_src-tabname } { ls_src-fieldname }| TO mt_srctabs.
          ENDLOOP.
        ENDIF.

        LOOP AT mt_srctabs INTO DATA(lv_entry).
          SPLIT lv_entry AT ` ` INTO DATA(lv_tab) DATA(lv_srcfield).
          DATA lv_tabname TYPE tabname.
          lv_tabname = lv_tab.

          " first key field after the client
          SELECT fieldname, datatype, leng, position FROM dd03l
            WHERE tabname = @lv_tabname AND as4local = 'A' AND keyflag = 'X'
            ORDER BY position
            INTO TABLE @DATA(lt_keys).
          DELETE lt_keys WHERE fieldname = 'MANDT' OR fieldname = 'CLIENT' OR fieldname CP '.*'.
          READ TABLE lt_keys INTO DATA(ls_key) INDEX 1.
          IF sy-subrc <> 0 OR ls_key-datatype <> 'CHAR' OR ls_key-leng < 16.
            CONTINUE.
          ENDIF.

          IF lcl_util=>has_rows( lcl_util=>select_by_field( iv_table = lv_tab iv_field = ls_key-fieldname
                                                            iv_value = iv_name iv_max = 1 ) ) = abap_true.
            ls_probe = VALUE #( otype = iv_type found = abap_true ptable = lv_tab
                                keyfield = ls_key-fieldname srcfield = lv_srcfield ).
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      INSERT ls_probe INTO TABLE mt_probe.
    ENDIF.

    IF ls_probe-found = abap_false.
      RETURN.
    ENDIF.

    DATA(lr_tab) = lcl_util=>select_by_field( iv_table = ls_probe-ptable iv_field = ls_probe-keyfield
                                              iv_value = iv_name iv_max = 50 ).
    IF lcl_util=>has_rows( lr_tab ) = abap_false.
      RETURN.
    ENDIF.
    ASSIGN lr_tab->* TO <lt_tab>.

    " only the active version when the table has versions
    DATA(lv_has_active) = abap_false.
    LOOP AT <lt_tab> ASSIGNING <ls_row>.
      IF lcl_util=>fv( is_row = <ls_row> iv_field = 'AS4LOCAL' ) = 'A' OR
         to_upper( lcl_util=>fv( is_row = <ls_row> iv_field = 'VERSION' ) ) = 'A'.
        lv_has_active = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    io_md->h2( |Source ({ ls_probe-ptable }-{ ls_probe-srcfield })| ).
    DATA(lv_lang) = SWITCH string( iv_type WHEN `DDLS` OR `DCLS` OR `DDLX` OR `BDEF` OR `SRVD` OR `DRTY`
                                           THEN `cds` ELSE `text` ).

    LOOP AT <lt_tab> ASSIGNING <ls_row>.
      IF lv_has_active = abap_true AND
         lcl_util=>fv( is_row = <ls_row> iv_field = 'AS4LOCAL' ) <> 'A' AND
         to_upper( lcl_util=>fv( is_row = <ls_row> iv_field = 'VERSION' ) ) <> 'A'.
        CONTINUE.
      ENDIF.
      DATA(lv_source) = lcl_util=>fv( is_row = <ls_row> iv_field = ls_probe-srcfield ).
      io_md->code_string( iv_src = lv_source iv_lang = lv_lang ).
      rv_found = abap_true.
    ENDLOOP.

    " the other fields of the source rows (long values truncated)
    io_md->h3( |{ ls_probe-ptable } attributes| ).
    LOOP AT <lt_tab> ASSIGNING <ls_row>.
      io_md->add( |- { io_md->inline( <ls_row> ) }| ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD source_block.
    DATA lt_src TYPE lcl_util=>ty_t_string.
    DATA lv_ok  TYPE abap_bool.

    lcl_util=>read_source( EXPORTING iv_prog = iv_prog IMPORTING et_src = lt_src ev_ok = lv_ok ).
    IF lv_ok = abap_false.
      IF iv_quiet = abap_false.
        err( iv_type = `PROG` iv_name = iv_prog iv_area = `SOURCE` iv_msg = `READ REPORT failed` ).
      ENDIF.
      RETURN.
    ENDIF.
    io_md->code( it_src = lt_src iv_title = |{ iv_title } ({ lines( lt_src ) } lines)| ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD textpool.
    DATA lt_tp   TYPE STANDARD TABLE OF textpool WITH EMPTY KEY.
    DATA lv_prog TYPE progname.

    lv_prog = iv_prog.
    READ TEXTPOOL lv_prog INTO lt_tp LANGUAGE sy-langu.
    IF lt_tp IS INITIAL.
      READ TEXTPOOL lv_prog INTO lt_tp LANGUAGE 'E'.
    ENDIF.
    IF lt_tp IS INITIAL.
      RETURN.
    ENDIF.
    io_md->table_md( ir_tab = REF #( lt_tp ) iv_title = |Text pool of { iv_prog }| ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD dynpros.
    TYPES: BEGIN OF ty_s_dynp_id,
             prog TYPE progname,
             dnum TYPE sydynnr,
           END OF ty_s_dynp_id.

    DATA ls_id   TYPE ty_s_dynp_id.
    DATA ls_head TYPE d020s.
    DATA lt_fld  TYPE STANDARD TABLE OF d021s WITH EMPTY KEY.
    DATA lt_flow TYPE STANDARD TABLE OF d022s WITH EMPTY KEY.
    DATA lt_mc   TYPE STANDARD TABLE OF d023s WITH EMPTY KEY.
    DATA lt_src  TYPE lcl_util=>ty_t_string.
    DATA lv_prog TYPE progname.

    lv_prog = iv_prog.
    SELECT prog, dnum FROM d020s WHERE prog = @lv_prog ORDER BY dnum INTO TABLE @DATA(lt_dyn).

    LOOP AT lt_dyn INTO DATA(ls_dyn).
      ls_id-prog = ls_dyn-prog.
      ls_id-dnum = ls_dyn-dnum.
      CLEAR: ls_head, lt_fld, lt_flow, lt_mc, lt_src.

      DATA(lv_dyn_ok) = abap_false.
      TRY.
          IMPORT DYNPRO ls_head lt_fld lt_flow lt_mc ID ls_id.
          lv_dyn_ok = xsdbool( sy-subrc = 0 ).
        CATCH cx_root.
          lv_dyn_ok = abap_false.
      ENDTRY.
      IF lv_dyn_ok = abap_false.
        err( iv_type = `DYNP` iv_name = |{ iv_prog } { ls_dyn-dnum }| iv_area = `SCREEN` iv_msg = `IMPORT DYNPRO failed` ).
        CONTINUE.
      ENDIF.

      io_md->h2( |Screen { ls_dyn-dnum }| ).
      dump_tab( io_md = io_md iv_table = `D020T`
                iv_where = |PROG = { lcl_util=>quote( iv_prog ) } AND DYNR = { lcl_util=>quote( CONV string( ls_dyn-dnum ) ) }|
                iv_title = `Screen title` ).
      io_md->dump( iv_data = ls_head iv_name = `Screen header` ).
      io_md->table_md( ir_tab = REF #( lt_fld ) iv_title = `Screen elements` ).
      LOOP AT lt_flow INTO DATA(ls_flow).
        APPEND CONV string( ls_flow-line ) TO lt_src.
      ENDLOOP.
      io_md->code( it_src = lt_src iv_title = `Flow logic` ).
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD docu.
    " SE61 documentation of the object (and of its components / messages)
    DATA lt_line TYPE STANDARD TABLE OF tline WITH EMPTY KEY.
    DATA lv_obj  TYPE doku_obj.
    DATA lv_pat  TYPE string.

    lv_obj = iv_name.
    lv_pat = COND #( WHEN iv_pattern IS NOT INITIAL THEN iv_pattern ELSE lcl_util=>pad_pattern( iv_val = iv_name iv_len = 30 ) ).

    SELECT DISTINCT id, object, langu FROM dokhl
      WHERE object = @lv_obj
         OR object LIKE @lv_pat ESCAPE '#'
      ORDER BY id, object, langu
      INTO TABLE @DATA(lt_dok)
      UP TO 500 ROWS.

    DATA(lv_first) = abap_true.
    LOOP AT lt_dok INTO DATA(ls_dok).
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
      IF sy-subrc <> 0 OR lt_line IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_first = abap_true.
        io_md->h2( `Documentation (SE61)` ).
        lv_first = abap_false.
      ENDIF.
      io_md->h3( |{ ls_dok-id } { condense( CONV string( ls_dok-object ) ) } [{ ls_dok-langu }]| ).
      LOOP AT lt_line INTO DATA(ls_line).
        io_md->add( SWITCH string( ls_line-tdformat
                      WHEN 'U1' OR 'U2' OR 'U3' OR 'U4' THEN |**{ ls_line-tdline }**|
                      WHEN 'B1' OR 'B2'                 THEN |- { ls_line-tdline }|
                      ELSE CONV string( ls_line-tdline ) ) ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD xref.
    " used objects from the where-used index; every used class,
    " interface, DDIC type, function module, program and transaction is
    " queued for extraction (depth / standard / max options)
    DATA lt_used  TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
    DATA lt_queue TYPE lcl_util=>ty_t_string.
    FIELD-SYMBOLS <lt_tab> TYPE STANDARD TABLE.

    IF ms_opt-xref = abap_false.
      RETURN.
    ENDIF.

    DATA(lv_where) = COND string( WHEN iv_like = abap_true
                                  THEN |INCLUDE LIKE { lcl_util=>quote( iv_include ) } ESCAPE '#'|
                                  ELSE |INCLUDE = { lcl_util=>quote( iv_include ) }| ).

    DATA(lr_gt) = lcl_util=>generic_select( iv_table = 'WBCROSSGT' iv_where = lv_where iv_max = 50000 ).
    IF lr_gt IS BOUND.
      ASSIGN lr_gt->* TO <lt_tab>.
      LOOP AT <lt_tab> ASSIGNING FIELD-SYMBOL(<ls_row>).
        DATA(lv_otype) = lcl_util=>fv( is_row = <ls_row> iv_field = 'OTYPE' ).
        DATA(lv_oname) = lcl_util=>fv( is_row = <ls_row> iv_field = 'NAME' ).
        DATA(lv_entry) = |{ lv_otype } { lv_oname }|.
        INSERT lv_entry INTO TABLE lt_used.
        " types, classes, interfaces, methods, events, attributes
        IF lv_otype = `TY` OR lv_otype = `ME` OR lv_otype = `EV` OR lv_otype = `DA` OR lv_otype = `IN`.
          IF lv_otype = `TY` OR lv_oname CS '\'.
            APPEND lv_oname TO lt_queue.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    DATA(lr_cr) = lcl_util=>generic_select( iv_table = 'CROSS' iv_where = lv_where iv_max = 50000 ).
    IF lr_cr IS BOUND.
      ASSIGN lr_cr->* TO <lt_tab>.
      LOOP AT <lt_tab> ASSIGNING <ls_row>.
        lv_otype = lcl_util=>fv( is_row = <ls_row> iv_field = 'TYPE' ).
        lv_oname = lcl_util=>fv( is_row = <ls_row> iv_field = 'NAME' ).
        lv_entry = |{ lv_otype } { lv_oname }|.
        INSERT lv_entry INTO TABLE lt_used.
        IF ms_opt-ext = abap_true.
          CASE lv_otype.
            WHEN `F`. queue_ext( iv_type = `FUNC` iv_name = lv_oname iv_reason = |called by { iv_include }| ).
            WHEN `R`. queue_ext( iv_type = `PROG` iv_name = lv_oname iv_reason = |submitted / included by { iv_include }| ).
            WHEN `T`. queue_ext( iv_type = `TRAN` iv_name = lv_oname iv_reason = |called by { iv_include }| ).
          ENDCASE.
        ENDIF.
      ENDLOOP.
    ENDIF.

    SORT lt_queue.
    DELETE ADJACENT DUPLICATES FROM lt_queue.
    LOOP AT lt_queue INTO DATA(lv_qname).
      queue_name( iv_name = lv_qname iv_reason = |used by { iv_include }| ).
    ENDLOOP.

    IF lt_used IS INITIAL.
      RETURN.
    ENDIF.

    io_md->h2( |Used objects (where-used index, { lines( lt_used ) } entries; TY=type/class, ME=method, | &&
               |DA=data, F=function module, N=message, R=program ...)| ).
    DATA(lv_n) = 0.
    LOOP AT lt_used INTO lv_entry.
      lv_n = lv_n + 1.
      IF lv_n > 3000.
        io_md->add( |- ... { lines( lt_used ) - 3000 } more| ).
        EXIT.
      ENDIF.
      io_md->add( |- { lv_entry }| ).
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_devc.
    io_md->h2( `Package attributes` ).
    dump_tab( io_md = io_md iv_table = `TDEVC`  iv_where = |DEVCLASS = { lcl_util=>quote( iv_name ) }| ).
    dump_tab( io_md = io_md iv_table = `TDEVCT` iv_where = |DEVCLASS = { lcl_util=>quote( iv_name ) }| iv_as_table = abap_true ).

    io_md->h2( `Sub packages` ).
    LOOP AT mt_pack INTO DATA(ls_pack) WHERE parent = iv_name.
      io_md->add( |- { ls_pack-devclass } - { ls_pack-descr } ({ ls_pack-objects } objects)| ).
    ENDLOOP.

    io_md->h2( `Objects of this package` ).
    LOOP AT mt_tadir INTO DATA(ls_tadir) WHERE devclass = iv_name.
      io_md->add( |- { ls_tadir-object } { ls_tadir-obj_name } -> `{ mo_writer->doc_path( iv_type = CONV #( ls_tadir-object ) iv_name = CONV #( ls_tadir-obj_name ) ) }`| ).
    ENDLOOP.

    " package interfaces / use accesses
    dump_tab( io_md = io_md iv_table = `PERMISSION` iv_where = |CLIENT_PAK = { lcl_util=>quote( iv_name ) }|
              iv_title = `Use accesses (PERMISSION)` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_prog.
    DATA(lv_q) = lcl_util=>quote( iv_name ).

    io_md->h2( `Program attributes` ).
    dump_tab( io_md = io_md iv_table = `TRDIR`  iv_where = |NAME = { lv_q }| ).
    dump_tab( io_md = io_md iv_table = `TRDIRT` iv_where = |NAME = { lv_q }| iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `REPOSRC` iv_where = |PROGNAME = { lv_q } AND R3STATE = 'A'|
              iv_title = `Source attributes (REPOSRC)` ).

    textpool( iv_prog = iv_name io_md = io_md ).

    IF ms_opt-src = abap_true.
      io_md->h2( `Source` ).
      source_block( iv_prog = iv_name iv_title = iv_name io_md = io_md ).
    ENDIF.

    IF ms_opt-dyn = abap_true.
      dynpros( iv_prog = iv_name io_md = io_md ).
      dump_tab( io_md = io_md iv_table = `RSMPTEXTS` iv_where = |PROGNAME = { lv_q }|
                iv_title = `GUI status / title texts (RSMPTEXTS)` iv_as_table = abap_true ).
      dump_tab( io_md = io_md iv_table = `VARID` iv_where = |REPORT = { lv_q }| iv_title = `Variants (VARID)` ).
    ENDIF.

    xref( iv_include = iv_name iv_like = abap_false io_md = io_md ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_clas.

    DATA lt_trdir TYPE STANDARD TABLE OF trdir WITH EMPTY KEY.
    DATA lt_meth  TYPE seop_methods_w_include.
    DATA lv_cls   TYPE seoclsname.

    TYPES: BEGIN OF ty_s_inc,
             rank    TYPE i,
             sortkey TYPE string,
             prog    TYPE progname,
             title   TYPE string,
           END OF ty_s_inc.
    DATA lt_inc TYPE STANDARD TABLE OF ty_s_inc WITH EMPTY KEY.

    lv_cls = iv_name.
    DATA(lv_q)      = lcl_util=>quote( iv_name ).
    DATA(lv_prefix) = lcl_util=>pool_prefix( iv_name ).

    SELECT SINGLE clstype FROM seoclass WHERE clsname = @lv_cls INTO @DATA(lv_clstype).
    IF sy-subrc <> 0.
      err( iv_type = `CLAS` iv_name = iv_name iv_area = `CLASS` iv_msg = `not in SEOCLASS` ).
      RETURN.
    ENDIF.
    DATA(lv_isintf) = xsdbool( lv_clstype = '1' ).

    " ---- properties / relations ------------------------------------------
    io_md->h2( `Properties` ).
    dump_tab( io_md = io_md iv_table = `SEOCLASSDF` iv_where = |CLSNAME = { lv_q } AND VERSION = '1'|
              iv_title = `SEOCLASSDF (category, exposure, final, abstract, message class, unit tests ...)` ).
    dump_tab( io_md = io_md iv_table = `SEOCLASSTX` iv_where = |CLSNAME = { lv_q }| iv_title = `Descriptions`
              iv_as_table = abap_true ).

    SELECT refclsname, reltype FROM seometarel
      WHERE clsname = @lv_cls AND version = '1'
      ORDER BY reltype, refclsname
      INTO TABLE @DATA(lt_rel).
    IF lt_rel IS NOT INITIAL.
      io_md->h3( `Relations` ).
      LOOP AT lt_rel INTO DATA(ls_rel).
        queue_name( iv_name = CONV #( ls_rel-refclsname ) iv_reason = |superclass / interface of { iv_name }| ).
        io_md->add( |- { SWITCH string( ls_rel-reltype
                              WHEN '2' THEN `inherits from`
                              WHEN '1' THEN `implements`
                              WHEN '0' THEN `includes interface`
                              ELSE |relation type { ls_rel-reltype }| ) } { ls_rel-refclsname }| ).
      ENDLOOP.
    ENDIF.

    SELECT clsname FROM seometarel
      WHERE refclsname = @lv_cls AND version = '1'
      ORDER BY clsname
      INTO TABLE @DATA(lt_users)
      UP TO 500 ROWS.
    IF lt_users IS NOT INITIAL.
      io_md->h3( COND #( WHEN lv_isintf = abap_true THEN `Implemented / included by` ELSE `Direct subclasses` ) ).
      LOOP AT lt_users INTO DATA(ls_user).
        io_md->add( |- { ls_user-clsname }| ).
      ENDLOOP.
    ENDIF.

    dump_tab( io_md = io_md iv_table = `SEOFRIENDS` iv_where = |CLSNAME = { lv_q }| iv_title = `Friends` ).
    dump_tab( io_md = io_md iv_table = `SEOTYPEPLS` iv_where = |CLSNAME = { lv_q }| iv_title = `Type groups / forward declarations` ).

    " ---- declaration with SE24 descriptions --------------------------------
    IF ms_opt-sig = abap_true.
      class_declaration( iv_cls = lv_cls iv_isintf = lv_isintf io_md = io_md ).

      IF lv_isintf = abap_false.
        SELECT mtdname, refclsname FROM seoredef
          WHERE clsname = @lv_cls AND version = '1'
          ORDER BY mtdname
          INTO TABLE @DATA(lt_redef).
        IF lt_redef IS NOT INITIAL.
          io_md->h3( `Redefined methods (signature: see the defining class)` ).
          LOOP AT lt_redef INTO DATA(ls_redef).
            io_md->add( |- { ls_redef-mtdname } (from { ls_redef-refclsname })| ).
          ENDLOOP.
        ENDIF.
      ENDIF.
    ENDIF.

    textpool( iv_prog = lv_prefix && COND string( WHEN lv_isintf = abap_true THEN `IP` ELSE `CP` ) io_md = io_md ).

    " ---- source: every include of the pool ----------------------------------
    IF ms_opt-src = abap_true.
      IF lv_isintf = abap_false.
        TRY.
            lt_meth = cl_oo_classname_service=>get_all_method_includes( lv_cls ).
          CATCH cx_root.
            CLEAR lt_meth.
        ENDTRY.
      ENDIF.

      DATA(lv_pat) = |{ lcl_util=>like_escape( lv_prefix ) }%|.
      SELECT * FROM trdir WHERE name LIKE @lv_pat ESCAPE '#' INTO TABLE @lt_trdir.

      LOOP AT lt_trdir INTO DATA(ls_trdir).
        DATA(lv_suffix) = CONV string( ls_trdir-name+30 ).
        DATA(ls_inc) = VALUE ty_s_inc( prog = ls_trdir-name sortkey = ls_trdir-name ).
        CASE lv_suffix.
          WHEN `CP`.    ls_inc-rank = 1.  ls_inc-title = `Class pool`.
          WHEN `CU`.    ls_inc-rank = 2.  ls_inc-title = `PUBLIC SECTION`.
          WHEN `CO`.    ls_inc-rank = 3.  ls_inc-title = `PROTECTED SECTION`.
          WHEN `CI`.    ls_inc-rank = 4.  ls_inc-title = `PRIVATE SECTION`.
          WHEN `CCDEF`. ls_inc-rank = 5.  ls_inc-title = `Class-relevant local types (CCDEF)`.
          WHEN `CCMAC`. ls_inc-rank = 6.  ls_inc-title = `Macros (CCMAC)`.
          WHEN `CCIMP`. ls_inc-rank = 7.  ls_inc-title = `Local types and classes (CCIMP)`.
          WHEN `CCAU`.  ls_inc-rank = 8.  ls_inc-title = `Test classes (CCAU)`.
          WHEN `CT`.    ls_inc-rank = 9.  ls_inc-title = `Local types (CT)`.
          WHEN `IP`.    ls_inc-rank = 1.  ls_inc-title = `Interface pool`.
          WHEN `IU`.    ls_inc-rank = 2.  ls_inc-title = `Interface declaration (IU)`.
          WHEN OTHERS.
            READ TABLE lt_meth INTO DATA(ls_meth) WITH KEY incname = ls_trdir-name.
            IF sy-subrc = 0.
              ls_inc-rank    = 50.
              ls_inc-sortkey = ls_meth-cpdkey-cpdname.
              ls_inc-title   = |METHOD { ls_meth-cpdkey-cpdname }|.
            ELSE.
              ls_inc-rank  = 90.
              ls_inc-title = |Include { lv_suffix }|.
            ENDIF.
        ENDCASE.
        APPEND ls_inc TO lt_inc.
      ENDLOOP.

      LOOP AT lt_meth INTO ls_meth.
        IF ls_meth-incname IS NOT INITIAL AND NOT line_exists( lt_inc[ prog = ls_meth-incname ] ).
          APPEND VALUE #( rank = 50 sortkey = ls_meth-cpdkey-cpdname prog = ls_meth-incname
                          title = |METHOD { ls_meth-cpdkey-cpdname }| ) TO lt_inc.
        ENDIF.
      ENDLOOP.

      SORT lt_inc BY rank sortkey.
      io_md->h2( `Source` ).
      LOOP AT lt_inc INTO ls_inc.
        source_block( iv_prog = CONV #( ls_inc-prog ) iv_title = |{ ls_inc-title } - { ls_inc-prog }| io_md = io_md ).
      ENDLOOP.
    ENDIF.

    xref( iv_include = |{ lcl_util=>like_escape( lv_prefix ) }%| iv_like = abap_true io_md = io_md ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD class_declaration.
    " every component as ABAP declaration with its SE24 description
    DATA lt_compo TYPE STANDARD TABLE OF seocompo   WITH EMPTY KEY.
    DATA lt_cdf   TYPE STANDARD TABLE OF seocompodf WITH EMPTY KEY.
    DATA lt_ctx   TYPE STANDARD TABLE OF seocompotx WITH EMPTY KEY.
    DATA lt_sco   TYPE STANDARD TABLE OF seosubco   WITH EMPTY KEY.
    DATA lt_sdf   TYPE STANDARD TABLE OF seosubcodf WITH EMPTY KEY.
    DATA lt_stx   TYPE STANDARD TABLE OF seosubcotx WITH EMPTY KEY.
    DATA lt_comp  TYPE ty_t_comp.
    DATA lt_sub   TYPE ty_t_sub.
    DATA ls_comp  TYPE ty_s_comp.
    DATA ls_sub   TYPE ty_s_sub.
    DATA lt_lines TYPE lcl_util=>ty_t_string.

    SELECT * FROM seocompo WHERE clsname = @iv_cls INTO TABLE @lt_compo.
    SELECT * FROM seocompodf WHERE clsname = @iv_cls AND version = '1' INTO TABLE @lt_cdf.
    IF lt_cdf IS INITIAL.
      SELECT * FROM seocompodf WHERE clsname = @iv_cls INTO TABLE @lt_cdf.
    ENDIF.
    SELECT * FROM seocompotx WHERE clsname = @iv_cls INTO TABLE @lt_ctx.
    SELECT * FROM seosubco   WHERE clsname = @iv_cls INTO TABLE @lt_sco.
    SELECT * FROM seosubcodf WHERE clsname = @iv_cls AND version = '1' INTO TABLE @lt_sdf.
    IF lt_sdf IS INITIAL.
      SELECT * FROM seosubcodf WHERE clsname = @iv_cls INTO TABLE @lt_sdf.
    ENDIF.
    SELECT * FROM seosubcotx WHERE clsname = @iv_cls INTO TABLE @lt_stx.

    LOOP AT lt_cdf INTO DATA(ls_df).
      CLEAR ls_comp.
      ls_comp-cmpname = ls_df-cmpname.
      READ TABLE lt_compo INTO DATA(ls_compo) WITH KEY cmpname = ls_df-cmpname.
      IF sy-subrc = 0.
        ls_comp-cmptype = lcl_util=>fv( is_row = ls_compo iv_field = 'CMPTYPE' ).
        ls_comp-mtdtype = lcl_util=>fv( is_row = ls_compo iv_field = 'MTDTYPE' ).
      ELSE.
        ls_comp-cmptype = lcl_util=>fv( is_row = ls_df iv_field = 'CMPTYPE' ).
      ENDIF.
      ls_comp-exposure   = lcl_util=>fv( is_row = ls_df iv_field = 'EXPOSURE' ).
      ls_comp-decl       = SWITCH #( ls_comp-cmptype
                             WHEN `0` THEN lcl_util=>fv( is_row = ls_df iv_field = 'ATTDECLTYP' )
                             WHEN `1` THEN lcl_util=>fv( is_row = ls_df iv_field = 'MTDDECLTYP' )
                             WHEN `2` THEN lcl_util=>fv( is_row = ls_df iv_field = 'EVTDECLTYP' ) ).
      ls_comp-rdonly     = lcl_util=>fv( is_row = ls_df iv_field = 'ATTRDONLY' ).
      ls_comp-attvalue   = lcl_util=>fv( is_row = ls_df iv_field = 'ATTVALUE' ).
      ls_comp-typtype    = lcl_util=>fv( is_row = ls_df iv_field = 'TYPTYPE' ).
      ls_comp-typename   = lcl_util=>fv( is_row = ls_df iv_field = 'TYPE' ).
      ls_comp-tableof    = lcl_util=>fv( is_row = ls_df iv_field = 'TABLEOF' ).
      ls_comp-isabstract = lcl_util=>fv( is_row = ls_df iv_field = 'MTDABSTRCT' ).
      ls_comp-isfinal    = lcl_util=>fv( is_row = ls_df iv_field = 'MTDFINAL' ).
      ls_comp-newexc     = lcl_util=>fv( is_row = ls_df iv_field = 'MTDNEWEXC' ).
      ls_comp-isalias    = lcl_util=>fv( is_row = ls_df iv_field = 'ALIAS' ).
      ls_comp-refcls     = lcl_util=>fv( is_row = ls_df iv_field = 'REFCLSNAME' ).
      ls_comp-refint     = lcl_util=>fv( is_row = ls_df iv_field = 'REFINTNAME' ).
      ls_comp-refcmp     = lcl_util=>fv( is_row = ls_df iv_field = 'REFCMPNAME' ).
      TRY.
          ls_comp-editorder = lcl_util=>fv( is_row = ls_df iv_field = 'EDITORDER' ).
        CATCH cx_root.
          ls_comp-editorder = 0.
      ENDTRY.
      IF iv_isintf = abap_true OR ls_comp-exposure IS INITIAL.
        ls_comp-exposure = COND #( WHEN ls_comp-exposure IS INITIAL THEN `2` ELSE ls_comp-exposure ).
      ENDIF.
      READ TABLE lt_ctx INTO DATA(ls_ctx) WITH KEY cmpname = ls_df-cmpname langu = sy-langu.
      IF sy-subrc <> 0.
        READ TABLE lt_ctx INTO ls_ctx WITH KEY cmpname = ls_df-cmpname.
      ENDIF.
      IF sy-subrc = 0.
        ls_comp-descr = ls_ctx-descript.
      ENDIF.
      APPEND ls_comp TO lt_comp.
    ENDLOOP.

    LOOP AT lt_sco INTO DATA(ls_sco).
      CLEAR ls_sub.
      ls_sub-cmpname = ls_sco-cmpname.
      ls_sub-sconame = ls_sco-sconame.
      ls_sub-scotype = lcl_util=>fv( is_row = ls_sco iv_field = 'SCOTYPE' ).
      READ TABLE lt_sdf INTO DATA(ls_sdf) WITH KEY cmpname = ls_sco-cmpname sconame = ls_sco-sconame.
      IF sy-subrc = 0.
        ls_sub-decl       = lcl_util=>fv( is_row = ls_sdf iv_field = 'PARDECLTYP' ).
        ls_sub-pass       = lcl_util=>fv( is_row = ls_sdf iv_field = 'PARPASSTYP' ).
        ls_sub-typtype    = lcl_util=>fv( is_row = ls_sdf iv_field = 'TYPTYPE' ).
        ls_sub-typename   = lcl_util=>fv( is_row = ls_sdf iv_field = 'TYPE' ).
        ls_sub-tableof    = lcl_util=>fv( is_row = ls_sdf iv_field = 'TABLEOF' ).
        ls_sub-isoptional = lcl_util=>fv( is_row = ls_sdf iv_field = 'PAROPTIONL' ).
        ls_sub-defval     = lcl_util=>fv( is_row = ls_sdf iv_field = 'PARVALUE' ).
        ls_sub-preferred  = lcl_util=>fv( is_row = ls_sdf iv_field = 'PARPREFERD' ).
        TRY.
            ls_sub-editorder = lcl_util=>fv( is_row = ls_sdf iv_field = 'EDITORDER' ).
          CATCH cx_root.
            ls_sub-editorder = 0.
        ENDTRY.
        IF ls_sub-scotype IS INITIAL.
          ls_sub-scotype = lcl_util=>fv( is_row = ls_sdf iv_field = 'SCOTYPE' ).
        ENDIF.
      ENDIF.
      READ TABLE lt_stx INTO DATA(ls_stx) WITH KEY cmpname = ls_sco-cmpname sconame = ls_sco-sconame langu = sy-langu.
      IF sy-subrc <> 0.
        READ TABLE lt_stx INTO ls_stx WITH KEY cmpname = ls_sco-cmpname sconame = ls_sco-sconame.
      ENDIF.
      IF sy-subrc = 0.
        ls_sub-descr = ls_stx-descript.
      ENDIF.
      APPEND ls_sub TO lt_sub.
    ENDLOOP.

    SORT lt_comp BY exposure DESCENDING cmptype editorder cmpname.
    SORT lt_sub  BY cmpname editorder sconame.

    " ---- build the declaration ---------------------------------------------
    APPEND COND string( WHEN iv_isintf = abap_true THEN |INTERFACE { to_lower( iv_cls ) } PUBLIC.|
                        ELSE |CLASS { to_lower( iv_cls ) } DEFINITION.| ) TO lt_lines.

    DATA(lt_expo) = COND lcl_util=>ty_t_string( WHEN iv_isintf = abap_true THEN VALUE #( ( `2` ) )
                                                ELSE VALUE #( ( `2` ) ( `1` ) ( `0` ) ) ).
    LOOP AT lt_expo INTO DATA(lv_expo).
      IF iv_isintf = abap_false.
        APPEND `` TO lt_lines.
        APPEND |  { SWITCH string( lv_expo WHEN `2` THEN `PUBLIC` WHEN `1` THEN `PROTECTED` ELSE `PRIVATE` ) } SECTION.| TO lt_lines.
      ENDIF.
      DATA(lv_pad) = COND string( WHEN iv_isintf = abap_true THEN `  ` ELSE `    ` ).

      " types, attributes / constants, events, methods, aliases
      LOOP AT VALUE lcl_util=>ty_t_string( ( `3` ) ( `0` ) ( `2` ) ( `1` ) ( `A` ) ) INTO DATA(lv_kind).
        LOOP AT lt_comp INTO ls_comp WHERE exposure = lv_expo.
          IF lv_kind = `A`.
            IF ls_comp-isalias <> abap_true.
              CONTINUE.
            ENDIF.
            APPEND |{ lv_pad }ALIASES { to_lower( ls_comp-cmpname ) } FOR | &&
                   |{ to_lower( COND string( WHEN ls_comp-refint IS NOT INITIAL THEN ls_comp-refint ELSE ls_comp-refcls ) ) }~| &&
                   |{ to_lower( ls_comp-refcmp ) }.| TO lt_lines.
            CONTINUE.
          ENDIF.
          IF ls_comp-cmptype <> lv_kind OR ls_comp-isalias = abap_true.
            CONTINUE.
          ENDIF.

          DATA(lv_comment) = COND string( WHEN ls_comp-descr IS NOT INITIAL THEN |   " { ls_comp-descr }| ).
          IF ls_comp-typtype = `1` OR ls_comp-typtype = `3`.
            queue_name( iv_name = ls_comp-typename iv_reason = |used in the declaration of { iv_cls }| ).
          ENDIF.
          DATA(lv_typing)  = lcl_util=>typing( iv_typtype = ls_comp-typtype iv_type = ls_comp-typename
                                               iv_tableof = ls_comp-tableof ).
          CASE lv_kind.
            WHEN `3`.
              APPEND |{ lv_pad }TYPES { to_lower( ls_comp-cmpname ) } { lv_typing }.{ lv_comment }| TO lt_lines.
            WHEN `0`.
              APPEND |{ lv_pad }{ SWITCH string( ls_comp-decl WHEN `1` THEN `CLASS-DATA` WHEN `2` THEN `CONSTANTS` ELSE `DATA` ) } | &&
                     |{ to_lower( ls_comp-cmpname ) } { lv_typing }| &&
                     |{ COND string( WHEN ls_comp-rdonly = abap_true THEN ` READ-ONLY` ) }| &&
                     |{ COND string( WHEN ls_comp-attvalue IS NOT INITIAL THEN | VALUE { ls_comp-attvalue }| ) }.| &&
                     lv_comment TO lt_lines.
            WHEN `2`.
              APPEND |{ lv_pad }{ COND string( WHEN ls_comp-decl = `1` THEN `CLASS-EVENTS` ELSE `EVENTS` ) } | &&
                     |{ to_lower( ls_comp-cmpname ) }{ lv_comment }| TO lt_lines.
              params_decl( EXPORTING it_sub = lt_sub is_comp = ls_comp iv_pad = lv_pad CHANGING ct_lines = lt_lines ).
            WHEN `1`.
              APPEND |{ lv_pad }{ COND string( WHEN ls_comp-decl = `1` THEN `CLASS-METHODS` ELSE `METHODS` ) } | &&
                     |{ to_lower( ls_comp-cmpname ) }| &&
                     |{ COND string( WHEN ls_comp-isabstract = abap_true THEN ` ABSTRACT` ) }| &&
                     |{ COND string( WHEN ls_comp-isfinal = abap_true THEN ` FINAL` ) }| &&
                     |{ COND string( WHEN ls_comp-refcmp IS NOT INITIAL
                                     THEN | FOR EVENT { to_lower( ls_comp-refcmp ) } OF { to_lower( ls_comp-refcls ) }{ to_lower( ls_comp-refint ) }| ) }| &&
                     lv_comment TO lt_lines.
              params_decl( EXPORTING it_sub = lt_sub is_comp = ls_comp iv_pad = lv_pad CHANGING ct_lines = lt_lines ).
          ENDCASE.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    APPEND `` TO lt_lines.
    APPEND COND string( WHEN iv_isintf = abap_true THEN `ENDINTERFACE.` ELSE `ENDCLASS.` ) TO lt_lines.

    io_md->h2( `Declaration (from the class repository, with SE24 descriptions)` ).
    io_md->add( `Generated from SEOCOMPO / SEOSUBCO; the exact source is in section "Source".` ).
    io_md->code( it_src = lt_lines ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD params_decl.
    DATA lt_decl TYPE lcl_util=>ty_t_string.
    DATA lv_pref TYPE string.

    DATA(lt_par) = VALUE ty_t_sub( FOR ls_s IN it_sub WHERE ( cmpname = is_comp-cmpname ) ( ls_s ) ).
    IF lt_par IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_par INTO DATA(ls_par) WHERE scotype <> `1`.
      IF NOT line_exists( lt_decl[ table_line = ls_par-decl ] ).
        APPEND ls_par-decl TO lt_decl.
      ENDIF.
    ENDLOOP.
    SORT lt_decl.

    LOOP AT lt_decl INTO DATA(lv_decl).
      APPEND |{ iv_pad }  { SWITCH string( lv_decl WHEN `0` THEN `IMPORTING` WHEN `1` THEN `EXPORTING`
                                                   WHEN `2` THEN `CHANGING`  WHEN `3` THEN `RETURNING`
                                                   ELSE |PARDECLTYP { lv_decl }| ) }| TO ct_lines.
      LOOP AT lt_par INTO ls_par WHERE scotype <> `1` AND decl = lv_decl.
        IF ls_par-typtype = `1` OR ls_par-typtype = `3`.
          queue_name( iv_name = ls_par-typename iv_reason = |used in the signature of { is_comp-cmpname }| ).
        ENDIF.
        APPEND |{ iv_pad }    | &&
               |{ COND string( WHEN ls_par-pass = `0` OR lv_decl = `3` THEN |VALUE({ to_lower( ls_par-sconame ) })|
                               ELSE |!{ to_lower( ls_par-sconame ) }| ) } | &&
               |{ lcl_util=>typing( iv_typtype = ls_par-typtype iv_type = ls_par-typename iv_tableof = ls_par-tableof ) }| &&
               |{ COND string( WHEN ls_par-isoptional = abap_true THEN ` OPTIONAL` ) }| &&
               |{ COND string( WHEN ls_par-defval IS NOT INITIAL THEN | DEFAULT { ls_par-defval }| ) }| &&
               |{ COND string( WHEN ls_par-descr IS NOT INITIAL THEN |   " { ls_par-descr }| ) }| TO ct_lines.
        IF ls_par-preferred = abap_true.
          lv_pref = to_lower( ls_par-sconame ).
        ENDIF.
      ENDLOOP.
      IF lv_decl = `0` AND lv_pref IS NOT INITIAL.
        APPEND |{ iv_pad }    PREFERRED PARAMETER { lv_pref }| TO ct_lines.
      ENDIF.
    ENDLOOP.

    DATA(lv_first) = abap_true.
    LOOP AT lt_par INTO ls_par WHERE scotype = `1`.
      IF lv_first = abap_true.
        lv_first = abap_false.
        APPEND |{ iv_pad }  { COND string( WHEN is_comp-newexc = abap_true THEN `RAISING` ELSE `EXCEPTIONS` ) }| TO ct_lines.
      ENDIF.
      APPEND |{ iv_pad }    { to_lower( ls_par-sconame ) }| &&
             |{ COND string( WHEN ls_par-descr IS NOT INITIAL THEN |   " { ls_par-descr }| ) }| TO ct_lines.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD fugr_names.
    " ZFG -> SAPLZFG / LZFG ; /ABC/FG -> /ABC/SAPLFG / /ABC/LFG
    DATA lv_off TYPE i.
    IF strlen( iv_fugr ) > 1 AND iv_fugr(1) = '/'.
      FIND FIRST OCCURRENCE OF '/' IN SECTION OFFSET 1 OF iv_fugr MATCH OFFSET lv_off.
      IF sy-subrc = 0.
        DATA(lv_ns)   = substring( val = iv_fugr len = lv_off + 1 ).
        DATA(lv_rest) = substring( val = iv_fugr off = lv_off + 1 ).
        ev_main   = |{ lv_ns }SAPL{ lv_rest }|.
        ev_prefix = |{ lv_ns }L{ lv_rest }|.
        RETURN.
      ENDIF.
    ENDIF.
    ev_main   = |SAPL{ iv_fugr }|.
    ev_prefix = |L{ iv_fugr }|.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_fugr.
    DATA lv_main   TYPE string.
    DATA lv_prefix TYPE string.
    DATA lv_pname  TYPE tfdir-pname.
    DATA lt_fm     TYPE STANDARD TABLE OF tfdir WITH EMPTY KEY.
    DATA lt_trdir  TYPE STANDARD TABLE OF trdir WITH EMPTY KEY.

    fugr_names( EXPORTING iv_fugr = iv_name IMPORTING ev_main = lv_main ev_prefix = lv_prefix ).
    lv_pname = lv_main.

    io_md->h2( `Function group` ).
    io_md->kv( iv_key = `Main program` iv_val = lv_main ).
    dump_tab( io_md = io_md iv_table = `TLIBG` iv_where = |AREA = { lcl_util=>quote( iv_name ) }| ).
    dump_tab( io_md = io_md iv_table = `TLIBT` iv_where = |AREA = { lcl_util=>quote( iv_name ) }| iv_as_table = abap_true ).

    SELECT * FROM tfdir WHERE pname = @lv_pname ORDER BY funcname INTO TABLE @lt_fm.

    io_md->h2( |Function modules ({ lines( lt_fm ) })| ).
    DATA lt_fm_inc TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT lt_fm INTO DATA(ls_fm).
      io_md->add( |- { ls_fm-funcname } -> `{ mo_writer->doc_path( iv_type = `FUNC` iv_name = CONV #( ls_fm-funcname ) ) }`| ).
      DATA(lv_fm_inc) = |{ lv_prefix }U{ ls_fm-include }|.
      INSERT lv_fm_inc INTO TABLE lt_fm_inc.
    ENDLOOP.

    textpool( iv_prog = lv_main io_md = io_md ).

    " every include of the group except the function module includes
    IF ms_opt-src = abap_true.
      io_md->h2( `Source (main program and includes; function modules have their own file)` ).
      source_block( iv_prog = lv_main iv_title = lv_main io_md = io_md ).
      DATA(lv_pat) = |{ lcl_util=>like_escape( lv_prefix ) }%|.
      SELECT * FROM trdir WHERE name LIKE @lv_pat ESCAPE '#' ORDER BY name INTO TABLE @lt_trdir.
      LOOP AT lt_trdir INTO DATA(ls_trdir).
        DATA(lv_inc) = CONV string( ls_trdir-name ).
        IF strlen( lv_inc ) <> strlen( lv_prefix ) + 3 OR line_exists( lt_fm_inc[ table_line = lv_inc ] ).
          CONTINUE.
        ENDIF.
        source_block( iv_prog = lv_inc iv_title = lv_inc io_md = io_md ).
      ENDLOOP.
    ENDIF.

    IF ms_opt-dyn = abap_true.
      dynpros( iv_prog = lv_main io_md = io_md ).
      dump_tab( io_md = io_md iv_table = `RSMPTEXTS` iv_where = |PROGNAME = { lcl_util=>quote( lv_main ) }|
                iv_title = `GUI status / title texts (RSMPTEXTS)` iv_as_table = abap_true ).
    ENDIF.

    xref( iv_include = |{ lcl_util=>like_escape( lv_prefix ) }%| iv_like = abap_true io_md = io_md ).

    " one document per function module
    LOOP AT lt_fm INTO ls_fm.
      TRY.
          x_func( iv_fm = CONV #( ls_fm-funcname ) iv_fugr = iv_name iv_prefix = lv_prefix is_tadir = is_tadir ).
        CATCH cx_root INTO DATA(lx_fm).
          err( iv_type = `FUNC` iv_name = CONV #( ls_fm-funcname ) iv_area = `FUNC` iv_msg = lx_fm->get_text( ) ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_func.
    DATA lv_fm TYPE rs38l_fnam.
    DATA lt_par TYPE STANDARD TABLE OF fupararef WITH EMPTY KEY.
    DATA lt_decl TYPE lcl_util=>ty_t_string.

    lv_fm = iv_fm.
    DATA(lv_q) = lcl_util=>quote( iv_fm ).
    DATA(lv_descr) = lcl_util=>text_of( iv_table = 'TFTIT' iv_keyfield = 'FUNCNAME' iv_name = iv_fm
                                        iv_langfield = 'SPRAS' iv_textfield = 'STEXT' ).

    DATA(lo_md) = NEW lcl_md( ).
    lo_md->h1( |FUNC { iv_fm }| ).
    lo_md->kv( iv_key = `Object type`    iv_val = `FUNC - Function module` ).
    lo_md->kv( iv_key = `Description`    iv_val = lv_descr ).
    lo_md->kv( iv_key = `Function group` iv_val = |{ iv_fugr } -> `{ mo_writer->doc_path( iv_type = `FUGR` iv_name = iv_fugr ) }`| ).
    lo_md->kv( iv_key = `Package`        iv_val = CONV #( is_tadir-devclass ) ).
    READ TABLE mt_extq INTO DATA(ls_eq) WITH KEY otype = `FUNC` name = iv_fm.
    IF sy-subrc = 0.
      lo_md->kv( iv_key = `Note` iv_val = |function module is OUTSIDE the extracted packages - extracted because it is { ls_eq-reason }| ).
    ENDIF.

    SELECT SINGLE * FROM tfdir WHERE funcname = @lv_fm INTO @DATA(ls_tfdir).
    lo_md->kv( iv_key = `Processing type` iv_val = SWITCH string( lcl_util=>fv( is_row = ls_tfdir iv_field = 'FMODE' )
                                                     WHEN 'R' THEN `Remote-enabled (RFC)`
                                                     WHEN 'X' THEN `Remote-enabled (RFC)`
                                                     WHEN 'K' THEN `Update module`
                                                     WHEN ''  THEN `Normal`
                                                     ELSE lcl_util=>fv( is_row = ls_tfdir iv_field = 'FMODE' ) ) ).
    DATA lt_tfdir TYPE STANDARD TABLE OF tfdir WITH EMPTY KEY.
    APPEND ls_tfdir TO lt_tfdir.
    lo_md->rows( ir_tab = REF #( lt_tfdir ) iv_title = `Attributes (TFDIR)` ).

    " ---- signature ------------------------------------------------------
    SELECT * FROM fupararef WHERE funcname = @lv_fm AND r3state = 'A' INTO TABLE @lt_par.
    SORT lt_par BY paramtype pposition.

    SELECT parameter, kind, stext FROM funct
      WHERE funcname = @lv_fm AND spras = @sy-langu
      INTO TABLE @DATA(lt_txt).
    IF lt_txt IS INITIAL.
      SELECT parameter, kind, stext FROM funct
        WHERE funcname = @lv_fm AND spras = 'E'
        INTO TABLE @lt_txt.
    ENDIF.

    APPEND |FUNCTION { to_lower( iv_fm ) }| TO lt_decl.
    LOOP AT VALUE lcl_util=>ty_t_string( ( `I` ) ( `E` ) ( `C` ) ( `T` ) ( `X` ) ) INTO DATA(lv_kind).
      DATA(lv_first) = abap_true.
      LOOP AT lt_par INTO DATA(ls_par) WHERE paramtype = lv_kind.
        IF lv_first = abap_true.
          lv_first = abap_false.
          APPEND |  { SWITCH string( lv_kind WHEN `I` THEN `IMPORTING` WHEN `E` THEN `EXPORTING`
                                             WHEN `C` THEN `CHANGING`  WHEN `T` THEN `TABLES`
                                             ELSE `EXCEPTIONS` ) }| TO lt_decl.
        ENDIF.
        DATA(lv_pname) = to_lower( CONV string( ls_par-parameter ) ).
        DATA(lv_type)  = lcl_util=>fv( is_row = ls_par iv_field = 'STRUCTURE' ).
        queue_name( iv_name = lv_type iv_reason = |used in the signature of function module { iv_fm }| ).
        DATA(lv_line)  = ``.
        IF lv_kind = `X`.
          lv_line = |    { lv_pname }|.
        ELSEIF lv_kind = `T`.
          lv_line = |    { lv_pname }{ COND string( WHEN lv_type IS NOT INITIAL
                                                    THEN |{ COND string( WHEN lcl_util=>fv( is_row = ls_par iv_field = 'TYPE' ) = abap_true
                                                                         THEN ` TYPE ` ELSE ` STRUCTURE ` ) }{ lv_type }| ) }|.
        ELSE.
          lv_line = |    { COND string( WHEN lcl_util=>fv( is_row = ls_par iv_field = 'REFERENCE' ) = abap_true
                                        THEN |REFERENCE({ lv_pname })| ELSE |VALUE({ lv_pname })| ) }| &&
                    |{ COND string( WHEN lv_type IS INITIAL THEN ``
                                    WHEN lcl_util=>fv( is_row = ls_par iv_field = 'REF_CLASS' ) = abap_true THEN | TYPE REF TO { lv_type }|
                                    WHEN lcl_util=>fv( is_row = ls_par iv_field = 'TYPE' ) = abap_true THEN | TYPE { lv_type }|
                                    ELSE | LIKE { lv_type }| ) }| &&
                    |{ COND string( WHEN lcl_util=>fv( is_row = ls_par iv_field = 'DEFAULTVAL' ) IS NOT INITIAL
                                    THEN | DEFAULT { lcl_util=>fv( is_row = ls_par iv_field = 'DEFAULTVAL' ) }| ) }| &&
                    |{ COND string( WHEN lcl_util=>fv( is_row = ls_par iv_field = 'OPTIONAL' ) = abap_true THEN ` OPTIONAL` ) }|.
        ENDIF.
        READ TABLE lt_txt INTO DATA(ls_txt) WITH KEY parameter = ls_par-parameter.
        IF sy-subrc = 0 AND ls_txt-stext IS NOT INITIAL.
          lv_line = |{ lv_line }   " { ls_txt-stext }|.
        ENDIF.
        APPEND lv_line TO lt_decl.
      ENDLOOP.
    ENDLOOP.
    lo_md->h2( `Signature` ).
    lo_md->code( it_src = lt_decl ).

    " ---- source ---------------------------------------------------------
    DATA(lv_include) = |{ iv_prefix }U{ lcl_util=>fv( is_row = ls_tfdir iv_field = 'INCLUDE' ) }|.
    IF ms_opt-src = abap_true.
      lo_md->h2( `Source` ).
      source_block( iv_prog = lv_include iv_title = lv_include io_md = lo_md ).
    ENDIF.

    xref( iv_include = lv_include iv_like = abap_false io_md = lo_md ).

    IF ms_opt-docu = abap_true.
      docu( iv_name = iv_fm io_md = lo_md ).
    ENDIF.

    mo_writer->add_doc( iv_type = `FUNC` iv_name = iv_fm iv_descr = lv_descr io_md = lo_md ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_tabl.
    DATA lt_dd03l TYPE STANDARD TABLE OF dd03l WITH EMPTY KEY.
    DATA lv_tab   TYPE tabname.

    lv_tab = iv_name.
    DATA(lv_q) = lcl_util=>quote( iv_name ).
    DATA(lv_l) = lcl_util=>quote( CONV string( sy-langu ) ).

    io_md->h2( `Dictionary definition` ).
    dump_tab( io_md = io_md iv_table = `DD02V` iv_where = |TABNAME = { lv_q } AND DDLANGUAGE = { lv_l }|
              iv_title = `Header (DD02V: table class, delivery class, enhancement category ...)` ).
    dump_tab( io_md = io_md iv_table = `DD09L` iv_where = |TABNAME = { lv_q } AND AS4LOCAL = 'A'|
              iv_title = `Technical settings (DD09L)` ).

    SELECT * FROM dd03l WHERE tabname = @lv_tab AND as4local = 'A' ORDER BY position INTO TABLE @lt_dd03l.
    IF lt_dd03l IS NOT INITIAL.
      SELECT rollname, ddtext FROM dd04t
        FOR ALL ENTRIES IN @lt_dd03l
        WHERE rollname = @lt_dd03l-rollname AND ddlanguage = @sy-langu AND as4local = 'A'
        INTO TABLE @DATA(lt_dtext).
      SELECT fieldname, ddtext FROM dd03t
        WHERE tabname = @lv_tab AND ddlanguage = @sy-langu AND as4local = 'A'
        INTO TABLE @DATA(lt_ftext).

      io_md->h3( |Fields ({ lines( lt_dd03l ) })| ).
      io_md->add( `| Pos | Field | Key | Data element | Type | Length | Dec | Check table | Description |` ).
      io_md->add( `| --- | --- | --- | --- | --- | --- | --- | --- | --- |` ).
      LOOP AT lt_dd03l INTO DATA(ls_f).
        queue_ddic( iv_name = CONV #( ls_f-rollname ) iv_reason = |used by table / structure { iv_name }| ).
        queue_ddic( iv_name = lcl_util=>fv( is_row = ls_f iv_field = 'PRECFIELD' ) iv_reason = |included in { iv_name }| ).
        READ TABLE lt_dtext INTO DATA(ls_dt) WITH KEY rollname = ls_f-rollname.
        DATA(lv_txt) = COND string( WHEN sy-subrc = 0 AND ls_f-rollname IS NOT INITIAL THEN ls_dt-ddtext ).
        IF lv_txt IS INITIAL.
          READ TABLE lt_ftext INTO DATA(ls_ft) WITH KEY fieldname = ls_f-fieldname.
          IF sy-subrc = 0.
            lv_txt = ls_ft-ddtext.
          ENDIF.
        ENDIF.
        io_md->add( |\| { CONV i( ls_f-position ) } \| { ls_f-fieldname } \| { ls_f-keyflag } \| { ls_f-rollname } \| | &&
                    |{ ls_f-datatype } \| { CONV i( ls_f-leng ) } \| { CONV i( ls_f-decimals ) } \| | &&
                    |{ lcl_util=>fv( is_row = ls_f iv_field = 'CHECKTABLE' ) } \| { lcl_util=>oneline( lv_txt ) } \|| ).
      ENDLOOP.
    ENDIF.

    dump_tab( io_md = io_md iv_table = `DD08V` iv_where = |TABNAME = { lv_q } AND DDLANGUAGE = { lv_l }| iv_title = `Foreign keys (DD08V)` ).
    dump_tab( io_md = io_md iv_table = `DD05S` iv_where = |TABNAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Foreign key fields (DD05S)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `DD12V` iv_where = |SQLTAB = { lv_q } AND DDLANGUAGE = { lv_l }| iv_title = `Indexes (DD12V)` ).
    dump_tab( io_md = io_md iv_table = `DD17S` iv_where = |SQLTAB = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Index fields (DD17S)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `DD35L` iv_where = |TABNAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Search help assignments (DD35L)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `TVDIR` iv_where = |TABNAME = { lv_q }| iv_title = `Table maintenance dialog (TVDIR)` ).

    " ---- contents of configuration tables -----------------------------------
    IF ms_opt-cont = abap_true.
      SELECT SINGLE * FROM dd02l WHERE tabname = @lv_tab AND as4local = 'A' INTO @DATA(ls_dd02l).
      IF sy-subrc = 0.
        DATA(lv_class)   = lcl_util=>fv( is_row = ls_dd02l iv_field = 'TABCLASS' ).
        DATA(lv_contflg) = lcl_util=>fv( is_row = ls_dd02l iv_field = 'CONTFLAG' ).
        IF ( lv_class = `TRANSP` OR lv_class = `POOL` OR lv_class = `CLUSTER` ) AND
           ( lv_contflg = `C` OR lv_contflg = `G` OR lv_contflg = `E` OR lv_contflg = `S` OR lv_contflg = `W` ).
          DATA(lr_cont) = lcl_util=>generic_select( iv_table = iv_name iv_where = `` iv_max = ms_opt-contr ).
          io_md->h2( |Table contents - configuration values (delivery class { lv_contflg }, client { sy-mandt }, max { ms_opt-contr } rows)| ).
          IF lcl_util=>has_rows( lr_cont ) = abap_true.
            DATA(lv_old) = lcl_util=>gv_maxr.
            lcl_util=>gv_maxr = ms_opt-contr.
            io_md->table_md( ir_tab = lr_cont iv_title = iv_name ).
            lcl_util=>gv_maxr = lv_old.
          ELSE.
            io_md->add( `(no entries or not readable)` ).
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_view.
    DATA(lv_q) = lcl_util=>quote( iv_name ).
    io_md->h2( `Dictionary definition` ).
    dump_tab( io_md = io_md iv_table = `DD25V` iv_where = |VIEWNAME = { lv_q } AND DDLANGUAGE = { lcl_util=>quote( CONV string( sy-langu ) ) }| iv_title = `Header (DD25V)` ).
    dump_tab( io_md = io_md iv_table = `DD26S` iv_where = |VIEWNAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Base tables (DD26S)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `DD27S` iv_where = |VIEWNAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Fields (DD27S)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `DD28S` iv_where = |CONDNAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Join / selection conditions (DD28S)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `TVDIR` iv_where = |TABNAME = { lv_q }| iv_title = `Table maintenance dialog (TVDIR)` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_dtel.
    DATA(lv_q) = lcl_util=>quote( iv_name ).
    DATA(lv_l) = lcl_util=>quote( CONV string( sy-langu ) ).
    io_md->h2( `Dictionary definition` ).
    dump_tab( io_md = io_md iv_table = `DD04V` iv_where = |ROLLNAME = { lv_q } AND DDLANGUAGE = { lv_l }| iv_title = `Data element (DD04V)` ).

    SELECT SINGLE domname FROM dd04l WHERE rollname = @iv_name AND as4local = 'A' INTO @DATA(lv_dom).
    IF sy-subrc = 0 AND lv_dom IS NOT INITIAL.
      queue_ddic( iv_name = CONV #( lv_dom ) iv_reason = |domain of data element { iv_name }| ).
      dump_tab( io_md = io_md iv_table = `DD07V`
                iv_where = |DOMNAME = { lcl_util=>quote( CONV string( lv_dom ) ) } AND DDLANGUAGE = { lv_l }|
                iv_title = |Fixed values of domain { lv_dom }| iv_as_table = abap_true ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_doma.
    DATA(lv_q) = lcl_util=>quote( iv_name ).
    DATA(lv_l) = lcl_util=>quote( CONV string( sy-langu ) ).
    io_md->h2( `Dictionary definition` ).
    dump_tab( io_md = io_md iv_table = `DD01V` iv_where = |DOMNAME = { lv_q } AND DDLANGUAGE = { lv_l }| iv_title = `Domain (DD01V)` ).
    dump_tab( io_md = io_md iv_table = `DD07V` iv_where = |DOMNAME = { lv_q } AND DDLANGUAGE = { lv_l }| iv_title = `Fixed values (DD07V)` iv_as_table = abap_true ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_ttyp.
    DATA(lv_q) = lcl_util=>quote( iv_name ).
    io_md->h2( `Dictionary definition` ).
    dump_tab( io_md = io_md iv_table = `DD40V` iv_where = |TYPENAME = { lv_q } AND DDLANGUAGE = { lcl_util=>quote( CONV string( sy-langu ) ) }| iv_title = `Table type (DD40V)` ).
    dump_tab( io_md = io_md iv_table = `DD42S` iv_where = |TYPENAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Key fields (DD42S)` iv_as_table = abap_true ).
    SELECT SINGLE rowtype FROM dd40l WHERE typename = @iv_name AND as4local = 'A' INTO @DATA(lv_rowtype).
    IF sy-subrc = 0.
      queue_ddic( iv_name = CONV #( lv_rowtype ) iv_reason = |line type of table type { iv_name }| ).
    ENDIF.
    dump_tab( io_md = io_md iv_table = `DD43V` iv_where = |TYPENAME = { lv_q }| iv_title = `Secondary keys (DD43V)` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_shlp.
    DATA(lv_q) = lcl_util=>quote( iv_name ).
    io_md->h2( `Dictionary definition` ).
    dump_tab( io_md = io_md iv_table = `DD30V` iv_where = |SHLPNAME = { lv_q } AND DDLANGUAGE = { lcl_util=>quote( CONV string( sy-langu ) ) }| iv_title = `Search help (DD30V)` ).
    dump_tab( io_md = io_md iv_table = `DD31S` iv_where = |SHLPNAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Included search helps (DD31S)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `DD32S` iv_where = |SHLPNAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Parameters (DD32S)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `DD33S` iv_where = |SHLPNAME = { lv_q } AND AS4LOCAL = 'A'| iv_title = `Parameter assignments (DD33S)` iv_as_table = abap_true ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_type.
    io_md->h2( `Type group source` ).
    source_block( iv_prog = |%_C{ iv_name }| iv_title = |%_C{ iv_name }| io_md = io_md ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_msag.
    DATA lv_arbgb TYPE arbgb.
    lv_arbgb = iv_name.

    io_md->h2( `Message class` ).
    dump_tab( io_md = io_md iv_table = `T100A` iv_where = |ARBGB = { lcl_util=>quote( iv_name ) }| ).

    SELECT msgnr, sprsl, text FROM t100
      WHERE arbgb = @lv_arbgb
      ORDER BY msgnr, sprsl
      INTO TABLE @DATA(lt_t100).
    io_md->h3( |Messages ({ lines( lt_t100 ) } texts, all languages)| ).
    io_md->add( `| No | Lang | Text |` ).
    io_md->add( `| --- | --- | --- |` ).
    LOOP AT lt_t100 INTO DATA(ls_t100).
      io_md->add( |\| { ls_t100-msgnr } \| { ls_t100-sprsl } \| { lcl_util=>oneline( CONV string( ls_t100-text ) ) } \|| ).
    ENDLOOP.

    dump_tab( io_md = io_md iv_table = `T100U` iv_where = |ARBGB = { lcl_util=>quote( iv_name ) }|
              iv_title = `Last change / self-explanatory flag (T100U)` iv_as_table = abap_true ).

    " long texts: DOKHL object = message class (20 chars) + number
    IF ms_opt-docu = abap_true.
      docu( iv_name = iv_name iv_pattern = lcl_util=>pad_pattern( iv_val = iv_name iv_len = 20 ) io_md = io_md ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_tran.
    DATA(lv_q) = lcl_util=>quote( iv_name ).
    io_md->h2( `Transaction` ).
    dump_tab( io_md = io_md iv_table = `TSTC`  iv_where = |TCODE = { lv_q }| iv_title = `Definition (TSTC)` ).
    dump_tab( io_md = io_md iv_table = `TSTCT` iv_where = |TCODE = { lv_q }| iv_title = `Texts (TSTCT)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `TSTCP` iv_where = |TCODE = { lv_q }| iv_title = `Parameters (TSTCP)` ).
    dump_tab( io_md = io_md iv_table = `TSTCA` iv_where = |TCODE = { lv_q }| iv_title = `Authorization values (TSTCA)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `TSTCC` iv_where = |TCODE = { lv_q }| iv_title = `GUI attributes (TSTCC)` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_sobj.
    FIELD-SYMBOLS <lt_tab> TYPE STANDARD TABLE.

    io_md->h2( `BOR object type` ).
    DATA(lr_tojtb) = lcl_util=>generic_select( iv_table = 'TOJTB' iv_where = |NAME = { lcl_util=>quote( iv_name ) }| ).
    io_md->rows( ir_tab = lr_tojtb iv_title = `Header (TOJTB)` ).

    " the BOR implementation program
    IF ms_opt-src = abap_true AND lcl_util=>has_rows( lr_tojtb ) = abap_true.
      ASSIGN lr_tojtb->* TO <lt_tab>.
      READ TABLE <lt_tab> ASSIGNING FIELD-SYMBOL(<ls_row>) INDEX 1.
      DATA(lv_prog) = lcl_util=>fv( is_row = <ls_row> iv_field = 'PROGNAME' ).
      IF lv_prog IS NOT INITIAL.
        io_md->h2( |Implementation program { lv_prog }| ).
        source_block( iv_prog = lv_prog iv_title = lv_prog io_md = io_md ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_wf.
    " PDTS / PDWS: TS90000001 / WS90000001 or the number only
    DATA lv_otype TYPE string.
    DATA lv_objid TYPE string.
    DATA lt_names TYPE lcl_util=>ty_t_string.
    DATA lt_tabs  TYPE ty_t_reftab.
    FIELD-SYMBOLS <lt_found> TYPE ANY TABLE.

    IF strlen( iv_name ) > 2 AND iv_name(2) CO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.
      lv_otype = iv_name(2).
      lv_objid = substring( val = iv_name off = 2 ).
    ELSE.
      lv_otype = COND #( WHEN iv_type = `PDWS` THEN `WS` ELSE `TS` ).
      lv_objid = iv_name.
    ENDIF.

    " ---- task / workflow object (HRS1000 texts, HRS1201 method binding,
    "      HRS1205 container ...)
    DATA(lv_found) = abap_false.
    LOOP AT discover( iv_pattern = `HRS1%` iv_field = `OBJID` ) INTO DATA(lv_tab).
      DATA(lr_tab) = lcl_util=>generic_select(
                       iv_table = lv_tab
                       iv_where = |OTYPE = { lcl_util=>quote( lv_otype ) } AND OBJID = { lcl_util=>quote( lv_objid ) }|
                       iv_max   = ms_opt-maxr ).
      IF lcl_util=>has_rows( lr_tab ) = abap_true.
        IF lv_found = abap_false.
          io_md->h2( |Workflow object { lv_otype } { lv_objid } (HRS1* tables: texts, method binding, container, ...)| ).
          lv_found = abap_true.
        ENDIF.
        io_md->rows( ir_tab = lr_tab iv_title = lv_tab ).
        ASSIGN lr_tab->* TO <lt_found>.
        scan_names( EXPORTING iv_data = <lt_found> CHANGING ct_names = lt_names ).
      ENDIF.
    ENDLOOP.

    " ---- workflow definition (latest version only) ------------------------
    IF lv_otype = `WS`.
      DATA(lv_wfd) = |WS{ lv_objid }|.
      LOOP AT discover( iv_pattern = `SWD%` iv_field = `WFD_ID` ) INTO lv_tab.
        lr_tab = lcl_util=>select_by_field( iv_table = lv_tab iv_field = `WFD_ID` iv_value = lv_wfd iv_ordered = abap_true ).
        IF lcl_util=>has_rows( lr_tab ) = abap_true.
          keep_latest( lr_tab ).
          APPEND VALUE #( tabname = lv_tab ref = lr_tab ) TO lt_tabs.
        ENDIF.
      ENDLOOP.

      IF lt_tabs IS NOT INITIAL.
        io_md->h2( |Workflow definition { lv_wfd } (latest version)| ).
        wf_diagram( it_tabs = lt_tabs io_md = io_md ).
        LOOP AT lt_tabs INTO DATA(ls_tabs).
          io_md->rows( ir_tab = ls_tabs-ref iv_title = |{ ls_tabs-tabname } (workflow definition)| ).
          ASSIGN ls_tabs-ref->* TO <lt_found>.
          scan_names( EXPORTING iv_data = <lt_found> CHANGING ct_names = lt_names ).
        ENDLOOP.
      ENDIF.
    ENDIF.

    " workflow classes (IF_WORKFLOW) and BOR objects used by the steps
    queue_refs( it_names  = lt_names
                iv_reason = |used by workflow { lv_otype } { lv_objid }|
                io_md     = io_md
                iv_title  = `Classes, interfaces and BOR objects used by this workflow / task` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_enho.
    DATA lt_trdir TYPE STANDARD TABLE OF trdir WITH EMPTY KEY.

    IF ms_opt-src = abap_false.
      RETURN.
    ENDIF.
    " enhancement implementation includes <ENHNAME>======...E / ...
    DATA(lv_pat) = |{ lcl_util=>like_escape( lcl_util=>pool_prefix( iv_name ) ) }%|.
    SELECT * FROM trdir WHERE name LIKE @lv_pat ESCAPE '#' ORDER BY name INTO TABLE @lt_trdir.
    IF lt_trdir IS NOT INITIAL.
      io_md->h2( `Enhancement implementation source` ).
      LOOP AT lt_trdir INTO DATA(ls_trdir).
        source_block( iv_prog = CONV #( ls_trdir-name ) iv_title = CONV #( ls_trdir-name ) io_md = io_md iv_quiet = abap_true ).
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD bopf_collect.
    " business objects of the package: TADIR BOBF + constants interfaces
    DATA lt_src TYPE lcl_util=>ty_t_string.
    DATA lv_ok  TYPE abap_bool.
    DATA lv_key TYPE /bobf/obm_bo_key.
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <lv_key> TYPE any.

    LOOP AT mt_tadir INTO DATA(ls_tadir) WHERE object = 'BOBF'.
      DATA(lr_obj) = lcl_util=>select_by_field( iv_table = '/BOBF/OBM_OBJ' iv_field = 'NAME'
                                                iv_value = CONV string( ls_tadir-obj_name ) iv_max = 1 ).
      IF lcl_util=>has_rows( lr_obj ) = abap_true.
        ASSIGN lr_obj->* TO <lt_tab>.
        READ TABLE <lt_tab> ASSIGNING FIELD-SYMBOL(<ls_obj>) INDEX 1.
        ASSIGN COMPONENT 'BO_KEY' OF STRUCTURE <ls_obj> TO <lv_key>.
        IF sy-subrc = 0.
          lv_key = <lv_key>.
          APPEND VALUE #( name = ls_tadir-obj_name bo_key = lv_key ) TO mt_bo.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " generated constants interfaces: SC_BO_KEY ... VALUE '<hex>'
    LOOP AT mt_tadir INTO ls_tadir WHERE object = 'INTF'.
      lcl_util=>read_source( EXPORTING iv_prog = lcl_util=>pool_prefix( ls_tadir-obj_name ) && `IU`
                             IMPORTING et_src = lt_src ev_ok = lv_ok ).
      IF lv_ok = abap_false.
        CONTINUE.
      ENDIF.
      LOOP AT lt_src INTO DATA(lv_line).
        DATA(lv_upper) = to_upper( lv_line ).
        IF lv_upper NS 'SC_BO_KEY' OR lv_upper NS '/BOBF/OBM_BO_KEY'.
          CONTINUE.
        ENDIF.
        DATA lv_value TYPE string.
        FIND REGEX `VALUE\s*'([0-9A-Fa-f]{32})'` IN lv_line IGNORING CASE SUBMATCHES lv_value.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        TRY.
            lv_key = to_upper( lv_value ).
          CATCH cx_root.
            CONTINUE.
        ENDTRY.
        IF line_exists( mt_bo[ bo_key = lv_key ] ).
          CONTINUE.
        ENDIF.
        DATA lv_bo_name TYPE /bobf/obm_name.
        TRY.
            lv_bo_name = /bobf/cl_frw_factory=>get_bo_name( iv_bo_key = lv_key ).
          CATCH cx_root.
            CLEAR lv_bo_name.
        ENDTRY.
        IF lv_bo_name IS INITIAL.
          lv_bo_name = ls_tadir-obj_name.
        ENDIF.
        APPEND VALUE #( name = lv_bo_name bo_key = lv_key ) TO mt_bo.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_bobf.
    " Complete BOPF business object:
    "  1. every row of every /BOBF/ table that has a BO_KEY field
    "  2. runtime configuration: every GET method and public attribute
    "     of the configuration object (/BOBF/IF_FRW_CONFIGURATION)
    "  3. implementing classes / interfaces (extracted as well)
    DATA lo_conf   TYPE REF TO /bobf/if_frw_configuration.
    DATA lt_names  TYPE lcl_util=>ty_t_string.
    DATA lt_ptab   TYPE abap_parmbind_tab.
    DATA lt_etab   TYPE abap_excpbind_tab.
    DATA lr_value  TYPE REF TO data.
    DATA lo_cdescr TYPE REF TO cl_abap_classdescr.
    DATA lo_ptype  TYPE REF TO cl_abap_datadescr.
    FIELD-SYMBOLS: <lt_tab> TYPE ANY TABLE,
                   <lv_val> TYPE any.

    DATA(lo_md) = NEW lcl_md( ).
    DATA(ls_tadir) = is_tadir.
    IF ls_tadir-obj_name IS INITIAL.
      ls_tadir-obj_name = iv_name.
    ENDIF.
    DATA(lv_descr) = |BOPF business object { iv_name }|.
    header( is_tadir = ls_tadir io_md = lo_md iv_descr = lv_descr ).
    lo_md->kv( iv_key = `BO key` iv_val = |{ iv_key }| ).

    " ---- 1. repository rows --------------------------------------------
    lo_md->h2( `BOPF repository (every /BOBF/ table row with this BO key)` ).
    lo_md->add( `Nodes, associations, actions, determinations, validations, queries, alternative keys, ` &&
                `status, authorization checks etc. - with all configuration values.` ).
    LOOP AT discover( iv_pattern = `/BOBF/%` iv_field = `BO_KEY` ) INTO DATA(lv_table).
      DATA(lr_rows) = lcl_util=>select_by_field( iv_table = lv_table iv_field = `BO_KEY`
                                                 iv_value = iv_key iv_max = ms_opt-maxr ).
      IF lcl_util=>has_rows( lr_rows ) = abap_true.
        lo_md->rows( ir_tab = lr_rows iv_title = lv_table ).
        ASSIGN lr_rows->* TO <lt_tab>.
        scan_names( EXPORTING iv_data = <lt_tab> CHANGING ct_names = lt_names ).
      ENDIF.
    ENDLOOP.

    " ---- 2. runtime configuration ---------------------------------------
    lo_md->h2( `Runtime configuration (/BOBF/IF_FRW_CONFIGURATION)` ).
    TRY.
        lo_conf = /bobf/cl_frw_factory=>get_configuration( iv_bo_key = iv_key ).
      CATCH cx_root INTO DATA(lx_conf).
        err( iv_type = `BOBF` iv_name = iv_name iv_area = `CONFIGURATION` iv_msg = lx_conf->get_text( ) ).
    ENDTRY.

    IF lo_conf IS BOUND.
      " generic object reference: dynamic access uses the dynamic type
      DATA lo_any TYPE REF TO object.
      lo_any = lo_conf.
      lo_cdescr ?= cl_abap_typedescr=>describe_by_object_ref( lo_any ).

      " public attributes
      LOOP AT lo_cdescr->attributes INTO DATA(ls_attr) WHERE visibility = cl_abap_objectdescr=>public.
        TRY.
            ASSIGN lo_any->(ls_attr-name) TO <lv_val>.
            IF sy-subrc = 0 AND <lv_val> IS NOT INITIAL.
              lo_md->dump( iv_data = <lv_val> iv_name = CONV #( ls_attr-name ) ).
              scan_names( EXPORTING iv_data = <lv_val> CHANGING ct_names = lt_names ).
            ENDIF.
          CATCH cx_root.
        ENDTRY.
      ENDLOOP.

      " every GET method without importing parameters (pure getters -
      " nothing is called that needs a key and could fail an assertion)
      LOOP AT lo_cdescr->methods INTO DATA(ls_meth)
           WHERE visibility = cl_abap_objectdescr=>public.
        DATA(lv_mname) = CONV string( ls_meth-name ).
        IF NOT ( lv_mname CP 'GET*' OR lv_mname CP '*~GET*' ).
          CONTINUE.
        ENDIF.

        CLEAR: lt_ptab, lt_etab.
        DATA(lv_callable) = abap_true.
        LOOP AT ls_meth-parameters INTO DATA(ls_parm).
          IF ls_parm-parm_kind = cl_abap_objectdescr=>importing.
            lv_callable = abap_false.
            EXIT.
          ENDIF.
          TRY.
              lo_cdescr->get_method_parameter_type(
                EXPORTING  p_method_name    = ls_meth-name
                           p_parameter_name = ls_parm-name
                RECEIVING  p_descr_ref      = lo_ptype
                EXCEPTIONS OTHERS           = 1 ).
              IF sy-subrc <> 0.
                lv_callable = abap_false.
                EXIT.
              ENDIF.
              CREATE DATA lr_value TYPE HANDLE lo_ptype.
            CATCH cx_root.
              lv_callable = abap_false.
              EXIT.
          ENDTRY.
          INSERT VALUE #( name  = ls_parm-name
                          kind  = SWITCH #( ls_parm-parm_kind
                                    WHEN cl_abap_objectdescr=>exporting THEN cl_abap_objectdescr=>importing
                                    WHEN cl_abap_objectdescr=>returning THEN cl_abap_objectdescr=>receiving
                                    ELSE cl_abap_objectdescr=>changing )
                          value = lr_value ) INTO TABLE lt_ptab.
        ENDLOOP.
        IF lv_callable = abap_false OR lt_ptab IS INITIAL.
          CONTINUE.
        ENDIF.
        IF ls_meth-exceptions IS NOT INITIAL AND
           lcl_util=>fv( is_row = ls_meth iv_field = 'IS_RAISING_EXCPS' ) <> abap_true.
          INSERT VALUE #( name = 'OTHERS' value = 99 ) INTO TABLE lt_etab.
        ENDIF.

        TRY.
            IF lt_etab IS INITIAL.
              CALL METHOD lo_any->(lv_mname) PARAMETER-TABLE lt_ptab.
            ELSE.
              CALL METHOD lo_any->(lv_mname) PARAMETER-TABLE lt_ptab EXCEPTION-TABLE lt_etab.
            ENDIF.
          CATCH cx_root.
            CONTINUE.
        ENDTRY.

        LOOP AT lt_ptab INTO DATA(ls_ptab).
          ASSIGN ls_ptab-value->* TO <lv_val>.
          IF sy-subrc = 0 AND <lv_val> IS NOT INITIAL.
            lo_md->dump( iv_data = <lv_val> iv_name = |{ to_lower( lv_mname ) } -> { to_lower( ls_ptab-name ) }| ).
            scan_names( EXPORTING iv_data = <lv_val> CHANGING ct_names = lt_names ).
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDIF.

    " ---- 3. implementing classes / interfaces ----------------------------
    queue_refs( it_names  = lt_names
                iv_reason = |used by BOPF business object { iv_name }|
                io_md     = lo_md
                iv_title  = `Implementing classes and interfaces (determinations, validations, actions, ...)` ).

    mo_writer->add_doc( iv_type = `BOBF` iv_name = iv_name iv_descr = lv_descr io_md = lo_md ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD queue_ext.
    " depth 1 = used directly by a package object, 2 = used by such an
    " object, ... ; standard SAP objects only with 'Incl. standard'
    DATA(lv_key) = |{ iv_type } { iv_name }|.
    IF iv_name IS INITIAL OR
       mv_depth + 1 > ms_opt-ldepth OR
       allowed( iv_name ) = abap_false OR
       line_exists( mt_inpack[ table_line = lv_key ] ) OR
       line_exists( mt_extkey[ table_line = lv_key ] ).
      RETURN.
    ENDIF.
    IF lines( mt_extq ) >= ms_opt-extmax.
      IF mv_ext_full = abap_false.
        mv_ext_full = abap_true.
        err( iv_type = `*` iv_name = `*` iv_area = `EXTERNAL`
             iv_msg = |Maximum of { ms_opt-extmax } objects outside the package reached - further references not extracted| ).
      ENDIF.
      RETURN.
    ENDIF.
    INSERT lv_key INTO TABLE mt_extkey.
    APPEND VALUE #( otype  = iv_type
                    name   = iv_name
                    reason = |{ iv_reason } (reference depth { mv_depth + 1 })|
                    depth  = mv_depth + 1 ) TO mt_extq.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD allowed.
    rv = xsdbool( ms_opt-std = abap_true OR is_customer( iv_name ) = abap_true ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD queue_name.
    iv_name = to_upper( condense( iv_name ) ).
    IF iv_name IS INITIAL OR iv_name(1) = '\'.
      RETURN.                                     " local / program-internal type
    ENDIF.
    IF iv_name CS '\'.
      SPLIT iv_name AT '\' INTO DATA(lv_head) DATA(lv_rest).
      iv_name = lv_head.
    ENDIF.
    IF iv_name CS '=>'.
      SPLIT iv_name AT '=>' INTO lv_head lv_rest.
      iv_name = lv_head.
    ENDIF.
    IF strlen( iv_name ) > 30.
      RETURN.
    ENDIF.
    DATA lv_cls TYPE seoclsname.
    lv_cls = iv_name.
    SELECT SINGLE clstype FROM seoclass WHERE clsname = @lv_cls INTO @DATA(lv_clstype).
    IF sy-subrc = 0.
      IF ms_opt-ext = abap_true.
        queue_ext( iv_type = COND #( WHEN lv_clstype = '1' THEN `INTF` ELSE `CLAS` )
                   iv_name = iv_name iv_reason = iv_reason ).
      ENDIF.
      RETURN.
    ENDIF.
    queue_ddic( iv_name = iv_name iv_reason = iv_reason ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD queue_refs.
    " names -> existing classes / interfaces (SEOCLASS) and BOR object
    " types (TOJTB); listed in the document, queued for extraction
    DATA lt_cls TYPE STANDARD TABLE OF seoclsname WITH EMPTY KEY.
    DATA lt_bor TYPE lcl_util=>ty_t_string.

    DATA(lt_names) = it_names.
    SORT lt_names.
    DELETE ADJACENT DUPLICATES FROM lt_names.
    LOOP AT lt_names INTO DATA(lv_name).
      IF lv_name IS NOT INITIAL AND strlen( lv_name ) <= 30 AND lv_name NS ` `.
        APPEND CONV seoclsname( lv_name ) TO lt_cls.
      ENDIF.
    ENDLOOP.
    IF lt_cls IS INITIAL.
      RETURN.
    ENDIF.

    SELECT clsname, clstype FROM seoclass
      FOR ALL ENTRIES IN @lt_cls
      WHERE clsname = @lt_cls-table_line
      INTO TABLE @DATA(lt_exist).
    SORT lt_exist BY clsname.

    LOOP AT lt_cls INTO DATA(lv_cls).
      IF line_exists( lt_exist[ clsname = lv_cls ] ).
        CONTINUE.
      ENDIF.
      IF lcl_util=>has_rows( lcl_util=>select_by_field( iv_table = 'TOJTB' iv_field = 'NAME'
                                                        iv_value = CONV string( lv_cls ) iv_max = 1 ) ) = abap_true.
        APPEND CONV string( lv_cls ) TO lt_bor.
      ENDIF.
    ENDLOOP.

    IF lt_exist IS INITIAL AND lt_bor IS INITIAL.
      RETURN.
    ENDIF.

    IF io_md IS BOUND.
      io_md->h2( |{ iv_title } ({ lines( lt_exist ) + lines( lt_bor ) })| ).
    ENDIF.

    LOOP AT lt_exist INTO DATA(ls_exist).
      DATA(lv_otype) = COND string( WHEN ls_exist-clstype = '1' THEN `INTF` ELSE `CLAS` ).
      DATA(lv_in)    = xsdbool( line_exists( mt_inpack[ table_line = |{ lv_otype } { ls_exist-clsname }| ] ) ).
      IF lv_in = abap_false AND ms_opt-ext = abap_true.
        queue_ext( iv_type = lv_otype iv_name = CONV #( ls_exist-clsname ) iv_reason = iv_reason ).
      ENDIF.
      IF io_md IS BOUND.
        io_md->add( |- { ls_exist-clsname } ({ lv_otype }{ COND string( WHEN lv_in = abap_false THEN `, outside the package` ) }) -> | &&
                    |{ COND string( WHEN lv_in = abap_true OR ms_opt-ext = abap_true
                                    THEN |`{ mo_writer->doc_path( iv_type = lv_otype iv_name = CONV #( ls_exist-clsname ) ) }`|
                                    ELSE `(not extracted)` ) }| ).
      ENDIF.
    ENDLOOP.

    LOOP AT lt_bor INTO DATA(lv_bor).
      DATA(lv_bin) = xsdbool( line_exists( mt_inpack[ table_line = |SOBJ { lv_bor }| ] ) ).
      IF lv_bin = abap_false AND ms_opt-ext = abap_true.
        queue_ext( iv_type = `SOBJ` iv_name = lv_bor iv_reason = iv_reason ).
      ENDIF.
      IF io_md IS BOUND.
        io_md->add( |- { lv_bor } (BOR object type{ COND string( WHEN lv_bin = abap_false THEN `, outside the package` ) }) -> | &&
                    |{ COND string( WHEN lv_bin = abap_true OR ms_opt-ext = abap_true
                                    THEN |`{ mo_writer->doc_path( iv_type = `SOBJ` iv_name = lv_bor ) }`|
                                    ELSE `(not extracted)` ) }| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD is_customer.
    rv = abap_false.
    IF iv_name IS INITIAL.
      RETURN.
    ENDIF.
    IF iv_name CP 'Z*' OR iv_name CP 'Y*'.
      rv = abap_true.
      RETURN.
    ENDIF.
    LOOP AT mt_ns INTO DATA(lv_ns).
      IF strlen( iv_name ) > strlen( lv_ns ) AND
         to_upper( substring( val = iv_name len = strlen( lv_ns ) ) ) = to_upper( lv_ns ).
        rv = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD queue_ddic.
    " customer data elements / structures / tables / table types /
    " domains used by the package but defined in another package
    DATA lv_tab TYPE tabname.

    IF ms_opt-extd = abap_false OR ms_opt-ddic = abap_false.
      RETURN.
    ENDIF.
    iv_name = to_upper( iv_name ).
    IF iv_name CS '=>' OR iv_name CS '\'.
      RETURN.
    ENDIF.
    IF iv_name CS '-'.                          " ZTABLE-FIELD -> ZTABLE
      SPLIT iv_name AT '-' INTO DATA(lv_head) DATA(lv_rest).
      iv_name = lv_head.
    ENDIF.
    IF allowed( iv_name ) = abap_false OR strlen( iv_name ) > 30.
      RETURN.
    ENDIF.
    IF line_exists( mt_extkey[ table_line = |DTEL { iv_name }| ] ) OR
       line_exists( mt_extkey[ table_line = |TABL { iv_name }| ] ) OR
       line_exists( mt_extkey[ table_line = |TTYP { iv_name }| ] ) OR
       line_exists( mt_extkey[ table_line = |VIEW { iv_name }| ] ) OR
       line_exists( mt_extkey[ table_line = |DOMA { iv_name }| ] ).
      RETURN.
    ENDIF.

    lv_tab = iv_name.
    SELECT SINGLE rollname FROM dd04l WHERE rollname = @lv_tab AND as4local = 'A' INTO @DATA(lv_dtel).
    IF sy-subrc = 0.
      queue_ext( iv_type = `DTEL` iv_name = iv_name iv_reason = iv_reason ).
      RETURN.
    ENDIF.
    SELECT SINGLE tabclass FROM dd02l WHERE tabname = @lv_tab AND as4local = 'A' INTO @DATA(lv_tabclass).
    IF sy-subrc = 0.
      queue_ext( iv_type = COND #( WHEN lv_tabclass = 'VIEW' THEN `VIEW` ELSE `TABL` )
                 iv_name = iv_name iv_reason = iv_reason ).
      RETURN.
    ENDIF.
    SELECT SINGLE typename FROM dd40l WHERE typename = @lv_tab AND as4local = 'A' INTO @DATA(lv_ttyp).
    IF sy-subrc = 0.
      queue_ext( iv_type = `TTYP` iv_name = iv_name iv_reason = iv_reason ).
      RETURN.
    ENDIF.
    SELECT SINGLE domname FROM dd01l WHERE domname = @lv_tab AND as4local = 'A' INTO @DATA(lv_doma).
    IF sy-subrc = 0.
      queue_ext( iv_type = `DOMA` iv_name = iv_name iv_reason = iv_reason ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD keep_latest.
    " keep only the rows of the highest VERSION (workflow definitions)
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <lt_new> TYPE STANDARD TABLE,
                   <ls_row> TYPE any.
    DATA lr_new TYPE REF TO data.
    DATA lv_max TYPE string.

    ASSIGN ir_tab->* TO <lt_tab>.
    LOOP AT <lt_tab> ASSIGNING <ls_row>.
      DATA(lv_ver) = lcl_util=>fv( is_row = <ls_row> iv_field = 'VERSION' ).
      IF lv_ver IS INITIAL.
        RETURN.                                  " table has no versions
      ENDIF.
      lv_ver = |{ lv_ver ALIGN = RIGHT WIDTH = 12 PAD = '0' }|.
      IF lv_ver > lv_max.
        lv_max = lv_ver.
      ENDIF.
    ENDLOOP.

    CREATE DATA lr_new LIKE <lt_tab>.
    ASSIGN lr_new->* TO <lt_new>.
    LOOP AT <lt_tab> ASSIGNING <ls_row>.
      lv_ver = lcl_util=>fv( is_row = <ls_row> iv_field = 'VERSION' ).
      IF |{ lv_ver ALIGN = RIGHT WIDTH = 12 PAD = '0' }| = lv_max.
        APPEND <ls_row> TO <lt_new>.
      ENDIF.
    ENDLOOP.
    <lt_tab> = <lt_new>.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD wf_diagram.
    " Mermaid flow chart from the workflow definition tables: the step
    " table is the one with NODEID + a text field, the connection table
    " the one with a *PRED* and a *SUCC* field.
    TYPES: BEGIN OF ty_s_node,
             id   TYPE string,
             text TYPE string,
           END OF ty_s_node.
    TYPES: BEGIN OF ty_s_edge,
             efrom TYPE string,
             eto   TYPE string,
           END OF ty_s_edge.
    DATA lt_node  TYPE SORTED TABLE OF ty_s_node WITH UNIQUE KEY id.
    DATA lt_edge  TYPE SORTED TABLE OF ty_s_edge WITH UNIQUE KEY efrom eto.
    DATA lt_lines TYPE lcl_util=>ty_t_string.
    DATA lo_table TYPE REF TO cl_abap_tabledescr.
    DATA lo_line  TYPE REF TO cl_abap_structdescr.
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <ls_row> TYPE any.

    LOOP AT it_tabs INTO DATA(ls_tab).
      ASSIGN ls_tab-ref->* TO <lt_tab>.
      TRY.
          lo_table ?= cl_abap_typedescr=>describe_by_data( <lt_tab> ).
          lo_line  ?= lo_table->get_table_line_type( ).
        CATCH cx_root.
          CONTINUE.
      ENDTRY.

      DATA(lv_text_f) = ``.
      DATA(lv_pred_f) = ``.
      DATA(lv_succ_f) = ``.
      DATA(lv_has_node) = abap_false.
      LOOP AT lo_line->components INTO DATA(ls_comp).
        DATA(lv_c) = CONV string( ls_comp-name ).
        IF lv_c = `NODEID`.
          lv_has_node = abap_true.
        ENDIF.
        IF lv_text_f IS INITIAL AND ( lv_c = `DESCRIPT` OR lv_c = `DESCRIPTION` OR lv_c = `SHORTTEXT` OR
                                      lv_c = `STEPTEXT` OR lv_c = `TEXT` OR lv_c = `DESCR` ).
          lv_text_f = lv_c.
        ENDIF.
        IF lv_pred_f IS INITIAL AND lv_c CS 'PRED'.
          lv_pred_f = lv_c.
        ENDIF.
        IF lv_succ_f IS INITIAL AND lv_c CS 'SUCC'.
          lv_succ_f = lv_c.
        ENDIF.
      ENDLOOP.

      LOOP AT <lt_tab> ASSIGNING <ls_row>.
        IF lv_has_node = abap_true AND lv_text_f IS NOT INITIAL.
          DATA(lv_id) = lcl_util=>fv( is_row = <ls_row> iv_field = 'NODEID' ).
          DATA(lv_tx) = lcl_util=>fv( is_row = <ls_row> iv_field = lv_text_f ).
          IF lv_id IS NOT INITIAL AND lv_tx IS NOT INITIAL AND NOT line_exists( lt_node[ id = lv_id ] ).
            INSERT VALUE #( id = lv_id text = lv_tx ) INTO TABLE lt_node.
          ENDIF.
        ENDIF.
        IF lv_pred_f IS NOT INITIAL AND lv_succ_f IS NOT INITIAL.
          DATA(lv_from) = lcl_util=>fv( is_row = <ls_row> iv_field = lv_pred_f ).
          DATA(lv_to)   = lcl_util=>fv( is_row = <ls_row> iv_field = lv_succ_f ).
          IF lv_from IS NOT INITIAL AND lv_to IS NOT INITIAL AND lines( lt_edge ) < 3000.
            INSERT VALUE #( efrom = lv_from eto = lv_to ) INTO TABLE lt_edge.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    IF lt_node IS NOT INITIAL.
      io_md->h3( |Steps ({ lines( lt_node ) })| ).
      io_md->add( `| Node | Step |` ).
      io_md->add( `| --- | --- |` ).
      LOOP AT lt_node INTO DATA(ls_node).
        io_md->add( |\| { ls_node-id } \| { lcl_util=>oneline( ls_node-text ) } \|| ).
      ENDLOOP.
    ENDIF.

    IF lt_edge IS INITIAL.
      RETURN.
    ENDIF.

    APPEND |```mermaid| TO lt_lines.
    APPEND `flowchart TD` TO lt_lines.
    LOOP AT lt_node INTO ls_node.
      DATA(lv_label) = |{ ls_node-id } { ls_node-text }|.
      REPLACE ALL OCCURRENCES OF REGEX `["\[\]\(\)\{\}<>|]` IN lv_label WITH ` `.
      APPEND |  N{ ls_node-id }["{ lv_label }"]| TO lt_lines.
    ENDLOOP.
    LOOP AT lt_edge INTO DATA(ls_edge).
      APPEND |  N{ ls_edge-efrom } --> N{ ls_edge-eto }| TO lt_lines.
    ENDLOOP.
    APPEND '```' TO lt_lines.

    io_md->h3( `Workflow diagram (Mermaid, generated from the definition tables - best effort)` ).
    LOOP AT lt_lines INTO DATA(lv_l).
      io_md->add( lv_l ).
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD lang_of.
    DATA lv_ext TYPE string.
    FIND REGEX `\.([A-Za-z0-9]+)$` IN iv_file SUBMATCHES lv_ext.
    rv = SWITCH #( to_lower( lv_ext )
           WHEN `js`         THEN `javascript`
           WHEN `ts`         THEN `typescript`
           WHEN `xml`        THEN `xml`
           WHEN `json`       THEN `json`
           WHEN `html` OR `htm` OR `bsp` OR `htmlb` THEN `html`
           WHEN `css` OR `less` THEN `css`
           WHEN `properties` THEN `properties`
           WHEN `md`         THEN `markdown`
           WHEN `yaml` OR `yml` THEN `yaml`
           WHEN `abap`       THEN `abap`
           ELSE `text` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_wapa.
    " BSP application / deployed UI5 (Fiori) application:
    "  1. every O2* repository table row (pages, views, controllers,
    "     navigation, attributes) - page / layout / event handler code
    "     reconstructed from O2PAGCON
    "  2. every text file of the application in the MIME repository
    "     (UI5: Component.js, manifest.json, controllers, views,
    "     fragments, i18n, css ...) - one document per file
    TYPES: BEGIN OF ty_s_grp,
             gkey  TYPE string,
             lines TYPE lcl_util=>ty_t_string,
           END OF ty_s_grp.
    DATA lt_grp   TYPE STANDARD TABLE OF ty_s_grp WITH EMPTY KEY.
    DATA lt_names TYPE lcl_util=>ty_t_string.
    DATA lt_files TYPE string_table.
    DATA lo_mr    TYPE REF TO object.
    DATA lv_x     TYPE xstring.
    DATA lv_ext   TYPE string.
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <ls_row> TYPE any,
                   <ls_grp> TYPE ty_s_grp.

    " ---- 1. BSP repository ------------------------------------------------
    io_md->h2( `BSP repository (O2* tables)` ).
    LOOP AT discover( iv_pattern = `O2%` iv_field = `APPLNAME` ) INTO DATA(lv_tab).
      DATA(lr_tab) = lcl_util=>select_by_field( iv_table = lv_tab iv_field = `APPLNAME` iv_value = iv_name
                                                iv_ordered = abap_true ).
      IF lcl_util=>has_rows( lr_tab ) = abap_false.
        CONTINUE.
      ENDIF.
      ASSIGN lr_tab->* TO <lt_tab>.
      scan_names( EXPORTING iv_data = <lt_tab> CHANGING ct_names = lt_names ).

      IF lv_tab <> `O2PAGCON`.
        io_md->rows( ir_tab = lr_tab iv_title = lv_tab ).
        CONTINUE.
      ENDIF.

      " page content: one line per row, grouped by page and part
      CLEAR lt_grp.
      LOOP AT <lt_tab> ASSIGNING <ls_row>.
        DATA(lv_version) = lcl_util=>fv( is_row = <ls_row> iv_field = 'VERSION' ).
        IF lv_version IS NOT INITIAL AND lv_version <> 'A'.
          CONTINUE.
        ENDIF.
        DATA(lv_gkey) = |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'PAGEKEY' ) } | &&
                        |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'OBJTYPE' ) }|.
        DATA(lv_line) = lcl_util=>fv( is_row = <ls_row> iv_field = 'CONTENT' ).
        IF lv_line IS INITIAL.
          lv_line = lcl_util=>fv( is_row = <ls_row> iv_field = 'LINE' ).
        ENDIF.
        READ TABLE lt_grp ASSIGNING <ls_grp> WITH KEY gkey = lv_gkey.
        IF sy-subrc <> 0.
          APPEND VALUE #( gkey = lv_gkey ) TO lt_grp ASSIGNING <ls_grp>.
        ENDIF.
        APPEND lv_line TO <ls_grp>-lines.
      ENDLOOP.
      io_md->h2( `Pages, views, controllers - layout and event handler code (O2PAGCON)` ).
      LOOP AT lt_grp ASSIGNING <ls_grp>.
        io_md->code( it_src = <ls_grp>-lines
                     iv_lang = lang_of( segment( val = condense( <ls_grp>-gkey ) index = 1 sep = ` ` ) )
                     iv_title = <ls_grp>-gkey ).
      ENDLOOP.
    ENDLOOP.

    " ---- 2. MIME repository files ----------------------------------------
    DATA(lv_ns)  = `sap`.
    DATA(lv_app) = to_lower( iv_name ).
    IF strlen( iv_name ) > 1 AND iv_name(1) = '/'.
      DATA lv_off TYPE i.
      FIND FIRST OCCURRENCE OF '/' IN SECTION OFFSET 1 OF iv_name MATCH OFFSET lv_off.
      IF sy-subrc = 0.
        lv_ns  = to_lower( substring( val = iv_name off = 1 len = lv_off - 1 ) ).
        lv_app = to_lower( substring( val = iv_name off = lv_off + 1 ) ).
      ENDIF.
    ENDIF.
    DATA(lv_base) = |/sap/bc/bsp/{ lv_ns }/{ lv_app }|.

    TRY.
        lo_mr = cl_mime_repository_api=>get_api( ).
        CALL METHOD lo_mr->('IF_MR_API~FILE_LIST')
          EXPORTING
            i_url            = lv_base
            i_recursive_call = abap_true
          IMPORTING
            e_files          = lt_files
          EXCEPTIONS
            OTHERS           = 1.
      CATCH cx_root INTO DATA(lx_mr).
        err( iv_type = `WAPA` iv_name = iv_name iv_area = `MIME` iv_msg = lx_mr->get_text( ) ).
    ENDTRY.

    IF lt_files IS INITIAL.
      io_md->h2( `Application files (MIME repository)` ).
      io_md->add( |No files found under { lv_base }.| ).
    ELSE.
      SORT lt_files.
      io_md->h2( |Application files ({ lines( lt_files ) }) under { lv_base }| ).
      LOOP AT lt_files INTO DATA(lv_file).
        DATA(lv_rel) = lv_file.
        REPLACE FIRST OCCURRENCE OF lv_base IN lv_rel WITH `` IGNORING CASE.
        CLEAR lv_ext.
        FIND REGEX `\.([A-Za-z0-9]+)$` IN lv_rel SUBMATCHES lv_ext.
        lv_ext = to_lower( lv_ext ).

        " binary files and generated bundles: listed only
        IF lv_ext = `png` OR lv_ext = `jpg` OR lv_ext = `jpeg` OR lv_ext = `gif` OR lv_ext = `ico` OR
           lv_ext = `bmp` OR lv_ext = `woff` OR lv_ext = `woff2` OR lv_ext = `ttf` OR lv_ext = `eot` OR
           lv_ext = `otf` OR lv_ext = `zip` OR lv_ext = `pdf` OR lv_ext = `map` OR lv_ext IS INITIAL OR
           lv_rel CP '*Component-preload.js' OR lv_rel CP '*-dbg.js'.
          io_md->add( |- `{ lv_rel }` (binary / generated - not exported)| ).
          CONTINUE.
        ENDIF.

        CLEAR lv_x.
        TRY.
            CALL METHOD lo_mr->('IF_MR_API~GET')
              EXPORTING
                i_url     = lv_file
              IMPORTING
                e_content = lv_x
              EXCEPTIONS
                OTHERS    = 1.
          CATCH cx_root.
            CLEAR lv_x.
        ENDTRY.
        IF lv_x IS INITIAL.
          io_md->add( |- `{ lv_rel }` (empty or not readable)| ).
          CONTINUE.
        ENDIF.

        DATA(lv_text) = ``.
        TRY.
            lv_text = cl_abap_codepage=>convert_from( source = lv_x ).
          CATCH cx_root.
            io_md->add( |- `{ lv_rel }` (not UTF-8 text - not exported)| ).
            CONTINUE.
        ENDTRY.

        DATA(lv_docname) = |{ iv_name }{ lv_rel }|.
        DATA(lo_file) = NEW lcl_md( ).
        lo_file->h1( |WAPA { iv_name } - { lv_rel }| ).
        lo_file->kv( iv_key = `Object type` iv_val = `WAPA - file of a BSP / UI5 application` ).
        lo_file->kv( iv_key = `Application` iv_val = |{ iv_name } -> `{ mo_writer->doc_path( iv_type = `WAPA` iv_name = iv_name ) }`| ).
        lo_file->kv( iv_key = `Package`     iv_val = CONV #( is_tadir-devclass ) ).
        lo_file->kv( iv_key = `MIME URL`    iv_val = lv_file ).
        lo_file->kv( iv_key = `Size`        iv_val = |{ xstrlen( lv_x ) } bytes| ).
        lo_file->code_string( iv_src = lv_text iv_lang = lang_of( lv_rel ) ).
        mo_writer->add_doc( iv_type = `WAPA` iv_name = lv_docname
                            iv_descr = |{ lv_rel } of application { iv_name }| io_md = lo_file ).

        io_md->add( |- `{ lv_rel }` -> `{ mo_writer->doc_path( iv_type = `WAPA` iv_name = lv_docname ) }`| ).
      ENDLOOP.
    ENDIF.

    " controller / handler classes of the application
    queue_refs( it_names  = lt_names
                iv_reason = |used by BSP application { iv_name }|
                io_md     = io_md
                iv_title  = `Controller and handler classes` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_wdyn.
    " Web Dynpro component: the generic WDY* table dump (below, in
    " x_discovery) already lists controllers, views, context, UI
    " elements, events and navigation. Here the controller / view
    " METHOD SOURCE CODE is rendered as ABAP, and the assistance class
    " and every class the component uses are queued for full source.
    DATA lt_names TYPE lcl_util=>ty_t_string.
    FIELD-SYMBOLS <lt_tab> TYPE STANDARD TABLE.

    DATA(lv_q) = lcl_util=>quote( iv_name ).

    io_md->h2( `Web Dynpro - controllers, views and method implementation` ).

    " structured overview (reliable transparent tables)
    dump_tab( io_md = io_md iv_table = `WDY_COMPONENT`  iv_where = |COMPONENT_NAME = { lv_q }|
              iv_title = `Component (WDY_COMPONENT: assistance class, interfaces ...)` ).
    dump_tab( io_md = io_md iv_table = `WDY_CONTROLLER` iv_where = |COMPONENT_NAME = { lv_q }|
              iv_title = `Controllers and views (WDY_CONTROLLER)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `WDY_CTLR_METHOD` iv_where = |COMPONENT_NAME = { lv_q }|
              iv_title = `Methods / event handlers / supply functions (WDY_CTLR_METHOD)` iv_as_table = abap_true ).
    dump_tab( io_md = io_md iv_table = `WDY_CTLR_PARAM` iv_where = |COMPONENT_NAME = { lv_q }|
              iv_title = `Method parameters (WDY_CTLR_PARAM)` iv_as_table = abap_true ).

    " method / view source code: every WDY table whose name points at a
    " controller / view / compiled source is scanned, and each readable
    " text field is rendered as an ABAP code block (release-robust: a
    " table or field that does not exist is simply skipped)
    io_md->h2( `Method and view source code` ).
    DATA(lv_any) = abap_false.
    LOOP AT discover( iv_pattern = `WDY%` iv_field = `COMPONENT_NAME` ) INTO DATA(lv_tab).
      IF lv_tab CS `CTLR` OR lv_tab CS `COMPILED` OR lv_tab CS `SOURCE` OR lv_tab CS `METHOD` OR lv_tab CS `VIEW`.
        render_code_fields( iv_table = lv_tab iv_where = |COMPONENT_NAME = { lv_q }| io_md = io_md ).
        lv_any = abap_true.
      ENDIF.
    ENDLOOP.
    IF lv_any = abap_false.
      io_md->add( `(no readable Web Dynpro source tables on this release - see the WDY* table dump below; ` &&
                  `the generated controller classes may hold the code)` ).
    ENDIF.

    " assistance class and other classes named in the component metadata
    DATA(lr_comp) = lcl_util=>generic_select( iv_table = `WDY_COMPONENT` iv_where = |COMPONENT_NAME = { lv_q }| ).
    IF lcl_util=>has_rows( lr_comp ) = abap_true.
      ASSIGN lr_comp->* TO <lt_tab>.
      scan_names( EXPORTING iv_data = <lt_tab> CHANGING ct_names = lt_names ).
    ENDIF.
    DATA(lr_use) = lcl_util=>generic_select( iv_table = `WDY_CTLR_USAGE` iv_where = |COMPONENT_NAME = { lv_q }|
                                             iv_max = ms_opt-maxr ).
    IF lcl_util=>has_rows( lr_use ) = abap_true.
      ASSIGN lr_use->* TO <lt_tab>.
      scan_names( EXPORTING iv_data = <lt_tab> CHANGING ct_names = lt_names ).
    ENDIF.
    queue_refs( it_names  = lt_names
                iv_reason = |used by Web Dynpro component { iv_name }|
                io_md     = io_md
                iv_title  = `Assistance class and classes used by the component` ).
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD render_code_fields.
    " render every readable text field of the rows as an ABAP code block
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <ls_row> TYPE any,
                   <lv_val> TYPE any.
    DATA lo_tab TYPE REF TO cl_abap_tabledescr.
    DATA lo_str TYPE REF TO cl_abap_structdescr.
    DATA lo_el  TYPE REF TO cl_abap_elemdescr.

    DATA(lr_tab) = lcl_util=>generic_select( iv_table = iv_table iv_where = iv_where iv_max = ms_opt-maxr ).
    IF lcl_util=>has_rows( lr_tab ) = abap_false.
      RETURN.
    ENDIF.
    ASSIGN lr_tab->* TO <lt_tab>.

    TRY.
        lo_tab ?= cl_abap_typedescr=>describe_by_data( <lt_tab> ).
        lo_str ?= lo_tab->get_table_line_type( ).
      CATCH cx_sy_move_cast_error.
        RETURN.
    ENDTRY.

    DATA(lv_header) = abap_false.
    LOOP AT <lt_tab> ASSIGNING <ls_row>.

      DATA(lv_key) = condense( |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'CONTROLLER_NAME' ) } | &&
                               |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'CMP_NAME' ) } | &&
                               |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'METHODNAME' ) } | &&
                               |{ lcl_util=>fv( is_row = <ls_row> iv_field = 'METHOD_NAME' ) }| ).

      LOOP AT lo_str->components INTO DATA(ls_comp).
        ASSIGN COMPONENT ls_comp-name OF STRUCTURE <ls_row> TO <lv_val>.
        IF sy-subrc <> 0 OR <lv_val> IS INITIAL.
          CONTINUE.
        ENDIF.
        TRY.
            lo_el ?= cl_abap_typedescr=>describe_by_data( <lv_val> ).
          CATCH cx_sy_move_cast_error.
            CONTINUE.
        ENDTRY.
        " a text field is a string, or a long character field
        DATA(lv_is_text) = xsdbool(
          lo_el->type_kind = cl_abap_typedescr=>typekind_string OR
          ( ( lo_el->type_kind = cl_abap_typedescr=>typekind_char OR
              lo_el->type_kind = 'g' ) AND lo_el->output_length >= 72 ) ).
        IF lv_is_text = abap_false.
          CONTINUE.
        ENDIF.

        DATA(lv_src) = lcl_util=>to_text( <lv_val> ).
        " looks like source: several lines, or clearly longer than a label
        IF lv_src NS lcl_util=>gv_nl AND strlen( lv_src ) < 120.
          CONTINUE.
        ENDIF.

        IF lv_header = abap_false.
          lv_header = abap_true.
          io_md->h3( |Source fields of { iv_table }| ).
        ENDIF.
        io_md->code_string( iv_src   = lv_src
                            iv_lang  = `abap`
                            iv_title = condense( |{ lv_key } ({ ls_comp-name })| ) ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD x_form.
    " Smart Form / Adobe form: every code node, program line,
    " initialization and global definition ends up in the generated
    " function module - its complete function group is exported
    DATA lv_fm     TYPE rs38l_fnam.
    DATA lt_trdir  TYPE STANDARD TABLE OF trdir WITH EMPTY KEY.

    IF iv_type = `SSFO`.
      DATA lv_form TYPE tdsfname.
      lv_form = iv_name.
      TRY.
          CALL FUNCTION 'SSF_FUNCTION_MODULE_NAME'
            EXPORTING
              formname = lv_form
            IMPORTING
              fm_name  = lv_fm
            EXCEPTIONS
              OTHERS   = 1.
          IF sy-subrc <> 0.
            CLEAR lv_fm.
          ENDIF.
        CATCH cx_root.
          CLEAR lv_fm.
      ENDTRY.
    ELSE.
      DATA lv_fp TYPE fpname.
      lv_fp = iv_name.
      " FP_FUNCTION_MODULE_NAME raises class-based exceptions on newer
      " releases and classic ones on older releases
      SELECT * FROM fupararef
        WHERE funcname = 'FP_FUNCTION_MODULE_NAME' AND paramtype = 'X' AND r3state = 'A'
        INTO TABLE @DATA(lt_exc).
      DATA(lv_classic) = abap_false.
      LOOP AT lt_exc INTO DATA(ls_exc).
        IF lcl_util=>fv( is_row = ls_exc iv_field = 'CLASS' ) IS INITIAL.
          lv_classic = abap_true.
        ENDIF.
      ENDLOOP.
      TRY.
          IF lv_classic = abap_true.
            CALL FUNCTION 'FP_FUNCTION_MODULE_NAME'
              EXPORTING
                i_name     = lv_fp
              IMPORTING
                e_funcname = lv_fm
              EXCEPTIONS
                OTHERS     = 1.
          ELSE.
            CALL FUNCTION 'FP_FUNCTION_MODULE_NAME'
              EXPORTING
                i_name     = lv_fp
              IMPORTING
                e_funcname = lv_fm.
          ENDIF.
        CATCH cx_root.
          CLEAR lv_fm.
      ENDTRY.
    ENDIF.

    IF lv_fm IS INITIAL.
      err( iv_type = iv_type iv_name = iv_name iv_area = `FORM`
           iv_msg = `Generated function module not found (form not activated / generated?)` ).
      RETURN.
    ENDIF.

    SELECT SINGLE pname FROM tfdir WHERE funcname = @lv_fm INTO @DATA(lv_pname).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    io_md->h2( |Generated code - function module { lv_fm } (contains every code node / program line of the form)| ).
    DATA(lv_main)   = CONV string( lv_pname ).
    DATA(lv_prefix) = lv_main.
    REPLACE FIRST OCCURRENCE OF `SAPL` IN lv_prefix WITH `L`.

    source_block( iv_prog = lv_main iv_title = lv_main io_md = io_md ).
    DATA(lv_pat) = |{ lcl_util=>like_escape( lv_prefix ) }%|.
    SELECT * FROM trdir WHERE name LIKE @lv_pat ESCAPE '#' ORDER BY name INTO TABLE @lt_trdir.
    LOOP AT lt_trdir INTO DATA(ls_trdir).
      IF strlen( ls_trdir-name ) <> strlen( lv_prefix ) + 3.
        CONTINUE.
      ENDIF.
      source_block( iv_prog = CONV #( ls_trdir-name ) iv_title = CONV #( ls_trdir-name ) io_md = io_md ).
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD scan_names.
    " collect values of components named *CLASS* / *INTERFACE* / *CLS*
    FIELD-SYMBOLS: <lt_tab> TYPE ANY TABLE,
                   <ls_row> TYPE any,
                   <lv_val> TYPE any.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.

    IF iv_depth > 6.
      RETURN.
    ENDIF.

    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( iv_data ).
    CASE lo_type->kind.
      WHEN cl_abap_typedescr=>kind_table.
        ASSIGN iv_data TO <lt_tab>.
        LOOP AT <lt_tab> ASSIGNING <ls_row>.
          scan_names( EXPORTING iv_data = <ls_row> iv_depth = iv_depth + 1 CHANGING ct_names = ct_names ).
        ENDLOOP.
      WHEN cl_abap_typedescr=>kind_struct.
        lo_struct ?= lo_type.
        LOOP AT lo_struct->components INTO DATA(ls_comp).
          ASSIGN COMPONENT ls_comp-name OF STRUCTURE iv_data TO <lv_val>.
          IF sy-subrc <> 0 OR <lv_val> IS INITIAL.
            CONTINUE.
          ENDIF.
          IF ls_comp-type_kind = cl_abap_typedescr=>typekind_char OR
             ls_comp-type_kind = cl_abap_typedescr=>typekind_string.
            IF ls_comp-name CS 'CLASS' OR ls_comp-name CS 'INTERFACE' OR ls_comp-name CS 'CLS' OR
               ls_comp-name CS 'INTF'  OR ls_comp-name CS 'OBJTYPE'   OR ls_comp-name CS 'OBJ_TYPE'.
              APPEND to_upper( condense( lcl_util=>to_text( <lv_val> ) ) ) TO ct_names.
            ENDIF.
          ELSEIF ls_comp-type_kind = cl_abap_typedescr=>typekind_table OR
                 ls_comp-type_kind = cl_abap_typedescr=>typekind_struct1 OR
                 ls_comp-type_kind = cl_abap_typedescr=>typekind_struct2.
            scan_names( EXPORTING iv_data = <lv_val> iv_depth = iv_depth + 1 CHANGING ct_names = ct_names ).
          ENDIF.
        ENDLOOP.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
INITIALIZATION.
  t_b1 = 'Packages and objects'.
  t_b2 = 'Content'.
  t_b3 = 'Output (Markdown ZIP)'.

  %_s_pack_%_app_%-text  = 'Package(s)'.
  %_s_type_%_app_%-text  = 'Object type filter'.
  %_s_name_%_app_%-text  = 'Object name filter'.
  %_p_sub_%_app_%-text   = 'Include all sub packages'.
  %_p_up_%_app_%-text    = 'Start at top super package'.
  %_p_src_%_app_%-text   = 'Source code'.
  %_p_sig_%_app_%-text   = 'Class / method signatures'.
  %_p_ddic_%_app_%-text  = 'DDIC definitions'.
  %_p_cont_%_app_%-text  = 'Customizing table contents'.
  %_p_contr_%_app_%-text = 'Max content rows / table'.
  %_p_bopf_%_app_%-text  = 'BOPF business objects'.
  %_p_ext_%_app_%-text   = 'Used classes/FMs/BOR outside'.
  %_p_extd_%_app_%-text  = 'Used DDIC outside package'.
  %_p_std_%_app_%-text   = 'Incl. standard SAP objects'.
  %_p_ldep_%_app_%-text  = 'Reference depth (1 = direct)'.
  %_p_extmx_%_app_%-text = 'Max objects outside package'.
  %_p_dyn_%_app_%-text   = 'Screens, GUI texts, variants'.
  %_p_docu_%_app_%-text  = 'SE61 documentation'.
  %_p_xref_%_app_%-text  = 'Used objects (where-used)'.
  %_p_frm_%_app_%-text   = 'Framework objects (WD,BOR..)'.
  %_p_maxr_%_app_%-text  = 'Max rows per repos. table'.
  %_r_skill_%_app_%-text = 'Documentation ZIPs'.
  %_r_plug_%_app_%-text  = 'Plugin-layout ZIPs'.
  %_p_sname_%_app_%-text = 'Skill name (optional)'.
  %_p_maxl_%_app_%-text  = 'Max lines per .md file'.
  %_p_volmb_%_app_%-text = 'Max MB per ZIP (uncompr.)'.
  %_p_maxf_%_app_%-text  = 'Max files per ZIP (skill)'.
  %_r_front_%_app_%-text = 'Download to PC'.
  %_r_appl_%_app_%-text  = 'Application server'.
  %_p_dir_%_app_%-text   = 'Directory'.
  %_p_test_%_app_%-text  = 'Test run (no files)'.

*&---------------------------------------------------------------------*
AT SELECTION-SCREEN.
  IF p_maxl < 200.
    MESSAGE 'Max lines per .md file must be at least 200' TYPE 'E'.
  ENDIF.
  IF p_volmb < 1.
    MESSAGE 'Max MB per ZIP must be at least 1' TYPE 'E'.
  ENDIF.

*&---------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_dir.
  DATA gv_folder TYPE string.
  IF r_front = abap_true.
    cl_gui_frontend_services=>directory_browse(
      CHANGING   selected_folder = gv_folder
      EXCEPTIONS OTHERS          = 1 ).
    cl_gui_cfw=>flush( ).
    IF gv_folder IS NOT INITIAL.
      p_dir = gv_folder.
    ENDIF.
  ENDIF.

*&---------------------------------------------------------------------*
START-OF-SELECTION.

  IF ( sy-batch = abap_true OR r_appl = abap_true ) AND p_dir IS INITIAL AND p_test = abap_false.
    MESSAGE 'Application server / background run: enter a directory (e.g. /tmp/zexport)' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  DATA(go_extractor) = NEW lcl_extractor( VALUE ty_s_opt(
    sub    = p_sub    up    = p_up    src  = p_src  sig  = p_sig
    ddic   = p_ddic   cont  = p_cont  bopf = p_bopf ext  = p_ext   extd = p_extd
    std    = p_std    ldepth = COND #( WHEN p_ldep > 0 THEN p_ldep ELSE 1 )
    extmax = COND #( WHEN p_extmx > 0 THEN p_extmx ELSE 5000 )
    dyn    = p_dyn    docu  = p_docu  xref = p_xref frm  = p_frm
    contr  = p_contr  maxr  = p_maxr  maxl = p_maxl volmb = p_volmb
    maxf   = p_maxf
    plugin = r_plug
    appl   = xsdbool( r_appl = abap_true OR sy-batch = abap_true )
    test   = p_test
    dir    = CONV string( p_dir )
    sname  = CONV string( p_sname ) ) ).

  go_extractor->run( ).
