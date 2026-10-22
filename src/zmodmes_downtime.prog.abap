*&---------------------------------------------------------------------*
*& ModernMES for SAP: machine downtime
*&
*& Start or end a downtime for a work center, or list recent ones.
*& https://github.com/modernmes/modernmes-sap
*&---------------------------------------------------------------------*
REPORT zmodmes_downtime.

PARAMETERS p_werks TYPE werks_d OBLIGATORY MEMORY ID wrk.
PARAMETERS p_arbpl TYPE arbpl OBLIGATORY MEMORY ID agr.
SELECTION-SCREEN SKIP.
PARAMETERS p_start RADIOBUTTON GROUP act DEFAULT 'X'.
PARAMETERS p_reason TYPE zmodmes_reason.
PARAMETERS p_aufnr TYPE aufnr.
PARAMETERS p_stop RADIOBUTTON GROUP act.
PARAMETERS p_list RADIOBUTTON GROUP act.
PARAMETERS p_days TYPE i DEFAULT 7.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_row,
        start_date TYPE d,
        start_time TYPE t,
        end_date   TYPE d,
        end_time   TYPE t,
        minutes    TYPE p LENGTH 10 DECIMALS 1,
        reason     TYPE zmodmes_reason,
        aufnr      TYPE aufnr,
        created_by TYPE syuname,
      END OF ty_row.
    TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    DATA mo_downtime TYPE REF TO zcl_modmes_downtime.

    METHODS show_list.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    mo_downtime = NEW #( ).
    CASE abap_true.
      WHEN p_start.
        IF p_reason IS INITIAL.
          MESSAGE 'Enter a downtime reason' TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
        IF mo_downtime->start( iv_werks  = p_werks
                               iv_arbpl  = p_arbpl
                               iv_reason = p_reason
                               iv_aufnr  = p_aufnr ) = abap_true.
          MESSAGE |Downtime started for { p_arbpl }| TYPE 'S'.
        ELSE.
          MESSAGE |{ p_arbpl } already has an open downtime; end it first| TYPE 'S' DISPLAY LIKE 'E'.
        ENDIF.
      WHEN p_stop.
        IF mo_downtime->stop( iv_werks = p_werks
                              iv_arbpl = p_arbpl ) = abap_true.
          MESSAGE |Downtime ended for { p_arbpl }| TYPE 'S'.
        ELSE.
          MESSAGE |{ p_arbpl } has no open downtime| TYPE 'S' DISPLAY LIKE 'E'.
        ENDIF.
      WHEN p_list.
        show_list( ).
    ENDCASE.
  ENDMETHOD.

  METHOD show_list.
    DATA lv_from TYPE tzntstmps.
    DATA lv_to TYPE tzntstmps.
    DATA lv_now TYPE tzntstmps.
    DATA(lv_days_back) = nmax( val1 = p_days - 1
                               val2 = 0 ).
    DATA(lv_first_day) = CONV d( sy-datum - lv_days_back ).
    CONVERT DATE lv_first_day TIME '000000' INTO TIME STAMP lv_from TIME ZONE sy-zonlo.
    GET TIME STAMP FIELD lv_now.
    lv_to = lv_now.

    DATA lt_rows TYPE ty_rows.
    LOOP AT mo_downtime->list( iv_werks = p_werks
                               iv_arbpl = p_arbpl
                               iv_from  = lv_from
                               iv_to    = lv_to ) ASSIGNING FIELD-SYMBOL(<ls_downtime>).
      APPEND INITIAL LINE TO lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      CONVERT TIME STAMP <ls_downtime>-start_ts TIME ZONE sy-zonlo
              INTO DATE <ls_row>-start_date TIME <ls_row>-start_time.
      DATA(lv_end) = COND tzntstmps( WHEN <ls_downtime>-end_ts IS INITIAL THEN lv_now
                                     ELSE <ls_downtime>-end_ts ).
      IF <ls_downtime>-end_ts IS NOT INITIAL.
        CONVERT TIME STAMP <ls_downtime>-end_ts TIME ZONE sy-zonlo
                INTO DATE <ls_row>-end_date TIME <ls_row>-end_time.
      ENDIF.
      <ls_row>-minutes    = cl_abap_tstmp=>subtract( tstmp1 = lv_end
                                                     tstmp2 = <ls_downtime>-start_ts ) / 60.
      <ls_row>-reason     = <ls_downtime>-reason.
      <ls_row>-aufnr      = <ls_downtime>-aufnr.
      <ls_row>-created_by = <ls_downtime>-created_by.
    ENDLOOP.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_alv)
                                CHANGING  t_table      = lt_rows ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv TYPE 'E'.
    ENDTRY.
    lo_alv->get_functions( )->set_default( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      |Downtimes of { p_arbpl } / plant { p_werks } (open ones have no end)| ).
    TRY.
        DATA(lo_columns) = lo_alv->get_columns( ).
        lo_columns->get_column( 'START_DATE' )->set_medium_text( 'Start date' ).
        lo_columns->get_column( 'START_TIME' )->set_medium_text( 'Start time' ).
        lo_columns->get_column( 'END_DATE' )->set_medium_text( 'End date' ).
        lo_columns->get_column( 'END_TIME' )->set_medium_text( 'End time' ).
        lo_columns->get_column( 'MINUTES' )->set_medium_text( 'Minutes' ).
      CATCH cx_salv_not_found.
        " Column names are fixed above; nothing to do.
    ENDTRY.
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  NEW lcl_app( )->run( ).
