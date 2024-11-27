#!/bin/bash

set -eu

YNH_HELPERS_VERSION=2.1
app=__APP__
YNH_APP_BASEDIR=/etc/yunohost/apps/"$app"
YNH_APP_ACTION=''

source /usr/share/yunohost/helpers

db_name=$(ynh_app_setting_get --key=db_name)
db_user=$(ynh_app_setting_get --key=db_user)
db_pwd=$(ynh_app_setting_get --key=db_pwd)
server_name=$(ynh_app_setting_get --key=server_name)

if [ -z ${1:-} ]; then
    echo "Usage: set_admin_user.sh user_to_set_as_admin"
    exit 1
fi

ynh_psql_db_shell <<< "UPDATE users SET admin = 1 WHERE name = '@$1:$server_name'"

exit 0
