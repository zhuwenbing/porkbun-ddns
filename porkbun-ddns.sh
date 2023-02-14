#!/bin/bash
set -euo pipefail

## Project:     Porkbun DDNS CLI
## Author:      Mr.Chu
## Requirement: curl/dig

####################################################################
###                                                              ###
###  Reference to https://porkbun.com/api/json/v3/documentation  ###
###                                                              ###
####################################################################

declare -g API_KEY SECRET_KEY URI_ENDPOINT
declare -g PROJECT COPYRIGHT LICENSE HELP
declare -g HOSTS LAST_IPS_FILE LAST_IP_V4 LAST_IP_V6
declare -g IP_ADDR_V4 IP_ADDR_V6 IP_V4_CHANGED IP_V6_CHANGED

# API Key:
API_KEY=
# Secret Key:
SECRET_KEY=
# URI Endpoint:
# DNS Edit Record by Domain, Subdomain and Type
URI_ENDPOINT=https://porkbun.com/api/json/v3/dns/editByNameType

PROJECT="Porkbun DDNS CLI v1.0.0 (2022.05.20)"
COPYRIGHT="Copyright (c) 2022 Mr.Chu"
LICENSE="MIT License: <https://opensource.org/licenses/MIT>"
HELP="Usage: porkbun-ddns.sh <command> ... [parameters ...]
Commands:
  --help                        Show this help message
  --version                     Show version info
  --api-key, -ak <apikey>       Specify Namesilo API Key
  --secret-key, -sk <secretkey> Specify Namesilo Secret Key
  --host, -h <host>             Add a hostname

Example:
  porkbun-ddns.sh \\
    -ak pk1_jeldvj74ql06qq81rfx7jqsaubno867q4zp3b2fi06pw2bns81innur6p0oq3n7s \\
    -sk sk1_kfkcxsgne1i8qm4mr8va8t9e8f5ezpw8fsin35uh8jjqwhgsfb7571y2wq3shdgx \\
    -h domain1.tld \\
    -h subdomain.domain1.tld \\
    -h subdomain.domain2.tld

Exit codes:
  0 Successfully updating for all host(s)
  9 Arguments error

Tips:
  Strongly recommand to refetch records or clear caches in file,
  if your DNS records have been updated by other ways.
"

parse_args() {
  local RE_KEY="^[0-9a-z_]{68}$"
  local RE_HOST="^([a-zA-Z0-9\-]{1,63}\.)+[a-zA-Z0-9\-]{1,63}$"
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --help)
      echo "${PROJECT:-}"
      echo "${HELP:-}"
      exit 0
      ;;
    --version)
      echo "${PROJECT:-}"
      echo "${COPYRIGHT:-}"
      echo "${LICENSE:-}"
      exit 0
      ;;
    --api-key | -ak)
      shift
      if [[ $1 =~ $RE_KEY ]]; then
        API_KEY="$1"
      else
        echo "Invalid API Key: $1"
        exit 9
      fi
      ;;
    --secret-key | -sk)
      shift
      if [[ $1 =~ $RE_KEY ]]; then
        SECRET_KEY="$1"
      else
        echo "Invalid Secret Key: $1"
        exit 9
      fi
      ;;
    --host | -h)
      shift
      if [[ $1 =~ $RE_HOST ]]; then
        HOSTS+=("$1")
      else
        echo "Invalid host format: $1"
        exit 9
      fi
      ;;
    esac
    shift
  done

  if [[ ! ${API_KEY:-} =~ $RE_KEY ]]; then
    echo "No valid API Key"
    exit 9
  elif [[ ! ${SECRET_KEY:-} =~ $RE_KEY ]]; then
    echo "No valid Secret Key"
    exit 9
  elif [[ -z ${HOSTS[@]} ]]; then
    echo "No valid host"
    exit 9
  elif [[ -z $(command -v curl) && -z $(command -v dig) ]]; then
    echo "Necessary requirement (curl/dig) does not exist."
    exit 9
  fi
}

load_cached_ips() {
  # The file used to store these last IPs.
  LAST_IPS_FILE=${0%/*}/lastIPs
  # Read these last IPs from the above file.
  if [ -f $LAST_IPS_FILE ]; then
    while read var value
    do
      export "$var"="$value"
    done < $LAST_IPS_FILE
  else
    LAST_IP_V4=1.1.1.1
    LAST_IP_V6=2606:4700:4700::1111
    cat <<EOF > $LAST_IPS_FILE
LAST_IP_V4 $LAST_IP_V4
LAST_IP_V6 $LAST_IP_V6
EOF
  fi
}

get_curr_ip() {
  local ARG POOL RE
  if [[ $1 == "-4" ]]; then
    POOL=(
      # "dig @1.1.1.1 whoami.cloudflare TXT ch -4 +short | sed 's/\"//g'"
      "dig @ns1.google.com o-o.myaddr.l.google.com TXT -4 +short | sed 's/\"//g'"
      "dig @resolver1.opendns.com myip.opendns.com A -4 +short"
    )
    RE="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
  elif [[ $1 == "-6" ]]; then
    POOL=(
      # "dig @2606:4700:4700::1111 whoami.cloudflare TXT ch -6 +short | sed 's/\"//g'"
      "dig @ns1.google.com o-o.myaddr.l.google.com TXT -6 +short | sed 's/\"//g'"
      "dig @resolver1.ipv6-sandbox.opendns.com myip.opendns.com AAAA -6 +short"
    )
    RE="^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{1,4}$"
  else
    return
  fi
  ARG="$1"

  ## Get public ip from pool in random order.
  local RES IDX IDX_RAN VAR
  for ((IDX = ${#POOL[@]} - 1; IDX >= 0; IDX--)); do
    IDX_RAN=$(($RANDOM % (IDX + 1)))
    VAR="${POOL[IDX]}"
    POOL[$IDX]="${POOL[IDX_RAN]}"
    POOL[$IDX_RAN]="$VAR"
    set +e
    RES=$(eval ${POOL[IDX]})
    set -e
    if [[ $RES =~ $RE ]]; then
      break
    else
      RES="NULL"
    fi
  done

  if [[ ${RES:-NULL} == "NULL" ]]; then
    return
  elif [[ $ARG == "-4" && $RES != ${IP_ADDR_V4:-NULL} ]]; then
    IP_ADDR_V4="$RES"
  elif [[ $ARG == "-6" && $RES != ${IP_ADDR_V6:-NULL} ]]; then
    IP_ADDR_V6="$RES"
  fi
}

check_changed() {
  # See if the IP has changed
  if [[ $IP_ADDR_V4 == $LAST_IP_V4 ]]; then
    IP_V4_CHANGED=false
    echo "Public.IP.Check -- Public IPv4 has not changed."
  else
    if [[ ${IP_ADDR_V4:-NULL} != "NULL" ]]; then
      IP_V4_CHANGED=true
    fi
  fi
  if [[ $IP_ADDR_V6 == $LAST_IP_V6 ]]; then
    IP_V6_CHANGED=false
    echo "Public.IP.Check -- Public IPv6 has not changed."
  else
    if [[ ${IP_ADDR_V6:-NULL} != "NULL" ]]; then
      IP_V6_CHANGED=true
    fi
  fi
}

update_records() {
  local HOST VAR
  for HOST in "${HOSTS[@]:-}"; do
    [[ -z $HOST ]] && continue
    VAR=(${HOST//./ })
    [[ ${#VAR[@]} -lt 2 ]] && continue
    do_update $HOST
  done
}

do_update() {
  # Domain
  # Subdomain: optional.
  local HOST DOMAIN SUBDOMAIN STATUS
  HOST=$1
  DOMAIN=$(echo $HOST | awk -F '.' '{ print $(NF-1)"."$NF }')
  SUBDOMAIN=$(echo ${HOST%$DOMAIN*} | sed 's/\(.*\)\..*/\1/')
  # echo "Subdomain -> $SUBDOMAIN  Domain -> $DOMAIN"
  # return
  if [[ $IP_V4_CHANGED == true ]]; then
    STATUS=$(curl -s -X POST "$URI_ENDPOINT/$DOMAIN/A/$SUBDOMAIN" -H "Content-Type: application/json" --data '{"secretapikey":"'$SECRET_KEY'","apikey":"'$API_KEY'","content": "'$IP_ADDR_V4'","ttl":"300"}' | sed -E 's/.*"status":"?([^,"]*)"?.*/\1/')
    if [[ $STATUS == "SUCCESS" ]]; then
      sed -i "s/$LAST_IP_V4/$IP_ADDR_V4/" $LAST_IPS_FILE
      echo "Public.IP.Check -- Public IPv4 has changed to $IP_ADDR_V4"
    fi
  fi
  if [[ $IP_V6_CHANGED == true ]]; then
    STATUS=$(curl -s -X POST "$URI_ENDPOINT/$DOMAIN/AAAA/$SUBDOMAIN" -H "Content-Type: application/json" --data '{"secretapikey":"'$SECRET_KEY'","apikey":"'$API_KEY'","content": "'$IP_ADDR_V6'","ttl":"300"}' | sed -E 's/.*"status":"?([^,"]*)"?.*/\1/')
    if [[ $STATUS == "SUCCESS" ]]; then
      sed -i "s/$LAST_IP_V6/$IP_ADDR_V6/" $LAST_IPS_FILE
      echo "Public.IP.Check -- Public IPv6 has changed to $IP_ADDR_V6"
    fi
  fi
}

main() {
  load_cached_ips
  get_curr_ip -4
  get_curr_ip -6
  check_changed
  update_records
}

parse_args $*
main
exit 0
