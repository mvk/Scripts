#!/usr/bin/env bash


target_user="${target_user:-"david"}"
target_app="${target_app:-"gnome-shell"}"
namespace="${1:-"org.freedesktop"}"
component="${2:-"NetworkManager"}"
app_pid="${3:-"$(pgrep -u "${target_user}" "${target_app}" | head -1 || true)"}"

while read -r action; do
    echo "in action: ${action}"
    pkaction --action-id "${action}" --verbose
    if [[ -n "${app_pid}" ]]; then
        echo "checking the policy for ${target_user} in app: ${target_app}"
        pkcheck --action-id "${action}" --process "${app_pid}"
        rc=$?
        echo "return code: ${rc}"
    fi
done < <(pkaction | grep "${namespace}.${component}" || true)
