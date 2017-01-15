#!/usr/bin/env bats

load setupvim

@test "test setup_git_url() all defaults" {
    curr_plugin="kuku/lala"
    expected="git://git@github.com:${curr_plugin}.git"
    run setup_git_url "${curr_plugin}"
    [[ "${output}" = "${expected}" ]]
    [[ "${status}" -eq 0 ]]
}


@test "test setup_git_url() schema override" {
    curr_plugin="kuku/lala"
    schema="https"
    expected="${schema}://github.com/${curr_plugin}/"
    run setup_git_url \
        "${curr_plugin}" \
        "${schema}"
    [[ "${output}" = "${expected}" ]]
    [[ "${status}" -eq 0 ]]
}

@test "test setup_git_url() full override" {
    curr_plugin="kuku/lala"
    schema="gopher"
    git_server="github.mycompany.local"
    username="lala"
    expected="${schema}://${username}@${git_server}/${curr_plugin}/"
    run setup_git_url \
        "${curr_plugin}" \
        "${schema}" \
        "${git_server}" \
        "${username}"
    [[ "${output}" = "${expected}" ]]
    [[ "${status}" -eq 0 ]]
}
