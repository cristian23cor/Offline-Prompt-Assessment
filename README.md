# Financial Data Ingestion and Canonical Modeling

Ingests transaction files from two clients into Snowflake and transforms them into one canonical model. Three formats: XML, JSON and CSV. Everything is done in SQL, with no Python and no external ETL tools.

## How to run

Upload the source files to the stage in two folders, `clientA/` and `clientB/`, then run the scripts in order:

| File | What it does |
|---|---|
| `stup.sql` | Database, schemas, stage, file formats |
| `raw.sql` | Loads every file line by line into one table |
| `repair_views.sql` | Fixes format problems so the files can be parsed |
| `staging.sql` | Flattens XML, JSON and CSV into rows and columns |
| `ddlcanonical.sql` | Canonical DDL, transformation and quality rules |
| `validation.sql` | Row counts, referential integrity and key uniqueness |

The scripts can be re-run. Tables are replaced or truncated before each load.

## Architecture

Three layers:

- RAW keeps the files exactly as received, one row per line, with file name and line number.
- STAGING repairs and flattens. No data is dropped here.
- CANONICAL holds the common model plus a rejects table.

RAW stores raw text instead of parsed objects because three of the files cannot be parsed as they are. Loading them as text first makes it possible to repair them with SQL and keeps the original available if the logic changes.

## The files are broken, not just dirty

The first problem is not bad data. Six of the fifteen files are invalid in their format and no parser will read them.

| Problem | Files | Fix |
|---|---|---|
| Markers `----- START OF FILE -----` outside the root element | 2 XML | Remove the marker lines and rebuild the document |
| Comments `// duplicate` inside JSON | 1 JSON | Cut from `//` to end of line, drop lines that are only comments |
| Annotations `<-- invalid customer` inside CSV rows | 7 CSV | Cut the annotation off the end of the row |

Two findings worth naming:

The file extension says nothing about validity. `ClientA_Transactions_4.txt` parses fine, while `ClientA_Transactions_1.xml` and `_7.xml` do not.

The seven XML files are one document cut into pieces. File 1 opens `<SalesData>`, file 7 closes it, and the ones in between are fragments with no root. They are joined back into a single document, keeping the original attributes.

## Canonical model

| Table | Grain |
|---|---|
| `DIM_CUSTOMER` | One customer per source system |
| `DIM_PRODUCT` | One product per source system |
| `FACT_ORDER` | One order |
| `FACT_ORDER_ITEM` | One line per order |
| `FACT_PAYMENT` | One payment |
| `REJECTS` | One detected anomaly |

The natural key is not the source ID, it is the pair `(source_system, source_id)`. `CUST-A-0001` and `C-CUST-5001` live in different ID spaces, and a third client could reuse either one. Surrogate keys are built on that pair.

## Design decisions

Names are not split. ClientA sends `first_name` and `last_name`, ClientC sends one full name. The model keeps all three columns and leaves the split fields null for ClientC. Splitting "Chris Evans" by assuming the first word is the first name would be inventing data.

Dimensions are built from every source, not only from the master file. `Customer.csv` covers 22 customers but the XML transactions mention 37. Using the CSV alone would leave 40% of ClientA orders with no customer. Fields that only exist in the master stay null for the rest, which makes the origin visible.

Orphan references point to an unknown member instead of null. Customer key `-1` and product key `-1` keep joins working and keep the problem visible in reports.

Bad rows are quarantined, not deleted. Every anomaly goes to `REJECTS` with a rule name and a severity. Nothing is silently dropped.

## Anomalies

Thirteen rules, 73 cases.

| Severity | Meaning | Cases |
|---|---|---|
| FATAL | Identity or reference is broken | 10 |
| REVIEW | Value is suspicious, needs a business decision | 22 |
| WARNING | Data is missing but the record still loads | 41 |

Duplicates are not all the same. Six transaction IDs repeat, but only one has different content between versions. The same happens with products: three SKUs repeat, one with two different prices. Applying one rule to all of them would lose data in those cases.

Two tie-break rules came out of the data:

For transactions, the version that reconciles with the payment amount wins. TXN-1001 has two versions, one with two items and one with one. The payment of 97.48 only matches the two-item version.

For products, a positive catalog price wins over a negative one. `C-SKU-011` appears at -59.99 and 59.99. `SKU-A-011` only appears at -9.99, so it stays negative and is flagged. When there is no information to decide, nothing is invented.

## Findings

21 of 40 ClientA orders have a payment that does not match the sum of their items. The rule splits them into four patterns:

| Pattern | Cases | Likely cause |
|---|---|---|
| Same value, opposite sign | 9 | Sign error in quantity or amount |
| Items are exactly double | 8 | Quantity applied twice |
| Payment is zero with real items | 2 | Payment not recorded |
| No pattern | 5 | Needs manual review |

The sources do not cover the same period. ClientA's order master stops at ORD-5020 while transactions reach ORD-5041. ClientC is the opposite: the CSV has 20 orders and the JSON only 9.

The two ClientC sources disagree on one payment. `C-ORD-9006` is PayPal in the CSV and CreditCard in the JSON, with the same amount. The CSV is treated as authoritative since it is a payment master with its own ID, currency and status.

## Assumptions

The folder named `Client B` contains ClientC data. The JSON declares `"client": "ClientC"` and every ID uses the `C-` prefix, including the CSV files in that folder. The prompt mentions three clients but only two are present.

The JSON is incomplete. Its own comments describe 120 transactions with 20 to 30 anomalies; the file has 11.

Email validation is deliberately simple. It checks for an `@` and a dot after it, which catches the seeded cases without pretending to be a full RFC check.
