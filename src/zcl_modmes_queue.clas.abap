"! <p class="shorttext synchronized">ModernMES for SAP: work center queue</p>
"! The operations a work center still has to run: operations of released
"! production orders that are not fully confirmed, earliest start first.
CLASS zcl_modmes_queue DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_operation,
        aufnr       TYPE aufnr,
        vornr       TYPE afvc-vornr,
        ltxa1       TYPE afvc-ltxa1,
        matnr       TYPE matnr,
        maktx       TYPE makt-maktx,
        "! Operation quantity, and what has been confirmed so far
        mgvrg       TYPE afvv-mgvrg,
        lmnga       TYPE afvv-lmnga,
        xmnga       TYPE afvv-xmnga,
        open_qty    TYPE afvv-mgvrg,
        meinh       TYPE afvv-meinh,
        fsavd       TYPE afvv-fsavd,
        werks       TYPE werks_d,
        arbpl       TYPE arbpl,
      END OF ty_operation.
    TYPES ty_operations TYPE STANDARD TABLE OF ty_operation WITH EMPTY KEY.

    "! Open operations of one work center in one plant.
    METHODS read
      IMPORTING iv_werks             TYPE werks_d
                iv_arbpl             TYPE arbpl
      RETURNING VALUE(rt_operations) TYPE ty_operations.

  PRIVATE SECTION.
    " System statuses (table JEST)
    CONSTANTS c_released TYPE jest-stat VALUE 'I0002'.
    CONSTANTS c_confirmed TYPE jest-stat VALUE 'I0009'.
    CONSTANTS c_deleted_operation TYPE jest-stat VALUE 'I0013'.
    CONSTANTS c_technically_complete TYPE jest-stat VALUE 'I0045'.
    CONSTANTS c_closed TYPE jest-stat VALUE 'I0046'.
    CONSTANTS c_deletion_flag TYPE jest-stat VALUE 'I0076'.
    " AUFK-AUTYP of a production order
    CONSTANTS c_production_order TYPE aufk-autyp VALUE '10'.

    TYPES ty_objnrs TYPE SORTED TABLE OF jest-objnr WITH UNIQUE KEY table_line.
ENDCLASS.


CLASS zcl_modmes_queue IMPLEMENTATION.
  METHOD read.
    SELECT a~aufnr, a~objnr AS order_objnr, k~plnbez AS matnr,
           c~vornr, c~ltxa1, c~objnr AS operation_objnr,
           v~mgvrg, v~lmnga, v~xmnga, v~meinh, v~fsavd
      FROM aufk AS a
             INNER JOIN afko AS k ON k~aufnr = a~aufnr
               INNER JOIN afvc AS c ON c~aufpl = k~aufpl
                 INNER JOIN afvv AS v ON v~aufpl = c~aufpl
                                     AND v~aplzl = c~aplzl
                   INNER JOIN crhd AS w ON w~objid = c~arbid
      WHERE a~werks = @iv_werks
        AND a~autyp = @c_production_order
        AND w~objty = 'A'
        AND w~arbpl = @iv_arbpl
      INTO TABLE @DATA(lt_rows).
    IF lt_rows IS INITIAL.
      RETURN.
    ENDIF.

    " Active statuses of the orders and operations found
    DATA lt_objnrs TYPE ty_objnrs.
    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      INSERT <ls_row>-order_objnr INTO TABLE lt_objnrs.
      INSERT <ls_row>-operation_objnr INTO TABLE lt_objnrs.
    ENDLOOP.
    SELECT objnr, stat
      FROM jest
      FOR ALL ENTRIES IN @lt_objnrs
      WHERE objnr = @lt_objnrs-table_line
        AND inact = @abap_false
      INTO TABLE @DATA(lt_status).
    SORT lt_status BY objnr stat.

    LOOP AT lt_rows ASSIGNING <ls_row>.
      DATA(lv_order_open) = xsdbool(
        line_exists( lt_status[ objnr = <ls_row>-order_objnr stat = c_released ] )
        AND NOT line_exists( lt_status[ objnr = <ls_row>-order_objnr stat = c_technically_complete ] )
        AND NOT line_exists( lt_status[ objnr = <ls_row>-order_objnr stat = c_closed ] )
        AND NOT line_exists( lt_status[ objnr = <ls_row>-order_objnr stat = c_deletion_flag ] ) ).
      DATA(lv_operation_open) = xsdbool(
        NOT line_exists( lt_status[ objnr = <ls_row>-operation_objnr stat = c_confirmed ] )
        AND NOT line_exists( lt_status[ objnr = <ls_row>-operation_objnr stat = c_deleted_operation ] ) ).
      IF lv_order_open = abap_false OR lv_operation_open = abap_false.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( aufnr    = <ls_row>-aufnr
                      vornr    = <ls_row>-vornr
                      ltxa1    = <ls_row>-ltxa1
                      matnr    = <ls_row>-matnr
                      mgvrg    = <ls_row>-mgvrg
                      lmnga    = <ls_row>-lmnga
                      xmnga    = <ls_row>-xmnga
                      open_qty = nmax( val1 = <ls_row>-mgvrg - <ls_row>-lmnga - <ls_row>-xmnga
                                       val2 = 0 )
                      meinh    = <ls_row>-meinh
                      fsavd    = <ls_row>-fsavd
                      werks    = iv_werks
                      arbpl    = iv_arbpl ) TO rt_operations.
    ENDLOOP.
    IF rt_operations IS INITIAL.
      RETURN.
    ENDIF.

    " Material descriptions in the logon language
    SELECT matnr, maktx
      FROM makt
      FOR ALL ENTRIES IN @rt_operations
      WHERE matnr = @rt_operations-matnr
        AND spras = @sy-langu
      INTO TABLE @DATA(lt_texts).
    SORT lt_texts BY matnr.
    LOOP AT rt_operations ASSIGNING FIELD-SYMBOL(<ls_operation>).
      READ TABLE lt_texts ASSIGNING FIELD-SYMBOL(<ls_text>)
           WITH KEY matnr = <ls_operation>-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        <ls_operation>-maktx = <ls_text>-maktx.
      ENDIF.
    ENDLOOP.

    SORT rt_operations BY fsavd aufnr vornr.
  ENDMETHOD.
ENDCLASS.
