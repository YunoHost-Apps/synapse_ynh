#!/bin/bash

set -eu

app=__APP__
YNH_APP_BASEDIR=/etc/yunohost/apps/"$app"
YNH_HELPERS_VERSION=2.1
YNH_APP_ACTION=''

pushd /etc/yunohost/apps/$app/conf

source /usr/share/yunohost/helpers

# Must load db_name var to load _common.sh
db_name=$(ynh_app_setting_get --key=db_name)
domain=$(ynh_app_setting_get  --key=domain)

source ../scripts/_common.sh

port_cli=$(ynh_app_setting_get --key=port_cli)
turnserver_pwd=$(ynh_app_setting_get --key=turnserver_pwd)
turnserver_cli_pwd=$(ynh_app_setting_get --key=turnserver_cli_pwd)
port_turnserver_tls=$(ynh_app_setting_get --key=port_turnserver_tls)
port_turnserver_alt_tls=$(ynh_app_setting_get --key=port_turnserver_alt_tls)
enable_dtls_for_audio_video_turn_call=$(ynh_app_setting_get --key=enable_dtls_for_audio_video_turn_call)

previous_checksum=$(ynh_app_setting_get --key=checksum__etc_matrix-synapse_coturn.conf)
configure_coturn
new_checksum=$(ynh_app_setting_get --key=checksum__etc_matrix-synapse_coturn.conf)

setfacl -R -m user:turnserver:rX  /etc/matrix-$app

if [ "$previous_checksum" != "$new_checksum" ]
then
    systemctl restart "$app"-coturn.service
fi

exit 0
