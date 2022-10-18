#!/bin/bash

SWVERSION="0104"
TARGET_IPADDR="192.168.0.39"
SRCVERSION="${SWVERSION}_20220725"
UTEST="17bbe7b5-3950-405e-9222-d07d2bf6b3d8"
WORKSPACE_DIR="/tmp/interface-${UTEST}-miwa"
INSTALL_DIR="/opt/interface-miwa"
GPIOFSYS="/sys/class/gpio"
KERNDEFLVF="/proc/sys/kernel/printk"
KERNDEFLV=`cat "${KERNDEFLVF}" | awk '{ print $1 }'`

CSV_RESULTS_SUMMARY="${WORKSPACE_DIR}/results_summary.csv"
SERIAL_NO_SRC_FILE="${WORKSPACE_DIR}/board_serial_no.txt"
IF_TEST_CONFIG="${INSTALL_DIR}/conf/setting.conf"

mkdir -p "${WORKSPACE_DIR}"
rm -rf "${CSV_RESULTS_SUMMARY}"

dmesg -n 3
cpufreq-set -g performance

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
  for ((idx=0;idx<42;idx++)) 
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


#---------------------------
#GPIO FUNCTIONS
#---------------------------
gpio_init() {
  GPIO_NUM="$1"
  GPIO_DIR="$2"
  echo "${GPIO_NUM}" > "${GPIOFSYS}/export"
  if [ -e "${GPIOFSYS}/gpio${GPIO_NUM}" ]; then
    echo "${GPIO_DIR}" > "${GPIOFSYS}/gpio${GPIO_NUM}/direction"
  else
    echo "GPIO INIT FAILED!!      [ GPIO$((GPIO_NUM/32+1))_IO$((GPIO_NUM%32)) ]"
  fi
}

gpio_deinit() {
  GPIO_NUM="$1"
  if [ -e "${GPIOFSYS}/gpio${GPIO_NUM}" ]; then
    echo "in" > "${GPIOFSYS}/gpio${GPIO_NUM}/direction"
    echo "${GPIO_NUM}" > "${GPIOFSYS}/unexport"
  else
    echo "GPIO DEINIT FAILED!!     [ GPIO$((GPIO_NUM/32+1))_IO$((GPIO_NUM%32)) ]"
  fi
}

gpio_getval() {
  GPIO_NUM="$1"
  if [ -e "${GPIOFSYS}/gpio${GPIO_NUM}" ]; then
    GPIO_GVAL=`cat "${GPIOFSYS}/gpio${GPIO_NUM}/value"`
  else
    echo "GPIO WAS NOT INITIATED!! [ GPIO$((GPIO_NUM/32+1))_IO$((GPIO_NUM%32)) ]"
  fi
  echo "$GPIO_GVAL"
}

gpio_setval() {
  GPIO_NUM="$1"
  GPIO_SVAL="$2"
  if [ -e "${GPIOFSYS}/gpio${GPIO_NUM}" ]; then
    echo "$GPIO_SVAL" > "${GPIOFSYS}/gpio${GPIO_NUM}/value"
  else
    echo "GPIO WAS NOT INITIATED!! [ GPIO$((GPIO_NUM/32+1))_IO$((GPIO_NUM%32)) ]"
  fi
}

gpio_blink() {
  GPIO_NUM="$1"
  GPIO_BL="$2"
  GPIO_FL="${WORKSPACE_DIR}/gpio${GPIO_NUM}.blink"
  if [ "x${GPIO_BL}" == "xON" ]; then
    echo "${GPIO_BL}" > "${GPIO_FL}"
  else
    test -f "${GPIO_FL}" && rm -f "${GPIO_FL}"
  fi
  test -f "${GPIO_FL}"
  while [ $? -eq 0 ]; do
    gpio_setval $GPIO_NUM 1
    sleep 0.1
    gpio_setval $GPIO_NUM 0
    sleep 0.2
    test -f "${GPIO_FL}"
  done
}

gpio_led_blink(){
  GPIO_LED=12
  gpio_init $GPIO_LED "out"
  
  gpio_blink $GPIO_LED "ON" &
  LED_PID=$!

  echo    ">>  CHECK IF LED IS BLINKING  <<"
  echo -n "PRESS ANY KEY TO CONTINUE: .. "
  read -rsn1
  echo "DONE"
  rm -f ${WORKSPACE_DIR}/gpio${GPIO_LED}.blink
  wait $LED_PID
  gpio_deinit $GPIO_LED
}

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
    HWSERIALNO=`echo "GETUSERINPUT" | nc "${SERVER_IPADDR}" 9999`
    if [ "${#HWSERIALNO}" -eq 30 ] && [[ "${HWSERIALNO: -20}" =~ ^[0-9]*$ ]]; then
      TEST_RESULT_VALUE="${HWSERIALNO}"
      TEST_RESULT_STATUS="PASSED"
      break
    fi
  done
  echo ""
  echo ""
  echo -n "${HWSERIALNO}" > "${SERIAL_NO_SRC_FILE}"
  if_do_log_write "0" "SERIAL NO" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_1() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [1] POWER INPUT" | nc ${SERVER_IPADDR} 9999
  TEST_RESULT_VALUE="OK"
  TEST_RESULT_STATUS="PASSED"
  if_do_log_write "1" "POWER INPUT" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_2() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [2] DDR4 R/W" | nc ${SERVER_IPADDR} 9999
  DDR_IMG_SRC="${WORKSPACE_DIR}/if_do_test_2_ddr_src_16MB.img"
  DDR_IMG_DST="${WORKSPACE_DIR}/if_do_test_2_ddr_dst_16MB.img"
  head -c 16m < "/dev/urandom" > "${DDR_IMG_SRC}"
  dd if="${DDR_IMG_SRC}" of="/dev/udmabuf0" bs=1M count=16 status=none > /dev/null 2>&1
  dd if="/dev/udmabuf0" of="${DDR_IMG_DST}" status=none > /dev/null 2>&1
  diff -Naur "${DDR_IMG_SRC}" "${DDR_IMG_DST}" > /dev/null 2>&1
  DDR_RWSTAT=$?
  if [ $DDR_RWSTAT -eq 0 ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  rm -f "${DDR_IMG_SRC}" "${DDR_IMG_DST}"
  if_do_log_write "2" "DDR4 R/W" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_3() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [3] eMMC OS FLASH" | nc ${SERVER_IPADDR} 9999
  #MOUNT eMMC and test if file exist
  ROOTDEV=$(sed "s/^.*root=//" /proc/cmdline | awk '{print $1}')
  SDDEV=${ROOTDEV:0:12}
  SDDEVNUM=${SDDEV: -1}
  if [ $SDDEVNUM -eq 1 ]; then
    MMCDEV="${SDDEV:0:11}2"
  elif [ $SDDEVNUM -eq 2 ]; then
    MMCDEV="${SDDEV:0:11}1"
  fi
  if [ ! -e "${MMCDEV}" ]; then
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
    if_do_log_write "3" "eMMC OS FLASH" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
    return 1
  fi
  
  EMMC_RAND="${WORKSPACE_DIR}/if_do_test_3_rand_512kb.img"
  EMMC_SIMG="${WORKSPACE_DIR}/if_do_test_3_emmc_512kb.img"
  EMMC_RAND_DST="${WORKSPACE_DIR}/if_do_test_3_rand_dst_512kb.img"
  EMMC_SIMG_DST="${WORKSPACE_DIR}/if_do_test_3_simg_dst_512kb.img"
  dd if="/dev/zero" of="${EMMC_RAND}" bs=1k count=512 conv=fsync status=none > /dev/null 2>&1
  dd if="${MMCDEV}" of="${EMMC_SIMG}" bs=1k skip=64 count=512 conv=fsync status=none > /dev/null 2>&1
  
  EMMC_RAND_SZ=$(wc -c "${EMMC_RAND}" | awk '{print $1}')
  EMMC_SIMG_SZ=$(wc -c "${EMMC_SIMG}" | awk '{print $1}')
  
  if [ $EMMC_RAND_SZ -eq $EMMC_SIMG_SZ ]; then
    dd if="${EMMC_RAND}" of="${MMCDEV}" bs=1k seek=64 count=512 conv=fsync status=none > /dev/null 2>&1
    dd if="${MMCDEV}" of="${EMMC_RAND_DST}" bs=1k skip=64 count=512 conv=fsync status=none > /dev/null 2>&1
    dd if="${EMMC_SIMG}" of="${MMCDEV}" bs=1k seek=64 count=512 conv=fsync status=none > /dev/null 2>&1
    dd if="${MMCDEV}" of="${EMMC_SIMG_DST}" bs=1k skip=64 count=512 conv=fsync status=none > /dev/null 2>&1
    sync
    diff -Naur "${EMMC_RAND}" "${EMMC_RAND_DST}" > /dev/null 2>&1
    EMMC_RWSTAT_RAND=$?
    diff -Naur "${EMMC_SIMG}" "${EMMC_SIMG_DST}" > /dev/null 2>&1
    EMMC_RWSTAT_SIMG=$?
    if [ $EMMC_RWSTAT_RAND -eq 0 ] && [ $EMMC_RWSTAT_SIMG -eq 0 ]; then
      TEST_RESULT_VALUE="OK"
      TEST_RESULT_STATUS="PASSED"
    else
      TEST_RESULT_VALUE="NG"
      TEST_RESULT_STATUS="FAILED"
    fi
    
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  
  rm -f "${EMMC_RAND}" "${EMMC_RAND_DST}" "${EMMC_SIMG}" "${EMMC_SIMG_DST}"
  if_do_log_write "3" "eMMC OS FLASH" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

#Test wifi in AP mode to check if it's available
if_do_test_4() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [4] WIFI CONNECTIVITY" | nc ${SERVER_IPADDR} 9999

  RETRYIT=0
  WIFIAV="${WORKSPACE_DIR}/if_do_test_4_availables.wifi"
  SSIDAV="${WORKSPACE_DIR}/if_do_test_4_availables.ssid"
  BSSADR="${WORKSPACE_DIR}/if_do_test_4_availables.bssa"
  NETWORKCONFIG="/etc/systemd/network/wlan0.network"
  WPACONFIG="/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf"

  test ! -e "/etc/wpa_supplicant" && mkdir -p "/etc/wpa_supplicant"
  if [ -f "${WPACONFIG}" ]; then
    WLSSID=`awk -F "#" '{print $1}' "${WPACONFIG}" | awk -F "=" '/ssid/{print $2}' | awk -F "\"" '{print $2}'`
    WLPSKN=`awk -F "#" '{print $1}' "${WPACONFIG}" | awk -F "=" '/psk/ {print $2}'`
  fi
  if [ -z "${WLSSID}" ] || [ -z "${WLPSKN}" ]; then
    WLSSID="HTC-network"
    WLPSKN="61e3eadac1ac1384b7200356cda8e0aa"
  fi
  if [ ! -f "${NETWORKCONFIG}" ]; then
    systemctl disable systemd-networkd

    #modprobe -r wfx
    cat > "${NETWORKCONFIG}" <<EOF
[Match]
Name=wlan0
KernelCommandLine=!nfsroot

[Network]
DNS=8.8.8.8
Address=192.168.0.175/24
Gateway=192.168.0.254

EOF
    ln -sf /etc/resolv-conf.systemd /etc/resolv.conf
    #modprobe wfx
    systemctl enable systemd-networkd
    systemctl restart systemd-networkd
    sync
  fi

  if [ ! -f "${WPACONFIG}" ]; then
    cat > "${WPACONFIG}"   << EOF
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1


network={
        ssid="${WLSSID}"
        psk=${WLPSKN}
}

EOF
    sync
    #rmmod wfx
    #modprobe wfx
    systemctl enable wpa_supplicant-nl80211@wlan0
    systemctl enable systemd-networkd
    systemctl restart wpa_supplicant-nl80211@wlan0
    systemctl restart systemd-networkd
    sleep 1
  fi
  if [ ! -f "/sys/class/net/wlan0/operstate" ]; then
    #rmmod wfx
    #modprobe wfx
    echo -n "RELOADING MODULE [ wfx ]  : "
    test -f "/sys/class/net/wlan0/operstate"
    while [ $? -ne 0 ] && [ $((RETRYIT++)) -lt 10 ]
    do
      sleep 0.5
      echo -n ". "
      test -f "/sys/class/net/wlan0/operstate"
    done

    echo ""
  fi

  if [ ! -f "/sys/class/net/wlan0/operstate" ]; then
    if_do_log_write "4" "WIFI CONNECTIVITY" "NG" "FAILED"
    return -1
  fi

  RETRYIT=0
  echo -n "WAITING FOR NETWORK TO BECOME AVAILABLE [ ${WLSSID} ]  :  "
  wpa_cli scan > /dev/null 2>&1
  wpa_cli scan_result > "${WIFIAV}"
  awk '!/^Selected/' "${WIFIAV}" | awk '!/^bssid/{print $5}' > "${SSIDAV}"
  awk '!/^Selected/' "${WIFIAV}" | awk '!/^bssid/{print $1}' > "${BSSADR}"
  WLAVAI=`cat "${SSIDAV}" | grep "${WLSSID}"`
  test -z "${WLAVAI}"
  while [ $? -eq 0 ] && [ $((RETRYIT++)) -lt 10 ]
  do
    sleep 0.5
    echo -n ". "
    wpa_cli scan > /dev/null 2>&1
    wpa_cli scan_result > "${WIFIAV}"
    awk '!/^Selected/' "${WIFIAV}" | awk '!/^bssid/{print $5}' > "${SSIDAV}"
    awk '!/^Selected/' "${WIFIAV}" | awk '!/^bssid/{print $1}' > "${BSSADR}"
    WLAVAI=`cat "${SSIDAV}" | grep "${WLSSID}"`
    test -z "${WLAVAI}"
  done

  SSIDNUM=0
  readarray SSIDLST < "${SSIDAV}"

  if [ -z "${WLAVAI}" ]; then
    echo ""
    echo "WIFI NETWORK [ ${WLSSID} ] IS NOT AVAILABLE! "
    echo "AVAILABLE NETWORKS ARE: "
    echo "=================================================="
    echo ""
    while read p; do
      if_ssids $((SSIDNUM++)) "$p"
    done < "${SSIDAV}"
    echo ""
    echo "--------------------------------------------------"
    echo ""
    for kentretry in Do the wifi connection process ; do
      echo "WHICH ONE DO YOU WANT TO CONNECT TO?"
      echo -n "PICK A NUMBER FROM THE LIST ABOVE: "
      read -e USERENTER
      echo ""

      if [ ${USERENTER} -lt 0 ] || [ ${USERENTER} -ge ${#SSIDLST[@]} ] ; then
        echo ""
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo "[ERROR] NUMBER [ ${USERENTER} ] OUT OF RANGE "
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo ""
        echo ""
        continue
      fi
      WLSSID=`echo ${SSIDLST[$USERENTER]} | tr -d '\n'`
      echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
      echo ""
      echo -n "ENTER PASSWORD FOR [ ${WLSSID} ]: "
      read -e WIFPASS
      echo -n "RECONFIRM PASSWORD [ ${WLSSID} ]: "
      read -e CFWIFPASS
      echo ""
      echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
      if [ ${#WIFPASS} -lt 8 ] || [ ${#CFWIFPASS} -gt 63 ]; then
        echo ""
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo "[ERROR] LENGTH OF THE PASSWORD IS INVALID [8~63] "
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo ""
        echo ""
        continue
      fi

      if [ "x$WIFPASS" == "x$CFWIFPASS" ]; then
        echo ""
        break
      else
        echo ""
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo "THE PASSWORDS DO NOT MATCH, TRY AGAIN"
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo ""
        echo ""
        continue
      fi
    done
    WLSSID=`echo ${SSIDLST[$USERENTER]} | tr -d '\n'`
    WLPSKN=`wpa_passphrase "${WLSSID}" "${WIFPASS}" | awk '!/#psk/' | awk -F "=" '/psk/{print $2}'`
    cat > "${WPACONFIG}"   << EOF
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1


network={
        ssid="${WLSSID}"
        psk=${WLPSKN}
}

EOF
    sync
    #rmmod wfx
    #modprobe wfx
    systemctl enable wpa_supplicant-nl80211@wlan0
    systemctl restart wpa_supplicant-nl80211@wlan0
    systemctl restart systemd-networkd
  else
    echo " OK"
  fi

  if [ ! -f "${NETWORKCONFIG}" ]; then

    cat > "${NETWORKCONFIG}" <<EOF
[Match]
Name=wlan0
KernelCommandLine=!nfsroot

[Network]
DNS=8.8.8.8
Address=192.168.0.175/24
Gateway=192.168.0.254

EOF
    sync
  fi

  if [ ! -f "${WPACONFIG}" ]; then
    cat > "${WPACONFIG}"   << EOF
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1


network={
        ssid="${WLSSID}"
        psk=${WLPSKN}
}

EOF
    sync
    #rmmod wfx
    #modprobe wfx
    systemctl enable wpa_supplicant-nl80211@wlan0
    systemctl restart wpa_supplicant-nl80211@wlan0
    systemctl restart systemd-networkd
  fi
  RETRYIT=0
  echo ""
  echo -n "WAITING FOR NETWORK TO BE CONNECTED : . "
  sleep 1
  RESP=`cat "/sys/class/net/wlan0/operstate"`
  test "w${RESP}" == "wup"
  while [ $? -ne 0 ] && [ $((RETRYIT++)) -lt 10 ]
  do
    sleep 0.5
    echo -n ". "
    RESP=`cat "/sys/class/net/wlan0/operstate"`
    test "w${RESP}" == "wup"
  done

  if [ "w${RESP}" == "wup" ]; then
    echo " CONNECTED"
    echo -n "CONNECTING TO TARGET $TARGET_IPADDR: "
    for retry in {1..10}; do
      echo -n ". "
      ping -c 1 -W 1 -I wlan0 "$TARGET_IPADDR" > /dev/null 2>&1
      RESP=$?
      test $RESP -eq 0 && break
    done 
    
    if [ $RESP -eq 0 ]; then
      NWRES="OK"
      echo " OK"
    else
      NWRES=""
      echo " TIMED OUT"
    fi
  else
    echo " TIMED OUT"
    for kentretry in Do the wifi connection process ; do
      echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
      echo ""
      echo -n "ENTER PASSWORD FOR [ ${WLSSID} ]: "
      read -e WIFPASS
      echo -n "RECONFIRM PASSWORD [ ${WLSSID} ]: "
      read -e CFWIFPASS
      echo ""
      echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
      if [ ${#WIFPASS} -lt 8 ] || [ ${#CFWIFPASS} -gt 63 ]; then
        echo ""
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo "[ERROR] LENGTH OF THE PASSWORD IS INVALID [8~63] "
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo ""
        echo ""
        continue
      fi

      if [ "x$WIFPASS" == "x$CFWIFPASS" ]; then
        echo ""
        break
      else
        echo ""
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo "THE PASSWORD DO NOT MATCH, TRY AGAIN"
        echo "::::::::::::::::::::::::::::::::::::::::::::::::::"
        echo ""
        echo ""
        continue
      fi
    done
    WLSSID=`echo ${SSIDLST[$USERENTER]} | tr -d '\n'`
    WLPSKN=`wpa_passphrase "${WLSSID}" "${WIFPASS}" | awk '!/#psk/' | awk -F "=" '/psk/{print $2}'`
    cat > "${WPACONFIG}"   << EOF
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1


network={
        ssid="${WLSSID}"
        psk=${WLPSKN}
}

EOF
    sync
    #rmmod wfx
    #modprobe wfx
    systemctl enable wpa_supplicant-nl80211@wlan0
    systemctl restart wpa_supplicant-nl80211@wlan0
    systemctl restart systemd-networkd
    NWRES=""

    RETRYIT=0
    echo ""
    echo -n "WAITING FOR NETWORK TO BE CONNECTED : . "
    sleep 1
    RESP=`cat "/sys/class/net/wlan0/operstate"`
    test "w${RESP}" == "wup"
    while [ $? -ne 0 ] && [ $((RETRYIT++)) -lt 10 ]
    do
      sleep 0.5
      echo -n ". "
      RESP=`cat "/sys/class/net/wlan0/operstate"`
      test "w${RESP}" == "wup"
    done
    if [ "w${RESP}" == "wup" ]; then
      echo " CONNECTED"
      echo -n "CONNECTING TO TARGET $TARGET_IPADDR: "
      for retry in {1..10}; do
        echo -n ". "
        ping -c 1 -W 1 -I wlan0 "$TARGET_IPADDR" > /dev/null 2>&1
        RESP=$?
        test $RESP -eq 0 && break
      done 
    
      if [ $RESP -eq 0 ]; then
        NWRES="OK"
        echo " OK"
      else
        NWRES=""
        echo " TIMED OUT"
      fi
    else
      echo " TIMED OUT"
      NWRES=""
    fi
  fi

  if [ ! -z "${NWRES}" ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi

  rm -f "${WIFIAV}" "${SSIDAV}" "${BSSADR}"
  
  if_do_log_write "4" "WIFI CONNECTIVITY" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_5() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [5] SDCARD R/W" | nc ${SERVER_IPADDR} 9999
  TESTFSIZE=$((1024*1024))
  RANDDEV="/dev/urandom"
  TMP_RANDNAME="${WORKSPACE_DIR}/${UTEST}_rand.img"
  DSC_RANDNAME="/opt/${UTEST}_rand.img"
  dd if="${RANDDEV}" of="${DSC_RANDNAME}" bs=1k count=1024 conv=fsync status=none > /dev/null 2>&1
  cp "${DSC_RANDNAME}" "${TMP_RANDNAME}"
  
  diff -Naur "${TMP_RANDNAME}" "${DSC_RANDNAME}" > /dev/null 2>&1
  RANDDIFSTAT=$?
  if [ -f "${DSC_RANDNAME}" ]; then
    RANDFSIZE=`ls -l "${DSC_RANDNAME}" | awk '{print $5}'`
    rm -f "${DSC_RANDNAME}"
    sync
  else
    RANDFSIZE=0
  fi
  
  if [ $RANDFSIZE -eq $TESTFSIZE ] && [ $RANDDIFSTAT -eq 0 ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  
  test -f "${TMP_RANDNAME}" && rm -f "${TMP_RANDNAME}"
  test -f "${DSC_RANDNAME}" && rm -f "${DSC_RANDNAME}"
  
  if_do_log_write "5" "SDCARD R/W" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_6() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [6] RS485 TRANSFER" | nc ${SERVER_IPADDR} 9999
  TEST_RESULTS_RET=$(${INSTALL_DIR}/bin/interface_miwa_rs485 | grep "^RS485 TEST PASSED $")
  if [ ! -z "${TEST_RESULTS_RET}" ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "6" "RS485 TRANSFER" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_7() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [7] USB TRANSFER" | nc ${SERVER_IPADDR} 9999
  TEST_LAN_MODULE=`lsusb | grep "LAN7500 Ethernet" | awk '{print $1}'`
  if [ ! -z "$TEST_LAN_MODULE" ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi  

  if_do_log_write "7" "USB TRANSFER" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_8() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [8] CAMERA CONTROL" | nc ${SERVER_IPADDR} 9999
  CAPWIDTH=1920
  CAPHEIGHT=1080
  CAPFCOUNT=30
  RETRYIT=0
  CAPPIXFMTOPT="RG10"
  if [ "$CAPPIXFMTOPT" == "BG10" ] || [ "$CAPPIXFMTOPT" == "RG10" ]; then
    CAPBPP=2
    CAPPIXFMT="$CAPPIXFMTOPT"
    rmmod mx6s_capture
    rmmod mxc_mipi_csi
    rmmod gc2053_camera_mipi
    modprobe mx6s_capture modflag=0
    modprobe mxc_mipi_csi
    modprobe gc2053_camera_mipi modflag=0
    sleep 1
  elif [ "$CAPPIXFMTOPT" == "BA81" ] || [ "$CAPPIXFMTOPT" == "RGGB" ]; then
    CAPBPP=1
    CAPPIXFMT="$CAPPIXFMTOPT"
    rmmod mx6s_capture
    rmmod mxc_mipi_csi
    rmmod gc2053_camera_mipi
    modprobe mx6s_capture modflag=1
    modprobe mxc_mipi_csi
    modprobe gc2053_camera_mipi modflag=1
    sleep 1
  else
    CAPBPP=1
    CAPPIXFMT='RGGB'
    rmmod mx6s_capture
    rmmod mxc_mipi_csi
    rmmod gc2053_camera_mipi
    modprobe mx6s_capture modflag=1
    modprobe mxc_mipi_csi
    modprobe gc2053_camera_mipi modflag=1
    sleep 1
  fi

  CAPFILE="${WORKSPACE_DIR}/if_do_test_08__${CAPWIDTH}x${CAPHEIGHT}_${CAPPIXFMT}.raw"
  CAPSIZE=$((${CAPWIDTH}*${CAPHEIGHT}*${CAPFCOUNT}*${CAPBPP}))
  v4l2-ctl --set-fmt-video=width=${CAPWIDTH},height=${CAPHEIGHT},pixelformat=${CAPPIXFMT} --stream-count=${CAPFCOUNT} --stream-mmap=4 \
  --stream-to="${CAPFILE}" > /dev/null 2>&1 &
  EXECSID=$!
  echo -n "GC2053 CAPTURING ${CAPPIXFMT} : "
  test -f "/proc/${EXECSID}/exe"
  while [ $? -eq 0 ] && [ $((RETRYIT++)) -lt 10 ]
  do
    sleep 0.5
    echo -n ". "
    test -f "/proc/${EXECSID}/exe"
  done

  if [ -f "/proc/${EXECSID}/exe" ]; then
    echo " TIMED OUT, TERMINATING !"
    kill -9 ${EXECSID}
    wait ${EXECSID} 2>/dev/null
  else
    echo " FINISHED !"
  fi
  if [ -f ${CAPFILE} ]; then
    FILESIZE=`ls -l "${CAPFILE}" | awk '{print $5}'`
    rm -f "${CAPFILE}"
    sync
  else
    FILESIZE=0
  fi
  if [ ${FILESIZE} -eq ${CAPSIZE} ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  
  if_do_log_write "8" "CAMERA CONTROL" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_9() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [9] VDD_SOC_0V8" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=0
  ADC_CHN=5
  STD_VOLTAGE="0.85"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  
  if_do_log_write "9" "VDD_SOC_0V8" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_10() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [10] VDD_ARM_0V9" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=0
  ADC_CHN=6
  STD_VOLTAGE="0.95"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi  

  if_do_log_write "10" "VDD_ARM_0V9" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_11() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [11] VDD_DRAM&PU_0V9" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=0
  ADC_CHN=7
  STD_VOLTAGE="0.975"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "11" "VDD_DRAM&PU_0V9" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_12() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [12] VDD_3V3" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=1
  ADC_CHN=0
  STD_VOLTAGE="3.3"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi

  if_do_log_write "12" "VDD_3V3" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_13() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [13] VDD_1V8" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=1
  ADC_CHN=1
  STD_VOLTAGE="1.8"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "13" "VDD_1V8" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_14() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [14] NVCC_DRAM_1V1" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=1
  ADC_CHN=2
  STD_VOLTAGE="1.1"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*3/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "14" "NVCC_DRAM_1V1" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_15() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [15] NVCC_SNVS_1V8" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=1
  ADC_CHN=3
  STD_VOLTAGE="1.8"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "15" "NVCC_SNVS_1V8" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_16() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [16] VDD_SNVS_0V8" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=1
  ADC_CHN=4
  STD_VOLTAGE="0.8"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "16" "VDD_SNVS_0V8" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_17() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [17] VDD_PHY_0V9" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=1
  ADC_CHN=5
  STD_VOLTAGE="0.9"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "17" "VDD_PHY_0V9" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_18() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [18] VDD_PHY_1V2" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=1
  ADC_CHN=6
  STD_VOLTAGE="1.2"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "18" "VDD_PHY_1V2" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_19() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [19] VDDA_1V8" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=1
  ADC_CHN=7
  STD_VOLTAGE="1.8"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "19" "VDDA_1V8" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_20() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [20] NVCC_SD2" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=2
  ADC_CHN=0
  STD_VOLTAGE="3.3"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS_3V3=1
  else
    TEST_RESULT_STATUS_3V3=0
  fi
  
  STD_VOLTAGE="1.8"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS_1V8=1
  else
    TEST_RESULT_STATUS_1V8=0
  fi
  
  if [ $TEST_RESULT_STATUS_1V8 -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  
  if_do_log_write "20" "NVCC_SD2" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_21() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [21] VERSA_VIN12" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=0
  ADC_CHN=2
  STD_VOLTAGE="12"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*10/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*33.1/9.1")
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_ORG:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "21" "VERSA_VIN12" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_22() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [22] DCDC_5V" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=0
  ADC_CHN=3
  STD_VOLTAGE="5"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4.5/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*13.8/9.1")
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_ORG:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "22" "DCDC_5V" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_23() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [23] VDD_5V" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=0
  ADC_CHN=4
  STD_VOLTAGE="5"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4.5/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*13.8/9.1")
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_ORG:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "23" "VDD_5V" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_24() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [24] CAMERA CONNECTIVITY" | nc ${SERVER_IPADDR} 9999

  if [ -e "/dev/i2cdev" ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "24" "CAMERA CONNECTIVITY" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_25() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [25] AVDD_2.8V" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=2
  ADC_CHN=1
  STD_VOLTAGE="2.8"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*3/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "25" "AVDD_2.8V" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_26() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [26] DVDD12" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=2
  ADC_CHN=2
  STD_VOLTAGE="1.2"
  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "26" "DVDD12" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_27() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [27] VOUT1_EN" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=2
  ADC_CHN=4
  STD_VOLTAGE="12"
  GPIO_12VOUT_EN1=83

  #Measure at high level and check if VOUT1 is in range 12 +- $STD_VOLTAGE_ERR
  gpio_init $GPIO_12VOUT_EN1 "out"
  gpio_setval $GPIO_12VOUT_EN1 1
  sleep 0.5

  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*10/100")
  MAX_VOLTAGE_HI=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE_HI=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*5.45/0.75")
  TEST_RESULT_VALUE_HI=${TEST_RESULT_VALUE_ORG:0:5}
  
  VOLTAGE_LE_HI=$(echo $TEST_RESULT_VALUE_HI'<='$MAX_VOLTAGE_HI | bc -l)
  VOLTAGE_GE_HI=$(echo $TEST_RESULT_VALUE_HI'>='$MIN_VOLTAGE_HI | bc -l)
  
  if [ $VOLTAGE_LE_HI -eq 1 ] && [ $VOLTAGE_GE_HI -eq 1 ]; then
    TEST_RESULT_STATUS_HI=1
  else
    TEST_RESULT_STATUS_HI=0
  fi
  
  #Measure at low level and check if VOUT1 is in range 0 ~ 2*$STD_VOLTAGE_ERR
  gpio_setval $GPIO_12VOUT_EN1 0
  sleep 0.5
  
  MAX_VOLTAGE_LO=$(bc -l <<< "$STD_VOLTAGE_ERR+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE_LO=$(bc -l <<< "$STD_VOLTAGE_ERR-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*5.45/0.75")
  TEST_RESULT_VALUE_LO=${TEST_RESULT_VALUE_ORG:0:5}
  
  VOLTAGE_LE_LO=$(echo $TEST_RESULT_VALUE_LO'<='$MAX_VOLTAGE_LO | bc -l)
  VOLTAGE_GE_LO=$(echo $TEST_RESULT_VALUE_LO'>='$MIN_VOLTAGE_LO | bc -l)
  
  if [ $VOLTAGE_LE_LO -eq 1 ] && [ $VOLTAGE_GE_LO -eq 1 ]; then
    TEST_RESULT_STATUS_LO=1
  else
    TEST_RESULT_STATUS_LO=0
  fi

  #Now check if all two cases is true or not
  if [ $TEST_RESULT_STATUS_HI -eq 1 ] && [ $TEST_RESULT_STATUS_LO -eq 1 ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  
  
  gpio_deinit $GPIO_12VOUT_EN1
  if_do_log_write "27" "VOUT1_EN" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_28() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [28] VOUT1" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=2
  ADC_CHN=4
  STD_VOLTAGE="12"
  GPIO_12VOUT_EN1=83

  gpio_init $GPIO_12VOUT_EN1 "out"
  gpio_setval $GPIO_12VOUT_EN1 1
  sleep 0.5

  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*10/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*5.45/0.75")
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_ORG:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  
  gpio_setval $GPIO_12VOUT_EN1 0
  gpio_deinit $GPIO_12VOUT_EN1

  if_do_log_write "28" "VOUT1" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_29() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [29] VOUT2_EN" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=2
  ADC_CHN=5
  STD_VOLTAGE="12"
  GPIO_12VOUT_EN2=84

  #Measure at high level and check if VOUT1 is in range 12 +- $STD_VOLTAGE_ERR
  gpio_init $GPIO_12VOUT_EN2 "out"
  gpio_setval $GPIO_12VOUT_EN2 1
  sleep 0.5

  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*10/100")
  MAX_VOLTAGE_HI=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE_HI=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*5.45/0.75")
  TEST_RESULT_VALUE_HI=${TEST_RESULT_VALUE_ORG:0:5}
  
  VOLTAGE_LE_HI=$(echo $TEST_RESULT_VALUE_HI'<='$MAX_VOLTAGE_HI | bc -l)
  VOLTAGE_GE_HI=$(echo $TEST_RESULT_VALUE_HI'>='$MIN_VOLTAGE_HI | bc -l)
  
  if [ $VOLTAGE_LE_HI -eq 1 ] && [ $VOLTAGE_GE_HI -eq 1 ]; then
    TEST_RESULT_STATUS_HI=1
  else
    TEST_RESULT_STATUS_HI=0
  fi
  
  #Measure at low level and check if VOUT1 is in range 0 ~ 2*$STD_VOLTAGE_ERR
  gpio_setval $GPIO_12VOUT_EN2 0
  sleep 0.5
  
  MAX_VOLTAGE_LO=$(bc -l <<< "$STD_VOLTAGE_ERR+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE_LO=$(bc -l <<< "$STD_VOLTAGE_ERR-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*5.45/0.75")
  TEST_RESULT_VALUE_LO=${TEST_RESULT_VALUE_ORG:0:5}
  
  VOLTAGE_LE_LO=$(echo $TEST_RESULT_VALUE_LO'<='$MAX_VOLTAGE_LO | bc -l)
  VOLTAGE_GE_LO=$(echo $TEST_RESULT_VALUE_LO'>='$MIN_VOLTAGE_LO | bc -l)
  
  if [ $VOLTAGE_LE_LO -eq 1 ] && [ $VOLTAGE_GE_LO -eq 1 ]; then
    TEST_RESULT_STATUS_LO=1
  else
    TEST_RESULT_STATUS_LO=0
  fi

  #Now check if all two cases is true or not
  if [ $TEST_RESULT_STATUS_HI -eq 1 ] && [ $TEST_RESULT_STATUS_LO -eq 1 ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  
  
  gpio_deinit $GPIO_12VOUT_EN2
  if_do_log_write "29" "VOUT2_EN" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_30() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [30] VOUT2" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=2
  ADC_CHN=5
  STD_VOLTAGE="12"  
  GPIO_12VOUT_EN2=84

  gpio_init $GPIO_12VOUT_EN2 "out"
  gpio_setval $GPIO_12VOUT_EN2 1
  sleep 0.5
  

  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*10/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE-$STD_VOLTAGE_ERR")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE_ORG=$(bc -l <<< "$TEST_RESULT_VALUE_RAW*5.45/0.75")
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_ORG:0:5}
  

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  
  gpio_setval $GPIO_12VOUT_EN2 0
  gpio_deinit $GPIO_12VOUT_EN2
  if_do_log_write "30" "VOUT2" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_31() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [31] THERMAL SENSOR" | nc ${SERVER_IPADDR} 9999
  if [ -f "/sys/bus/i2c/devices/0-0048/hwmon/hwmon0/name" ]; then
    THERMAL_SENSOR_NAME=$(cat /sys/bus/i2c/devices/0-0048/hwmon/hwmon0/name | grep "^tmp1075$")
  else
    THERMAL_SENSOR_NAME="null"
  fi
  if [ "x${THERMAL_SENSOR_NAME}" == "xtmp1075" ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"  
  fi

  if_do_log_write "31" "THERMAL SENSOR" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_32() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [32] LED CONTROL" | nc ${SERVER_IPADDR} 9999
  ADC_NUM=0
  ADC_CHN=0
  ADC_CHN_STATE=0
  TEST_RESULT_VALUE_CH=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  for ((ADC_CHN=1; ADC_CHN<8; ADC_CHN++))
  do
    TEST_RESULT_VALUE_GET=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
    TEST_RESULT_STATE=$(echo ${TEST_RESULT_VALUE_GET}'=='${TEST_RESULT_VALUE_CH} | bc -l)
    if [ $TEST_RESULT_STATE -eq 1 ]; then
      ADC_CHN_STATE=$((ADC_CHN_STATE+1))
    fi
  done
  if [ $ADC_CHN_STATE -ne 7 ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi

  if_do_log_write "32" "LED CONTROL" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_33() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [33] KEY INFOMATION PROGRAM" | nc ${SERVER_IPADDR} 9999

  SECURITY_IC_ADDR=`i2cdetect -y 3 | grep "^40" | awk '{print $10}'`
  if [ "0x${SECURITY_IC_ADDR}" == "0x48" ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  
  if_do_log_write "33" "KEY INFOMATION PROGRAM" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_34() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [34] SERIAL NO PROGRAM" | nc ${SERVER_IPADDR} 9999
  EPROM_OFS_ADDR=$(printf "%d" 0x40)
  SERIAL_NO_DST_FILE="${WORKSPACE_DIR}/board_serial_dst_file.txt"
  dd if="${SERIAL_NO_SRC_FILE}" of="/sys/bus/i2c/devices/1-0050/eeprom" bs=1 count=30 seek=${EPROM_OFS_ADDR} conv=notrunc status=none > /dev/null 2>&1
  dd if="/sys/bus/i2c/devices/1-0050/eeprom" of="${SERIAL_NO_DST_FILE}" bs=1 count=30 skip=${EPROM_OFS_ADDR} conv=notrunc status=none > /dev/null 2>&1
  sync
  diff -Naur "${SERIAL_NO_SRC_FILE}" "${SERIAL_NO_DST_FILE}" > /dev/null 2>&1
  EPROM_STAT=$?
  if [ $EPROM_STAT -eq 0 ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  rm -f "${SERIAL_NO_SRC_FILE}" "${SERIAL_NO_DST_FILE}"
  if_do_log_write "34" "SERIAL NO PROGRAM" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}


if_do_bootsw_read() {
  ADC_NUM=$1
  ADC_CHN=$2
  STD_VOLTAGE="1.8"

  STD_VOLTAGE_ERR=$(bc -l <<< "$STD_VOLTAGE*4/100")
  MAX_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE+$STD_VOLTAGE_ERR")
  MIN_VOLTAGE=$(bc -l <<< "$STD_VOLTAGE/2")
  TEST_RESULT_VALUE_RAW=$(${INSTALL_DIR}/bin/interface_miwa_adc $ADC_NUM $ADC_CHN | awk -F ':' '{print $2}')
  TEST_RESULT_VALUE=${TEST_RESULT_VALUE_RAW:0:5}

  VOLTAGE_LE=$(echo $TEST_RESULT_VALUE'<='$MAX_VOLTAGE | bc -l)
  VOLTAGE_GE=$(echo $TEST_RESULT_VALUE'>='$MIN_VOLTAGE | bc -l)
  
  if [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 1 ]; then
    TEST_RESULT_STATE=1
  elif  [ $VOLTAGE_LE -eq 1 ] && [ $VOLTAGE_GE -eq 0 ]; then
    TEST_RESULT_STATE=0
  else
    TEST_RESULT_STATE=2
  fi
  echo "${TEST_RESULT_STATE}"
}

if_do_test_35() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [35] BOOT FROM SD" | nc ${SERVER_IPADDR} 9999

  BOOTMODE_ADDRESS=0x30390070
  BOOTMODE_VALUE=`/unit_tests/memtool $BOOTMODE_ADDRESS 1 | grep "^$BOOTMODE_ADDRESS" | awk '{ print $2 }'`

  if [ -z $BOOTMODE_VALUE ] || [[ ! "$BOOTMODE_VALUE" =~ ^[0-9a-fA-F]*$ ]]; then
    TEST_RESULT_VALUE=""
    TEST_RESULT_STATUS="FAILED"
  else
    BOOTMODE_VALUEHEX=0x$BOOTMODE_VALUE
    BOOTMODE_RES=$(((BOOTMODE_VALUEHEX >> 24)&0x3))
    if [ $BOOTMODE_RES -eq 2 ]; then
      TEST_RESULT_VALUE="OK"
      TEST_RESULT_STATUS="PASSED"
    else
      TEST_RESULT_VALUE="NG"
      TEST_RESULT_STATUS="FAILED"
    fi
  fi

  if_do_log_write "35" "BOOT FROM SD" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_36() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [36] BOOT_MODE SWITCH" | nc ${SERVER_IPADDR} 9999
  echo ""
  echo ""
  echo "--------------------------------------"
  echo ">>>        BOOT SWITCH TEST        <<<"
  echo "--------------------------------------"
  echo ""
  echo -n "[1] PLEASE SET SW7:  OFF >>> ON "
  echo "STATUSPOPUP:[1] スイッチを設定してください 　<br/>SW7:  OFF >>> ON " | nc "${SERVER_IPADDR}" 9999
  BOOT_MODE1=$(if_do_bootsw_read 2 6)
  BOOT_MODE0=$(if_do_bootsw_read 2 7)
  test "w${BOOT_MODE1}${BOOT_MODE0}" == "w01"
  while [ $? -ne 0 ]
  do
    sleep 0.2
    BOOT_MODE1=$(if_do_bootsw_read 2 6)
    BOOT_MODE0=$(if_do_bootsw_read 2 7)
    test "w${BOOT_MODE1}${BOOT_MODE0}" == "w01"
  done
  BOOT_MODE_DL=${BOOT_MODE1}${BOOT_MODE0}
  echo "  [OK]"
  echo "STATUSDIALOGCLR" | nc "${SERVER_IPADDR}" 9999
  echo -n "[2] PLEASE SET SW7:  OFF <<< ON "
  echo "STATUSPOPUP:[2] スイッチを設定してください 　<br/>SW7:  ON >>> OFF " | nc "${SERVER_IPADDR}" 9999
  BOOT_MODE1=$(if_do_bootsw_read 2 6)
  BOOT_MODE0=$(if_do_bootsw_read 2 7)
  
  test "w${BOOT_MODE1}${BOOT_MODE0}" == "w10"
  while [ $? -ne 0 ]
  do
    sleep 0.2
    BOOT_MODE1=$(if_do_bootsw_read 2 6)
    BOOT_MODE0=$(if_do_bootsw_read 2 7)
    test "w${BOOT_MODE1}${BOOT_MODE0}" == "w10"
  done
  BOOT_MODE_BT=${BOOT_MODE1}${BOOT_MODE0}
  echo "  [OK]"
  echo "STATUSDIALOGCLR" | nc "${SERVER_IPADDR}" 9999
  echo ""
  echo ""
  
  if [ "w${BOOT_MODE_DL}" == "w01" ] && [ "w${BOOT_MODE_BT}" == "w10" ]; then
    TEST_RESULT_VALUE="OK"
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_VALUE="NG"
    TEST_RESULT_STATUS="FAILED"
  fi
  if_do_log_write "36" "BOOT_MODE SWITCH" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_37() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [37] TESTAPP VERSION" | nc ${SERVER_IPADDR} 9999
  TEST_RESULT_VALUE="${SWVERSION}"
  TEST_RESULT_STATUS="PASSED"
  if_do_log_write "37" "TESTAPP VERSION" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_38() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [38] WIFI MAC ADDRESS" | nc ${SERVER_IPADDR} 9999
  
  TEST_RESULT_VALUE=`cat /sys/class/net/wlan0/address | tr '[:lower:]' '[:upper:]'`
  if [ ! -z "${TEST_RESULT_VALUE}" ]; then
    TEST_RESULT_STATUS="PASSED"
  else
    TEST_RESULT_STATUS="FAILED"
  fi
  
  if_do_log_write "38" "WIFI MAC ADDRESS" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_39() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [39] TEST DATE" | nc ${SERVER_IPADDR} 9999
  #This information will be updated later
  TEST_RESULT_VALUE="2022/07/09 15:26:22"
  TEST_RESULT_STATUS="PASSED"
  if_do_log_write "39" "TEST DATE" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_40() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [40] PERSON IN CHARGE" | nc ${SERVER_IPADDR} 9999

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
  if_do_log_write "40" "PERSON IN CHARGE" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}

if_do_test_41() {
  echo "SHOWTESTPROG: PERFORMING TEST CASE [41] GENERATION" | nc ${SERVER_IPADDR} 9999
  #This information will be updated later
  TEST_RESULT_VALUE="0"
  TEST_RESULT_STATUS="PASSED"
  if_do_log_write "41" "GENERATION" "${TEST_RESULT_VALUE}" "${TEST_RESULT_STATUS}"
}





#PERFORM TEST CASE [0] SERIAL NO"
if_do_test_0

#PERFORM TEST CASE [1] POWER INPUT"
if_do_test_1

#PERFORM TEST CASE [2] DDR4 R/W"
if_do_test_2

#PERFORM TEST CASE [3] eMMC OS FLASH"
if_do_test_3

#PERFORM TEST CASE [4] WIFI CONNECTIVITY"
if_do_test_4

#PERFORM TEST CASE [5] SDCARD R/W"
if_do_test_5

#PERFORM TEST CASE [6] RS485 TRANSFER"
if_do_test_6

#PERFORM TEST CASE [7] USB TRANSFER"
if_do_test_7

#PERFORM TEST CASE [8] CAMERA CONTROL"
if_do_test_8

#PERFORM TEST CASE [9] VDD_SOC_0V8"
if_do_test_9

#PERFORM TEST CASE [10] VDD_ARM_0V9"
if_do_test_10

#PERFORM TEST CASE [11] VDD_DRAM&PU_0V9"
if_do_test_11

#PERFORM TEST CASE [12] VDD_3V3"
if_do_test_12

#PERFORM TEST CASE [13] VDD_1V8"
if_do_test_13

#PERFORM TEST CASE [14] NVCC_DRAM_1V1"
if_do_test_14

#PERFORM TEST CASE [15] NVCC_SNVS_1V8"
if_do_test_15

#PERFORM TEST CASE [16] VDD_SNVS_0V8"
if_do_test_16

#PERFORM TEST CASE [17] VDD_PHY_0V9"
if_do_test_17

#PERFORM TEST CASE [18] VDD_PHY_1V2"
if_do_test_18

#PERFORM TEST CASE [19] VDDA_1V8"
if_do_test_19

#PERFORM TEST CASE [20] NVCC_SD2"
if_do_test_20

#PERFORM TEST CASE [21] VERSA_VIN12"
if_do_test_21

#PERFORM TEST CASE [22] DCDC_5V"
if_do_test_22

#PERFORM TEST CASE [23] VDD_5V"
if_do_test_23

#PERFORM TEST CASE [24] CAMERA CONNECTIVITY"
if_do_test_24

#PERFORM TEST CASE [25] AVDD_2.8V"
if_do_test_25

#PERFORM TEST CASE [26] DVDD12"
if_do_test_26

#PERFORM TEST CASE [27] VOUT1_EN"
if_do_test_27

#PERFORM TEST CASE [28] VOUT1"
if_do_test_28

#PERFORM TEST CASE [29] VOUT2_EN"
if_do_test_29

#PERFORM TEST CASE [30] VOUT2"
if_do_test_30

#PERFORM TEST CASE [31] THERMAL SENSOR"
if_do_test_31

#PERFORM TEST CASE [32] LED CONTROL"
if_do_test_32

#PERFORM TEST CASE [33] KEY INFOMATION PROGRAM"
if_do_test_33

#PERFORM TEST CASE [34] SERIAL NO PROGRAM"
if_do_test_34

#PERFORM TEST CASE [35] BOOT FROM SD"
if_do_test_35

#PERFORM TEST CASE [36] BOOT_MODE SWITCH"
if_do_test_36

#PERFORM TEST CASE [37] TESTAPP VERSION"
if_do_test_37

#PERFORM TEST CASE [38] WIFI MAC ADDRESS"
if_do_test_38

#PERFORM TEST CASE [39] TEST DATE"
if_do_test_39

#PERFORM TEST CASE [40] PERSON IN CHARGE"
if_do_test_40

#PERFORM TEST CASE [41] GENERATION"
if_do_test_41

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

dmesg -n ${KERNDEFLV}
rm -rf "${WORKSPACE_DIR}"

exit 0