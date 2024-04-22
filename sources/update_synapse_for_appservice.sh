#!/bin/bash

set -eu

app=__APP__
service_config_file=/etc/matrix-$app/conf.d/app_service.yaml

# Backup the previous config file
cp $service_config_file /tmp/app_service_backup.yaml

if [ -n "$(ls /etc/matrix-$app/app-service/)" ]; then
    echo "app_service_config_files:" > $service_config_file
else
    echo "" > $service_config_file
fi
for f in $(ls /etc/matrix-$app/app-service/); do
    echo "  - /etc/matrix-$app/app-service/$f" >> $service_config_file
done

# Set permissions
chown $app $service_config_file
chown $app /etc/matrix-$app/app-service/*
chmod 600 $service_config_file
chmod 600 /etc/matrix-$app/app-service/*

systemctl restart $app.service

if [ $? -eq 0 ]; then
    rm /tmp/app_service_backup.yaml
    exit 0
else
    echo "Failed to restart synapse with the new config file. Restore the old config file !!"
    cp /tmp/app_service_backup.yaml $service_config_file
fi
