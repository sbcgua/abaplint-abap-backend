CLASS zcl_abaplint_deps_find DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING
        !iv_max_level TYPE i DEFAULT 20 .
    METHODS find_by_item
      IMPORTING
        !iv_object_type TYPE trobjtype
        !iv_object_name TYPE sobj_name
      RETURNING
        VALUE(rt_tadir) TYPE zif_abapgit_definitions=>ty_tadir_tt
      RAISING
        zcx_abapgit_exception
        zcx_abaplint_error .
    METHODS find_by_item_minimal
      IMPORTING
        !iv_object_type TYPE trobjtype
        !iv_object_name TYPE sobj_name
      RETURNING
        VALUE(rt_tadir) TYPE zif_abapgit_definitions=>ty_tadir_tt
      RAISING
        zcx_abapgit_exception .
    METHODS find_by_packages
      IMPORTING
        !it_packages    TYPE tr_devclasses
      RETURNING
        VALUE(rt_tadir) TYPE zif_abapgit_definitions=>ty_tadir_tt
      RAISING
        zcx_abapgit_exception
        zcx_abaplint_error .
  PROTECTED SECTION.

    TYPES:
      BEGIN OF ty_tadir,
        ref_obj_type TYPE trobjtype,
        ref_obj_name TYPE sobj_name,
        devclass     TYPE devclass,
      END OF ty_tadir .
    TYPES:
      ty_tadir_tt TYPE SORTED TABLE OF ty_tadir WITH UNIQUE KEY ref_obj_type ref_obj_name .

    DATA mv_max_level TYPE i .

    METHODS convert_senvi_to_tadir
      IMPORTING
        !it_senvi       TYPE senvi_tab
      RETURNING
        VALUE(rt_tadir) TYPE ty_tadir_tt .
    METHODS find_clas_dependencies
      IMPORTING
        !iv_name  TYPE tadir-obj_name
        !iv_level TYPE i
      CHANGING
        !ct_tadir TYPE ty_tadir_tt
      RAISING
        zcx_abaplint_error .
    METHODS find_dtel_dependencies
      IMPORTING
        !iv_name  TYPE tadir-obj_name
      CHANGING
        !ct_tadir TYPE ty_tadir_tt .
    METHODS get_dependencies
      IMPORTING
        !is_object TYPE zif_abapgit_definitions=>ty_tadir
        !iv_level  TYPE i
      RAISING
        zcx_abaplint_error .
    METHODS resolve
      IMPORTING
        !it_wbcrossgt TYPE wbcrossgtt
      CHANGING
        !ct_tadir     TYPE ty_tadir_tt .
    METHODS update_index
      IMPORTING
        !iv_name TYPE seoclsname .
  PRIVATE SECTION.

    DATA mv_packages TYPE tr_devclasses .
    DATA mv_results TYPE ty_tadir_tt .
    DATA ms_types TYPE envi_types .

    METHODS add_subpackages
      IMPORTING
        !iv_package TYPE devclass .
    METHODS clean_own_packages .
    METHODS clear_results .
    METHODS determine_package
      IMPORTING
        !iv_object_type   TYPE trobjtype
        !iv_object_name   TYPE sobj_name
      RETURNING
        VALUE(rv_package) TYPE devclass .
    METHODS prepare_supported_types
      RETURNING
        VALUE(rs_types) TYPE envi_types .
    METHODS set_package_tree
      IMPORTING
        !it_packages TYPE tr_devclasses .
    METHODS convert_type_to_r3tr
      IMPORTING
        !iv_object_type  TYPE trobjtype
        !iv_object_name  TYPE sobj_name
        !iv_encl_object  TYPE sobj_name
      RETURNING
        VALUE(rs_object) TYPE zif_abapgit_definitions=>ty_tadir .
ENDCLASS.



CLASS ZCL_ABAPLINT_DEPS_FIND IMPLEMENTATION.


  METHOD add_subpackages.

    DATA: lt_packages LIKE mv_packages.
    DATA: lv_package LIKE LINE OF mv_packages.

    APPEND iv_package TO mv_packages.
    SELECT devclass FROM tdevc INTO TABLE lt_packages WHERE parentcl = iv_package.
    LOOP AT lt_packages INTO lv_package.
      add_subpackages( lv_package ).
    ENDLOOP.

  ENDMETHOD.


  METHOD clean_own_packages.

    DATA: lv_package LIKE LINE OF mv_packages.

    LOOP AT mv_packages INTO lv_package.
      READ TABLE mv_results
        WITH KEY ref_obj_type = 'DEVC' ref_obj_name = lv_package
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        DELETE mv_results INDEX sy-tabix.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD clear_results.
    CLEAR mv_results[].
  ENDMETHOD.


  METHOD constructor.
    mv_max_level = iv_max_level.
    ms_types = prepare_supported_types( ).
  ENDMETHOD.


  METHOD convert_senvi_to_tadir.

* do not use CL_WB_RIS_ENVIRONMENT, it does not exist in 740sp08

    DATA: ls_senvi       LIKE LINE OF it_senvi,
          ls_tadir       LIKE LINE OF rt_tadir,
          lv_object      TYPE trobjtype,
          lv_object_name TYPE sobj_name,
          ls_object      TYPE zif_abapgit_definitions=>ty_tadir,
          lv_obj         TYPE zif_abapgit_definitions=>ty_item.

    LOOP AT it_senvi INTO ls_senvi.
      lv_object = ls_senvi-type.
      lv_object_name = ls_senvi-object.

      ls_object = convert_type_to_r3tr(
        iv_object_type = lv_object
        iv_object_name = lv_object_name
        iv_encl_object = ls_senvi-encl_obj ).

      "successfull translation and suppoeted type
      IF ls_object-object IS NOT INITIAL AND ls_object-obj_name IS NOT INITIAL.
        lv_obj = ls_object-object.
        IF zcl_abapgit_objects=>is_supported( lv_obj ) = abap_true.
          CLEAR ls_tadir.
          ls_tadir-ref_obj_type = ls_object-object.
          ls_tadir-ref_obj_name = ls_object-obj_name.
          INSERT ls_tadir INTO TABLE rt_tadir.
        ELSE.
          MESSAGE s004(zabaplint) WITH ls_object-object ls_object-obj_name.
        ENDIF.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD convert_type_to_r3tr.

    DATA ls_ko TYPE ko100.
    DATA lv_object TYPE trobjtype.
    DATA lv_object_name TYPE sobj_name.
    DATA ls_e071 TYPE e071.
    DATA ls_tadir TYPE tadir.
    DATA lv_clstype TYPE seoclstype.

    CLEAR rs_object.
    lv_object = iv_object_type.
    lv_object_name = iv_object_name.

    CASE lv_object.
      WHEN 'INCL'.
        lv_object = 'PROG'.
      WHEN 'STRU'.
        lv_object = 'TABL'.
      WHEN 'MESS'.
        lv_object = 'MSAG'.
        lv_object_name = iv_encl_object.
      WHEN OTHERS.

* 1. Determine if R3TR already
        CALL FUNCTION 'TR_GET_PGMID_FOR_OBJECT'
          EXPORTING
            iv_object      = lv_object
          IMPORTING
            es_type        = ls_ko
          EXCEPTIONS
            illegal_object = 1
            OTHERS         = 2.

        IF sy-subrc = 1.
* 2. Map WB type to TADIR
          CALL FUNCTION 'GET_TADIR_TYPE_FROM_WB_TYPE'
            EXPORTING
              wb_objtype        = lv_object(3)
            IMPORTING
              transport_objtype = lv_object
            EXCEPTIONS
              no_mapping_found  = 1
              no_unique_mapping = 2
              OTHERS            = 3.
          IF sy-subrc = 0.
            lv_object_name = iv_encl_object.
            "Class vs. interface is not differenciated
            IF lv_object = 'CLAS'.
              "Decide if interface / class
              SELECT SINGLE clstype FROM seoclass INTO lv_clstype WHERE clsname = lv_object_name.
              IF sy-subrc = 0.
                IF lv_clstype = seoc_clstype_interface.
                  lv_object = 'INTF'.
                ENDIF.
              ELSE.
                "Decide if Enhancement Spot
                SELECT COUNT( * ) FROM badi_spot WHERE badi_name = lv_object_name.
                IF sy-subrc = 0.
                  lv_object = 'ENHS'.
                ENDIF.
              ENDIF.
            ENDIF.
            "Retry type check
            CALL FUNCTION 'TR_GET_PGMID_FOR_OBJECT'
              EXPORTING
                iv_object      = lv_object
              IMPORTING
                es_type        = ls_ko
              EXCEPTIONS
                illegal_object = 1
                OTHERS         = 2.
          ELSE.
            ASSERT 0 = 1. "Unknown Type
          ENDIF.
        ENDIF.
        ASSERT sy-subrc = 0. "Something missing in translation

        "3. Translate TADIR entry
        ls_e071-pgmid = ls_ko-pgmid.
        ls_e071-object = ls_ko-object.
        ls_e071-obj_name = lv_object_name.
        CALL FUNCTION 'TR_CHECK_TYPE'
          EXPORTING
            wi_e071              = ls_e071
            iv_translate_objname = 'X'
          IMPORTING
            we_tadir             = ls_tadir.
        ASSERT sy-subrc = 0. "Type must exist
        lv_object = ls_tadir-object.
        lv_object_name = ls_tadir-obj_name.

        "Object name empty -> does not exist
        IF lv_object_name IS NOT INITIAL.
          rs_object-object = lv_object.
          rs_object-obj_name = lv_object_name.
        ENDIF.
    ENDCASE.
  ENDMETHOD.


  METHOD determine_package.
*
* Translate certain Object Types
*
    DATA: lv_type      TYPE trobjtype,
          lv_name      TYPE sobj_name,
          lv_is_fugr   TYPE flag,
          lv_namespace TYPE namespace,
          lv_fugr      TYPE rs38l_area.

    CLEAR rv_package.
    lv_type = iv_object_type.
    lv_name = iv_object_name.

    "Translation of Types / Names
    CASE iv_object_type.
      WHEN 'FUNC'.
        SELECT SINGLE pname FROM tfdir INTO lv_name.
        lv_type = 'FUGR'.
      WHEN 'PROG'.
        CALL FUNCTION 'RS_PROGNAME_SPLIT'
          EXPORTING
            progname_with_namespace = lv_name
          IMPORTING
            namespace               = lv_namespace
            fugr_is_name            = lv_is_fugr
            fugr_group              = lv_fugr
          EXCEPTIONS
            delimiter_error         = 1
            OTHERS                  = 2.
        IF sy-subrc = 0 AND lv_is_fugr IS NOT INITIAL.
          lv_type = 'FUGR'.
          IF lv_namespace IS NOT INITIAL.
            CONCATENATE lv_namespace lv_fugr INTO lv_name.
          ELSE.
            lv_name = lv_fugr.
          ENDIF.
        ENDIF.
    ENDCASE.

    SELECT SINGLE devclass FROM tadir INTO rv_package
       WHERE pgmid = 'R3TR'
       AND object = lv_type
       AND obj_name = lv_name.

    IF sy-subrc <> 0 OR rv_package IS INITIAL.
      rv_package = '$NONE'.
    ENDIF.
  ENDMETHOD.


  METHOD find_by_item.

* finds dependencies by item, package tree is ignored

    DATA: ls_object   TYPE zif_abapgit_definitions=>ty_tadir,
          lt_packages TYPE tr_devclasses,
          lv_package  TYPE devclass,
          ls_result   LIKE LINE OF mv_results.

    FIELD-SYMBOLS <ls_tadir> LIKE LINE OF rt_tadir.

    ls_object-object = iv_object_type.
    ls_object-obj_name = iv_object_name.
    ls_object-devclass = lv_package.

    IF ls_object-object = 'DEVC'.
      APPEND ls_object-object TO lt_packages.
    ENDIF.

    set_package_tree( lt_packages ).
    clear_results( ).

    get_dependencies(
      is_object = ls_object
      iv_level  = 1 ).

    LOOP AT mv_results INTO ls_result.
      APPEND INITIAL LINE TO rt_tadir ASSIGNING <ls_tadir>.
      <ls_tadir>-object = ls_result-ref_obj_type.
      <ls_tadir>-obj_name = ls_result-ref_obj_name.
      <ls_tadir>-devclass = ls_result-devclass.
    ENDLOOP.

  ENDMETHOD.


  METHOD find_by_item_minimal.

* find minimal dependencies required by abaplint to perform syntax check

* Candidates:
*   super classes, required for abaplint syntax check
*   interfaces that are implemented, required for abaplint syntax check
*   objects used within same package/project scope

* todo
    WRITE iv_object_type.
    WRITE iv_object_name.
    CLEAR rt_tadir.

  ENDMETHOD.


  METHOD find_by_packages.

* given a set of packages, all dependencies are found for these packages
* only returns dependencies outside of the input package structure

    DATA: lv_package LIKE LINE OF it_packages,
          ls_result  LIKE LINE OF mv_results,
          ls_object  TYPE zif_abapgit_definitions=>ty_tadir.

    FIELD-SYMBOLS <ls_tadir> LIKE LINE OF rt_tadir.

    "Determine Package Tree
    set_package_tree( it_packages ).
    clear_results( ).

    LOOP AT it_packages INTO lv_package.
      ls_object-object   = 'DEVC'.
      ls_object-obj_name = lv_package.

      cl_progress_indicator=>progress_indicate(
        i_text               = |Processing, { ls_object-object } { ls_object-obj_name }|
        i_processed          = sy-tabix
        i_total              = lines( it_packages )
        i_output_immediately = abap_true ).

      get_dependencies(
        is_object  = ls_object
        iv_level   = 1 ).
    ENDLOOP.

    clean_own_packages( ).

    LOOP AT mv_results INTO ls_result.
      APPEND INITIAL LINE TO rt_tadir ASSIGNING <ls_tadir>.
      <ls_tadir>-object = ls_result-ref_obj_type.
      <ls_tadir>-obj_name = ls_result-ref_obj_name.
      <ls_tadir>-devclass = ls_result-devclass.
    ENDLOOP.

  ENDMETHOD.


  METHOD find_clas_dependencies.

    DATA lt_includes TYPE STANDARD TABLE OF programm WITH DEFAULT KEY.
    DATA lt_wbcrossgt TYPE wbcrossgtt.
    DATA lv_clsname TYPE seoclsname.
    DATA lv_final TYPE abap_bool.
    DATA lo_oo_class TYPE REF TO cl_oo_class.

    lv_clsname = |{ iv_name }|.

    TRY.
        lo_oo_class ?= cl_oo_class=>get_instance( lv_clsname ).
        lv_final = lo_oo_class->is_final( ).
      CATCH cx_class_not_existent.
        RETURN.
    ENDTRY.

    APPEND cl_oo_classname_service=>get_pubsec_name( |{ iv_name }| ) TO lt_includes.
    IF lv_final = abap_false.
      APPEND cl_oo_classname_service=>get_prosec_name( |{ iv_name }| ) TO lt_includes.
    ENDIF.

    SELECT * FROM wbcrossgt INTO CORRESPONDING FIELDS OF TABLE lt_wbcrossgt
      FOR ALL ENTRIES IN lt_includes
      WHERE include = lt_includes-table_line
      AND name <> iv_name.
    IF lines( lt_wbcrossgt ) = 0.
* update so it is correct in the next run
      update_index( lv_clsname ).

      SELECT * FROM wbcrossgt INTO CORRESPONDING FIELDS OF TABLE lt_wbcrossgt
        FOR ALL ENTRIES IN lt_includes
        WHERE include = lt_includes-table_line
        AND name <> iv_name.
    ENDIF.

    IF iv_level < mv_max_level.
      resolve(
        EXPORTING
          it_wbcrossgt = lt_wbcrossgt
        CHANGING
          ct_tadir     = ct_tadir ).
    ELSE.
      RAISE EXCEPTION TYPE zcx_abaplint_error
        EXPORTING
          message = |Max depth { mv_max_level } reached for class { lv_clsname }. Exiting dependency walk|.
    ENDIF.

  ENDMETHOD.


  METHOD find_dtel_dependencies.

* find just the domain for the data element if exists, ignores value tables and more

*    DATA: lv_domname TYPE dd04l-domname
*          ls_tadir   LIKE LINE OF ct_tadir
*
*    SELECT SINGLE domname FROM dd04l
*      INTO lv_domname
*      WHERE rollname = iv_name
*      AND as4local = 'A'
*      AND as4vers = 0
*    IF sy-subrc = 0 AND NOT lv_domname IS INITIAL
*      ls_tadir-ref_obj_type = 'DOMA'
*      ls_tadir-ref_obj_name = lv_domname
*      INSERT ls_tadir INTO TABLE ct_tadir
*    ENDIF

    DATA ls_x030l TYPE x030l.
    DATA lv_tabname TYPE dd02l-tabname.
    DATA ls_tadir LIKE LINE OF ct_tadir.

    lv_tabname = iv_name.

* black magic, read the nametab to get the domain for the data element
* this is faster as it runs only on application server
    CALL FUNCTION 'DD_GET_NAMETAB_HEADER'
      EXPORTING
        tabname   = lv_tabname
      IMPORTING
        x030l_wa  = ls_x030l
      EXCEPTIONS
        not_found = 1
        OTHERS    = 2.
    IF sy-subrc = 0 AND NOT ls_x030l-refname IS INITIAL.
      ls_tadir-ref_obj_type = 'DOMA'.
      ls_tadir-ref_obj_name = ls_x030l-refname.
      INSERT ls_tadir INTO TABLE ct_tadir.
    ENDIF.

  ENDMETHOD.


  METHOD get_dependencies.

    DATA: lv_obj_type    TYPE euobj-id,
          lt_tadir       TYPE ty_tadir_tt,
          lt_environment TYPE senvi_tab,
          lv_index       LIKE sy-tabix,
          ls_tadir       TYPE LINE OF ty_tadir_tt,
          lv_flag        TYPE flag,
          lv_devclass    TYPE devclass,
          lv_delflag     TYPE objdelflag.
    DATA: BEGIN OF ls_tadir_obj,
            object    TYPE trobjtype,
            obj_name  TYPE sobj_name,
            srcsystem TYPE srcsystem,
            author    TYPE responsibl,
            devclass  TYPE devclass,
            genflag   TYPE genflag,
          END OF ls_tadir_obj.
    DATA ls_object TYPE zif_abapgit_definitions=>ty_tadir.
    DATA lv_level LIKE iv_level.


    IF is_object-object = 'DEVC' AND is_object-obj_name(1) = '$'.
* nothing
    ELSE.
      SELECT SINGLE object obj_name srcsystem author devclass genflag
        FROM tadir INTO CORRESPONDING FIELDS OF ls_tadir_obj
        WHERE pgmid = 'R3TR' AND object = is_object-object AND obj_name = is_object-obj_name.
      IF sy-subrc <> 0 OR ls_tadir_obj-genflag = abap_true.
        RETURN.
      ENDIF.
    ENDIF.

*
* Determine direct dependency
*
    IF is_object-object = 'CLAS'.
      find_clas_dependencies(
        EXPORTING
          iv_name  = is_object-obj_name
          iv_level = iv_level
        CHANGING
          ct_tadir = lt_tadir ).
    ELSEIF is_object-object = 'DTEL'.
      find_dtel_dependencies(
        EXPORTING
          iv_name  = is_object-obj_name
        CHANGING
          ct_tadir = lt_tadir ).
    ELSE.
      lv_obj_type = is_object-object.

      CALL FUNCTION 'REPOSITORY_ENVIRONMENT_SET'
        EXPORTING
          obj_type          = lv_obj_type
          object_name       = is_object-obj_name
          environment_types = ms_types
          online_force      = 'X'
        TABLES
          environment       = lt_environment
        EXCEPTIONS
          batch             = 1
          batchjob_error    = 2
          not_executed      = 3
          OTHERS            = 4.
      IF sy-subrc = 3.
        RETURN.
      ENDIF.
      ASSERT sy-subrc = 0.

      lt_tadir = convert_senvi_to_tadir( lt_environment ).
    ENDIF.

*
* Remove entries already in collection
*
    IF lines( mv_results ) > 0.
      LOOP AT lt_tadir INTO ls_tadir.
        lv_index = sy-tabix.
        READ TABLE mv_results WITH KEY ref_obj_type = ls_tadir-ref_obj_type
                                       ref_obj_name = ls_tadir-ref_obj_name
                              TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          DELETE lt_tadir INDEX lv_index.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lines( lt_tadir ) = 0.
      RETURN.
    ENDIF.

*
* Remove entries from own package (or sub packages)
*
    LOOP AT lt_tadir INTO ls_tadir.
      IF ls_tadir-ref_obj_type = 'DEVC'. "sub packages are not handled otherwise
        CONTINUE.
      ENDIF.
      lv_index = sy-tabix.
      lv_devclass = determine_package( iv_object_type = ls_tadir-ref_obj_type
                                       iv_object_name = ls_tadir-ref_obj_name ).

      lv_flag = 'X'.
      IF sy-subrc = 0.
        READ TABLE mv_packages FROM lv_devclass TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          CLEAR lv_flag.
        ENDIF.
      ENDIF.
      IF lv_flag = 'X'.
        DELETE lt_tadir INDEX lv_index.
      ELSE.
        ls_tadir-devclass = lv_devclass.
        MODIFY lt_tadir FROM ls_tadir INDEX lv_index.
      ENDIF.
    ENDLOOP.

    "Remove entries without TADIR or with delete flag set
    LOOP AT lt_tadir INTO ls_tadir.
      SELECT SINGLE delflag FROM tadir INTO lv_delflag
        WHERE pgmid = 'R3TR'
        AND object = ls_tadir-ref_obj_type
        AND obj_name = ls_tadir-ref_obj_name.
      IF sy-subrc <> 0 OR lv_delflag IS NOT INITIAL.
        MESSAGE s005(zabaplint) WITH ls_tadir-ref_obj_type ls_tadir-ref_obj_name.
        DELETE lt_tadir.
      ENDIF.
    ENDLOOP.

    "Add to dependency collection
    INSERT LINES OF lt_tadir INTO TABLE mv_results.

*
* if SAP object, do not go deeper
*
* TODO: when is this valid? add as configuration in constructor?
    IF NOT ( ( ls_tadir_obj-author = 'SAP'
           OR ls_tadir_obj-author = 'SAP*' )
           AND ls_tadir_obj-srcsystem = 'SAP' ).
*
* Try to find dependend objects
*
      LOOP AT lt_tadir INTO ls_tadir
          WHERE ref_obj_type <> 'MSAG'
          AND ref_obj_type <> 'DOMA'.
        ls_object-object   = ls_tadir-ref_obj_type.
        ls_object-obj_name = ls_tadir-ref_obj_name.
        ls_object-devclass = ls_tadir-devclass.

        lv_level = iv_level + 1.

        get_dependencies(
          is_object  = ls_object
          iv_level   = lv_level ).
      ENDLOOP.
    ENDIF.
  ENDMETHOD.


  METHOD prepare_supported_types.

    DATA: ls_type TYPE zif_abapgit_definitions=>ty_item.

    CLEAR ms_types.

    ls_type-obj_type = 'PROG'.
    rs_types-prog = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'FUGR'.
    rs_types-fugr = zcl_abapgit_objects=>is_supported( ls_type ).

* not needed by abaplint yet
*    ls_type-obj_type = 'LDBA'
*    rs_types-ldba = zcl_abapgit_objects=>is_supported( ls_type )

    ls_type-obj_type = 'MSAG'.
    rs_types-msag = zcl_abapgit_objects=>is_supported( ls_type ).

    ls_type-obj_type = 'TRAN'.
    rs_types-tran = zcl_abapgit_objects=>is_supported( ls_type ).

    rs_types-func = rs_types-fugr.

* not needed by abaplint yet
*    ls_type-obj_type = 'DIAL'
*    rs_types-dial = zcl_abapgit_objects=>is_supported( ls_type )

    ls_type-obj_type = 'TABL'.
    rs_types-tabl = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'SHLP'.
    rs_types-shlp = zcl_abapgit_objects=>is_supported( ls_type ).

* handled manually in the code
    rs_types-doma = abap_false.

    ls_type-obj_type = 'DTEL'.
    rs_types-dtel = zcl_abapgit_objects=>is_supported( ls_type ).

    ls_type-obj_type = 'VIEW'.
    rs_types-view = zcl_abapgit_objects=>is_supported( ls_type ).

* not needed by abaplint yet
*    ls_type-obj_type = 'MCOB'
*    rs_types-mcob = zcl_abapgit_objects=>is_supported( ls_type )

* not needed by abaplint yet
*    ls_type-obj_type = 'MCID'
*    rs_types-mcid = zcl_abapgit_objects=>is_supported( ls_type )

    ls_type-obj_type = 'PARA'.
    rs_types-para = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'CONV'.
    rs_types-conv = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'SUSO'.
    rs_types-suso = zcl_abapgit_objects=>is_supported( ls_type ).

* TYPE are not handled properly in abaplint right now, so skip
*    ls_type-obj_type = 'TYPE'
*    rs_types-type = zcl_abapgit_objects=>is_supported( ls_type )

    ls_type-obj_type = 'TTYP'.
    rs_types-ttyp = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'PROG'.
    rs_types-prog = zcl_abapgit_objects=>is_supported( ls_type ).
    rs_types-stru = rs_types-tabl.

* not needed by abaplint yet
*    ls_type-obj_type = 'ENQU'
*    rs_types-enqu = zcl_abapgit_objects=>is_supported( ls_type )

* not needed by abaplint yet
*    ls_type-obj_type = 'SQLT'
*    rs_types-sqlt = zcl_abapgit_objects=>is_supported( ls_type )

    ls_type-obj_type = 'CLAS'.
    rs_types-clas = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'INTF'.
    rs_types-intf = zcl_abapgit_objects=>is_supported( ls_type ).

* not needed by abaplint yet
*    ls_type-obj_type = 'UDMO'
*    rs_types-udmo = zcl_abapgit_objects=>is_supported( ls_type )
* not needed by abaplint yet
*    ls_type-obj_type = 'UENO'
*    rs_types-ueno = zcl_abapgit_objects=>is_supported( ls_type )
* not needed by abaplint yet
*    ls_type-obj_type = 'SHI3'
*    rs_types-shi3 = zcl_abapgit_objects=>is_supported( ls_type )
* not needed by abaplint yet
*    ls_type-obj_type = 'CNTX'
*    rs_types-cntx = zcl_abapgit_objects=>is_supported( ls_type )

    ls_type-obj_type = 'TTAB'.
    rs_types-ttab = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'IASP'.
    rs_types-iasp = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'IATU'.
    rs_types-iatu = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'CLIF'.
    rs_types-clif = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'SOBJ'.
    rs_types-sobj = zcl_abapgit_objects=>is_supported( ls_type ).

* not needed by abaplint yet
*    ls_type-obj_type = 'WDYN'
*    rs_types-wdyn = zcl_abapgit_objects=>is_supported( ls_type )

* not needed by abaplint yet
*    ls_type-obj_type = 'WDYA'
*    rs_types-wdya = zcl_abapgit_objects=>is_supported( ls_type )

    ls_type-obj_type = 'XSLT'.
    rs_types-xslt = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'ENHS'.
    rs_types-enhs = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'ENSC'.
    rs_types-ensc = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'ENHC'.
    rs_types-enhc = zcl_abapgit_objects=>is_supported( ls_type ).
    ls_type-obj_type = 'ENHO'.
    rs_types-enho = zcl_abapgit_objects=>is_supported( ls_type ).

* not needed by abaplint yet
*    ls_type-obj_type = 'SFBF'
*    rs_types-sfbf = zcl_abapgit_objects=>is_supported( ls_type )
* not needed by abaplint yet
*    ls_type-obj_type = 'SFSW'
*    rs_types-sfsw = zcl_abapgit_objects=>is_supported( ls_type )

    ls_type-obj_type = 'DEVC'.
    rs_types-devc = zcl_abapgit_objects=>is_supported( ls_type ).

* not needed by abaplint yet
*    ls_type-obj_type = 'SQSC'
*    rs_types-sqsc = zcl_abapgit_objects=>is_supported( ls_type )
* not needed by abaplint yet
*    ls_type-obj_type = 'STOB'
*    rs_types-stob = zcl_abapgit_objects=>is_supported( ls_type )

  ENDMETHOD.


  METHOD resolve.

    DATA ls_wbcrossgt LIKE LINE OF it_wbcrossgt.
    DATA ls_tadir LIKE LINE OF ct_tadir.
    DATA lv_clstype TYPE seoclass-clstype.

    LOOP AT it_wbcrossgt INTO ls_wbcrossgt.
      CASE ls_wbcrossgt-otype.
        WHEN 'TY'.
          SELECT SINGLE clstype FROM seoclass INTO lv_clstype WHERE clsname = ls_wbcrossgt-name(30).
          IF sy-subrc <> 0.
            "Decide if Enhancement Spot
            SELECT COUNT( * ) FROM badi_spot WHERE badi_name = ls_wbcrossgt-name.
            IF sy-subrc = 0.
              CLEAR ls_tadir.
              ls_tadir-ref_obj_type = 'ENHS'.
              ls_tadir-ref_obj_name = ls_wbcrossgt-name.
              INSERT ls_tadir INTO TABLE ct_tadir.
            ELSE.
              CONTINUE.
            ENDIF.
          ENDIF.

          CASE lv_clstype.
            WHEN seoc_clstype_class.
              CLEAR ls_tadir.
              ls_tadir-ref_obj_type = 'CLAS'.
              ls_tadir-ref_obj_name = ls_wbcrossgt-name.
              INSERT ls_tadir INTO TABLE ct_tadir.

            WHEN seoc_clstype_interface.
              CLEAR ls_tadir.
              ls_tadir-ref_obj_type = 'INTF'.
              ls_tadir-ref_obj_name = ls_wbcrossgt-name.
              INSERT ls_tadir INTO TABLE ct_tadir.

            WHEN OTHERS.
              ASSERT 0 = 1.
          ENDCASE.

        WHEN OTHERS.
          CONTINUE. " todo ?
      ENDCASE.
    ENDLOOP.

  ENDMETHOD.


  METHOD set_package_tree.

    DATA: lv_package LIKE LINE OF it_packages.

    CLEAR mv_packages[].
    "Determine sub packages
    LOOP AT it_packages INTO lv_package.
      add_subpackages( lv_package ).
    ENDLOOP.

  ENDMETHOD.


  METHOD update_index.

    DATA lv_include TYPE seoclsname.
    DATA lo_cross TYPE REF TO cl_wb_crossreference.

    lv_include = cl_oo_classname_service=>get_classpool_name( iv_name ).

    CREATE OBJECT lo_cross
      EXPORTING
        p_name    = |{ lv_include }|
        p_include = |{ lv_include }|.

    lo_cross->index_actualize( ).

  ENDMETHOD.
ENDCLASS.