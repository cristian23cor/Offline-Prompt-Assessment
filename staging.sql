USE DATABASE EJERCICIO_NUAAV;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_XML_TRANSACTIONS AS
WITH txn AS (
  SELECT
    t.value AS tx,
    XMLGET(t.value, 'Order')   AS ord,
    XMLGET(t.value, 'Payment') AS pay
  FROM EJERCICIO_NUAAV.RAW.XML_PARSED,
       LATERAL FLATTEN(input => doc:"$") t
  WHERE t.value:"@" = 'Transaction'
),
con_cliente AS (
  SELECT
    tx, ord, pay,
    XMLGET(ord, 'Customer') AS cust
  FROM txn
)
SELECT
  'ClientA' AS source_system,
  GET(XMLGET(tx,  'TransactionID'), '$')::STRING AS transaction_id,
  GET(XMLGET(ord, 'OrderID'),       '$')::STRING AS order_id,
  GET(XMLGET(ord, 'OrderDate'),     '$')::STRING AS order_date_raw,
  GET(XMLGET(cust, 'CustomerID'), '$')::STRING AS customer_id,
  GET(XMLGET(XMLGET(cust, 'Name'), 'FirstName'), '$')::STRING AS first_name,
  GET(XMLGET(XMLGET(cust, 'Name'), 'LastName'),  '$')::STRING AS last_name,
  GET(XMLGET(cust, 'Email'), '$')::STRING AS email,
  GET(XMLGET(pay, 'Method'), '$')::STRING AS payment_method,
  GET(XMLGET(pay, 'Amount'), '$')::STRING AS payment_amount_raw,
  XMLGET(pay, 'Amount'):"@currency"::STRING AS payment_currency,
  tx AS raw_transaction
FROM con_cliente;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_XML_ITEMS AS
WITH txn AS (
  SELECT
    t.value AS tx,
    GET(XMLGET(t.value, 'TransactionID'), '$')::STRING AS transaction_id
  FROM EJERCICIO_NUAAV.RAW.XML_PARSED,
       LATERAL FLATTEN(input => doc:"$") t
  WHERE t.value:"@" = 'Transaction'
),
nodos AS (
  SELECT
    transaction_id,
    i.value AS nodo,
    TYPEOF(i.value) AS tipo
  FROM txn,
       LATERAL FLATTEN(input => XMLGET(tx, 'Items')) i
  WHERE TYPEOF(i.value) IN ('XML', 'ARRAY')
),
expandidos AS (
  SELECT transaction_id, nodo AS item
  FROM nodos
  WHERE tipo = 'XML'

  UNION ALL

  SELECT n.transaction_id, a.value AS item
  FROM nodos n,
       LATERAL FLATTEN(input => n.nodo) a
  WHERE n.tipo = 'ARRAY'
)
SELECT
  'ClientA' AS source_system,
  transaction_id,
  ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY 1) AS item_seq,
  item
FROM expandidos;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_XML_ITEMS_FLAT AS
SELECT
  source_system,
  transaction_id,
  item_seq,
  GET(XMLGET(item, 'SKU'),         '$')::STRING AS sku,
  GET(XMLGET(item, 'Description'), '$')::STRING AS description,
  GET(XMLGET(item, 'Quantity'),    '$')::STRING AS quantity_raw,
  GET(XMLGET(item, 'UnitPrice'),   '$')::STRING AS unit_price_raw,
  XMLGET(item, 'UnitPrice'):"@currency"::STRING AS currency,
  item AS raw_item
FROM EJERCICIO_NUAAV.STAGING.V_XML_ITEMS;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_JSON_TRANSACTIONS AS
SELECT
  doc:client::STRING AS source_system,
  t.value:id::STRING                   AS transaction_id,
  t.value:order:id::STRING             AS order_id,
  t.value:order:date::STRING           AS order_date_raw,
  t.value:order:customer:id::STRING    AS customer_id,
  t.value:order:customer:name::STRING  AS customer_name,
  t.value:order:customer:email::STRING AS email,
  t.value:payment:method::STRING       AS payment_method,
  t.value:payment:total::STRING        AS payment_amount_raw,
  ARRAY_SIZE(t.value:items)            AS num_items,
  t.value AS raw_transaction
FROM EJERCICIO_NUAAV.RAW.JSON_PARSED,
     LATERAL FLATTEN(input => doc:transactions) t;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_JSON_ITEMS AS
SELECT
  doc:client::STRING AS source_system,
  t.value:id::STRING AS transaction_id,
  i.index + 1        AS item_seq,
  i.value:sku::STRING            AS sku,
  i.value:description::STRING    AS description,
  i.value:qty::STRING            AS quantity_raw,
  i.value:price:amount::STRING   AS unit_price_raw,
  i.value:price:currency::STRING AS currency,
  i.value AS raw_item
FROM EJERCICIO_NUAAV.RAW.JSON_PARSED,
     LATERAL FLATTEN(input => doc:transactions) t,
     LATERAL FLATTEN(input => t.value:items) i;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_CSV_ORDERS AS
WITH datos AS (
  SELECT file_name, line_number, linea
  FROM EJERCICIO_NUAAV.STAGING.V_CSV_LINES_CLEAN
  WHERE file_name ILIKE '%order%'
    AND linea NOT ILIKE 'order_id,%'
)
SELECT
  CASE WHEN file_name LIKE 'clientA%' THEN 'ClientA' ELSE 'ClientC' END AS source_system,
  file_name,
  line_number,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 1)), '') AS order_id,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 2)), '') AS customer_id,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 3)), '') AS order_date_raw,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 4)), '') AS order_status,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 5)), '') AS channel
FROM datos;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_CSV_CUSTOMERS_A AS
WITH datos AS (
  SELECT line_number, linea
  FROM EJERCICIO_NUAAV.STAGING.V_CSV_LINES_CLEAN
  WHERE file_name = 'clientA/Customer.csv'
    AND linea NOT ILIKE 'customer_id,%'
)
SELECT
  'ClientA' AS source_system,
  line_number,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 1)), '') AS customer_id,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 2)), '') AS first_name,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 3)), '') AS last_name,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 4)), '') AS email,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 5)), '') AS loyalty_tier,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 6)), '') AS signup_source,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 7)), '') AS is_active_raw
FROM datos;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_CSV_CUSTOMERS_C AS
WITH datos AS (
  SELECT line_number, linea
  FROM EJERCICIO_NUAAV.STAGING.V_CSV_LINES_CLEAN
  WHERE file_name = 'clientB/Customer.CSV'
    AND linea NOT ILIKE 'customer_id,%'
)
SELECT
  'ClientC' AS source_system,
  line_number,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 1)), '') AS customer_id,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 2)), '') AS customer_name,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 3)), '') AS email,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 4)), '') AS segment,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 5)), '') AS is_active_raw
FROM datos;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_CSV_PRODUCTS AS
WITH datos AS (
  SELECT file_name, line_number, linea
  FROM EJERCICIO_NUAAV.STAGING.V_CSV_LINES_CLEAN
  WHERE file_name ILIKE '%product%'
    AND linea NOT ILIKE 'sku,%'
)
SELECT
  CASE WHEN file_name LIKE 'clientA%' THEN 'ClientA' ELSE 'ClientC' END AS source_system,
  file_name,
  line_number,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 1)), '') AS sku,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 2)), '') AS product_name,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 3)), '') AS category,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 4)), '') AS unit_price_raw,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 5)), '') AS currency,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 6)), '') AS is_active_raw
FROM datos;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_CSV_PAYMENTS_C AS
WITH datos AS (
  SELECT line_number, linea
  FROM EJERCICIO_NUAAV.STAGING.V_CSV_LINES_CLEAN
  WHERE file_name = 'clientB/Payments.csv'
    AND linea NOT ILIKE 'payment_id,%'
)
SELECT
  'ClientC' AS source_system,
  line_number,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 1)), '') AS payment_id,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 2)), '') AS order_id,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 3)), '') AS payment_method,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 4)), '') AS amount_raw,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 5)), '') AS currency,
  NULLIF(TRIM(SPLIT_PART(linea, ',', 6)), '') AS status
FROM datos;


