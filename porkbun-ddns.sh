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
declare -g IP_ADDR_V4 IP_ADDR_V6
declare -g LAST_IPS_FILE HOSTS
declare -a CMD_HOSTS=()

# API Key:
API_KEY=
# Secret Key:
SECRET_KEY=

# URI Endpoint:
# DNS Edit Record by Domain, Subdomain and Type
URI_ENDPOINT=https://porkbun.com/api/json/v3/dns/editByNameType

PROJECT="Porkbun DDNS CLI v1.0.3 (2024.2.5)"
COPYRIGHT="Copyright (c) 2023 Mr.Chu"
LICENSE="MIT License: <https://opensource.org/licenses/MIT>"
HELP="Usage: porkbun-ddns.sh <command> ... [parameters ...]
Commands:
  --help                        Show this help message.
  --version                     Show version info.
  --api-key, -ak <apikey>       Specify Porkbun API Key.
  --secret-key, -sk <secretkey> Specify Porkbun Secret Key.
  --host, -h <host>             Add a hostname.
  --config-file, -c <filepath>  The path to config file.

Example:
  # Read parameters from a config file.
  porkbun-ddns.sh \\
    -c /etc/porkbun.conf

  # Pass parameters from the command line.
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

show_help() {
  echo "${PROJECT:-}"
  echo "${HELP:-}"
  exit 0
}

show_version() {
  echo "${PROJECT:-}"
  echo "${COPYRIGHT:-}"
  echo "${LICENSE:-}"
  exit 0
}

check_key() {
  local RE_KEY='^[0-9a-z_]{68}$'
  if [[ ! $1 =~ $RE_KEY ]]; then
    echo "Invalid $2: $1"
    exit 9
  fi
}

check_host() {
  local RE_HOST='^([a-zA-Z0-9\-]{1,63}\.)+[a-zA-Z0-9\-]{1,63}$'
  if [[ ! $1 =~ $RE_HOST ]]; then
    echo "Invalid host format: $1"
    exit 9
  fi
}

read_config_file() {
  if [ -f "$1" ]; then
    while IFS='=' read -r key value; do
      case "$key" in
        apikey) [[ -z ${API_KEY:-} ]] && API_KEY="$value" ;;
        secretkey) [[ -z ${SECRET_KEY:-} ]] && SECRET_KEY="$value" ;;
        hosts) IFS=',' read -r -a HOSTS <<< "$value" ;;
      esac
    done < "$1"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --help) show_help ;;
    --version) show_version ;;
    --api-key | -ak)
      check_key $2 "API Key"
      API_KEY="$2"
      shift
      ;;
    --secret-key | -sk)
      check_key $2 "Secret Key"
      SECRET_KEY="$2"
      shift
      ;;
    --host | -h)
      check_host $2
      CMD_HOSTS+=("$2")
      shift
      ;;
    --config-file | -c)
      read_config_file $2
      shift
      ;;
    esac
    shift
  done

  # In this script, we specify that command-line arguments take precedence over parameters in the configuration file.
  if [[ ${#CMD_HOSTS[@]} -gt 0 ]]; then
    HOSTS=("${CMD_HOSTS[@]}")
  fi

  if [[ -z ${API_KEY:-} ]]; then
    echo "No valid API Key"
    exit 9
  elif [[ -z ${SECRET_KEY:-} ]]; then
    echo "No valid Secret Key"
    exit 9
  elif [[ -z ${HOSTS[@]} ]]; then
    echo "No valid host"
    exit 9
  elif [[ -z $(command -v curl) && -z $(command -v dig) ]]; then
    echo "Necessary requirement (curl/dig) does not exist."
    exit 9
  fi

  # echo "Apikey: $API_KEY"
  # echo "Secretkey: $SECRET_KEY"

  # echo "Hosts:"
  # for host in "${HOSTS[@]}"; do
    # echo "  $host"
  # done
}

load_cached_ips() {
  local HOST
  declare -A IP_CACHE

  # The file used to store these last IPs.
  LAST_IPS_FILE=${0%/*}/lastIPs

  # Read these last IPs from the above file and populate the IP_CACHE array.
  if [ -f $LAST_IPS_FILE ]; then
    while IFS= read -r line; do
      HOST=$(echo "$line" | awk '{print $1}')
      IP_CACHE["$HOST"]="$line"
    done <$LAST_IPS_FILE

    for HOST in "${HOSTS[@]}"; do
      if [ ! -v IP_CACHE["$HOST"] ] || [ -z "${IP_CACHE["$HOST"]}" ]; then
        echo "$HOST A 1.1.1.1" >>"$LAST_IPS_FILE"
        echo "$HOST AAAA 2606:4700:4700::1111" >>"$LAST_IPS_FILE"
      else
        unset IP_CACHE["$HOST"]
      fi
    done

    # for key in "${!IP_CACHE[@]}"; do
    #   echo "Key: $key, Value: ${IP_CACHE[$key]}"
    # done

    # Remove obsolete entries from the file
    for HOST in "${!IP_CACHE[@]}"; do
      sed -i "/^$HOST /d" "$LAST_IPS_FILE"
    done
  else
    for HOST in "${HOSTS[@]}"; do
      echo "$HOST A 1.1.1.1" >>"$LAST_IPS_FILE"
      echo "$HOST AAAA 2606:4700:4700::1111" >>"$LAST_IPS_FILE"
    done
  fi
}

get_curr_ip() {
  local ARG POOL RE
  if [[ $1 == "-4" ]]; then
    POOL=(
      "dig @one.one.one.one whoami.cloudflare TXT ch -4 +short | tr -d '\"'"
      "dig @ns1.google.com o-o.myaddr.l.google.com TXT -4 +short | tr -d '\"'"
      "dig @resolver1.opendns.com myip.opendns.com A -4 +short"
    )
    RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  elif [[ $1 == "-6" ]]; then
    POOL=(
      "dig @one.one.one.one whoami.cloudflare TXT ch -6 +short | tr -d '\"'"
      "dig @ns1.google.com o-o.myaddr.l.google.com TXT -6 +short | tr -d '\"'"
      "dig @resolver1.ipv6-sandbox.opendns.com myip.opendns.com AAAA -6 +short"
    )
    RE='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{1,4}$'
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

  if [[ $ARG == "-4" ]]; then
    IP_ADDR_V4="$RES"
  fi

  if [[ $ARG == "-6" ]]; then
    IP_ADDR_V6="$RES"
  fi
}

update_record() {
  local STATUS MAX_RETRIES RETRY_COUNT HOST DOMAIN SUBDOMAIN TYPE IP_ADDR

  HOST=$1
  DOMAIN=$(echo $HOST | awk -F '.' '{ print $(NF-1)"."$NF }')
  # Subdomain is optional, it may be empty.
  SUBDOMAIN=$(echo ${HOST%$DOMAIN*} | sed 's/\(.*\)\..*/\1/')
  # echo "Subdomain -> $SUBDOMAIN  Domain -> $DOMAIN"

  TYPE=$2
  IP_ADDR=$3

  STATUS=""
  MAX_RETRIES=3
  RETRY_COUNT=0
  while [[ $STATUS != "SUCCESS" && $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    STATUS=$(curl -s -X POST "$URI_ENDPOINT/$DOMAIN/$TYPE/$SUBDOMAIN" -H "Content-Type: application/json" --data "{\"secretapikey\":\"${SECRET_KEY}\",\"apikey\":\"${API_KEY}\",\"content\":\"${IP_ADDR}\"}" | sed -E 's/.*"status":"?([^,"]*)"?.*/\1/')
    sleep 3
    if [[ $STATUS == "SUCCESS" ]]; then
      break
    else
      RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
  done

  if [[ $STATUS == "SUCCESS" ]]; then
    sed -i "/^$HOST $TYPE /s/[^ ]*$/$IP_ADDR/g" "$LAST_IPS_FILE"
    echo "The $TYPE of '$HOST' has been successfully updated to $IP_ADDR!"
  else
    echo "The $TYPE update of '$HOST' has failed!"
  fi
}

update_records() {
  local HOST TYPE IP VAR DOMAIN SUBDOMAIN
  while IFS= read -r line; do
    HOST=$(echo "$line" | awk '{print $1}')
    TYPE=$(echo "$line" | awk '{print $2}')
    IP=$(echo "$line" | awk '{print $3}')

    [[ -z $HOST ]] && continue
    VAR=(${HOST//./ })
    [[ ${#VAR[@]} -lt 2 ]] && continue

    if [ "$TYPE" = "A" ] && [ ${IP_ADDR_V4:-NULL} == "NULL" ]; then
      continue
    fi
    if [ "$TYPE" = "AAAA" ] && [ ${IP_ADDR_V6:-NULL} == "NULL" ]; then
      continue
    fi

    if [ "$TYPE" = "A" ] && [ "$IP" != "$IP_ADDR_V4" ]; then
      update_record "$HOST" "$TYPE" "$IP_ADDR_V4"
    elif [ "$TYPE" = "AAAA" ] && [ "$IP" != "$IP_ADDR_V6" ]; then
      update_record "$HOST" "$TYPE" "$IP_ADDR_V6"
    fi
  done <$LAST_IPS_FILE
}

main() {
  load_cached_ips
  get_curr_ip -4
  get_curr_ip -6
  update_records
}

parse_args "$@"
main
exit 0
