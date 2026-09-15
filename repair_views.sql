USE DATABASE EJERCICIO_NUAAV;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_XML_UNIFIED AS
WITH lineas AS (
  SELECT
    file_name,
    line_number,
    raw_line,
    TO_NUMBER(REGEXP_SUBSTR(file_name, 'Transactions_(\\d+)', 1, 1, 'e', 1)) AS file_seq
  FROM EJERCICIO_NUAAV.RAW.RAW_FILE_LINES
  WHERE (file_name LIKE '%.xml' OR file_name LIKE '%.txt')
    AND raw_line IS NOT NULL
    AND raw_line NOT LIKE '-----%'
    AND raw_line NOT LIKE '%SalesData%'
),
meta AS (
  SELECT raw_line AS original_tag
  FROM EJERCICIO_NUAAV.RAW.RAW_FILE_LINES
  WHERE raw_line LIKE '<SalesData%'
  LIMIT 1
)
SELECT
  (SELECT TRIM(original_tag) FROM meta) ||
  LISTAGG(raw_line, '\n') WITHIN GROUP (ORDER BY file_seq, line_number) ||
  '</SalesData>' AS xml_text
FROM lineas;

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.RAW.XML_PARSED AS
SELECT
  PARSE_XML(xml_text) AS doc,
  CURRENT_TIMESTAMP() AS parsed_at
FROM EJERCICIO_NUAAV.STAGING.V_XML_UNIFIED;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_JSON_REPAIRED AS
WITH lineas AS (
  SELECT
    line_number,
    TRIM(REGEXP_REPLACE(raw_line, '//.*$', '')) AS linea_limpia
  FROM EJERCICIO_NUAAV.RAW.RAW_FILE_LINES
  WHERE file_name = 'clientB/transactions.json'
    AND raw_line IS NOT NULL
    AND raw_line NOT LIKE '-----%'
)
SELECT
  LISTAGG(linea_limpia, '\n') WITHIN GROUP (ORDER BY line_number) AS json_text
FROM lineas
WHERE linea_limpia <> '';

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.RAW.JSON_PARSED AS
SELECT
  PARSE_JSON(json_text) AS doc,
  CURRENT_TIMESTAMP()   AS parsed_at
FROM EJERCICIO_NUAAV.STAGING.V_JSON_REPAIRED;

CREATE OR REPLACE VIEW EJERCICIO_NUAAV.STAGING.V_CSV_LINES_CLEAN AS
SELECT
  file_name,
  line_number,
  TRIM(REGEXP_REPLACE(raw_line, '\\s*<--.*$', '')) AS linea
FROM EJERCICIO_NUAAV.RAW.RAW_FILE_LINES
WHERE file_name ILIKE '%.csv'
  AND raw_line IS NOT NULL
  AND raw_line NOT LIKE '-----%'
  AND TRIM(raw_line) <> '';