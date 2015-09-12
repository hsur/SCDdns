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
  sa_api "/commonserviceitem/${DNS_RESOURCE_ID}" "GET" "" - \
  | json -0 "CommonServiceItem.Settings.DNS.ResourceRecordSets" \
  | json -0 -c "this.Name == '$DNS_HOSTNAME'" '0.RData'

  return ${PIPESTATUS[0]} 
}

set_scdns_ip(){

  DNS_CONF=`sa_api "/commonserviceitem/${DNS_RESOURCE_ID}" "GET" "" - \
  | json -0 -A -e "
  for( var i in this ){
    if( i == 'CommonServiceItem' ){ continue; }
    delete this[i];
  }
  for( var i in this.CommonServiceItem ){
    if( i == 'Settings' ){ continue; }
    delete this.CommonServiceItem[i]
  }
  var rr = this.CommonServiceItem.Settings.DNS.ResourceRecordSets;
  var updated = false;
  for( var i = 0; i < rr.length ; i++){
    if(rr[i].Name != '$DNS_HOSTNAME' ){ continue; }
    rr[i].RData = '$1';
    rr[i].TTL = $DNS_TTL;
    updated = true;
  }
  if( !updated ){
     rr.push({'Name':'$DNS_HOSTNAME','Type':'A','TTL':$DNS_TTL,'RData':'$1'})
  }
  "`
  if [ $? -ne 0 ] ; then
    return 1
  fi

  sa_api "/commonserviceitem/${DNS_RESOURCE_ID}" "PUT" "${DNS_CONF}" - | json Success
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
  logger "[ERROR] Failed to look up global IP address." 
  logger "===== END ====="
  exit 1
fi

if [ "${CUR_IP}" = "${LAST_IP}" ]; then
  logger "[INFO] Global IP address is not changed. (${CUR_IP})"
  logger "===== END ====="
  exit 2
fi

SC_IP=`get_scdns_ip`
if [ $? -ne 0 ] ; then
  logger "[ERROR] Failed to look up SC DNS."
  logger "===== END ====="
  return 1
fi

logger "[INFO] Current A record: $SC_IP"
if [ "${CUR_IP}" = "${SC_IP}" ]; then
  logger "[INFO] No need to update A record."
  logger "===== END ====="
  exit 3
fi

logger "[INFO] Updating A record"
RES=`set_scdns_ip $CUR_IP`
if [ $? -ne 0 ] ; then
  logger "[ERROR] Failed to update SC DNS."
  logger "===== END ====="
  return 1
fi
logger "[INFO] Result: $RES"

echo -n "${CUR_IP}" > lastip.txt
logger "===== END ====="
