# Auto-tag every Claude Code session with the directory you launched it from,
# so concurrent sessions are told apart by project instead of by random UUID.
#
# Install:
#     echo "source $(pwd)/tag-sessions.sh" >> ~/.zshrc
#     exec zsh
#
# Then `./usage-report --sessions` shows project names, and you can drill in with
#     ./usage-report -m --session my-project
#
# Claude Code has no built-in workspace attribute, so this is the only way to
# know which session was which. Set OTEL_RESOURCE_ATTRIBUTES yourself before
# launching to override the automatic tag.

claude() {
  local auto="project=${PWD##*/},dir=${PWD}"
  OTEL_RESOURCE_ATTRIBUTES="${OTEL_RESOURCE_ATTRIBUTES:+${OTEL_RESOURCE_ATTRIBUTES},}${auto}" \
    command claude "$@"
}
