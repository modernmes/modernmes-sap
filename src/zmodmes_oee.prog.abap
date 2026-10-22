*&---------------------------------------------------------------------*
*& ModernMES for SAP: OEE by work center and day
*&
*& Availability: planned minutes per day minus the downtimes recorded
*&   with ZMODMES_DOWNTIME.
*& Performance:  standard time of the confirmed quantity (routing
*&   standard value P_VGW per base quantity) against the run time.
*& Quality:      confirmed yield against yield plus scrap.
*& Quantities come from production order confirmations (AFRU) by
*& posting date; reversed confirmations are left out.
*& https://github.com/modernmes/modernmes-sap
*&---------------------------------------------------------------------*
REPORT zmodmes_oee.

DATA gv_arbpl TYPE crhd-arbpl.
DATA gv_budat TYPE afru-budat.

PARAMETERS p_werks TYPE werks_d OBLIGATORY MEMORY ID wrk.
SELECT-OPTIONS s_arbpl FOR gv_arbpl.
SELECT-OPTIONS s_date FOR gv_budat OBLIGATORY NO-EXTENSION.
PARAMETERS p_plan TYPE i DEFAULT 480 OBLIGATORY.
PARAMETERS p_vgw TYPE n LENGTH 1 DEFAULT '2'.

INITIALIZATION.
  s_date[] = VALUE #( ( sign = 'I' option = 'BT' low = sy-datum - 6 high = sy-datum ) ).

AT SELECTION-SCREEN.
  IF p_vgw < 1 OR p_vgw > 6.
    MESSAGE 'Standard value number must be 1 to 6' TYPE 'E'.
  ENDIF.
  IF p_plan <= 0.
    MESSAGE 'Planned minutes must be above 0' TYPE 'E'.
  ENDIF.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_row,
        arbpl            TYPE arbpl,
        day              TYPE d,
        planned_minutes  TYPE zcl_modmes_oee=>ty_minutes,
        downtime_minutes TYPE zcl_modmes_oee=>ty_minutes,
        run_minutes      TYPE zcl_modmes_oee=>ty_minutes,
        ideal_minutes    TYPE zcl_modmes_oee=>ty_minutes,
        good_quantity    TYPE zcl_modmes_oee=>ty_quantity,
        scrap_quantity   TYPE zcl_modmes_oee=>ty_quantity,
        availability_pct TYPE p LENGTH 6 DECIMALS 1,
        performance_pct  TYPE p LENGTH 6 DECIMALS 1,
        quality_pct      TYPE p LENGTH 6 DECIMALS 1,
        oee_pct          TYPE p LENGTH 6 DECIMALS 1,
        "! Confirmations whose standard time could not be converted
        no_standard      TYPE i,
      END OF ty_row.
    TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    METHODS day_bounds
      IMPORTING iv_day  TYPE d
      EXPORTING ev_from TYPE tzntstmps
                ev_to   TYPE tzntstmps.
    METHODS display
      CHANGING ct_rows TYPE ty_rows.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_rows TYPE ty_rows.

    SELECT objid, arbpl
      FROM crhd
      WHERE objty = 'A'
        AND werks = @p_werks
        AND arbpl IN @s_arbpl
      ORDER BY arbpl
      INTO TABLE @DATA(lt_work_centers).
    IF lt_work_centers IS INITIAL.
      MESSAGE 'No work centers found' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " Confirmations with the operation's standard values
    SELECT r~arbid, r~budat, r~lmnga, r~xmnga,
           v~bmsch, v~vgw01, v~vgw02, v~vgw03, v~vgw04, v~vgw05, v~vgw06,
           v~vge01, v~vge02, v~vge03, v~vge04, v~vge05, v~vge06
      FROM afru AS r
             INNER JOIN afvv AS v ON v~aufpl = r~aufpl
                                 AND v~aplzl = r~aplzl
      FOR ALL ENTRIES IN @lt_work_centers
      WHERE r~arbid = @lt_work_centers-objid
        AND r~werks = @p_werks
        AND r~budat IN @s_date
        AND r~stokz = @abap_false
        AND r~stzhl = '00000000'
      INTO TABLE @DATA(lt_confirmations).

    FIELD-SYMBOLS <lv_value> TYPE any.
    FIELD-SYMBOLS <lv_unit> TYPE any.
    DATA(lo_downtime) = NEW zcl_modmes_downtime( ).
    DATA lv_now TYPE tzntstmps.
    GET TIME STAMP FIELD lv_now.
    DATA(lv_value_name) = |VGW0{ p_vgw }|.
    DATA(lv_unit_name) = |VGE0{ p_vgw }|.

    LOOP AT lt_work_centers ASSIGNING FIELD-SYMBOL(<ls_work_center>).
      DATA(lv_day) = s_date[ 1 ]-low.
      DATA(lv_last) = COND d( WHEN s_date[ 1 ]-high IS INITIAL THEN s_date[ 1 ]-low ELSE s_date[ 1 ]-high ).
      WHILE lv_day <= lv_last.
        IF lv_day NOT IN s_date.
          lv_day = lv_day + 1.
          CONTINUE.
        ENDIF.
        DATA ls_row TYPE ty_row.
        CLEAR ls_row.
        ls_row-arbpl = <ls_work_center>-arbpl.
        ls_row-day   = lv_day.
        ls_row-planned_minutes = p_plan.

        " Downtime inside this day, open ones counted until now
        DATA lv_from TYPE tzntstmps.
        DATA lv_to TYPE tzntstmps.
        day_bounds( EXPORTING iv_day  = lv_day
                    IMPORTING ev_from = lv_from
                              ev_to   = lv_to ).
        DATA lv_seconds TYPE decfloat34.
        lv_seconds = 0.
        LOOP AT lo_downtime->list( iv_werks = p_werks
                                   iv_arbpl = <ls_work_center>-arbpl
                                   iv_from  = lv_from
                                   iv_to    = lv_to ) ASSIGNING FIELD-SYMBOL(<ls_downtime>).
          DATA(lv_end) = COND tzntstmps( WHEN <ls_downtime>-end_ts IS INITIAL THEN lv_now
                                         ELSE <ls_downtime>-end_ts ).
          " Seconds since the day started, so the overlap works on one clock
          lv_seconds = lv_seconds + zcl_modmes_oee=>overlap_seconds(
            iv_from1 = cl_abap_tstmp=>subtract( tstmp1 = <ls_downtime>-start_ts tstmp2 = lv_from )
            iv_to1   = cl_abap_tstmp=>subtract( tstmp1 = lv_end tstmp2 = lv_from )
            iv_from2 = 0
            iv_to2   = cl_abap_tstmp=>subtract( tstmp1 = lv_to tstmp2 = lv_from ) ).
        ENDLOOP.
        ls_row-downtime_minutes = lv_seconds / 60.

        LOOP AT lt_confirmations ASSIGNING FIELD-SYMBOL(<ls_confirmation>)
             WHERE arbid = <ls_work_center>-objid AND budat = lv_day.
          ls_row-good_quantity  = ls_row-good_quantity + <ls_confirmation>-lmnga.
          ls_row-scrap_quantity = ls_row-scrap_quantity + <ls_confirmation>-xmnga.
          UNASSIGN: <lv_value>, <lv_unit>.
          ASSIGN COMPONENT lv_value_name OF STRUCTURE <ls_confirmation> TO <lv_value>.
          ASSIGN COMPONENT lv_unit_name OF STRUCTURE <ls_confirmation> TO <lv_unit>.
          IF <lv_value> IS NOT ASSIGNED OR <lv_unit> IS NOT ASSIGNED
              OR <ls_confirmation>-bmsch <= 0 OR zcl_modmes_oee=>is_time_unit( <lv_unit> ) = abap_false.
            ls_row-no_standard = ls_row-no_standard + 1.
            CONTINUE.
          ENDIF.
          DATA(lv_minutes) = zcl_modmes_oee=>to_minutes( iv_value = CONV #( <lv_value> )
                                                         iv_unit  = <lv_unit> ).
          ls_row-ideal_minutes = ls_row-ideal_minutes
            + lv_minutes * ( <ls_confirmation>-lmnga + <ls_confirmation>-xmnga ) / <ls_confirmation>-bmsch.
        ENDLOOP.

        DATA(ls_result) = zcl_modmes_oee=>calculate( VALUE #( planned_minutes  = ls_row-planned_minutes
                                                              downtime_minutes = ls_row-downtime_minutes
                                                              ideal_minutes    = ls_row-ideal_minutes
                                                              good_quantity    = ls_row-good_quantity
                                                              scrap_quantity   = ls_row-scrap_quantity ) ).
        ls_row-run_minutes      = ls_result-run_minutes.
        ls_row-availability_pct = ls_result-availability * 100.
        ls_row-performance_pct  = ls_result-performance * 100.
        ls_row-quality_pct      = ls_result-quality * 100.
        ls_row-oee_pct          = ls_result-oee * 100.
        APPEND ls_row TO lt_rows.
        lv_day = lv_day + 1.
      ENDWHILE.
    ENDLOOP.

    display( CHANGING ct_rows = lt_rows ).
  ENDMETHOD.

  METHOD day_bounds.
    DATA(lv_next) = CONV d( iv_day + 1 ).
    CONVERT DATE iv_day TIME '000000' INTO TIME STAMP ev_from TIME ZONE sy-zonlo.
    CONVERT DATE lv_next TIME '000000' INTO TIME STAMP ev_to TIME ZONE sy-zonlo.
  ENDMETHOD.

  METHOD display.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_alv)
                                CHANGING  t_table      = ct_rows ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv TYPE 'E'.
    ENDTRY.
    lo_alv->get_functions( )->set_default( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_display_settings( )->set_list_header( |OEE by work center and day, plant { p_werks }| ).
    TRY.
        DATA(lo_columns) = lo_alv->get_columns( ).
        lo_columns->get_column( 'DAY' )->set_medium_text( 'Day' ).
        lo_columns->get_column( 'PLANNED_MINUTES' )->set_medium_text( 'Planned min' ).
        lo_columns->get_column( 'DOWNTIME_MINUTES' )->set_medium_text( 'Downtime min' ).
        lo_columns->get_column( 'RUN_MINUTES' )->set_medium_text( 'Run min' ).
        lo_columns->get_column( 'IDEAL_MINUTES' )->set_medium_text( 'Standard min' ).
        lo_columns->get_column( 'GOOD_QUANTITY' )->set_medium_text( 'Yield' ).
        lo_columns->get_column( 'SCRAP_QUANTITY' )->set_medium_text( 'Scrap' ).
        lo_columns->get_column( 'AVAILABILITY_PCT' )->set_medium_text( 'Availability %' ).
        lo_columns->get_column( 'PERFORMANCE_PCT' )->set_medium_text( 'Performance %' ).
        lo_columns->get_column( 'QUALITY_PCT' )->set_medium_text( 'Quality %' ).
        lo_columns->get_column( 'OEE_PCT' )->set_medium_text( 'OEE %' ).
        lo_columns->get_column( 'NO_STANDARD' )->set_medium_text( 'No std. time' ).
      CATCH cx_salv_not_found.
        " Column names are fixed above; nothing to do.
    ENDTRY.
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  NEW lcl_app( )->run( ).
