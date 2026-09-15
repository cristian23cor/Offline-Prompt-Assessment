USE DATABASE EJERCICIO_NUAAV;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE TABLE EJERCICIO_NUAAV.RAW.RAW_FILE_LINES (
  file_name    STRING,
  line_number  NUMBER,
  raw_line     STRING,
  loaded_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO EJERCICIO_NUAAV.RAW.RAW_FILE_LINES (file_name, line_number, raw_line)
FROM (
  SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, $1
  FROM @EJERCICIO_NUAAV.RAW.SRC_FILES/clientA/
)
FILE_FORMAT = (FORMAT_NAME = 'EJERCICIO_NUAAV.RAW.FF_RAW_LINES')
ON_ERROR = CONTINUE;

COPY INTO EJERCICIO_NUAAV.RAW.RAW_FILE_LINES (file_name, line_number, raw_line)
FROM (
  SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, $1
  FROM @EJERCICIO_NUAAV.RAW.SRC_FILES/clientB/
)
FILE_FORMAT = (FORMAT_NAME = 'EJERCICIO_NUAAV.RAW.FF_RAW_LINES')
ON_ERROR = CONTINUE;

SELECT file_name,
       COUNT(*)                                          AS total_lineas,
       COUNT_IF(raw_line LIKE '-----%')                  AS marcadores,
       COUNT_IF(raw_line LIKE '%<--%')                   AS anotaciones,
       COUNT_IF(raw_line LIKE '%//%')                    AS comentarios,
       COUNT_IF(raw_line IS NULL OR TRIM(raw_line) = '') AS lineas_vacias
FROM EJERCICIO_NUAAV.RAW.RAW_FILE_LINES
GROUP BY file_name
ORDER BY file_name;