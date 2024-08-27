# Evaluates the input in another shell and detects changes in the environment. Returns a record of modified variables that may be passed on to `load-env`.
#
# Note that using the default --save-env-command, (only) the default 'from_string' environment conversions (PATH, Path) will be applied. Furthermore, some special variables (PWD, NU_VERSION, NU_LOG_*) will be discarded.
#
# Works out of the box with bash, zsh, fish and others. For PowerShell use `eval-sh pwsh`. For Nushell use `eval-sh nu`.
def eval-sh [
    --shell (-s): string = /bin/sh # Shell to evaluate the input with
    --execute-script: closure # Execute a given script in a given shell
    --cmd-to-script: closure # Convert a given command into a (part of) a shell script
    --preprocess-input: closure # Preprocess the given input
    --save-env-cmd: closure # Command that saves the environment to a given file as NUON
]: string -> record {
    # Unfortunately, we cannot use closures as default arguments. https://github.com/nushell/nushell/issues/13684
    let save_env_cmd = $save_env_cmd
        | default { |out: string| [$env.SHELL --no-config-file --commands $'$env | to nuon | save --force ($out)'] } # Using nu as an environment probe is not ideal (see above). However, anything (more) reliable (available anywhere, proper escaping) will have to be shipped by Nushell.
    let preprocess_input = $preprocess_input
        | default { |input: string| if ($input | str ends-with "\n") { $input } else { $input + "\n" }}
    let cmd_to_script = $cmd_to_script
        | default { |cmd: list<string>| ($cmd | each { |c| $"'($c)'" } | str join ' ') + "\n" }
    let execute_script = $execute_script
        | default { |shell: string, script: string| ^$shell -c ($script + (do $cmd_to_script ['true'])) } # The ultimate command might be treated differently which affects the value of variables such as SHLVL and XPC_SERVICE_NAME. That's why we append a noop. https://unix.stackexchange.com/a/305146

    let tmp_before = (mktemp --tmpdir)
    let tmp_after = (mktemp --tmpdir)
    do --capture-errors $execute_script $shell (
          (do $cmd_to_script (do $save_env_cmd $tmp_before))
        + (do $preprocess_input $in)
        + (do $cmd_to_script (do $save_env_cmd $tmp_after))
    )
    let before = open $tmp_before | from nuon
    let after = open $tmp_after | from nuon
    rm $tmp_before $tmp_after
    $after
        | transpose name value
        | reduce --fold {} { |it, acc| if ($it.name in $before and ($before | get $it.name) == $it.value) { $acc } else { $acc | insert $it.name $it.value } }
}

alias "eval-sh pwsh" = eval-sh --shell pwsh --cmd-to-script { |cmd| '& ' + ($cmd | each { |c| $"'($c)'" } | str join ' ') + "\n" }

# Note that Nushell exports only a few types of variables (string, int, ..)
alias "eval-sh nu" = eval-sh --shell nu --cmd-to-script { |cmd| '^' + ($cmd | each { |c| $"'($c)'" } | str join ' ') + "\n" }
