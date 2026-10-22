# ModernMES for SAP

Free, open-source shop floor basics that run inside SAP: a work center queue,
operation confirmations, machine downtime and a daily OEE report. Plain ABAP,
installed with [abapGit](https://abapgit.org), MIT licensed.

> **Status: beta.** The code passes abaplint and its unit tests, but it has
> not yet been run on a real SAP system. Try it in a sandbox or test client
> first, and please open an issue with what you find.

## What it does

| Program | What it does |
|---|---|
| `ZMODMES_QUEUE` | Open operations of one work center: released production orders, operations not yet fully confirmed, earliest start first. Click the confirm icon of a row to post yield, scrap and final confirmation. |
| `ZMODMES_DOWNTIME` | Start or end a downtime for a work center with a reason (and optionally the order it held up), or list recent downtimes. |
| `ZMODMES_OEE` | OEE per work center and day: availability, performance, quality and OEE, with the minutes and quantities behind them. |

Confirmations are posted with SAP's standard BAPI
(`BAPI_PRODORDCONF_CREATE_TT`), the same posting as transaction CO11N. SAP
proposes activities and goods movements from the order first
(`BAPI_PRODORDCONF_GET_TT_PROP`), so backflushing and automatic goods receipt
follow your routing, control keys and BOM exactly as they do in CO11N. If SAP
refuses a confirmation, nothing is posted and SAP's own messages are shown.

### How OEE is calculated

For each work center and day:

- **Availability** = (planned minutes − downtime minutes) / planned minutes.
  Planned minutes per day is a selection parameter (default 480). Downtime
  comes from `ZMODMES_DOWNTIME`; a downtime still open counts until now.
- **Performance** = standard minutes / run minutes. Standard minutes are the
  confirmed quantity (yield + scrap) times the operation's standard value per
  base quantity. Pick which standard value (1–6) holds machine time for your
  standard value key; the default is 2. Units S, MIN and H are converted; other
  units are counted in the *No std. time* column instead. Performance above
  100% usually means the routing's standard times are looser than reality.
- **Quality** = yield / (yield + scrap).
- **OEE** = availability × performance × quality.

Quantities come from production order confirmations (table AFRU) by posting
date; reversed confirmations are left out.

## Requirements

- SAP NetWeaver / ABAP Platform 7.50 or newer with the PP module: SAP ECC 6.0
  EhP8, or SAP S/4HANA on-premise or private cloud.
- [abapGit](https://abapgit.org) to install it.

It reads standard tables (AUFK, AFKO, AFVC, AFVV, AFRU, CRHD, JEST, MAKT)
directly, which classic ABAP allows. It does not run in SAP S/4HANA Cloud,
public edition, or in the BTP ABAP environment.

## Installation

1. In abapGit choose **New Online**, enter
   `https://github.com/modernmes/modernmes-sap` and a package, for example
   `ZMODMES` (or `$ZMODMES` to try it without transports).
2. **Pull**. abapGit creates the table, data element, classes and programs.
3. Run the programs with SA38 or SE38, or give them transaction codes in SE93.

Without internet access from SAP, download the repository as a ZIP and use
abapGit's **New Offline** → **Import ZIP**.

## Objects

| Object | Type | Purpose |
|---|---|---|
| `ZMODMES_DOWNTIME` | Table | Downtime per work center (start, end, reason, order, user) |
| `ZMODMES_REASON` | Data element | Downtime reason text |
| `ZCL_MODMES_QUEUE` | Class | Reads a work center's open operations |
| `ZCL_MODMES_CONFIRM` | Class | Posts a confirmation through the standard BAPIs |
| `ZCL_MODMES_DOWNTIME` | Class | Starts, ends and lists downtimes |
| `ZCL_MODMES_OEE` | Class | OEE arithmetic, with unit tests |
| `ZMODMES_QUEUE`, `ZMODMES_DOWNTIME`, `ZMODMES_OEE` | Programs | The three screens above |

## Authorizations

- Confirmations go through SAP's BAPI, which runs the same authorization
  checks as CO11N.
- Writing downtimes is not authorization-checked by the code. Control who may
  run `ZMODMES_DOWNTIME` (an authorization group on the program, or a
  transaction code with its own check).

## Development

The checks run on every push in GitHub Actions and can be run locally with
Node.js 20:

```sh
npm ci
npm test   # abaplint, then the ABAP unit tests
```

The unit tests are transpiled to JavaScript with the
[abaplint transpiler](https://github.com/abaplint/transpiler), so they run
without an SAP system. Inside SAP, run them as usual with Ctrl+Shift+F10 on
`ZCL_MODMES_OEE`.

Pull requests are welcome. Please keep to the existing style and add a unit
test for new logic.

## Need more than the basics?

This module covers the essentials inside SAP. [ModernMES](https://modernmes.com/en/)
is the full manufacturing execution system: operator terminals at the machine
with badge sign-in and barcoded route cards, a live shop floor view, quality
and maintenance records, reports, and connections to SAP Business One,
SAP S/4HANA and other ERPs, as a cloud service or on-premise.

## License

[MIT](LICENSE). SAP, S/4HANA and other SAP products are trademarks of SAP SE.
This project is not affiliated with or endorsed by SAP SE.
