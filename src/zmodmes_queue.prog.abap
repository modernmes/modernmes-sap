*&---------------------------------------------------------------------*
*& ModernMES for SAP: work center queue
*&
*& Lists the open operations of one work center. Click the confirm icon
*& of a row to post yield and scrap for that operation (same posting as
*& CO11N). https://github.com/modernmes/modernmes-sap
*&---------------------------------------------------------------------*
REPORT zmodmes_queue.

PARAMETERS p_werks TYPE werks_d OBLIGATORY MEMORY ID wrk.
PARAMETERS p_arbpl TYPE arbpl OBLIGATORY MEMORY ID agr.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_row,
        confirm TYPE icon_d.
        INCLUDE TYPE zcl_modmes_queue=>ty_operation.
    TYPES END OF ty_row.
    TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.
    TYPES ty_fields TYPE STANDARD TABLE OF sval WITH EMPTY KEY.

    " ICON_OKAY
    CONSTANTS c_icon_confirm TYPE icon_d VALUE '@0V@'.

    DATA mt_rows TYPE ty_rows.
    DATA mo_alv TYPE REF TO cl_salv_table.

    METHODS load.
    METHODS confirm
      IMPORTING is_row TYPE ty_row.
    METHODS on_link_click
      FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    load( ).
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = mo_alv
                                CHANGING  t_table      = mt_rows ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv TYPE 'E'.
    ENDTRY.

    mo_alv->get_functions( )->set_default( abap_true ).
    mo_alv->get_columns( )->set_optimize( abap_true ).
    mo_alv->get_display_settings( )->set_list_header(
      |Work center { p_arbpl } / plant { p_werks }: open operations| ).
    TRY.
        DATA(lo_column) = CAST cl_salv_column_table( mo_alv->get_columns( )->get_column( 'CONFIRM' ) ).
        lo_column->set_icon( abap_true ).
        lo_column->set_cell_type( if_salv_c_cell_type=>hotspot ).
        lo_column->set_short_text( 'Confirm' ).
        lo_column->set_medium_text( 'Confirm' ).
        lo_column->set_long_text( 'Confirm operation' ).
        lo_column = CAST cl_salv_column_table( mo_alv->get_columns( )->get_column( 'OPEN_QTY' ) ).
        lo_column->set_short_text( 'Open' ).
        lo_column->set_medium_text( 'Open quantity' ).
        lo_column->set_long_text( 'Open quantity' ).
        mo_alv->get_columns( )->get_column( 'WERKS' )->set_visible( abap_false ).
        mo_alv->get_columns( )->get_column( 'ARBPL' )->set_visible( abap_false ).
      CATCH cx_salv_not_found.
        " Column names are fixed above; nothing to do.
    ENDTRY.

    SET HANDLER on_link_click FOR mo_alv->get_event( ).
    mo_alv->display( ).
  ENDMETHOD.

  METHOD load.
    DATA(lt_operations) = NEW zcl_modmes_queue( )->read( iv_werks = p_werks
                                                         iv_arbpl = p_arbpl ).
    CLEAR mt_rows.
    LOOP AT lt_operations ASSIGNING FIELD-SYMBOL(<ls_operation>).
      APPEND INITIAL LINE TO mt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      MOVE-CORRESPONDING <ls_operation> TO <ls_row>.
      <ls_row>-confirm = c_icon_confirm.
    ENDLOOP.
  ENDMETHOD.

  METHOD on_link_click.
    READ TABLE mt_rows INDEX row ASSIGNING FIELD-SYMBOL(<ls_row>).
    IF sy-subrc <> 0 OR column <> 'CONFIRM'.
      RETURN.
    ENDIF.
    confirm( <ls_row> ).
  ENDMETHOD.

  METHOD confirm.
    " Yield proposed as the open quantity; final when nothing stays open.
    DATA(lt_fields) = VALUE ty_fields(
      ( tabname = 'AFRU' fieldname = 'LMNGA' value = condense( CONV string( is_row-open_qty ) ) )
      ( tabname = 'AFRU' fieldname = 'XMNGA' value = '0' )
      ( tabname = 'AFRU' fieldname = 'AUERU' value = 'X' ) ).
    DATA lv_answer TYPE c LENGTH 1.

    CALL FUNCTION 'POPUP_GET_VALUES'
      EXPORTING
        popup_title     = |Confirm { is_row-aufnr ALPHA = OUT } / { is_row-vornr }|
      IMPORTING
        returncode      = lv_answer
      TABLES
        fields          = lt_fields
      EXCEPTIONS
        error_in_fields = 1
        OTHERS          = 2.
    IF sy-subrc <> 0 OR lv_answer = 'A'.
      RETURN.
    ENDIF.

    DATA ls_request TYPE zcl_modmes_confirm=>ty_request.
    ls_request-aufnr = is_row-aufnr.
    ls_request-vornr = is_row-vornr.
    ls_request-unit  = is_row-meinh.
    ls_request-final = xsdbool( lt_fields[ fieldname = 'AUERU' ]-value IS NOT INITIAL ).
    TRY.
        " The popup returns quantities in internal format (decimal point).
        ls_request-yield = condense( lt_fields[ fieldname = 'LMNGA' ]-value ).
        ls_request-scrap = condense( lt_fields[ fieldname = 'XMNGA' ]-value ).
      CATCH cx_sy_conversion_error.
        MESSAGE 'Enter the quantities as numbers' TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.
    IF ls_request-yield < 0 OR ls_request-scrap < 0
        OR ( ls_request-yield = 0 AND ls_request-scrap = 0 AND ls_request-final = abap_false ).
      MESSAGE 'Nothing to confirm' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    DATA(ls_result) = NEW zcl_modmes_confirm( )->post( ls_request ).
    IF ls_result-success = abap_true.
      MESSAGE |Confirmed { is_row-aufnr ALPHA = OUT } / { is_row-vornr }| TYPE 'S'.
      load( ).
      mo_alv->refresh( ).
      RETURN.
    ENDIF.

    " Show SAP's own messages: why the confirmation was refused.
    DATA lt_log TYPE STANDARD TABLE OF bapiret2 WITH EMPTY KEY.
    lt_log = ls_result-messages.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_log)
                                CHANGING  t_table      = lt_log ).
        lo_log->set_screen_popup( start_column = 5
                                  end_column   = 120
                                  start_line   = 3
                                  end_line     = 15 ).
        lo_log->display( ).
      CATCH cx_salv_msg.
        MESSAGE 'The confirmation was not posted' TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  NEW lcl_app( )->run( ).
