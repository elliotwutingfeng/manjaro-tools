#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

connect(){
    ${alt_storage} && server="storage-in" || server="storage"
    local storage="@${server}.osdn.net:/storage/groups/m/ma/"
    echo "${account}${storage}${project}"
}

connect_webserver(){
    local webserver="@shell.osdn.net:/home/groups/m/ma/"
    echo "${account}${webserver}${project}"
}

make_torrent(){
    find ${src_dir} -type f -name "*.torrent" -delete

    if [[ -n $(find ${src_dir} -type f -name "*.iso") ]]; then
        for iso in $(ls ${src_dir}/*.iso); do
            local seed=https://${host}/dl/${project}/${iso##*/}
            local mktorrent_args=(-c "${torrent_meta}" -p -l ${piece_size} -a ${tracker_url} -w ${seed})
            ${verbose} && mktorrent_args+=(-v)
            msg2 "Creating (%s) ..." "${iso##*/}.torrent"
            mktorrent ${mktorrent_args[*]} -o ${iso}.torrent ${iso}
        done
    fi
}

prepare_transfer(){
    profile="$1"
    hidden="$2"
    edition=$(get_edition "${profile}")
    [[ -z ${project} ]] && project="$(get_project)"
    server=$(connect)

    target_dir="${profile}/${dist_release}"
    src_dir="${run_dir}/${edition}/${target_dir}"

    ${hidden} && target_dir="${profile}/.${dist_release}"
}

start_agent(){
    msg2 "Initializing SSH agent..."
    ssh-agent | sed 's/^echo/#echo/' > "$1"
    chmod 600 "$1"
    . "$1" > /dev/null
    ssh-add
}

ssh_add(){
    local ssh_env="$USER_HOME/.ssh/environment"

    if [ -f "${ssh_env}" ]; then
         . "${ssh_env}" > /dev/null
         ps -ef | grep ${SSH_AGENT_PID} | grep ssh-agent$ > /dev/null || {
            start_agent ${ssh_env};
        }
    else
        start_agent ${ssh_env};
    fi
}

sync_dir(){
    count=1
    max_count=10
    prepare_transfer "$1" "${hidden}"

    ${torrent} && make_torrent
    ${sign} && signiso "${src_dir}"
    ${ssh_agent} && ssh_add

    msg "Start upload [%s] to [%s] ..." "$1" "${project}"

    while [[ $count -le $max_count ]]; do
    rsync ${rsync_args[*]} --exclude '.latest*' ${src_dir}/ ${server}/${target_dir}/
        if [[ $? != 0 ]]; then
            count=$(($count + 1))
            msg "Upload failed. retrying (%s/%s) ..." "$count" "$max_count"
            sleep 2
        else
            count=$(($max_count + 1))
            [[ -f "${src_dir}/.latest" ]] && sync_latest_html
            [[ -f "${src_dir}/.latest.php" ]] && sync_latest_php
            msg "Done upload [%s]" "$1"
            show_elapsed_time "${FUNCNAME}" "${timer_start}"
        fi
    done

}

sync_latest_html(){
    msg2 "Uploading url redirector ..."
    local webserver=$(connect_webserver)
    local htdocs="htdocs/${profile}"
    local html="latest"
    scp "${src_dir}/.${html}" "${webserver}/${htdocs}/${html}"
    rm -f "${src_dir}/.${html}"
}

sync_latest_php(){
    msg2 "Uploading php redirector ..."
    local webserver=$(connect_webserver)
    local htdocs="htdocs/${profile}"
    local php="latest.php"
    scp "${src_dir}/.${php}" "${webserver}/${htdocs}/${php}"
    rm -f "${src_dir}/.${php}"
}
