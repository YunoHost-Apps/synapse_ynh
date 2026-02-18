#!/bin/bash

set -eu

app=__APP__
YNH_HELPERS_VERSION=2.1
YNH_APP_ACTION=''
YNH_STDINFO=/dev/stdout
source /usr/share/yunohost/helpers

port_synapse_tls=$(ynh_app_setting_get  --key=port_synapse_tls)
service_config_file="/etc/matrix-$app/conf.d/app_service.yaml"
backup_app_service=$(mktemp)

# Backup the previous config file
cp "$service_config_file" "$backup_app_service"

if [ -n "$(ls "/etc/matrix-$app/app-service/")" ]; then
    echo "app_service_config_files:" > "$service_config_file"

    for f in "/etc/matrix-$app/app-service/"*; do
        echo "  - $f" >> "$service_config_file"
    done

    chown "$app" "/etc/matrix-$app/app-service/"*
    chmod 600 "/etc/matrix-$app/app-service/"*

    # Add synapse_clean_unreferenced_states cron
    cp "/etc/matrix-$app/sources/synapse_clean_unreferenced_states" "/etc/cron.d/synapse_clean_unreferenced_states"
else
    echo "" > "$service_config_file"
    
    # Remove synapse_clean_unreferenced_states cron
    ynh_safe_rm /etc/cron.d/synapse_clean_unreferenced_states
fi
chown "$app" "$service_config_file"
chmod 600 "$service_config_file"

set +e
ynh_systemctl --service="$app".service --action=restart --wait_until="Synapse now listening on TCP port $port_synapse_tls" --log_path="/var/log/matrix-$app/homeserver.log" --timeout=300
res=$?
set -e
set +x

if [ $res -eq 0 ]; then
    rm "$backup_app_service"
    exit 0
else
    echo "Failed to restart synapse with the new config file. Restore the old config file !!"
    cp "$backup_app_service" "$service_config_file"
    rm "$backup_app_service"
    ynh_systemctl --service="$app".service --action=restart --wait_until="Synapse now listening on TCP port $port_synapse_tls" --log_path="/var/log/matrix-$app/homeserver.log" --timeout=300
    exit 1
fi
