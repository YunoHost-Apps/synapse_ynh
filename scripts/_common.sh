readonly python_version="$(python3 -V | cut -d' ' -f2 | cut -d. -f1-2)"
readonly code_dir="/opt/yunohost/matrix-$app"
readonly domain_whitelist_client="$(yunohost --output-as json domain list  | jq -r '.domains | .[]')"

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
    # Note that we put patch into scripts dir because /source are not stored and can't be used on restore
    if ! grep -F -q '# LDAP Filter anonymous user Applied' $code_dir/lib/python$python_version/site-packages/ldap_auth_provider.py; then
        pushd $code_dir/lib/python$python_version/site-packages
        patch < $YNH_APP_BASEDIR/scripts/patch/ldap_auth_filter_anonymous_user.patch
        popd
    fi
}

configure_coturn() {
    # Get public IP and set as external IP for coturn
    # note : '|| true' is used to ignore the errors if we can't get the public ipv4 or ipv6
    local public_ip4="$(curl -s ip.yunohost.org)" || true
    local public_ip6="$(curl -s ipv6.yunohost.org)" || true

    local turn_external_ip=""
    if [ -n "$public_ip4" ] && ynh_validate_ip4 --ip_address="$public_ip4"
    then
        turn_external_ip+="$public_ip4,"
    fi
    if [ -n "$public_ip6" ] && ynh_validate_ip6 --ip_address="$public_ip6"
    then
        turn_external_ip+="$public_ip6"
    fi
    ynh_add_jinja_config --template="turnserver.conf" --destination="/etc/matrix-$app/coturn.conf"
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

ensure_vars_set() {
    if [ -z "${report_stats:-}" ]; then
        report_stats=false
        ynh_app_setting_set --app="$app" --key=report_stats --value="$report_stats"
    fi
    if [ -z "${e2e_enabled_by_default:-}" ] ; then
        e2e_enabled_by_default=invite
        ynh_app_setting_set --app="$app" --key=e2e_enabled_by_default --value="$e2e_enabled_by_default"
    fi

    if [ -z "${turnserver_pwd:-}" ]; then
        turnserver_pwd=$(ynh_string_random --length=30)
        ynh_app_setting_set --app="$app" --key=turnserver_pwd --value="$turnserver_pwd"
    fi

    if [ -z "${web_client_location:-}" ]
    then
        web_client_location="https://matrix.to/"

        element_instance=element
        if yunohost --output-as plain app list | grep -q "^$element_instance"'$'; then
            element_domain=$(ynh_app_setting_get --app $element_instance --key domain)
            element_path=$(ynh_app_setting_get --app $element_instance --key path)
            web_client_location="https://""$element_domain""$element_path"
        fi
        ynh_app_setting_set --app="$app" --key=web_client_location --value="$web_client_location"
    fi
    if [ -z "${client_base_url:-}" ]
    then
        client_base_url="$web_client_location"
        ynh_app_setting_set --app="$app" --key=client_base_url --value="$client_base_url"
    fi
    if [ -z "${invite_client_location:-}" ]
    then
        invite_client_location="$web_client_location"
        ynh_app_setting_set --app="$app" --key=invite_client_location --value="$invite_client_location"
    fi

    if [ -z "${allow_public_rooms_without_auth:-}" ]
    then
        allow_public_rooms_without_auth=${allow_public_rooms:-false}
        ynh_app_setting_set --app="$app" --key=allow_public_rooms_without_auth --value="$allow_public_rooms_without_auth"
    fi
    if [ -z "${allow_public_rooms_over_federation:-}" ]
    then
        allow_public_rooms_over_federation=${allow_public_rooms:-false}
        ynh_app_setting_set --app="$app" --key=allow_public_rooms_over_federation --value="$allow_public_rooms_over_federation"
    fi
    if [ -z "${max_upload_size:-}" ]
    then
        max_upload_size=100M
        ynh_app_setting_set --app="$app" --key=max_upload_size --value="$max_upload_size"
    fi
    if [ -z "${disable_msisdn_registration:-}" ]
    then
        disable_msisdn_registration=true
        ynh_app_setting_set --app="$app" --key=disable_msisdn_registration --value=$disable_msisdn_registration
    fi
    if [ -z "${account_threepid_delegates_msisdn:-}" ]
    then
        account_threepid_delegates_msisdn=''
        ynh_app_setting_set --app="$app" --key=account_threepid_delegates_msisdn --value="$account_threepid_delegates_msisdn"
    fi

    if [ -z "${registrations_require_3pid:-}" ]
    then
        registrations_require_3pid=email
        ynh_app_setting_set --app="$app" --key=registrations_require_3pid --value="$registrations_require_3pid"
    fi
    if [ -z "${allowed_local_3pids_email:-}" ]
    then
        allowed_local_3pids_email=''
        ynh_app_setting_set --app="$app" --key=allowed_local_3pids_email --value="$allowed_local_3pids_email"
    fi
    if [ -z "${allowed_local_3pids_msisdn:-}" ]
    then
        allowed_local_3pids_msisdn=''
        ynh_app_setting_set --app="$app" --key=allowed_local_3pids_msisdn --value="$allowed_local_3pids_msisdn"
    fi
    if [ -z "${account_threepid_delegates_msisdn:-}" ]
    then
        account_threepid_delegates_msisdn=""
        ynh_app_setting_set --app="$app" --key=account_threepid_delegates_msisdn --value="$account_threepid_delegates_msisdn"
    fi

    if [ -z "${allow_guest_access:-}" ]
    then
        allow_guest_access=false
        ynh_app_setting_set --app="$app" --key=allow_guest_access --value="$allow_guest_access"
    fi
    if [ -z "${default_identity_server:-}" ]
    then
        default_identity_server='https://matrix.org'
        ynh_app_setting_set --app=$app --key=default_identity_server --value="$default_identity_server"
    fi

    if [ -z "${auto_join_rooms:-}" ]
    then
        auto_join_rooms=''
        ynh_app_setting_set --app="$app" --key=auto_join_rooms --value="$auto_join_rooms"
    fi
    if [ -z "${autocreate_auto_join_rooms:-}" ]
    then
        autocreate_auto_join_rooms=false
        ynh_app_setting_set --app="$app" --key=autocreate_auto_join_rooms --value="$autocreate_auto_join_rooms"
    fi
    if [ -z "${auto_join_rooms_for_guests:-}" ]
    then
        auto_join_rooms_for_guests=true
        ynh_app_setting_set --app="$app" --key=auto_join_rooms_for_guests --value="$auto_join_rooms_for_guests"
    fi

    if [ -z "${enable_notifs:-}" ]
    then
        enable_notifs=true
        ynh_app_setting_set --app="$app" --key=enable_notifs --value="$enable_notifs"
    fi
    if [ -z "${notif_for_new_users:-}" ]
    then
        notif_for_new_users=true
        ynh_app_setting_set --app="$app" --key=notif_for_new_users --value="$notif_for_new_users"
    fi
    if [ -z "${enable_group_creation:-}" ]
    then
        enable_group_creation=true
        ynh_app_setting_set --app="$app" --key=enable_group_creation --value="$enable_group_creation"
    fi

    if [ -z "${enable_3pid_lookup:-}" ]
    then
        enable_3pid_lookup=false
        ynh_app_setting_set --app="$app" --key=enable_3pid_lookup --value="$enable_3pid_lookup"
    fi

    if [ -z "${push_include_content:-}" ]
    then
        push_include_content=true
        ynh_app_setting_set --app="$app" --key=push_include_content --value="$push_include_content"
    fi

    if [ -z "${enable_dtls_for_audio_video_turn_call:-}" ]
    then
        enable_dtls_for_audio_video_turn_call=true
        ynh_app_setting_set --app="$app" --key=enable_dtls_for_audio_video_turn_call --value="$enable_dtls_for_audio_video_turn_call"
    fi
}

set_permissions() {
    chown $app:$app -R "$code_dir"
    chmod o= -R "$code_dir"

    chmod 770 "$code_dir"/Coturn_config_rotate.sh
    chmod 700 "$code_dir"/update_synapse_for_appservice.sh
    chmod 700 "$code_dir"/set_admin_user.sh

    if [ "${1:-}" == data ]; then
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
    setfacl -R -m user:turnserver:rwX  /var/log/matrix-"$app"
}
