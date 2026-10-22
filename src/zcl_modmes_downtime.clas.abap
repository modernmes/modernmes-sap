"! <p class="shorttext synchronized">ModernMES for SAP: machine downtime</p>
"! Downtime per work center, kept in table ZMODMES_DOWNTIME. A work center
"! has at most one open downtime (no end time yet) at a time.
CLASS zcl_modmes_downtime DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_downtimes TYPE STANDARD TABLE OF zmodmes_downtime WITH EMPTY KEY.

    "! Starts a downtime now. Returns abap_false when one is already open.
    METHODS start
      IMPORTING iv_werks          TYPE werks_d
                iv_arbpl          TYPE arbpl
                iv_reason         TYPE zmodmes_reason
                iv_aufnr          TYPE aufnr OPTIONAL
      RETURNING VALUE(rv_started) TYPE abap_bool.

    "! Ends the open downtime now. Returns abap_false when none is open.
    METHODS stop
      IMPORTING iv_werks          TYPE werks_d
                iv_arbpl          TYPE arbpl
      RETURNING VALUE(rv_stopped) TYPE abap_bool.

    "! The open downtime of a work center, initial when there is none.
    METHODS open_downtime
      IMPORTING iv_werks           TYPE werks_d
                iv_arbpl           TYPE arbpl
      RETURNING VALUE(rs_downtime) TYPE zmodmes_downtime.

    "! Downtimes of a work center that overlap [iv_from, iv_to), open ones
    "! included.
    METHODS list
      IMPORTING iv_werks            TYPE werks_d
                iv_arbpl            TYPE arbpl
                iv_from             TYPE tzntstmps
                iv_to               TYPE tzntstmps
      RETURNING VALUE(rt_downtimes) TYPE ty_downtimes.
ENDCLASS.


CLASS zcl_modmes_downtime IMPLEMENTATION.
  METHOD start.
    rv_started = abap_false.
    IF open_downtime( iv_werks = iv_werks
                      iv_arbpl = iv_arbpl ) IS NOT INITIAL.
      RETURN.
    ENDIF.

    DATA ls_downtime TYPE zmodmes_downtime.
    TRY.
        ls_downtime-id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        RETURN.
    ENDTRY.
    ls_downtime-werks      = iv_werks.
    ls_downtime-arbpl      = iv_arbpl.
    ls_downtime-reason     = iv_reason.
    ls_downtime-aufnr      = iv_aufnr.
    ls_downtime-created_by = sy-uname.
    GET TIME STAMP FIELD ls_downtime-start_ts.

    INSERT zmodmes_downtime FROM @ls_downtime.
    rv_started = xsdbool( sy-subrc = 0 ).
    COMMIT WORK.
  ENDMETHOD.

  METHOD stop.
    DATA(ls_downtime) = open_downtime( iv_werks = iv_werks
                                       iv_arbpl = iv_arbpl ).
    IF ls_downtime IS INITIAL.
      rv_stopped = abap_false.
      RETURN.
    ENDIF.

    GET TIME STAMP FIELD ls_downtime-end_ts.
    UPDATE zmodmes_downtime FROM @ls_downtime.
    rv_stopped = xsdbool( sy-subrc = 0 ).
    COMMIT WORK.
  ENDMETHOD.

  METHOD open_downtime.
    SELECT *
      FROM zmodmes_downtime
      WHERE werks  = @iv_werks
        AND arbpl  = @iv_arbpl
        AND end_ts = 0
      ORDER BY start_ts DESCENDING
      INTO TABLE @DATA(lt_open)
      UP TO 1 ROWS.
    IF lt_open IS NOT INITIAL.
      rs_downtime = lt_open[ 1 ].
    ENDIF.
  ENDMETHOD.

  METHOD list.
    SELECT *
      FROM zmodmes_downtime
      WHERE werks     = @iv_werks
        AND arbpl     = @iv_arbpl
        AND start_ts  < @iv_to
        AND ( end_ts >= @iv_from OR end_ts = 0 )
      ORDER BY start_ts
      INTO TABLE @rt_downtimes.
  ENDMETHOD.
ENDCLASS.
