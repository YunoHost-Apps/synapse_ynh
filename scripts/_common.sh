python_version="$(python3 -V | cut -d' ' -f2 | cut -d. -f1-2)"
code_dir="/opt/yunohost/matrix-$app"
db_name_slidingproxy=${db_name}_slidingproxy
install_sources() {
    # Install/upgrade synapse in virtualenv

    # Clean venv is it was on python2.7 or python3 with old version in case major upgrade of debian
    if [ ! -e $code_dir/bin/python3 ] || [ ! -e $code_dir/lib/python$python_version ]; then
        ynh_secure_remove --file=$code_dir/bin
        ynh_secure_remove --file=$code_dir/lib
        ynh_secure_remove --file=$code_dir/lib64
        ynh_secure_remove --file=$code_dir/include
        ynh_secure_remove --file=$code_dir/share
        ynh_secure_remove --file=$code_dir/pyvenv.cfg
    fi

    mkdir -p $code_dir
    chown $app:root -R $code_dir

    if [ -n "$(uname -m | grep arm)" ]
    then
        # Clean old file, sometimes it could make some big issues if we don't do this!!
        ynh_secure_remove --file=$code_dir/bin
        ynh_secure_remove --file=$code_dir/lib
        ynh_secure_remove --file=$code_dir/include
        ynh_secure_remove --file=$code_dir/share

        ynh_setup_source --dest_dir=$code_dir/ --source_id="synapse_prebuilt_armv7_$(lsb_release --codename --short)"

        # Fix multi-instance support
        for f in $(ls $code_dir/bin); do
            if ! [[ $f =~ "__" ]]; then
                ynh_replace_special_string --match_string='#!/opt/yunohost/matrix-synapse' --replace_string='#!'$code_dir --target_file=$code_dir/bin/$f
            fi
        done
    else

        # Install virtualenv if it don't exist
        test -e $code_dir/bin/python3 || python3 -m venv $code_dir

        # Install synapse in virtualenv
        local pip3=$code_dir/bin/pip3

        $pip3 install --upgrade setuptools wheel pip cffi
        $pip3 install --upgrade -r $YNH_APP_BASEDIR/conf/requirement_$(lsb_release --codename --short).txt
    fi

    # Apply patch for LDAP auth if needed
    if ! grep -F -q '# LDAP Filter anonymous user Applied' $code_dir/lib/python$python_version/site-packages/ldap_auth_provider.py; then
        pushd $code_dir/lib/python$python_version/site-packages
        patch < $YNH_APP_BASEDIR/sources/ldap_auth_filter_anonymous_user.patch
        popd
    fi

    # Setup chroot for sliding proxy
    # Note that on debian bullseye we can't support run directly sliding proxy as it require new version of libc not available on debian bullseye
    mkdir -p  $code_dir/sliding-chroot
    ynh_setup_source -r --dest_dir=$code_dir/sliding-chroot/ --source_id=sliding_proxy_rootfs
    mkdir -p  $code_dir/sliding-chroot/bin
    ynh_setup_source --dest_dir=$code_dir/sliding-chroot/bin/ --source_id=sliding_proxy
}

configure_synapse() {
    local domain_whitelist_client=$(yunohost --output-as plain domain list \
        | grep -E "^#" -v \
        | sort | uniq \
        | sed -r 's|^(.*)$|      - \1|' \
        | sed -z 's|\n|\\n|g')
    local macaroon_secret_key_param='macaroon_secret_key: "'$macaroon_secret_key'"'
    local auto_join_rooms_sed_param=""
    if [ -n "$auto_join_rooms" ]; then
        auto_join_rooms_sed_param+='auto_join_rooms:'
        while read -d, room; do
            auto_join_rooms_sed_param+='\n  - "'$room'"'
        done <<< "${auto_join_rooms},"
    fi
    local registration_require_3pid_sed_param=""
    case ${registrations_require_3pid} in
        'email')
            registration_require_3pid_sed_param="registrations_require_3pid:\n  - email"
            ;;
        'msisdn')
            registration_require_3pid_sed_param="registrations_require_3pid:\n  - msisdn"
            ;;
        'email&msisdn')
            registration_require_3pid_sed_param="registrations_require_3pid:\n  - email\n  - msisdn"
            ;;
    esac

    local allowd_local_3pids_sed_param=""
    if [ -n "$allowed_local_3pids_email" ] || [ -n "$allowed_local_3pids_msisdn" ]; then
        allowd_local_3pids_sed_param="allowed_local_3pids:"

        if [ -n "$allowed_local_3pids_email" ]; then
            while read -d, pattern ; do
                allowd_local_3pids_sed_param+="\n  - medium: email\n    pattern: '$pattern'"
            done <<< "${allowed_local_3pids_email},"
        fi
        if [ -n "$allowed_local_3pids_msisdn" ]; then
            while read -d, pattern ; do
                allowd_local_3pids_sed_param+="\n  - medium: msisdn\n    pattern: '$pattern'"
            done <<< "${allowed_local_3pids_msisdn},"
        fi
    fi
    local turn_server_config=""
    if $enable_dtls_for_audio_video_turn_call; then
        turn_server_config='turn_uris: [ "stuns:'$domain:$port_turnserver_tls'?transport=dtls", "stuns:'$domain:$port_turnserver_tls'?transport=tls", "turns:'$domain:$port_turnserver_tls'?transport=dtls", "turns:'$domain:$port_turnserver_tls'?transport=tls" ]'
    else
        turn_server_config='turn_uris: [ "turn:'$domain:$port_turnserver_tls'?transport=udp", "turn:'$domain:$port_turnserver_tls'?transport=tcp" ]'
    fi

    ynh_add_config --template="homeserver.yaml" --destination="/etc/matrix-$app/homeserver.yaml"
    sed -i "s|_DOMAIN_WHITELIST_CLIENT_|$domain_whitelist_client|g" /etc/matrix-$app/homeserver.yaml
    sed -i "s|_AUTO_JOIN_ROOMS_SED_PARAM_|$auto_join_rooms_sed_param|g" /etc/matrix-$app/homeserver.yaml
    sed -i "s|_REGISTRATION_REQUIRE_3PID_SED_PARAM_|$registration_require_3pid_sed_param|g" /etc/matrix-$app/homeserver.yaml
    sed -i "s|_ALLOWD_LOCAL_3PIDS_SED_PARAM_|$allowd_local_3pids_sed_param|g" /etc/matrix-$app/homeserver.yaml
    ynh_store_file_checksum --file=/etc/matrix-$app/homeserver.yaml

    ynh_add_config --template="log.yaml" --destination="/etc/matrix-$app/log.yaml"
}

configure_coturn() {
    # Get public IP and set as external IP for coturn
    # note : '|| true' is used to ignore the errors if we can't get the public ipv4 or ipv6
    local public_ip4="$(curl -s ip.yunohost.org)" || true
    local public_ip6="$(curl -s ipv6.yunohost.org)" || true

    local turn_external_ip=""
    if [ -n "$public_ip4" ] && ynh_validate_ip4 --ip_address="$public_ip4"
    then
        turn_external_ip+="external-ip=$public_ip4\\n"
    fi

    if [ -n "$public_ip6" ] && ynh_validate_ip6 --ip_address="$public_ip6"
    then
        turn_external_ip+="external-ip=$public_ip6\\n"
    fi

    ynh_add_config --template="turnserver.conf" --destination="/etc/matrix-$app/coturn.conf"
    sed -i "s|_TURN_EXTERNAL_IP_|$turn_external_ip|g" /etc/matrix-$app/coturn.conf
    ynh_store_file_checksum --file=/etc/matrix-$app/coturn.conf
}

configure_nginx() {
    local e2e_enabled_by_default_client_config

    # Create .well-known redirection for access by federation
    if yunohost --output-as plain domain list | grep -q "^$server_name$"
    then
        local e2e_enabled_by_default_client_config
        if [ $e2e_enabled_by_default == "off" ]; then
            e2e_enabled_by_default_client_config=false
        else
            e2e_enabled_by_default_client_config=true
        fi
        ynh_add_config --template="server_name.conf" --destination="/etc/nginx/conf.d/${server_name}.d/${app}_server_name.conf"
    fi

    # Create a dedicated NGINX config
    ynh_add_nginx_config
}

set_permissions() {
    chown $app:$app -R $code_dir
    chmod o= -R $code_dir

    chmod 770 $code_dir/Coturn_config_rotate.sh
    chmod 700 $code_dir/update_synapse_for_appservice.sh
    chmod 700 $code_dir/set_admin_user.sh
    chmod 755 $code_dir/sliding-chroot/bin/sliding-proxy

    if [ "${1:-}" == data ]; then
        find $data_dir \(   \! -perm -o= \
                         -o \! -user $app \
                         -o \! -group $app \) \
                    -exec chown $app:$app {} \; \
                    -exec chmod o= {} \;
    fi

    chown $app:$app -R /etc/matrix-$app
    chmod u=rwX,g=rX,o= -R /etc/matrix-$app
    setfacl -R -m user:turnserver:rX  /etc/matrix-$app

    chmod 600 /etc/matrix-$app/$server_name.signing.key

    chown $app:root -R /var/log/matrix-$app
    setfacl -R -m user:turnserver:rwX  /var/log/matrix-$app
}
