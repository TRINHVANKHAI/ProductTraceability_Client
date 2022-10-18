#!/bin/bash

SERVER_IPADDR="192.168.1.121"
SERVER_PORT="3306"
MYSQL_USER="miwakensa"
MYSQL_PASS="hinoeng"
MYSQL_CPU_DB="miwa_CPU__RDCA"
MYSQL_LAN_DB="miwa_LAN__EUCU"

UTEST="618fb163-3500-45b8-805a-42d94f361cd3"
WORKSPACE_DIR="/tmp/lanmac-${UTEST}-miwadb"
mkdir -p "${WORKSPACE_DIR}"
CSV_FILE_TEMP="${WORKSPACE_DIR}/miwakensa_template.csv"
INSTALL_DIR="/opt/lanmac-miwa"
IF_TEST_CONFIG="${INSTALL_DIR}/conf/setting.conf"

if [ -f "${IF_TEST_CONFIG}" ]; then
  TARGET_IPADDR=$(awk -F '=' '/^TARGET_IP_ADDRESS/{print $2}' "${IF_TEST_CONFIG}")
  if [ -z "${TARGET_IPADDR}" ]; then
    TARGET_IPADDR="192.168.0.39"
  fi
  SERVER_IPADDR=$(awk -F '=' '/^SERVER_IP_ADDRESS/{print $2}' "${IF_TEST_CONFIG}")
  if [ -z "${SERVER_IPADDR}" ]; then
    SERVER_IPADDR="192.168.1.121"
  fi
else
  TARGET_IPADDR="192.168.0.39"
  SERVER_IPADDR="192.168.1.121"
fi


if [ -z "$1" ]; then
  echo "USAGE: $0 <CSV summary file>"
  exit 1
else
  CSV_RESULTS_SUMMARY="$1"
fi

dbupload_generate_template(){
  cat << _MY_B64_FILE_EOF | base64 -d > "$1"
77u/5Z+65p2/44K344Oq44Ki44OrTm8uLOaciee3mkxBTumAmuS/oSzmpJzmn7tGL1cgVmVyLixM
QU4gTUFD44Ki44OJ44Os44K5LOaknOafu+aXpeaZgizmi4XlvZPogIUs5LiW5Luj44OV44Op44Kw
ClJEQ0EtQjAxTEEwMTAwMDAyMjA2MDc1NDEwMDAwMSxPSywwMTAwLEY3OjUwOkNEOjFBOjUxOkQy
LDIwMjEvMDUvMDkgMTQ6MjY6MDks576O5ZKM5aSq6YOOLDAK
_MY_B64_FILE_EOF

}
dbupload_generate_template "${CSV_FILE_TEMP}"

if [ -f "${CSV_FILE_TEMP}" ]; then  
  IFS=',' read -r -a TEST_CATAGORIES < "${CSV_FILE_TEMP}"
  rm -f "${CSV_FILE_TEMP}"
else
  echo "CSV template file not found"
  exit 1
fi

if [ -f "${CSV_RESULTS_SUMMARY}" ]; then
  for ((idx=0;idx<7;idx++)) 
  do
    TEST_RESULT_NAME[$idx]=`awk -F ',' '/'"^${idx},"'/{print $2}' "${CSV_RESULTS_SUMMARY}"`
    TEST_RESULT_VALUE[$idx]=`awk -F ',' '/'"^${idx},"'/{print $3}' "${CSV_RESULTS_SUMMARY}"`

    if [ -z "${TEST_RESULT_VALUE[$idx]}" ]; then
      echo "Result is wrong at [${idx}] ${TEST_RESULT_NAME[$idx]} '${TEST_RESULT_VALUE[$idx]}'"
      exit 1
    fi
  done
else
  echo "CSV result file not found"
  exit 1
fi


dbupload_create_table() {
  TABLE_NAME="$1"
  if [ -z "${TABLE_NAME}" ]; then
    echo "Please specify the table name"
    return 1
  fi

  mysql -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} <<SQL_QUERIES
CREATE TABLE IF NOT EXISTS \`${TABLE_NAME}\` (
\`${TEST_CATAGORIES[0]}\`        VARCHAR(30) NOT NULL,
\`${TEST_CATAGORIES[1]}\`        VARCHAR(2) NOT NULL,
\`${TEST_CATAGORIES[2]}\`       VARCHAR(4) NOT NULL,
\`${TEST_CATAGORIES[3]}\`       VARCHAR(17) NOT NULL,
\`${TEST_CATAGORIES[4]}\`       VARCHAR(19) NOT NULL,
\`${TEST_CATAGORIES[5]}\`       VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
\`${TEST_CATAGORIES[6]}\`       VARCHAR(1) NOT NULL,
PRIMARY KEY (\`${TEST_CATAGORIES[0]}\`,\`${TEST_CATAGORIES[6]}\`),
UNIQUE KEY  (\`${TEST_CATAGORIES[3]}\`,\`${TEST_CATAGORIES[6]}\`)
)
ENGINE = InnoDB;
SQL_QUERIES

  RESP=$?
  if [ $RESP -eq 0 ]; then
    return 0
  else
    echo "Cannot create table"
    return $RESP
  fi
}



dbupload_get_duplicate_by_serialno() {
TABLE_NAME="$1"
SERIAL_NO="$2"
mysql -N -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} <<SQL_QUERIES
SELECT COUNT(*) FROM \`${TABLE_NAME}\` WHERE \`${TEST_CATAGORIES[0]}\`='${SERIAL_NO}';
SQL_QUERIES
}


dbupload_check_mac_duplicate() {
  TABLE_NAME="$1"
  MAC_ADDRESS="${TEST_RESULT_VALUE[3]}"
  GENERATION_NO=$(mysql -N -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} <<SQL_QUERIES
SELECT MAX(\`${TEST_CATAGORIES[6]}\`) FROM \`${TABLE_NAME}\` WHERE \`${TEST_CATAGORIES[3]}\`='${MAC_ADDRESS}';
SQL_QUERIES
)

  if [ -z "${GENERATION_NO}" ]; then
    echo "-1"
    return 1
  fi
  if [[ ! "${GENERATION_NO}" =~ ^[0-9]*$ ]] && [ "${GENERATION_NO}" != "NULL" ]; then
    echo "-2"
    return 2
  fi
  if [ "${GENERATION_NO}" == "NULL" ]; then
    echo "0"
  else
    echo "$((GENERATION_NO+1))"
  fi
  return 0
}

dbupload_get_date() {
  GET_DATE_RAW=$(mysql -N -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} <<SQL_QUERIES
SELECT CURDATE();
SQL_QUERIES
)
  RESP=$?
  if [ $RESP -eq 0 ]; then
    GET_DATE_VALUE=$(echo "${GET_DATE_RAW}" | tr -d '-')
    if [[ "${GET_DATE_VALUE}" =~ ^[0-9]*$ ]]; then
      echo "${GET_DATE_VALUE}"
    fi
  else
    echo ""
  fi
}

dbupload_get_datetime() {
  GET_DATETIME_RAW=$(mysql -N -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} <<SQL_QUERIES
SELECT NOW();
SQL_QUERIES
)
  RESP=$?
  if [ $RESP -eq 0 ]; then
    GET_DATETIME_VALUE=$(echo "${GET_DATETIME_RAW}" | sed "s/\-/\//g")
    GET_DATETIME_CHECK=$(echo "${GET_DATETIME_RAW}" | tr -d '\:\-\ ')
    if [[ "${GET_DATETIME_CHECK}" =~ ^[0-9]*$ ]]; then
      echo "${GET_DATETIME_VALUE}"
    fi
  else
    echo ""
  fi
}


dbupload_check_connection_to_sql_server(){
  mysql -N -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB}
}



dbupload_insert_into_table_from_csv() {
  TABLE_NAME="$1"
  mysql -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} --local-infile=1 << SQL_QUERIES
LOAD DATA LOCAL INFILE  
'${TEST_RESULTS_CSV}' 
INTO TABLE \`${TABLE_NAME}\` 
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
LINES TERMINATED BY '\n';
SQL_QUERIES
  RESP=$?
  if [ $RESP -eq 0 ]; then
    echo "Insert csv to server"
    return 0
  else
    echo "Cannot insert test data to server"
    return $RESP
  fi
}


dbupload_insert_into_table() {
  TABLE_NAME="$1"
  KENSA_DATETIME="$2"
  mysql -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} <<SQL_QUERIES
INSERT INTO \`${TABLE_NAME}\` (
\`${TEST_CATAGORIES[0]}\`,
\`${TEST_CATAGORIES[1]}\`,
\`${TEST_CATAGORIES[2]}\`,
\`${TEST_CATAGORIES[3]}\`,
\`${TEST_CATAGORIES[4]}\`,
\`${TEST_CATAGORIES[5]}\`,
\`${TEST_CATAGORIES[6]}\`) 
VALUES (
'${TEST_RESULT_VALUE[0]}',
'${TEST_RESULT_VALUE[1]}',
'${TEST_RESULT_VALUE[2]}',
'${TEST_RESULT_VALUE[3]}',
'${KENSA_DATETIME}',
'${TEST_RESULT_VALUE[5]}',
'${TEST_RESULT_VALUE[6]}');
SQL_QUERIES
  RESP=$?
  echo "RESPONSE $RESP"
}


dbupload_insert_into_table_gen() {
  TABLE_NAME="$1"
  KENSA_DATETIME="$2"
  LAST_GENERATION_NO="$3"

  mysql -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} <<SQL_QUERIES
INSERT INTO \`${TABLE_NAME}\` (
\`${TEST_CATAGORIES[0]}\`,
\`${TEST_CATAGORIES[1]}\`,
\`${TEST_CATAGORIES[2]}\`,
\`${TEST_CATAGORIES[3]}\`,
\`${TEST_CATAGORIES[4]}\`,
\`${TEST_CATAGORIES[5]}\`,
\`${TEST_CATAGORIES[6]}\`) 
VALUES (
'${TEST_RESULT_VALUE[0]}',
'${TEST_RESULT_VALUE[1]}',
'${TEST_RESULT_VALUE[2]}',
'${TEST_RESULT_VALUE[3]}',
'${KENSA_DATETIME}',
'${TEST_RESULT_VALUE[5]}',
'${LAST_GENERATION_NO}');
SQL_QUERIES
  RESP=$?
  echo "$RESP"
}


dbupload_insert_into_table_update() {
  TABLE_NAME="$1"
  KENSA_DATETIME="$2"
  LAST_GENERATION_NO="0"

  mysql -h${SERVER_IPADDR} -u${MYSQL_USER} -p${MYSQL_PASS} --database=${MYSQL_LAN_DB} <<SQL_QUERIES
INSERT INTO \`${TABLE_NAME}\` (
\`${TEST_CATAGORIES[0]}\`,
\`${TEST_CATAGORIES[1]}\`,
\`${TEST_CATAGORIES[2]}\`,
\`${TEST_CATAGORIES[3]}\`,
\`${TEST_CATAGORIES[4]}\`,
\`${TEST_CATAGORIES[5]}\`,
\`${TEST_CATAGORIES[6]}\`) 
VALUES (
'${TEST_RESULT_VALUE[0]}',
'${TEST_RESULT_VALUE[1]}',
'${TEST_RESULT_VALUE[2]}',
'${TEST_RESULT_VALUE[3]}',
'${KENSA_DATETIME}',
'${TEST_RESULT_VALUE[5]}',
'${LAST_GENERATION_NO}')
ON DUPLICATE KEY UPDATE 
\`${TEST_CATAGORIES[1]}\`='${TEST_RESULT_VALUE[1]}',
\`${TEST_CATAGORIES[2]}\`='${TEST_RESULT_VALUE[2]}',
\`${TEST_CATAGORIES[3]}\`='${TEST_RESULT_VALUE[3]}',
\`${TEST_CATAGORIES[4]}\`='${TEST_RESULT_VALUE[4]}',
\`${TEST_CATAGORIES[5]}\`='${TEST_RESULT_VALUE[5]}';
SQL_QUERIES
  RESP=$?
  echo "$RESP"
}



KENSA_DATE=$(dbupload_get_date)
KENSA_G_DATETIME=$(dbupload_get_datetime)
KENSA_BYDATE_TABLE="EUCU-A03_E33082+_${KENSA_DATE}_A_01"
KENSA_GENERAL_TABLE="EUCU-A03_E33082+_GENERAL_A_01"
if [ -z "${KENSA_DATE}" ]; then
  echo "Cannot aquire date time information from server"
  exit 1
fi

dbupload_create_table "${KENSA_GENERAL_TABLE}"
dbupload_create_table "${KENSA_BYDATE_TABLE}"

GENERATION=$(dbupload_check_mac_duplicate "${KENSA_GENERAL_TABLE}")
RESP=$?
if [ "${RESP}" -eq 0 ]; then
  if [ "${GENERATION}" == "0" ]; then
    UPLD_STATUS=$(dbupload_insert_into_table_gen "${KENSA_GENERAL_TABLE}" "${KENSA_G_DATETIME}" "${GENERATION}")
    if [ $UPLD_STATUS -ne 0 ]; then
      echo "ERROR: Can not update data to genenral csv"
      exit 1
    fi
    UPLD_STATUS=$(dbupload_insert_into_table_gen "${KENSA_BYDATE_TABLE}" "${KENSA_G_DATETIME}" "${GENERATION}")
    if [ $UPLD_STATUS -ne 0 ]; then
      echo "ERROR: Can not update data to date csv"
      exit 1
    fi
  elif [ "${GENERATION}" -le 9 ]; then
    echo    "This board has been setup for $GENERATION times."
    echo -n "Do you want to update the result ( Yes ):  "
    echo "QUERYPOPUP:このボードは $GENERATION 回試験しました。 試験結果を保存しますか" | nc "${SERVER_IPADDR}" 9999
    while true 
    do
      sleep 1
      echo -n ". "
      GENERATION_RESPONSE=`echo "QUERYGETRES" | nc "${SERVER_IPADDR}" 9999`
      if [ "x${GENERATION_RESPONSE}" == "xACCEPTED" ] || [ "x${GENERATION_RESPONSE}" == "xREJECTED" ]; then
        break
      fi
      
    done
    
    if [ "x${GENERATION_RESPONSE}" == "xACCEPTED" ]; then
      UPLD_STATUS=$(dbupload_insert_into_table_gen "${KENSA_GENERAL_TABLE}" "${KENSA_G_DATETIME}" "${GENERATION}")
      if [ $UPLD_STATUS -ne 0 ]; then
        echo "ERROR: Can not update data to genenral csv"
        exit 1
      fi
      UPLD_STATUS=$(dbupload_insert_into_table_gen "${KENSA_BYDATE_TABLE}" "${KENSA_G_DATETIME}" "${GENERATION}")
      if [ $UPLD_STATUS -ne 0 ]; then
        echo "ERROR: Can not update data to date csv"
        exit 1
      fi
    else
      echo "You have discarded, nothing change"
      exit 1
    fi
  else
    echo "Excess the max 10 times to rework for this board"
    exit 1
  fi
else
  exit 1
fi

rm -rf "${WORKSPACE_DIR}"

exit 0
