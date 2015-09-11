#!/bin/bash
# sakura cloud ddns

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

cmd_check(){ which $1 > /dev/null 2>&1 || ( echo "$1 command not found" && exit 5 ) }

logger(){
  if [ "$#" -ne 0 ] ; then
    echo "`date "+%Y-%m-%d %H:%M:%S"` [$$]: $@"
  fi
}

sa_api(){
  if [ "$#" -ne 4 ] ; then
    return 1
  fi
  curl --user "${SEC_TOKEN}":"${SEC_SECRET}" \
    -X "${2}" \
    -d "${3}" \
    -o ${4} \
    https://secure.sakura.ad.jp/cloud/zone/${SC_ZONE}/api/cloud/1.1${1} \
    -s
  return $?
}

get_scdns_ip(){
  sa_api "/commonserviceitem/${DNS_RESOURCE_ID}" "GET" "" - | json 'CommonServiceItem.Settings.DNS.ResourceRecordSets[0].RData'
  return ${PIPESTATUS[0]} 
}

set_scdns_ip(){
  sa_api "/commonserviceitem/${DNS_RESOURCE_ID}" "PUT" "{'CommonServiceItem':{'Settings':{'DNS':{'ResourceRecordSets':[{'Name':'$DNS_HOSTNAME','Type':'A','RData':'$1','TTL':$DNS_TTL}]}}}}" - | json Success
  return ${PIPESTATUS[0]}
}


###### MAIN Routine #####

cmd_check curl
cmd_check json

CONFIG="./config.json"
if [ -n "$1" ] ; then
    CONFIG="$1"
fi

read SEC_TOKEN SEC_SECRET SC_ZONE DNS_RESOURCE_ID DNS_HOSTNAME DNS_TTL< <( json -a token secret zone ddns.resource_id ddns.hostname ddns.ttl< $CONFIG )

logger "===== START ====="
TIMESTAMP="`date "+%Y%m%d"`"

CUR_IP=`curl -s http://ipcheck.ieserver.net/`
#CUR_IP=`curl -s https://httpbin.org/ip | json origin`
#CUR_IP=`curl -s http://ifconfig.me/all.json | json ip_addr`
LAST_IP=`cat lastip.txt`

if [ -z ${CUR_IP} ]; then
  logger "IP cannot detect" 
  logger "===== END ====="
  exit 1
fi

if [ "${CUR_IP}" = "${LAST_IP}" ]; then
  echo "IP not changed: ${CUR_IP}"
  logger "===== END ====="
  exit 2
fi

SC_IP=`get_scdns_ip`
logger "sakura_ip: $SC_IP"
if [ "${CUR_IP}" = "${SC_IP}" ]; then
  logger "IP is already set."
  logger "===== END ====="
  exit 3
fi

logger "Updating Sakura DNS"
RES=`set_scdns_ip $CUR_IP`
logger "Result: $RES"

echo "${CUR_IP}" > lastip.txt
logger "===== END ====="
