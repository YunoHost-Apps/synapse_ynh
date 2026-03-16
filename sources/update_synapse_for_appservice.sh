#!/bin/bash
set -eu
app=__APP__
YNH_HELPERS_VERSION=2.1
YNH_APP_ACTION=''
YNH_STDINFO=/dev/stdout
source /usr/share/yunohost/helpers

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
else
    echo "" > "$service_config_file"
fi
chown "$app" "$service_config_file"
chmod 600 "$service_config_file"

set +e
ynh_systemctl --service="$app" --action=restart --log_path=systemd
res=$?
set -e

# Wait a moment and verify service is actually running
sleep 5
if ! systemctl is-active --quiet "$app"; then
    echo "Failed to restart synapse with the new config file. Restore the old config file !!"
    cp "$backup_app_service" "$service_config_file"
    rm "$backup_app_service"
    ynh_systemctl --service="$app" --action=restart --log_path=systemd
    sleep 5
    if ! systemctl is-active --quiet "$app"; then
        echo "ERROR: Synapse failed to start even after restoring config!"
        exit 1
    fi
fi

rm "$backup_app_service"
exit 0
