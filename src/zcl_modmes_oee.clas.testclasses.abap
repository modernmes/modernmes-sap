CLASS ltcl_oee DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS textbook_example FOR TESTING.
    METHODS downtime_longer_than_plan FOR TESTING.
    METHODS no_data_gives_zero FOR TESTING.
    METHODS units FOR TESTING.
    METHODS overlap FOR TESTING.
ENDCLASS.


CLASS ltcl_oee IMPLEMENTATION.
  METHOD textbook_example.
    " 480 min planned, 48 min down, 1 min per piece, 400 made, 8 of them scrap.
    DATA(ls_result) = zcl_modmes_oee=>calculate( VALUE #( planned_minutes  = 480
                                                          downtime_minutes = 48
                                                          ideal_minutes    = 400
                                                          good_quantity    = 392
                                                          scrap_quantity   = 8 ) ).
    cl_abap_unit_assert=>assert_equals( exp = 432
                                        act = ls_result-run_minutes ).
    cl_abap_unit_assert=>assert_equals( exp = '0.9000'
                                        act = ls_result-availability ).
    cl_abap_unit_assert=>assert_equals( exp = '0.9259'
                                        act = ls_result-performance ).
    cl_abap_unit_assert=>assert_equals( exp = '0.9800'
                                        act = ls_result-quality ).
    cl_abap_unit_assert=>assert_equals( exp = '0.8166'
                                        act = ls_result-oee ).
  ENDMETHOD.

  METHOD downtime_longer_than_plan.
    DATA(ls_result) = zcl_modmes_oee=>calculate( VALUE #( planned_minutes  = 60
                                                          downtime_minutes = 90 ) ).
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = ls_result-run_minutes ).
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = ls_result-oee ).
  ENDMETHOD.

  METHOD no_data_gives_zero.
    DATA(ls_result) = zcl_modmes_oee=>calculate( VALUE #( ) ).
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = ls_result-availability ).
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = ls_result-quality ).
  ENDMETHOD.

  METHOD units.
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = zcl_modmes_oee=>to_minutes( iv_value = 120
                                                                          iv_unit  = 'S' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 90
                                        act = zcl_modmes_oee=>to_minutes( iv_value = '1.5'
                                                                          iv_unit  = 'H' ) ).
    cl_abap_unit_assert=>assert_true( zcl_modmes_oee=>is_time_unit( ' min' ) ).
    cl_abap_unit_assert=>assert_false( zcl_modmes_oee=>is_time_unit( 'KG' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = zcl_modmes_oee=>to_minutes( iv_value = 1
                                                                          iv_unit  = 'KG' ) ).
  ENDMETHOD.

  METHOD overlap.
    cl_abap_unit_assert=>assert_equals( exp = 30
                                        act = zcl_modmes_oee=>overlap_seconds( iv_from1 = 0
                                                                               iv_to1   = 60
                                                                               iv_from2 = 30
                                                                               iv_to2   = 120 ) ).
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = zcl_modmes_oee=>overlap_seconds( iv_from1 = 0
                                                                               iv_to1   = 10
                                                                               iv_from2 = 20
                                                                               iv_to2   = 30 ) ).
  ENDMETHOD.
ENDCLASS.
