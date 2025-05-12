#!/bin/bash

set -eu

readonly app_name=synapse

source auto_update_config.sh

readonly debian_version_name_1=bullseye
readonly debian_version_name_2=bookworm

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

upgrade_app() {
    (
        set -eu
        local new_checksum
        local prev_checksum

        # Define output file name
        # arm build: ${result_prefix_name_deb_1}-bin1_armv7l.tar.gz
        # arm build checksum: ${result_prefix_name_deb_1}-bin1_armv7l-sha256.txt
        # requirement.txt: ${result_prefix_name_deb_1}-build1_requirement.txt
        readonly result_prefix_name_deb_1="matrix-synapse_${app_version}-$debian_version_name_1"
        readonly result_prefix_name_deb_2="matrix-synapse_${app_version}-$debian_version_name_2"

        # Build armv7 build
        build_cmd_deb_1 "$app_version" "$result_prefix_name_deb_1"
        build_cmd_deb_2 "$app_version" "$result_prefix_name_deb_2"
        push_armv7_build

        # Update python requirement
        cp "$build_result_path_deb_1/${result_prefix_name_deb_1}"-build1_requirement.txt ../conf/requirement_"$debian_version_name_1".txt
        cp "$build_result_path_deb_2/${result_prefix_name_deb_2}"-build1_requirement.txt ../conf/requirement_"$debian_version_name_2".txt

        # Update manifest
        sed -r -i 's|version = "[[:alnum:].]{4,8}~ynh[[:alnum:].]{1,2}"|version = "'"${app_version}"'~ynh1"|' ../manifest.toml

        # Update synapse link
        sed -r -i "s|armhf.url\s*=(.*)/releases/download/v[[:alnum:].]{4,10}/matrix-synapse_[[:alnum:].]{4,10}-$debian_version_name_1-bin[[:digit:]]_armv7l.tar.gz|armhf.url =\1/releases/download/v${app_version}/matrix-synapse_${app_version}-$debian_version_name_1-bin1_armv7l.tar.gz|"  ../manifest.toml
        sed -r -i "s|armhf.url\s*=(.*)/releases/download/v[[:alnum:].]{4,10}/matrix-synapse_[[:alnum:].]{4,10}-$debian_version_name_2-bin[[:digit:]]_armv7l\.tar\.gz|armhf.url =\1/releases/download/v${app_version}/matrix-synapse_${app_version}-$debian_version_name_2-bin1_armv7l.tar.gz|"  ../manifest.toml

        # Update synapse link checksum
        sha256sum_arm_archive_deb_1=$(cat "$build_result_path_deb_1/${result_prefix_name_deb_1}-bin1_armv7l-sha256.txt")
        sha256sum_arm_archive_deb_2=$(cat "$build_result_path_deb_2/${result_prefix_name_deb_2}-bin1_armv7l-sha256.txt")
        prev_sha256sum_arm_archive_deb_1=$(get_from_manifest ".resources.sources.${app_name}_prebuilt_armv7_$debian_version_name_1.armhf.sha256")
        prev_sha256sum_arm_archive_deb_2=$(get_from_manifest ".resources.sources.${app_name}_prebuilt_armv7_$debian_version_name_2.armhf.sha256")
        sed -r -i "s|$prev_sha256sum_arm_archive_deb_1|$sha256sum_arm_archive_deb_1|" ../manifest.toml
        sed -r -i "s|$prev_sha256sum_arm_archive_deb_2|$sha256sum_arm_archive_deb_2|" ../manifest.toml

        # Update lk-jwt
        wget -O archive.tar.gz "https://github.com/element-hq/lk-jwt-service/archive/refs/tags/v${lk_jwt_version}.tar.gz"
        new_checksum=$(sha256sum archive.tar.gz | cut -d' ' -f1)
        rm archive.tar.gz

        sed -r -i "s|url\s*=(.*)/element-hq/lk-jwt-service/archive/refs/tags/v[[:alnum:].]{4,10}\.tar\.gz|url =\1/element-hq/lk-jwt-service/archive/refs/tags/v${lk_jwt_version}.tar.gz|"  ../manifest.toml
        prev_checksum=$(get_from_manifest ".resources.sources.lk_jwt.sha256")
        sed -r -i "s|$prev_checksum|$new_checksum|" ../manifest.toml

        # Update livekit
        wget -O checksums.txt "https://github.com/livekit/livekit/releases/download/v${livekit_version}/checksums.txt"
        for arch in amd64 arm64 armhf; do
            sed -r -i "s|${arch}\.url\s*=(.*)/livekit/livekit/releases/download/v[[:alnum:].]{4,10}/livekit_[[:alnum:].]{4,10}_linux_${arch}.tar.gz|${arch}.url =\1/livekit/livekit/releases/download/v${livekit_version}/livekit_${livekit_version}_linux_${arch}.tar.gz|"  ../manifest.toml
            prev_checksum="$(get_from_manifest ".resources.sources.livekit.${arch}.sha256")"
            new_checksum="$(grep -F "livekit_${livekit_version}_linux_${arch}.tar.gz" checksums.txt | cut -d' ' -f1)"
            sed -r -i "s|$prev_checksum|$new_checksum|" ../manifest.toml
        done
        rm checksums.txt

        git commit -a -m "Upgrade $app_name to $app_version"
        git push gitea auto_update:auto_update
    ) 2>&1 | tee "${app_name}_build_temp.log"
    return ${PIPESTATUS[0]}
}

push_armv7_build() {
    ## Make a draft release json with a markdown body
    local release='"tag_name": "v'$app_version'", "target_commitish": "master", "name": "v'$app_version'", '
    local body="$app_name prebuilt bin for ${app_name}_ynh\\n=========\\nPlease refer to upstream project for the change : https://github.com/element-hq/synapse/releases\\n\\nSha256sum for $debian_version_name_1 : $(cat $build_result_path_deb_1/${result_prefix_name_deb_1}-bin1_armv7l-sha256.txt)\\nSha256sum for $debian_version_name_2 : $(cat $build_result_path_deb_2/${result_prefix_name_deb_2}-bin1_armv7l-sha256.txt)"
    release+='"body": "'$body'",'
    release+='"draft": true, "prerelease": false'
    release='{'$release'}'
    local url="https://api.github.com/repos/$owner/$repo/releases"
    local succ=$(curl -H "Authorization: token $perstok" --data "$release" $url)

    ## In case of success, we upload a file
    local upload_generic=$(echo "$succ" | grep upload_url)
    if [[ $? -eq 0 ]]; then
        echo "Release created."
    else
        echo "Error creating release!"
        return 1
    fi

    local upload_prefix
    local upload_file
    local upload_ok
    local download
    for archive_name in $build_result_path_deb_1/${result_prefix_name_deb_1}-bin1_armv7l.tar.gz \
                        $build_result_path_deb_2/${result_prefix_name_deb_2}-bin1_armv7l.tar.gz
    do

        # $upload_generic is like:
        # "upload_url": "https://uploads.github.com/repos/:owner/:repo/releases/:ID/assets{?name,label}",
        upload_prefix=$(echo $upload_generic | cut -d "\"" -f4 | cut -d "{" -f1)
        upload_file="$upload_prefix?name=${archive_name##*/}"

        echo "Start uploading file"
        i=0
        upload_ok=false
        while [ $i -le 4 ]; do
            i=$((i+1))
            # Download file
            set +e
            succ=$(curl -H "Authorization: token $perstok" \
                -H "Content-Type: $(file -b --mime-type $archive_name)" \
                -H "Accept: application/vnd.github.v3+json" \
                --data-binary @$archive_name $upload_file)
            res=$?
            set -e
            if [ $res -ne 0 ]; then
                echo "Curl upload failled"
                continue
            fi
            echo "Upload done, check result"

            set +eu
            download=$(echo "$succ" | egrep -o "browser_download_url.+?")
            res=$?
            if [ $res -ne 0 ] || [ -z "$download" ]; then
                set -eu
                echo "Result upload error"
                continue
            fi
            set -eu
            echo "$download" | cut -d: -f2,3 | cut -d\" -f2
            echo "Upload OK"
            upload_ok=true
            break
        done

        if ! $upload_ok; then
            echo "Upload completely failed, exit"
            return 1
        fi
    done
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
