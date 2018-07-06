#!/bin/bash

app_instance=__APP__

source /usr/share/yunohost/helpers

external_IP_line="external-ip=__IPV4__,__IPV6__"

public_ip4="$(curl ip.yunohost.org)" || true
public_ip6="$(curl ipv6.yunohost.org)" || true

if [[ -n "$public_ip4" ]] && ynh_validate_ip 4 "$public_ip4"
then
    external_IP_line="${external_IP_line/'__IPV4__'/$public_ip4}"
else
    external_IP_line="${external_IP_line/'__IPV4__,'/}"
fi

if [[ -n "$public_ip6" ]] && ynh_validate_ip 6 "$public_ip6"
then
    external_IP_line="${external_IP_line/'__IPV6__'/$public_ip6}"
else
    external_IP_line="${external_IP_line/',__IPV6__'/}"
fi

ynh_replace_string "^external-ip=.*\$" "$external_IP_line" "/etc/matrix-$app_instance/coturn.conf"

exit 0