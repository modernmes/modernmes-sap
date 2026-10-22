"! <p class="shorttext synchronized">ModernMES for SAP: OEE calculation</p>
"! Overall equipment effectiveness = availability x performance x quality.
"! Plain arithmetic without database access, so it is unit tested anywhere.
CLASS zcl_modmes_oee DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_ratio TYPE p LENGTH 8 DECIMALS 4.
    TYPES ty_minutes TYPE p LENGTH 10 DECIMALS 2.
    TYPES ty_quantity TYPE p LENGTH 13 DECIMALS 3.

    TYPES:
      BEGIN OF ty_input,
        "! Time the machine was scheduled to run
        planned_minutes  TYPE ty_minutes,
        "! Recorded downtime inside the planned time
        downtime_minutes TYPE ty_minutes,
        "! Standard time for everything produced (good and scrap)
        ideal_minutes    TYPE ty_minutes,
        good_quantity    TYPE ty_quantity,
        scrap_quantity   TYPE ty_quantity,
      END OF ty_input.

    TYPES:
      BEGIN OF ty_result,
        run_minutes  TYPE ty_minutes,
        availability TYPE ty_ratio,
        "! Above 1 when the routing's standard times are looser than reality
        performance  TYPE ty_ratio,
        quality      TYPE ty_ratio,
        oee          TYPE ty_ratio,
      END OF ty_result.

    "! Availability = run time / planned time, performance = ideal time /
    "! run time, quality = good / (good + scrap). A factor without data
    "! (no planned time, no run time, nothing produced) is 0.
    CLASS-METHODS calculate
      IMPORTING is_input         TYPE ty_input
      RETURNING VALUE(rs_result) TYPE ty_result.

    "! Whether to_minutes can convert this unit: the internal units S, MIN and H.
    CLASS-METHODS is_time_unit
      IMPORTING iv_unit         TYPE csequence
      RETURNING VALUE(rv_known) TYPE abap_bool.

    "! A routing standard value in minutes; 0 for a unit is_time_unit refuses.
    CLASS-METHODS to_minutes
      IMPORTING iv_value          TYPE decfloat34
                iv_unit           TYPE csequence
      RETURNING VALUE(rv_minutes) TYPE decfloat34.

    "! Seconds that the intervals [from1, to1) and [from2, to2) share,
    "! all given in seconds on the same clock.
    CLASS-METHODS overlap_seconds
      IMPORTING iv_from1          TYPE decfloat34
                iv_to1            TYPE decfloat34
                iv_from2          TYPE decfloat34
                iv_to2            TYPE decfloat34
      RETURNING VALUE(rv_seconds) TYPE decfloat34.

  PRIVATE SECTION.
    CLASS-METHODS ratio
      IMPORTING iv_part         TYPE decfloat34
                iv_whole        TYPE decfloat34
      RETURNING VALUE(rv_ratio) TYPE ty_ratio.
ENDCLASS.


CLASS zcl_modmes_oee IMPLEMENTATION.
  METHOD calculate.
    DATA(lv_downtime) = nmin( val1 = is_input-downtime_minutes
                              val2 = is_input-planned_minutes ).
    rs_result-run_minutes  = is_input-planned_minutes - lv_downtime.
    rs_result-availability = ratio( iv_part  = rs_result-run_minutes
                                    iv_whole = is_input-planned_minutes ).
    rs_result-performance  = ratio( iv_part  = is_input-ideal_minutes
                                    iv_whole = rs_result-run_minutes ).
    rs_result-quality      = ratio( iv_part  = is_input-good_quantity
                                    iv_whole = is_input-good_quantity + is_input-scrap_quantity ).
    rs_result-oee = rs_result-availability * rs_result-performance * rs_result-quality.
  ENDMETHOD.

  METHOD is_time_unit.
    DATA(lv_unit) = to_upper( condense( iv_unit ) ).
    rv_known = xsdbool( lv_unit = 'S' OR lv_unit = 'MIN' OR lv_unit = 'H' ).
  ENDMETHOD.

  METHOD to_minutes.
    CASE to_upper( condense( iv_unit ) ).
      WHEN 'S'.
        rv_minutes = iv_value / 60.
      WHEN 'MIN'.
        rv_minutes = iv_value.
      WHEN 'H'.
        rv_minutes = iv_value * 60.
      WHEN OTHERS.
        rv_minutes = 0.
    ENDCASE.
  ENDMETHOD.

  METHOD overlap_seconds.
    DATA(lv_from) = nmax( val1 = iv_from1
                          val2 = iv_from2 ).
    DATA(lv_to) = nmin( val1 = iv_to1
                        val2 = iv_to2 ).
    rv_seconds = nmax( val1 = lv_to - lv_from
                       val2 = 0 ).
  ENDMETHOD.

  METHOD ratio.
    IF iv_whole <= 0.
      rv_ratio = 0.
      RETURN.
    ENDIF.
    rv_ratio = iv_part / iv_whole.
  ENDMETHOD.
ENDCLASS.
