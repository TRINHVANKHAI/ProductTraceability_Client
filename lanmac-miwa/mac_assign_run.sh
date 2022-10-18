#!/bin/sh
###########################################
#DATE RELEASED: 2022 Aug 16 15:04:20
#VERSION: 1.0.2
###########################################

SWVERSION="0102"
TARGET_IPADDR="192.168.1.121"
SRCVERSION="${SWVERSION}_20220816"
UTEST="17bbe7b5-3950-405e-9222-d07d2bf6b3d8"
WORKSPACE_DIR="/tmp/lanmac-${UTEST}-miwa"
INSTALL_DIR="/opt/lanmac-miwa"
MSGDEFLVF="/proc/sys/kernel/printk"
MSGPRFXDF="8439BE0"
USBLAN_IF="eth0"
USBLAN_MAGIC=0x7500
MSGDEFLVL=`cat $MSGDEFLVF | awk '{ print $1 }'`

USERINPUTFILE="${WORKSPACE_DIR}/userinput.txt"
CSV_RESULTS_SUMMARY="${WORKSPACE_DIR}/results_summary.csv"
IF_TEST_CONFIG="${INSTALL_DIR}/conf/setting.conf"

mkdir -p "${WORKSPACE_DIR}"
rm -rf "${CSV_RESULTS_SUMMARY}"

dmesg -n 2
cpufreq-set -g performance

if [ -f "${IF_TEST_CONFIG}" ]; then
  TARGET_IPADDR=$(awk -F '=' '/^TARGET_IP_ADDRESS/{print $2}' "${IF_TEST_CONFIG}")
  if [ -z "${TARGET_IPADDR}" ]; then
    TARGET_IPADDR="192.168.1.121"
  fi
  SERVER_IPADDR=$(awk -F '=' '/^SERVER_IP_ADDRESS/{print $2}' "${IF_TEST_CONFIG}")
  if [ -z "${SERVER_IPADDR}" ]; then
    SERVER_IPADDR="192.168.1.121"
  fi
else
  TARGET_IPADDR="192.168.1.121"
  SERVER_IPADDR="192.168.1.121"
fi


if_msg() {
  printf "  [%-2s] %-30s: %-10s %-10s \n" "$1" "$2" "$3"
}
if_info() {
  printf "  [%-2s] %-30s: \e[0;32m%-10s\e[0m %-10s \n" "$1" "$2" "$3"
}
if_warn() {
  printf "  [%-2s] %-30s: \e[0;33m%-10s\e[0m %-10s \n" "$1" "$2" "$3"
}

if_err() {
  printf "\e[0;33m* [%-2s] %-30s: \e[0;31m%-10s\e[0m %-10s \n" "$1" "$2" "$3"
}

pr_success() {
  printf "%-20s: \e[1;32m%-10s\e[0m %-10s \n" "$1" "$2" "$3"
}

pr_error() {
  printf "%-20s: \e[1;31m%-10s\e[0m %-10s \n" "$1" "$2" "$3"
}


if_ssids() {
  printf "%-2s \e[0;33m%-2s\e[0m %-40s \n" "[" "$1" "] : $2"
}

if_do_log_write() {
  NUMBER="$1"
  INTERFACE="$2"
  VALUE="$3"
  STATUS="$4"
  echo "${NUMBER},${INTERFACE},${VALUE},${STATUS}" >> "${CSV_RESULTS_SUMMARY}"
  sync
}

if_do_result_SUMMARY() {
  echo ""
  echo ""
  echo "#========================================================"
  echo "#  RESULT SUMMARY  "
  echo "#--------------------------------------------------------"
  echo ""
  READFILE="${CSV_RESULTS_SUMMARY}"
  if [ ! -f "$READFILE" ]; then
    echo "NO SUCH FILE $READFILE"
    return 1
  fi
  TEST_RET_STATE=0
  for ((idx=0;idx<7;idx++)) 
  do
    TEST_RESULTS_NUMBER=$((idx+1))
    TEST_RESULTS_NAME=`awk -F ',' '/'"^${idx},"'/{print $2}' "${READFILE}"`
    TEST_RESULTS_STATUS=`awk -F ',' '/'"^${idx},"'/{print $4}' "${READFILE}"`
    if [ "x${TEST_RESULTS_STATUS}" == "xPASSED" ]; then
      if_info "${TEST_RESULTS_NUMBER}" "${TEST_RESULTS_NAME}" "${TEST_RESULTS_STATUS}"
      echo "POSTRESULTS:${TEST_RESULTS_NUMBER},${TEST_RESULTS_NAME},${TEST_RESULTS_STATUS}" | nc "${SERVER_IPADDR}" 9999
    fi
    if [ "x${TEST_RESULTS_STATUS}" == "xFAILED" ]; then
      if_err  "${TEST_RESULTS_NUMBER}" "${TEST_RESULTS_NAME}" "${TEST_RESULTS_STATUS}"
      echo "POSTRESULTS:${TEST_RESULTS_NUMBER},${TEST_RESULTS_NAME},${TEST_RESULTS_STATUS}" | nc "${SERVER_IPADDR}" 9999
      TEST_RET_STATE=1
    fi
  done
  
  
  echo ""
  echo "--------------------------------------------------------"
  echo ""
  return $TEST_RET_STATE
}



do_check_lan_plug() {
  LANIF=$1
  HWADDRF="/sys/class/net/$LANIF/address"
  DEVALIA="/sys/class/net/$LANIF/device/modalias"
  if [ -z "$LANIF" ]; then
    echo -e "\033[1;91mPLEASE SPECIFY LAN INTERFACE\033[0;m"
    dmesg -n $MSGDEFLVL
    return 1
  fi
  
  if [ ! -e "$HWADDRF" ]; then
    echo -e "\033[1;91mERR: $LANIF IS NOT PRESENT, PLEASE INSERT THE LAN7500 MODULE\033[0;m"
    dmesg -n $MSGDEFLVL
    return 1
  fi

  DEVID=`cat $DEVALIA | grep "0424p7500"`
  if [ -z "$DEVID" ]; then
    echo -e "\033[1;91mERR: $LANIF IS NOT LAN7500 MODULE\033[0;m"
    dmesg -n $MSGDEFLVL
    return 1
  fi

  echo -n "CONNECTING TO HOST  "
  RETRYIT=0
  RESP=`cat "/sys/class/net/$LANIF/operstate"`
  test "w${RESP}" == "wup"
  while [ $? -ne 0 ] && [ $((RETRYIT++)) -lt 60 ]
  do
    sleep 0.5
    echo -n ". "
    RESP=`cat "/sys/class/net/$LANIF/operstate"`
    test "w${RESP}" == "wup"
  done
  if [ "w${RESP}" == "wup" ]; then
    echo -e "[\033[1;32m CONNECTED \033[0;m]"
    return 0
  else
    echo -e "[\033[1;91m TIMED OUT \033[0;m]"
    return 1
  fi
}

do_check_lan_unplug() {
  LANIF=$1
  HWADDRF="/sys/class/net/$LANIF/address"
  if [ -e "$HWADDRF" ]; then
    return 1
  else
    return 0
  fi
}

do_MAC_programming() {
  LANIF=$1

  ETHADDHWR=`awk -F "," '{print $2}' "${USERINPUTFILE}"`
  if [ ${#ETHADDHWR} -ne 17 ] || [[ ! "$ETHADDHSC" =~ ^[0-9a-fA-F]*$ ]]; then
    echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
    echo -e "\033[1;91m MAC ADDRESS WRONG! REBOOT AND TRY AGAIN\033[0;m"
    echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
    dmesg -n $MSGDEFLVL
    return 1
  fi
  echo -e "MAC ADDRESS IS ASSIGNED AS____:\033[1;93m $ETHADDHWR \033[0;m"

  VALUE=`echo "$ETHADDHWR" | awk -F ":" '{print $1}'`
  ethtool -E $LANIF magic "$USBLAN_MAGIC" offset 0x01 value "0x$VALUE"
  VALUE=`echo "$ETHADDHWR" | awk -F ":" '{print $2}'`
  ethtool -E $LANIF magic "$USBLAN_MAGIC" offset 0x02 value "0x$VALUE"
  VALUE=`echo "$ETHADDHWR" | awk -F ":" '{print $3}'`
  ethtool -E $LANIF magic "$USBLAN_MAGIC" offset 0x03 value "0x$VALUE"
  VALUE=`echo "$ETHADDHWR" | awk -F ":" '{print $4}'`
  ethtool -E $LANIF magic "$USBLAN_MAGIC" offset 0x04 value "0x$VALUE"
  VALUE=`echo "$ETHADDHWR" | awk -F ":" '{print $5}'`
  ethtool -E $LANIF magic "$USBLAN_MAGIC" offset 0x05 value "0x$VALUE"
  VALUE=`echo "$ETHADDHWR" | awk -F ":" '{print $6}'`
  ethtool -E $LANIF magic "$USBLAN_MAGIC" offset 0x06 value "0x$VALUE"
  
  echo ""
  echo "==================================================="
  echo ""
  echo ""

  echo ":::::::::::::::::::::::::::::::::::::"
  
  GETVAL=`ethtool -e $LANIF offset 0x01 length 6`
  RAWVAL=`echo "$GETVAL" | awk -F ':' '/01:/{print $2}' | tr '[:lower:]' '[:upper:]' | tr -d [:space:]`
  CFMVAL=`echo "$ETHADDHWR" | sed "s/\://g"`
  
  if [ "${CFMVAL}" == "${RAWVAL}" ]; then
    echo -e ":::::::::\033[1;32m MAC WRITE SUCCESS \033[0;m:::::::::"
    MACWRRET=0
  else
    echo -e ":::::::::\033[1;91m MAC WRITE FAILED  \033[0;m:::::::::"
    MACWRRET=1
  fi
  
  echo ":::::::::::::::::::::::::::::::::::::"
  /sbin/ip link set $LANIF down
  /sbin/ip link set dev $LANIF address "$ETHADDHWR"
  /sbin/ip link set $LANIF up
  systemctl restart systemd-networkd
  sleep 1
  echo ""
  echo ""
  return $MACWRRET
}

do_MAC_erasing() {
  LANIF="$1"
  VALUE="$2"
  if [ -z "$VALUE" ]; then
    VALUE="0xFF"
  fi
  
  echo -n "ARE YOU SURE TO CLEAR THE MAC ADDRESS ON EPROM? (Yes/n) ? "
  read -e CONFIRMED
  if [ "x$CONFIRMED" == "xYes" ]; then
    for OFFSET in {1..6}; do
      ethtool -E ${LANIF} magic "$USBLAN_MAGIC" offset $OFFSET value "$VALUE"
    done
    echo "PERFORMED MAC ADDRESS CLEAR"
  else
    echo "YOU ANSWER NO, DO NOTHING"
  fi
}

do_check_lan_plug $USBLAN_IF
while [ $? -ne 0 ]
do
  sleep 0.5
  do_check_lan_plug $USBLAN_IF
done


if [ "x$1" == "x--reset" ]; then
  do_MAC_erasing "$USBLAN_IF" 0xff
fi



if_do_test_0() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [0] SERIAL NO" | nc ${SERVER_IPADDR} 9999
  TEST_RESULT_VALUE=""
  TEST_RESULT_STATUS="FAILED"
  SERIALNUMBER_RETRY=0
  echo "WAITING FOR USER INPUT FROM ${SERVER_IPADDR}:9999 ..."
  false
  while [ $((SERIALNUMBER_RETRY++)) -lt 28800 ]
  do
    sleep 1
    echo -n ". "
    GETUSERINPUT=`echo "GETUSERINPUT" | nc "${SERVER_IPADDR}" 9999`
    if [ -z "${GETUSERINPUT}" ]; then
        GETUSERINPUT="x,x"
    fi
    echo "${GETUSERINPUT}" > "${USERINPUTFILE}"
    HWSERIALNO=`awk -F "," '{print $1}' "${USERINPUTFILE}"`
    if [ "${#HWSERIALNO}" -eq 30 ] && [[ "${HWSERIALNO: -20}" =~ ^[0-9]*$ ]]; then
      TEST_RESULT_VALUE="${HWSERIALNO}"
      TEST_RESULT_STATUS="PASSED"
      break
    fi
  done

  if_do_log_write "0" "SERIAL NO" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_1() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [1] USB LAN MODULE CONNECTIVITY" | nc ${SERVER_IPADDR} 9999
  NETIF="$USBLAN_IF"
  IPADDR="${TARGET_IPADDR}"

  do_MAC_programming ${NETIF}
  MACWRSTATUS=$?
  if [ $MACWRSTATUS -ne 0 ]; then
    echo "MAC PROGRAMMING ERROR, EXIT"
    exit 1
  fi
  
  NETWORKCONFIG="/etc/systemd/network/${NETIF}.network"
  if [ ! -f "${NETWORKCONFIG}" ]; then
    systemctl disable systemd-networkd

    cat > "${NETWORKCONFIG}" <<EOF
[Match]
Name=${NETIF}

[Network]
DNS=8.8.8.8
Address=192.168.0.188/24
Gateway=192.168.0.254

EOF
    ln -sf /etc/resolv-conf.systemd /etc/resolv.conf
    systemctl enable systemd-networkd
    systemctl restart systemd-networkd
    sync
  fi
  echo -n "CONNECTING TO NETWORK  "
  RETRYIT=0
  RESP=`cat "/sys/class/net/$NETIF/operstate"`
  test "w${RESP}" == "wup"
  while [ $? -ne 0 ] && [ $((RETRYIT++)) -lt 60 ]
  do
    sleep 0.5
    echo -n ". "
    RESP=`cat "/sys/class/net/$NETIF/operstate"`
    test "w${RESP}" == "wup"
  done
  if [ "w${RESP}" == "wup" ]; then
    echo -e "[\033[1;32m CONNECTED \033[0;m]"
  else
    echo -e "[\033[1;91m TIMED OUT \033[0;m]"
  fi
  
  echo ""
  echo ""
  echo ""
  
  if [ "w${RESP}" == "wup" ]; then
    echo -n "CONNECTING TO TARGET DEVICE $IPADDR: "
    for retry in {1..60}; do
      echo -n ". "
      ping -c 1 -W 1 -I $NETIF "$IPADDR" > /dev/null 2>&1
      RESP=$?
      test $RESP -eq 0 && break
    done 
    
    if [ $RESP -eq 0 ]; then
      NWRES="OK"
      echo " OK"
      echo ""
      echo ""
      echo "::::::::::::::::::::::::::::::::::::::"
      echo -e "::::::\033[1;32m NETWORK PING TEST PASSED \033[0;m::::::"
    else
      NWRES=""
      echo " TIMED OUT"
      echo ""
      echo ""
      echo "::::::::::::::::::::::::::::::::::::::"
      echo -e "::::::\033[1;91m NETWORK PING TEST FAILED \033[0;m::::::"
    fi
  else
    NWRES=""
    echo -e "::::::\033[1;91m NETWORK PING TEST FAILED \033[0;m::::::"
  fi
  echo "::::::::::::::::::::::::::::::::::::::"
  echo ""
  echo ""
  if [ ! -z "${NWRES}" ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "1" "USB LAN MODULE CONNECTIVITY" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_2() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [2] TESTAPP VERSION" | nc ${SERVER_IPADDR} 9999
  TEST_RESULT_VALUE="${SWVERSION}"
  TEST_RESULT_STATUS="PASSED"
  if_do_log_write "2" "TESTAPP VERSION" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_3() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [3] LAN MAC ADDRESS" | nc ${SERVER_IPADDR} 9999
  NETIF="$USBLAN_IF"
  USBLAN_HWADDR_VALUE=`cat "/sys/class/net/${NETIF}/address"`
  USBLAN_HWADDR_CONFIG=`echo "${USBLAN_HWADDR_VALUE}" | sed "s/\://g"`
  USBLAN_HWADDR_GETVAL=`ethtool -e $NETIF offset 0x01 length 6`
  USBLAN_HWADDR_RAWVAL=`echo "$USBLAN_HWADDR_GETVAL" | awk -F ':' '/01:/{print $2}' | tr -d [:space:]`
  
  if [ "x${USBLAN_HWADDR_CONFIG}" == "x${USBLAN_HWADDR_RAWVAL}" ]; then
    TEST_RESULT_VALUE=`echo "${USBLAN_HWADDR_VALUE}" | tr '[:lower:]' '[:upper:]'`
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE=""
    TEST_RESULT_STATUS="FAILED"
  fi

  if_do_log_write "3" "LAN MAC ADDRESS" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_4() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [4] TEST DATE" | nc ${SERVER_IPADDR} 9999
  TEST_RESULT_VALUE="2022/08/08 15:26:22"
  TEST_RESULT_STATUS="PASSED"
  if_do_log_write "4" "TEST DATE" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_5() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [5] PERSON IN CHARGE" | nc ${SERVER_IPADDR} 9999
  TEST_RESULT_VALUE_RAW=`echo "GETUSERNAME" | nc ${SERVER_IPADDR} 9999`
  TEST_RESULT_VALUE=`echo "${TEST_RESULT_VALUE_RAW}" | awk -F "," '{print $1}'`
  if [ -z "${TEST_RESULT_VALUE}" ]; then
    TEST_RESULT_VALUE=$(awk -F '=' '/^PERSONINCHARGE/{print $2}' "${IF_TEST_CONFIG}")
  fi
  if [ -z "${TEST_RESULT_VALUE}" ]; then
    TEST_RESULT_STATUS="FAILED"
  else
    TEST_RESULT_STATUS="PASSED"
  fi
  if_do_log_write "5" "PERSON IN CHARGE" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_6() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [6] GENERATION" | nc ${SERVER_IPADDR} 9999
  TEST_RESULT_VALUE="0"
  TEST_RESULT_STATUS="PASSED"
  if_do_log_write "6" "GENERATION" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}


#PERFORM TEST CASE [0] SERIAL NO"
if_do_test_0

#PERFORM TEST CASE [1] USB LAN MODULE CONNECTIVITY"
if_do_test_1

#PERFORM TEST CASE [2] TESTAPP VERSION"
if_do_test_2

#PERFORM TEST CASE [3] LAN MAC ADDRESS"
if_do_test_3

#PERFORM TEST CASE [4] TEST DATE"
if_do_test_4

#PERFORM TEST CASE [5] PERSON IN CHARGE"
if_do_test_5

#PERFORM TEST CASE [6] GENERATION"
if_do_test_6

#Show results on terminal
if_do_result_SUMMARY
TEST_OVRL_STATE=$?
echo "OVERALLSTATUS:${TEST_OVRL_STATE}" | nc "${SERVER_IPADDR}" 9999

${INSTALL_DIR}/bin/db_upload.sh "${CSV_RESULTS_SUMMARY}"
DB_UPLD_STATE=$?
echo "RESULTSAVESTA:${DB_UPLD_STATE}" | nc "${SERVER_IPADDR}" 9999

echo ""
echo ""
echo "======================================"
echo ""
if [ $DB_UPLD_STATE -eq 0 ]; then
  pr_success "SAVING THE RESULT" "SUCCESS"
else
  pr_error   "SAVING THE RESULT" "FAILED"
fi
echo ""
echo ""

dmesg -n ${MSGDEFLVL}
rm -rf "${WORKSPACE_DIR}"

echo -n "WAITING FOR LAN MODULE BEING UNPLUGGED .. "
do_check_lan_unplug $USBLAN_IF
while [ $? -ne 0 ]
do
  sleep 0.5
  do_check_lan_unplug $USBLAN_IF
done
echo " [OK]"

exit 0
