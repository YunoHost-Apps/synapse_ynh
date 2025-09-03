readonly python_version="$(python3 -V | cut -d' ' -f2 | cut -d. -f1-2)"
readonly domains_list="$(yunohost --output-as json domain list  | jq -r '.domains | .[]')"
#
# TODO Ideally we must have a dedicated domain for this but for now it's not supported
# so we just use the main app domain
# Since Yunohost support multiple domain for the same app we should move it to sfu.$domain
#
readonly sfu_domain="$domain"

install_sources() {
    # Install/upgrade synapse in virtualenv

    # Clean venv is it was on python2.7 or python3 with old version in case major upgrade of debian
    if [ ! -e "$install_dir/venv"/bin/python3 ] || [ ! -e "$install_dir/venv/lib/python$python_version" ]; then
        ynh_safe_rm "$install_dir/venv"/bin
        ynh_safe_rm "$install_dir/venv"/lib
        ynh_safe_rm "$install_dir/venv"/lib64
        ynh_safe_rm "$install_dir/venv"/include
        ynh_safe_rm "$install_dir/venv"/share
        ynh_safe_rm "$install_dir/venv"/pyvenv.cfg
    fi

    mkdir -p "$install_dir/venv"
    chown "$app":root -R "$install_dir/venv"

    if [ -n "$(uname -m | grep arm)" ]
    then
        # Clean old file, sometimes it could make some big issues if we don't do this!!
        ynh_safe_rm "$install_dir/venv"/bin
        ynh_safe_rm "$install_dir/venv"/lib
        ynh_safe_rm "$install_dir/venv"/include
        ynh_safe_rm "$install_dir/venv"/share

        ynh_setup_source --dest_dir="$install_dir/venv"/ --source_id="synapse_prebuilt_armv7_$(lsb_release --codename --short)"

        # Fix multi-instance support
        for f in "$install_dir/venv"/bin/*; do
            ynh_replace_regex --match='#!/opt/yunohost/matrix-synapse' --replace='#!'"$install_dir/venv" --file="$f"
        done
    else

        # Install virtualenv if it don't exist
        test -e "$install_dir/venv"/bin/python3 || python3 -m venv "$install_dir/venv"

        # Install synapse in virtualenv
        local pip3="$install_dir/venv"/bin/pip3

        $pip3 install --upgrade setuptools wheel pip cffi
        $pip3 install --upgrade -r "$YNH_APP_BASEDIR/conf/requirement_$(lsb_release --codename --short).txt"
    fi

    # Apply patch for LDAP auth if needed
    # Note that we put patch into scripts dir because /source are not stored and can't be used on restore
    if ! grep -F -q '# LDAP Filter anonymous user Applied' "$install_dir/venv/lib/python$python_version/site-packages/ldap_auth_provider.py"; then
        pushd "$install_dir/venv/lib/python$python_version/site-packages"
        patch < "$YNH_APP_BASEDIR"/scripts/patch/ldap_auth_filter_anonymous_user.patch
        popd
    fi

    # Install livekit jwt
    ynh_setup_source --source_id=lk_jwt --dest_dir="$install_dir/lk_jwt"

    chown "$app" -R "$install_dir"

    pushd "$install_dir/lk_jwt"
    ynh_hide_warnings ynh_exec_as_app go build -o lk-jwt-service .
    popd

    # Install livekit server for element-call
    ynh_setup_source --source_id=livekit --dest_dir="$install_dir/livekit"
}

get_lk_node_ip() {
    local public_ip4
    public_ip4="$(curl -s https://ip.yunohost.org)" || true

    lk_node_ip=""
    if [ -n "$public_ip4" ] && ynh_validate_ip --family=4 --ip_address="$public_ip4"
    then
        lk_node_ip="--node-ip $public_ip4"
    fi
}

configure_coturn() {
    # Get public IP and set as external IP for coturn
    # note : '|| true' is used to ignore the errors if we can't get the public ipv4 or ipv6
    local public_ip4
    local public_ip6
    public_ip4="$(curl -s https://ip.yunohost.org)" || true
    public_ip6="$(curl -s https://ipv6.yunohost.org)" || true

    local turn_external_ip=""
    if [ -n "$public_ip4" ] && ynh_validate_ip --family=4 --ip_address="$public_ip4"
    then
        turn_external_ip+="$public_ip4,"
    fi
    if [ -n "$public_ip6" ] && ynh_validate_ip --family=6 --ip_address="$public_ip6"
    then
        turn_external_ip+="$public_ip6"
    fi
    ynh_config_add --jinja --template="turnserver.conf" --destination="/etc/matrix-$app/coturn.conf"
}

configure_nginx() {
    local e2e_enabled_by_default_client_config
    if [ "$e2e_enabled_by_default" == "off" ]; then
        e2e_enabled_by_default_client_config=false
    else
        e2e_enabled_by_default_client_config=true
    fi

    # Create .well-known redirection for access by federation
    if yunohost --output-as plain domain list | grep -q "^$server_name$" && [ "$server_name" != "$domain" ]
    then
        ynh_config_add --template="server_name.conf" --destination="/etc/nginx/conf.d/${server_name}.d/${app}_server_name.conf"
    fi
    if [ -z "$contact_admin_email" ] && [ -z "$contact_admin_matrix_id" ]; then
        ynh_print_warn "It seem that you didn't set a admin contact. Please set a admin contact (email or/and matrix ID) from the config panel in 'Main settings' > 'Contact for the administrator of the synapse instance'"
    fi

    ynh_config_add --jinja --template='nginx.conf.inc' --destination="/etc/nginx/conf.d/${domain}.d/${app}.conf.inc"

    # Create a dedicated NGINX config
    ynh_config_add_nginx
}

configure_php() {
    ynh_config_add_phpfpm
    ynh_replace --match="chdir = $install_dir" \
                --replace="chdir = $install_dir/cas" \
                --file="/etc/php/$php_version/fpm/pool.d/$app.conf"
    ynh_store_file_checksum "/etc/php/$php_version/fpm/pool.d/$app.conf"
    ynh_systemctl --service="php$php_version-fpm" --action=reload
}

ensure_vars_set() {
    ynh_app_setting_set_default --key=report_stats --value=false
    ynh_app_setting_set_default --key=e2e_enabled_by_default --value=invite
    ynh_app_setting_set_default --key=turnserver_pwd --value="$(ynh_string_random --length=30)"
    ynh_app_setting_set_default --key=turnserver_cli_pwd --value="$(ynh_string_random --length=30)"

    if [ -z "${web_client_location:-}" ]
    then
        web_client_location="https://matrix.to/"

        element_instance=element
        if yunohost --output-as plain app list | grep -q "^$element_instance"'$'; then
            element_domain=$(ynh_app_setting_get --app=$element_instance --key=domain)
            element_path=$(ynh_app_setting_get --app=$element_instance --key=path)
            web_client_location="https://""$element_domain""$element_path"
        fi
        ynh_app_setting_set --key=web_client_location --value="$web_client_location"
    fi

    ynh_app_setting_set_default --key=jitsi_server --value=jitsi.riot.im

    ynh_app_setting_set_default --key=client_base_url --value="$web_client_location"
    ynh_app_setting_set_default --key=invite_client_location --value="$web_client_location"

    ynh_app_setting_set_default --key=allow_public_rooms_without_auth --value="${allow_public_rooms:-false}"
    ynh_app_setting_set_default --key=allow_public_rooms_over_federation --value="${allow_public_rooms:-false}"
    ynh_app_setting_set_default --key=max_upload_size --value=100M
    ynh_app_setting_set_default --key=disable_msisdn_registration --value=true
    ynh_app_setting_set_default --key=account_threepid_delegates_msisdn --value=''
    ynh_app_setting_set_default --key=registrations_require_3pid --value=email
    ynh_app_setting_set_default --key=allowed_local_3pids_email --value=''
    ynh_app_setting_set_default --key=allowed_local_3pids_msisdn --value=''
    ynh_app_setting_set_default --key=account_threepid_delegates_msisdn --value=''
    ynh_app_setting_set_default --key=allow_guest_access --value=false
    ynh_app_setting_set_default --key=default_identity_server --value='https://matrix.org'
    ynh_app_setting_set_default --key=auto_join_rooms --value=''
    ynh_app_setting_set_default --key=autocreate_auto_join_rooms --value=false
    ynh_app_setting_set_default --key=auto_join_rooms_for_guests --value=true
    ynh_app_setting_set_default --key=enable_notifs --value=true
    ynh_app_setting_set_default --key=notif_for_new_users --value=true
    ynh_app_setting_set_default --key=enable_group_creation --value=true
    ynh_app_setting_set_default --key=enable_3pid_lookup --value=false
    ynh_app_setting_set_default --key=push_include_content --value=true
    ynh_app_setting_set_default --key=enable_dtls_for_audio_video_turn_call --value=true
    ynh_app_setting_set_default --key=allow_to_send_request_to_localhost --value=false

    ynh_app_setting_set_default --key=livekit_secret --value="$(ynh_string_random --length=40)"

    ynh_app_setting_set_default --key=contact_admin_email --value=''
    ynh_app_setting_set_default --key=contact_admin_matrix_id --value=''
    ynh_app_setting_set_default --key=contact_support_page --value=''
}

set_permissions() {
    chown -R "$app:$app" "$install_dir"
    chmod -R u+rwX,g+rX-w,o= "$install_dir"

    chmod 750 "$install_dir"/Coturn_config_rotate.sh
    chmod 700 "$install_dir"/update_synapse_for_appservice.sh
    chmod 700 "$install_dir"/set_admin_user.sh

    chmod 640 "$install_dir"/cas/cas_server.php
    chown "$app":www-data "$install_dir" "$install_dir"/cas "$install_dir"/cas/cas_server.php

    if [ "${1:-}" == data ]; then
        chmod 750 "$data_dir"
        find "$data_dir" \(   \! -perm -o= \
                         -o \! -user "$app" \
                         -o \! -group "$app" \) \
                    -exec chown "$app:$app" {} \; \
                    -exec chmod o= {} \;
    fi

    chown "$app:$app" -R /etc/matrix-"$app"
    chmod u=rwX,g=rX,o= -R /etc/matrix-"$app"
    setfacl -R -m user:turnserver:rX  /etc/matrix-"$app"

    chmod 600 /etc/matrix-"$app"/"$server_name".signing.key

    chown "$app":root -R /var/log/matrix-"$app"
    chmod u=rwX,g=rX,o= -R /var/log/matrix-"$app"
    setfacl -R -m user:turnserver:rwX  /var/log/matrix-"$app"
}
