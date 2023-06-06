dependances="coturn build-essential python3-dev libffi-dev python3-pip python3-setuptools sqlite3 libssl-dev python3-venv libxml2-dev libxslt1-dev python3-lxml zlib1g-dev libjpeg-dev libpq-dev postgresql acl"
python_version="$(python3 -V | cut -d' ' -f2 | cut -d. -f1-2)"
#REMOVEME? app=$YNH_APP_INSTANCE_NAME

install_sources() {
    # Install/upgrade synapse in virtualenv

    # Clean venv is it was on python2.7 or python3 with old version in case major upgrade of debian
    if [ ! -e $install_dir/bin/python3 ] || [ ! -e $install_dir/lib/python$python_version ]; then
#REMOVEME?         ynh_secure_remove --file=$install_dir/bin
#REMOVEME?         ynh_secure_remove --file=$install_dir/lib
#REMOVEME?         ynh_secure_remove --file=$install_dir/lib64
#REMOVEME?         ynh_secure_remove --file=$install_dir/include
#REMOVEME?         ynh_secure_remove --file=$install_dir/share
#REMOVEME?         ynh_secure_remove --file=$install_dir/pyvenv.cfg
    fi

    mkdir -p $install_dir
    chown $synapse_user:root -R $install_dir

    if [ -n "$(uname -m | grep arm)" ]
    then
        # Clean old file, sometimes it could make some big issues if we don't do this!!
#REMOVEME?         ynh_secure_remove --file=$install_dir/bin
#REMOVEME?         ynh_secure_remove --file=$install_dir/lib
#REMOVEME?         ynh_secure_remove --file=$install_dir/include
#REMOVEME?         ynh_secure_remove --file=$install_dir/share

        ynh_setup_source --dest_dir=$install_dir/ --source_id="armv7_$(lsb_release --codename --short)"

        # Fix multi-instance support
        for f in $(ls $install_dir/bin); do
            if ! [[ $f =~ "__" ]]; then
                ynh_replace_special_string --match_string='#!/opt/yunohost/matrix-synapse' --replace_string='#!'$install_dir --target_file=$install_dir/bin/$f
            fi
        done
    else

        # Install virtualenv if it don't exist
#REMOVEME?         test -e $install_dir/bin/python3 || python3 -m venv $install_dir

        # Install synapse in virtualenv

        # We set all necessary environement variable to create a python virtualenvironnement.
        u_arg='u'
        set +$u_arg;
        source $install_dir/bin/activate
        set -$u_arg;
        if [ $(lsb_release --codename --short) == "bullseye" ]; then
            # Fix issue with setuptools https://github.com/pypa/setuptools/issues/3118
            pip3 install --upgrade setuptools==60.8.2 wheel pip
        else
            pip3 install --upgrade setuptools wheel pip
        fi

        pip3 install --upgrade cffi ndg-httpsclient psycopg2 lxml jinja2
        pip3 install --upgrade -r $YNH_APP_BASEDIR/conf/requirement_$(lsb_release --codename --short).txt

        # This function was defined when we called "source $install_dir/bin/activate". With this function we undo what "$install_dir/bin/activate" does
        set +$u_arg;
        deactivate
        set -$u_arg;
    fi
}

get_domain_list() {
    yunohost --output-as plain domain list | grep -E "^#" -v | sort | uniq | while read domain; do
        echo -n "      - https://$domain\n"
    done
}
