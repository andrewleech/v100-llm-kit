What does this project do?
What are its two API endpoints?
Show me the add_todo handler from app.py
# ^ Three turns. The first two answer straight from the preloaded CLAUDE.md (fast chat, no
# tool call). The third triggers a quick file read. Run in a project that has a CLAUDE.md so
# the overview is already in context and the chat turns are snappy — the bundled
# scripts/demo/sample-project is exactly this (tiny Flask todo-api with a CLAUDE.md). Run it
# twice: the first interactive run primes the prompt cache so turn 1 of the second run is warm.
#
#   ANTHROPIC_BASE_URL=http://localhost:8011 ANTHROPIC_MODEL="Gemma-4-26B-A4B" \
#     CLAUDE_CONFIG_DIR=... ./record-claude-code.sh project-tour ../sample-project
