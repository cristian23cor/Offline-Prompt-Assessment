USE WAREHOUSE COMPUTE_WH;
USE DATABASE EJERCICIO_NUAAV;

CREATE SCHEMA IF NOT EXISTS EJERCICIO_NUAAV.CANONICAL;

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER (
  customer_key        NUMBER IDENTITY PRIMARY KEY,
  source_system       STRING NOT NULL,
  source_customer_id  STRING NOT NULL,
  first_name          STRING,
  last_name           STRING,
  full_name           STRING,
  email               STRING,
  email_is_valid      BOOLEAN,
  loyalty_tier        STRING,
  segment             STRING,
  signup_source       STRING,
  is_active           BOOLEAN,
  loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.CANONICAL.DIM_PRODUCT (
  product_key      NUMBER IDENTITY PRIMARY KEY,
  source_system    STRING NOT NULL,
  sku              STRING,
  product_name     STRING,
  category         STRING,
  list_price       NUMBER(18,4),
  currency         STRING,
  is_active        BOOLEAN,
  loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.CANONICAL.FACT_ORDER (
  order_key        NUMBER IDENTITY PRIMARY KEY,
  source_system    STRING NOT NULL,
  source_order_id  STRING,
  transaction_id   STRING,
  customer_key     NUMBER,
  order_date       DATE,
  order_status     STRING,
  channel          STRING,
  loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.CANONICAL.FACT_ORDER_ITEM (
  order_item_key  NUMBER IDENTITY PRIMARY KEY,
  order_key       NUMBER,
  product_key     NUMBER,
  item_seq        NUMBER,
  quantity        NUMBER(18,4),
  unit_price      NUMBER(18,4),
  currency        STRING,
  line_amount     NUMBER(18,4),
  loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.CANONICAL.FACT_PAYMENT (
  payment_key       NUMBER IDENTITY PRIMARY KEY,
  order_key         NUMBER,
  source_payment_id STRING,
  payment_method    STRING,
  amount            NUMBER(18,4),
  currency          STRING,
  payment_status    STRING,
  loaded_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.CANONICAL.REJECTS (
  reject_key    NUMBER IDENTITY PRIMARY KEY,
  source_system STRING,
  entity        STRING,
  record_id     STRING,
  rule_name     STRING,
  severity      STRING,
  detail        STRING,
  raw_record    VARIANT,
  detected_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

TRUNCATE TABLE EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER;
TRUNCATE TABLE EJERCICIO_NUAAV.CANONICAL.DIM_PRODUCT;


INSERT INTO EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER
  (customer_key, source_system, source_customer_id, full_name, email_is_valid)
VALUES (-1, 'UNKNOWN', 'UNKNOWN', 'Unknown Customer', FALSE);

INSERT INTO EJERCICIO_NUAAV.CANONICAL.DIM_PRODUCT
  (product_key, source_system, sku, product_name)
VALUES (-1, 'UNKNOWN', 'UNKNOWN', 'Unknown Product');

INSERT INTO EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER
  (source_system, source_customer_id, first_name, last_name, full_name,
   email, email_is_valid, loyalty_tier, segment, signup_source, is_active)
WITH clienta AS (
  SELECT
    source_system,
    customer_id,
    first_name,
    last_name,
    TRIM(COALESCE(first_name,'') || ' ' || COALESCE(last_name,'')) AS full_name,
    email,
    loyalty_tier,
    NULL AS segment,
    signup_source,
    is_active_raw
  FROM EJERCICIO_NUAAV.STAGING.V_CSV_CUSTOMERS_A
),
clientc AS (
  SELECT
    source_system,
    customer_id,
    NULL AS first_name,
    NULL AS last_name,
    customer_name AS full_name,
    email,
    NULL AS loyalty_tier,
    segment,
    NULL AS signup_source,
    is_active_raw
  FROM EJERCICIO_NUAAV.STAGING.V_CSV_CUSTOMERS_C
),
unidos AS (
  SELECT * FROM clienta
  UNION ALL
  SELECT * FROM clientc
)
SELECT
  source_system,
  customer_id,
  first_name,
  last_name,
  NULLIF(full_name, '') AS full_name,
  email,
  CASE
    WHEN email IS NULL THEN FALSE
    WHEN email NOT LIKE '%@%.%' THEN FALSE
    ELSE TRUE
  END AS email_is_valid,
  loyalty_tier,
  segment,
  signup_source,
  TRY_TO_BOOLEAN(is_active_raw) AS is_active
FROM unidos
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY source_system, customer_id
  ORDER BY customer_id
) = 1;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER
  (source_system, source_customer_id, first_name, last_name, full_name, email, email_is_valid)
SELECT
  x.source_system,
  x.customer_id,
  x.first_name,
  x.last_name,
  NULLIF(TRIM(COALESCE(x.first_name,'') || ' ' || COALESCE(x.last_name,'')), '') AS full_name,
  x.email,
  CASE WHEN x.email IS NULL THEN FALSE
       WHEN x.email NOT LIKE '%@%.%' THEN FALSE
       ELSE TRUE END AS email_is_valid
FROM EJERCICIO_NUAAV.STAGING.V_XML_TRANSACTIONS x
LEFT JOIN EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER d
       ON d.source_system = x.source_system
      AND d.source_customer_id = x.customer_id
WHERE d.customer_key IS NULL
  AND x.customer_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY x.customer_id ORDER BY x.transaction_id) = 1;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER
  (source_system, source_customer_id, full_name, email, email_is_valid)
SELECT
  j.source_system,
  j.customer_id,
  NULLIF(TRIM(j.customer_name), '') AS full_name,
  j.email,
  CASE WHEN j.email IS NULL THEN FALSE
       WHEN j.email NOT LIKE '%@%.%' THEN FALSE
       ELSE TRUE END AS email_is_valid
FROM EJERCICIO_NUAAV.STAGING.V_JSON_TRANSACTIONS j
LEFT JOIN EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER d
       ON d.source_system = j.source_system
      AND d.source_customer_id = j.customer_id
WHERE d.customer_key IS NULL
  AND j.customer_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY j.customer_id ORDER BY j.transaction_id) = 1;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.DIM_PRODUCT
  (source_system, sku, product_name, category, list_price, currency, is_active)
SELECT
  source_system,
  sku,
  product_name,
  category,
  TRY_TO_NUMBER(unit_price_raw, 18, 4) AS list_price,
  currency,
  TRY_TO_BOOLEAN(is_active_raw) AS is_active
FROM EJERCICIO_NUAAV.STAGING.V_CSV_PRODUCTS
WHERE sku IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY source_system, sku
  ORDER BY
    CASE WHEN TRY_TO_NUMBER(unit_price_raw, 18, 4) >= 0 THEN 0 ELSE 1 END,
    line_number
) = 1;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.DIM_PRODUCT
  (source_system, sku, product_name)
WITH items AS (
  SELECT source_system, sku, description FROM EJERCICIO_NUAAV.STAGING.V_XML_ITEMS_FLAT
  UNION ALL
  SELECT source_system, sku, description FROM EJERCICIO_NUAAV.STAGING.V_JSON_ITEMS
)
SELECT DISTINCT
  i.source_system,
  i.sku,
  i.description
FROM items i
LEFT JOIN EJERCICIO_NUAAV.CANONICAL.DIM_PRODUCT p
  ON p.source_system = i.source_system AND p.sku = i.sku
WHERE p.product_key IS NULL
  AND i.sku IS NOT NULL
  AND TRIM(i.sku) <> ''
QUALIFY ROW_NUMBER() OVER (PARTITION BY i.source_system, i.sku ORDER BY i.description) = 1;

TRUNCATE TABLE EJERCICIO_NUAAV.CANONICAL.FACT_ORDER;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.FACT_ORDER
  (source_system, source_order_id, transaction_id, customer_key,
   order_date, order_status, channel)
WITH ordenes_csv AS (
  SELECT source_system, order_id, customer_id, order_date_raw, order_status, channel
  FROM EJERCICIO_NUAAV.STAGING.V_CSV_ORDERS
  QUALIFY ROW_NUMBER() OVER (PARTITION BY source_system, order_id ORDER BY line_number) = 1
),
txn_xml AS (
  SELECT source_system, order_id, transaction_id, customer_id, order_date_raw
  FROM EJERCICIO_NUAAV.STAGING.V_XML_TRANSACTIONS
  WHERE order_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY transaction_id) = 1
),
txn_json AS (
  SELECT source_system, order_id, transaction_id, customer_id, order_date_raw
  FROM EJERCICIO_NUAAV.STAGING.V_JSON_TRANSACTIONS
  WHERE order_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY transaction_id) = 1
),
txn AS (
  SELECT * FROM txn_xml
  UNION ALL
  SELECT * FROM txn_json
),
claves AS (
  SELECT source_system, order_id FROM ordenes_csv
  UNION
  SELECT source_system, order_id FROM txn
)
SELECT
  k.source_system,
  k.order_id,
  t.transaction_id,
  COALESCE(d.customer_key, -1) AS customer_key,
  TRY_TO_DATE(COALESCE(c.order_date_raw, t.order_date_raw)) AS order_date,
  c.order_status,
  c.channel
FROM claves k
LEFT JOIN ordenes_csv c ON c.source_system = k.source_system AND c.order_id = k.order_id
LEFT JOIN txn t         ON t.source_system = k.source_system AND t.order_id = k.order_id
LEFT JOIN EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER d
       ON d.source_system = k.source_system
      AND d.source_customer_id = COALESCE(c.customer_id, t.customer_id);

TRUNCATE TABLE EJERCICIO_NUAAV.CANONICAL.FACT_ORDER_ITEM;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.FACT_ORDER_ITEM
  (order_key, product_key, item_seq, quantity, unit_price, currency, line_amount)
WITH items AS (
  SELECT source_system, transaction_id, item_seq, sku,
         quantity_raw, unit_price_raw, currency
  FROM EJERCICIO_NUAAV.STAGING.V_XML_ITEMS_FLAT

  UNION ALL

  SELECT source_system, transaction_id, item_seq, sku,
         quantity_raw, unit_price_raw, currency
  FROM EJERCICIO_NUAAV.STAGING.V_JSON_ITEMS
),
casteados AS (
  SELECT
    i.*,
    TRY_TO_NUMBER(i.quantity_raw,   18, 4) AS quantity,
    TRY_TO_NUMBER(i.unit_price_raw, 18, 4) AS unit_price
  FROM items i
)
SELECT
  o.order_key,
  COALESCE(p.product_key, -1) AS product_key,
  c.item_seq,
  c.quantity,
  c.unit_price,
  c.currency,
  c.quantity * c.unit_price AS line_amount
FROM casteados c
JOIN EJERCICIO_NUAAV.CANONICAL.FACT_ORDER o
  ON o.source_system  = c.source_system
 AND o.transaction_id = c.transaction_id
LEFT JOIN EJERCICIO_NUAAV.CANONICAL.DIM_PRODUCT p
  ON p.source_system = c.source_system
 AND p.sku           = c.sku;

TRUNCATE TABLE EJERCICIO_NUAAV.CANONICAL.FACT_PAYMENT;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.FACT_PAYMENT
  (order_key, source_payment_id, payment_method, amount, currency, payment_status)
SELECT
  o.order_key,
  NULL AS source_payment_id,
  x.payment_method,
  TRY_TO_NUMBER(x.payment_amount_raw, 18, 4) AS amount,
  x.payment_currency,
  NULL AS payment_status
FROM EJERCICIO_NUAAV.STAGING.V_XML_TRANSACTIONS x
JOIN EJERCICIO_NUAAV.CANONICAL.FACT_ORDER o
  ON o.source_system = x.source_system AND o.transaction_id = x.transaction_id
WHERE x.payment_amount_raw IS NOT NULL

UNION ALL

SELECT
  o.order_key,
  p.payment_id,
  p.payment_method,
  TRY_TO_NUMBER(p.amount_raw, 18, 4) AS amount,
  p.currency,
  p.status
FROM EJERCICIO_NUAAV.STAGING.V_CSV_PAYMENTS_C p
JOIN EJERCICIO_NUAAV.CANONICAL.FACT_ORDER o
  ON o.source_system = p.source_system AND o.source_order_id = p.order_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY p.payment_id ORDER BY p.line_number) = 1;



USE DATABASE EJERCICIO_NUAAV;
USE WAREHOUSE COMPUTE_WH;

TRUNCATE TABLE EJERCICIO_NUAAV.CANONICAL.REJECTS;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
WITH txns AS (
  SELECT source_system, transaction_id FROM EJERCICIO_NUAAV.STAGING.V_XML_TRANSACTIONS
  UNION ALL
  SELECT source_system, transaction_id FROM EJERCICIO_NUAAV.STAGING.V_JSON_TRANSACTIONS
)
SELECT
  source_system,
  'TRANSACTION',
  transaction_id,
  'DUPLICATE_TRANSACTION_ID',
  'FATAL',
  'Transaction ID appears ' || COUNT(*) || ' times; kept one version'
FROM txns
WHERE transaction_id IS NOT NULL AND TRIM(transaction_id) <> ''
GROUP BY 1,2,3,4,5
HAVING COUNT(*) > 1;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
SELECT source_system, 'TRANSACTION', order_id, 'MISSING_TRANSACTION_ID', 'FATAL',
       'Transaction has no ID'
FROM EJERCICIO_NUAAV.STAGING.V_XML_TRANSACTIONS
WHERE transaction_id IS NULL OR TRIM(transaction_id) = ''

UNION ALL

SELECT source_system, 'ORDER', transaction_id, 'MISSING_ORDER_ID', 'FATAL',
       'Transaction has no order ID'
FROM EJERCICIO_NUAAV.STAGING.V_JSON_TRANSACTIONS
WHERE order_id IS NULL;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
SELECT source_system, 'ORDER', source_order_id, 'MISSING_ORDER_DATE', 'WARNING',
       'Order date is null or unparseable; loaded with NULL'
FROM EJERCICIO_NUAAV.CANONICAL.FACT_ORDER
WHERE order_date IS NULL;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
SELECT source_system, 'CUSTOMER', source_customer_id, 'INVALID_EMAIL', 'WARNING',
       'Email missing or malformed: ' || COALESCE(email, '(null)')
FROM EJERCICIO_NUAAV.CANONICAL.DIM_CUSTOMER
WHERE NOT email_is_valid AND customer_key > 0;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
SELECT
  o.source_system, 'ORDER_ITEM', o.transaction_id,
  CASE WHEN i.quantity < 0 THEN 'NEGATIVE_QUANTITY'
       WHEN i.quantity = 0 THEN 'ZERO_QUANTITY'
       ELSE 'NULL_QUANTITY' END,
  CASE WHEN i.quantity < 0 THEN 'REVIEW' ELSE 'WARNING' END,
  'Quantity = ' || COALESCE(i.quantity::STRING, '(null)')
FROM EJERCICIO_NUAAV.CANONICAL.FACT_ORDER_ITEM i
JOIN EJERCICIO_NUAAV.CANONICAL.FACT_ORDER o ON o.order_key = i.order_key
WHERE i.quantity IS NULL OR i.quantity <= 0;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
SELECT source_system, 'ORDER', source_order_id, 'ORPHAN_CUSTOMER', 'FATAL',
       'Customer not found in dimension; mapped to unknown member'
FROM EJERCICIO_NUAAV.CANONICAL.FACT_ORDER
WHERE customer_key IS NULL OR customer_key = -1;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
SELECT source_system, 'PRODUCT', sku, 'NEGATIVE_LIST_PRICE', 'REVIEW',
       'Catalog price is negative: ' || list_price::STRING
FROM EJERCICIO_NUAAV.CANONICAL.DIM_PRODUCT
WHERE list_price < 0;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
SELECT DISTINCT
  'ClientC', 'PAYMENT', p.order_id, 'SOURCE_CONFLICT_PAYMENT_METHOD', 'REVIEW',
  'CSV says ' || p.payment_method || ', JSON says ' || j.payment_method
FROM EJERCICIO_NUAAV.STAGING.V_CSV_PAYMENTS_C p
JOIN EJERCICIO_NUAAV.STAGING.V_JSON_TRANSACTIONS j ON j.order_id = p.order_id
WHERE p.payment_method <> j.payment_method;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
SELECT source_system, 'ORDER', source_order_id, 'ORDER_WITHOUT_TRANSACTION', 'REVIEW',
       'Order exists in master but has no transaction; status = ' || COALESCE(order_status,'(null)')
FROM EJERCICIO_NUAAV.CANONICAL.FACT_ORDER
WHERE transaction_id IS NULL;

INSERT INTO EJERCICIO_NUAAV.CANONICAL.REJECTS
  (source_system, entity, record_id, rule_name, severity, detail)
WITH suma AS (
  SELECT order_key, SUM(line_amount) AS total_items
  FROM EJERCICIO_NUAAV.CANONICAL.FACT_ORDER_ITEM
  GROUP BY 1
)
SELECT
  o.source_system,
  'PAYMENT',
  o.source_order_id,
  CASE
    WHEN p.amount = 0 AND s.total_items <> 0
      THEN 'PAYMENT_ZERO_WITH_ITEMS'
    WHEN ABS(ABS(p.amount) - ABS(s.total_items)) < 0.01
         AND SIGN(p.amount) <> SIGN(s.total_items)
      THEN 'PAYMENT_ITEMS_SIGN_MISMATCH'
    WHEN ABS(s.total_items) > 0
         AND ABS(ABS(s.total_items / NULLIF(p.amount,0)) - 2) < 0.01
      THEN 'PAYMENT_ITEMS_QUANTITY_DOUBLED'
    ELSE 'PAYMENT_ITEMS_AMOUNT_MISMATCH'
  END,
  'REVIEW',
  'Payment = ' || p.amount::STRING || ' | Items sum = ' || s.total_items::STRING
FROM EJERCICIO_NUAAV.CANONICAL.FACT_PAYMENT p
JOIN EJERCICIO_NUAAV.CANONICAL.FACT_ORDER o ON o.order_key = p.order_key
JOIN suma s ON s.order_key = p.order_key
WHERE ABS(COALESCE(p.amount,0) - COALESCE(s.total_items,0)) > 0.01;




