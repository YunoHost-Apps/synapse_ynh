#!/bin/bash

app_instance=__APP__

ynh_validate_ip()
{
  # http://stackoverflow.com/questions/319279/how-to-validate-ip-address-in-python#319298

  local IP_ADDRESS_FAMILY=$1
  local IP_ADDRESS=$2

  [ "$IP_ADDRESS_FAMILY" == "4" ] || [ "$IP_ADDRESS_FAMILY" == "6" ] || return 1

  python /dev/stdin << EOF
import socket
import sys
family = { "4" : socket.AF_INET, "6" : socket.AF_INET6 }
try:
    socket.inet_pton(family["$IP_ADDRESS_FAMILY"], "$IP_ADDRESS")
except socket.error:
    sys.exit(1)
sys.exit(0)
EOF
}

external_IP_line="external-ip=__IPV4__,__IPV6__"

public_ip4="$(curl ip.yunohost.org)" || true
public_ip6="$(curl ipv6.yunohost.org)" || true

if [[ -n "$public_ip4" ]] && ynh_validate_ip 4 "$public_ip4"
then
    external_IP_line="${external_IP_line/'__IPV4__'/$public_ip4}"
else
    external_IP_line="${external_IP_line/'__IPV4__,'/}"
fi

if [[ -n "$public_ip6" ]] && ynh_valide_ip 6 "$public_ip6"
then
    external_IP_line="${external_IP_line/'__IPV6__'/$public_ip6}"
else
    external_IP_line="${external_IP_line/',__IPV6__'/}"
fi

sed --in-place  "s@^external-ip=.*\$@$external_IP_line@g"  "/etc/matrix-$app_instance/coturn.conf"

exit 0