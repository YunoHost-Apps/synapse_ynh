#!/bin/bash

set -eu

readonly app_name=synapse

readonly deb1_py_version=3.11.2
readonly deb2_py_version=3.13.5
readonly deb1_name=bookworm
readonly deb2_name=trixie

source auto_update_config.sh

get_from_manifest() {
    result=$(python3 <<EOL
import toml
import json
with open("../manifest.toml", "r") as f:
    file_content = f.read()
loaded_toml = toml.loads(file_content)
json_str = json.dumps(loaded_toml)
print(json_str)
EOL
    )
    echo "$result" | jq -r "$1"
}

check_app_version() {
    local app_remote_version
    app_remote_version=$(curl 'https://api.github.com/repos/element-hq/synapse/releases/latest' -H 'Host: api.github.com' --compressed | jq -r ".tag_name" | cut -dv -f2)
    lk_jwt_version=$(curl 'https://api.github.com/repos/element-hq/lk-jwt-service/releases/latest' -H 'Host: api.github.com' --compressed | jq -r ".tag_name" | cut -dv -f2)
    livekit_version=$(curl 'https://api.github.com/repos/livekit/livekit/releases/latest' -H 'Host: api.github.com' --compressed | jq -r ".tag_name" | cut -dv -f2)

    ## Check if new build is needed
    if [[ "$app_version" != "$app_remote_version" ]]
    then
        app_version="$app_remote_version"
        return 0
    else
        return 1
    fi
}

build_requirement() {
    local deb_py_version="$1"
    local deb_name="$2"

    venv_dir="$(mktemp -d)"
    ~/.pyenv/versions/"${deb_py_version}"/bin/python -m venv "$venv_dir"
    "$venv_dir/bin/pip3" install --upgrade pip pip-tools
    cat << EOF > "$venv_dir/requirements.in"
matrix-synapse==$app_version
matrix-synapse-ldap3
matrix-synapse[postgres]==$app_version
lxml
EOF
    "$venv_dir/bin/pip-compile" "$venv_dir/requirements.in" --output-file "../conf/requirement_${deb_name}.txt"
}

upgrade_app() {
    (
        set -eu
        local new_checksum
        local prev_checksum

        # Update manifest
        sed -r -i 's|version = "[[:alnum:].]{4,8}~ynh[[:alnum:].]{1,2}"|version = "'"${app_version}"'~ynh1"|' ../manifest.toml

        # Update requirements.txt
        build_requirement $deb1_py_version ${deb1_name}
        build_requirement $deb2_py_version ${deb2_name}

        # Update lk-jwt
        sed -r -i "s|url\s*=(.*)/element-hq/lk-jwt-service/releases/download/v[[:alnum:].]{4,10}/lk-jwt-service_linux_|url =\1/element-hq/lk-jwt-service/releases/download/v${lk_jwt_version}/lk-jwt-service_linux_|"  ../manifest.toml
        for arch in amd64 arm64; do
            wget -O lk-jwt-service "https://github.com/element-hq/lk-jwt-service/releases/download/v${lk_jwt_version}/lk-jwt-service_linux_${arch}"
            new_checksum=$(sha256sum lk-jwt-service | cut -d' ' -f1)
            prev_checksum=$(get_from_manifest ".resources.sources.lk_jwt.${arch}.sha256")
            sed -r -i "s|$prev_checksum|$new_checksum|" ../manifest.toml
        done
        rm lk-jwt-service

        # Update livekit
        wget -O checksums.txt "https://github.com/livekit/livekit/releases/download/v${livekit_version}/checksums.txt"
        sed -r -i "s|\.url\s*=(.*)/livekit/livekit/releases/download/v[[:alnum:].]{4,10}/livekit_[[:alnum:].]{4,10}_linux_|.url =\1/livekit/livekit/releases/download/v${livekit_version}/livekit_${livekit_version}_linux_|"  ../manifest.toml
        for arch in amd64 arm64; do
            prev_checksum="$(get_from_manifest ".resources.sources.livekit.${arch}.sha256")"
            new_checksum="$(grep -F "livekit_${livekit_version}_linux_${arch}.tar.gz" checksums.txt | cut -d' ' -f1)"
            sed -r -i "s|$prev_checksum|$new_checksum|" ../manifest.toml
        done
        rm checksums.txt

        git commit -a -m "Upgrade $app_name to $app_version"
        git push origin auto_update:auto_update
    ) 2>&1 | tee "${app_name}_build_temp.log"
    return ${PIPESTATUS[0]}
}

app_version=$(get_from_manifest ".version" |  cut -d'~' -f1)

if check_app_version
then
    set +eu
    upgrade_app
    res=$?
    set -eu
    if [ $res -eq 0 ]; then
        result="Success"
    else
        result="Failed"
    fi
    msg="Build: $app_name version $app_version"

    echo "$msg" | mail.mailutils --content-type="text/plain; charset=UTF-8" -A "${app_name}_build_temp.log" -s "Autoupgrade $app_name : $result" "$notify_email"
fi
