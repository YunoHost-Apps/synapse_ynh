#!/bin/bash
#
# synapse_clean_unreferenced_states cron weekly

YNH_HELPERS_VERSION=2.1
app=__APP__
YNH_APP_BASEDIR=/etc/yunohost/apps/"$app"
YNH_APP_ACTION=''

source /usr/share/yunohost/helpers

db_name=$(ynh_app_setting_get --key=db_name)
db_user=$(ynh_app_setting_get --key=db_user)
db_pwd=$(ynh_app_setting_get --key=db_pwd)
server_name=$(ynh_app_setting_get --key=server_name)
install_dir="/var/www/$app"

df -h
if $(systemctl stop $app); then
    mv /etc/systemd/system/$app.service /root
    systemctl daemon-reload
    # Ensure that nobody restarts synapse while this is running
    $install_dir/rust-synapse-find-unreferenced-state-groups -p "postgresql://$db_user:$db_pwd@localhost/$db_name" -o "$install_dir/unreferenced.csv"
    mv /root/$app.service /etc/systemd/system
    systemctl daemon-reload
    systemctl restart $app
    ynh_psql_db_shell <<< "SELECT pg_size_pretty( pg_database_size( '$db_name' ) );"
    ynh_psql_db_shell <<< "CREATE TEMPORARY TABLE unreffed(id BIGINT PRIMARY KEY);COPY unreffed FROM '$install_dir/unreferenced.csv' WITH (FORMAT 'csv');DELETE FROM state_groups_state WHERE state_group IN (SELECT id FROM unreffed);DELETE FROM state_group_edges WHERE state_group IN (SELECT id FROM unreffed);DELETE FROM state_groups WHERE id IN (SELECT id FROM unreffed);"
    echo "Synapse unreferenced states deleted from psql"
    if $(systemctl stop $app); then
        ynh_psql_db_shell <<< "SELECT pg_size_pretty( pg_database_size( '$db_name' ) );"
        ynh_psql_db_shell <<< "REINDEX DATABASE $db_name;"
        echo "$app psql REINDEXed"
        systemctl restart $app
    else
    echo "Could not stop $app for psql REINDEX"
    fi
    ynh_psql_db_shell <<< "SELECT pg_size_pretty( pg_database_size( '$db_name' ) );"
    ynh_psql_db_shell <<< "VACUUM FULL;"
    ynh_psql_db_shell <<< "SELECT pg_size_pretty( pg_database_size( '$db_name' ) );"
    echo "$app psql VACUUMed"
else
    echo "Could not stop $app for cleaning unreferenced-state-groups"
fi
systemctl restart $app
df -h

exit 0
