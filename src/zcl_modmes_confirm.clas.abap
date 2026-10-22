"! <p class="shorttext synchronized">ModernMES for SAP: operation confirmation</p>
"! Posts a production order confirmation through SAP's standard BAPI, the
"! same posting as transaction CO11N. SAP proposes activities and goods
"! movements (backflush, automatic goods receipt) from the order, so they
"! follow the routing, control key and BOM exactly as in CO11N.
CLASS zcl_modmes_confirm DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_request,
        aufnr TYPE aufnr,
        vornr TYPE afvc-vornr,
        yield TYPE afru-lmnga,
        scrap TYPE afru-xmnga,
        unit  TYPE afru-meinh,
        "! abap_true: final confirmation, the operation is then complete
        final TYPE abap_bool,
        text  TYPE bapi_pp_timeticket-conf_text,
      END OF ty_request.

    TYPES ty_messages TYPE STANDARD TABLE OF bapiret2 WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        success  TYPE abap_bool,
        "! SAP's messages; they say why when nothing was posted
        messages TYPE ty_messages,
      END OF ty_result.

    "! Posts and commits the confirmation. Nothing is posted when SAP reports
    "! an error.
    METHODS post
      IMPORTING is_request       TYPE ty_request
      RETURNING VALUE(rs_result) TYPE ty_result.

  PRIVATE SECTION.
    TYPES ty_timetickets TYPE STANDARD TABLE OF bapi_pp_timeticket WITH EMPTY KEY.
    TYPES ty_goodsmovements TYPE STANDARD TABLE OF bapi2017_gm_item_create WITH EMPTY KEY.
    TYPES ty_links TYPE STANDARD TABLE OF bapi_link_conf_goodsmov WITH EMPTY KEY.
    TYPES ty_details TYPE STANDARD TABLE OF bapi_coru_return WITH EMPTY KEY.

    METHODS collect
      IMPORTING is_return   TYPE bapiret1
                it_details  TYPE ty_details
      CHANGING  ct_messages TYPE ty_messages.
ENDCLASS.


CLASS zcl_modmes_confirm IMPLEMENTATION.
  METHOD post.
    DATA lt_timetickets TYPE ty_timetickets.
    DATA lt_goodsmovements TYPE ty_goodsmovements.
    DATA lt_links TYPE ty_links.
    DATA lt_details TYPE ty_details.
    DATA ls_return TYPE bapiret1.

    rs_result-success = abap_false.

    lt_timetickets = VALUE #( ( orderid        = is_request-aufnr
                                operation      = is_request-vornr
                                yield          = is_request-yield
                                scrap          = is_request-scrap
                                conf_quan_unit = is_request-unit ) ).

    " Let SAP propose activities and goods movements for this quantity.
    CALL FUNCTION 'BAPI_PRODORDCONF_GET_TT_PROP'
      EXPORTING
        propose            = VALUE bapi_pp_conf_prop( activity      = abap_true
                                                      goodsmovement = abap_true )
      IMPORTING
        return             = ls_return
      TABLES
        timetickets        = lt_timetickets
        goodsmovements     = lt_goodsmovements
        link_conf_goodsmov = lt_links
        detail_return      = lt_details.
    collect( EXPORTING is_return   = ls_return
                       it_details  = lt_details
             CHANGING  ct_messages = rs_result-messages ).
    IF line_exists( rs_result-messages[ type = 'E' ] ) OR line_exists( rs_result-messages[ type = 'A' ] ).
      RETURN.
    ENDIF.

    LOOP AT lt_timetickets ASSIGNING FIELD-SYMBOL(<ls_ticket>).
      <ls_ticket>-yield     = is_request-yield.
      <ls_ticket>-scrap     = is_request-scrap.
      <ls_ticket>-fin_conf  = COND #( WHEN is_request-final = abap_true THEN 'X' ELSE space ).
      <ls_ticket>-conf_text = is_request-text.
    ENDLOOP.

    CLEAR: ls_return, lt_details.
    CALL FUNCTION 'BAPI_PRODORDCONF_CREATE_TT'
      EXPORTING
        post_wrong_entries = '0'
      IMPORTING
        return             = ls_return
      TABLES
        timetickets        = lt_timetickets
        goodsmovements     = lt_goodsmovements
        link_conf_goodsmov = lt_links
        detail_return      = lt_details.
    collect( EXPORTING is_return   = ls_return
                       it_details  = lt_details
             CHANGING  ct_messages = rs_result-messages ).

    IF line_exists( rs_result-messages[ type = 'E' ] ) OR line_exists( rs_result-messages[ type = 'A' ] ).
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      RETURN.
    ENDIF.

    DATA ls_commit TYPE bapiret2.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait   = abap_true
      IMPORTING
        return = ls_commit.
    IF ls_commit-type = 'E' OR ls_commit-type = 'A'.
      APPEND ls_commit TO rs_result-messages.
      RETURN.
    ENDIF.
    rs_result-success = abap_true.
  ENDMETHOD.

  METHOD collect.
    IF is_return-type IS NOT INITIAL.
      APPEND VALUE #( type       = is_return-type
                      id         = is_return-id
                      number     = is_return-number
                      message    = is_return-message
                      message_v1 = is_return-message_v1
                      message_v2 = is_return-message_v2
                      message_v3 = is_return-message_v3
                      message_v4 = is_return-message_v4 ) TO ct_messages.
    ENDIF.
    LOOP AT it_details ASSIGNING FIELD-SYMBOL(<ls_detail>) WHERE type IS NOT INITIAL.
      APPEND VALUE #( type       = <ls_detail>-type
                      id         = <ls_detail>-id
                      number     = <ls_detail>-number
                      message    = <ls_detail>-message
                      message_v1 = <ls_detail>-message_v1
                      message_v2 = <ls_detail>-message_v2
                      message_v3 = <ls_detail>-message_v3
                      message_v4 = <ls_detail>-message_v4 ) TO ct_messages.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
