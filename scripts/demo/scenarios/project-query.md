List the files in this project and tell me in two sentences what it does.
# ^ The prompt above is what gets typed into Claude Code.
#
# Point of this demo: shows the local model actually doing agentic work — running the ls
# tool, reading the result, and summarising — not just chatting. Run it inside a small
# sample repo so the answer is quick and the file list fits on screen.
#
# Longer reply (tool call + summary), so give it room:
#   REPLY_WAIT=120 ./record-claude-code.sh project-query /path/to/sample-repo
