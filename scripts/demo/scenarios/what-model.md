What model are you and who made you? One short paragraph.
# ^ The prompt above is what gets typed into Claude Code.
#
# Point of this demo: a fully local Qwen3/Gemma 4 will answer with its real identity
# (e.g. "I'm Qwen, made by Alibaba Cloud"), which proves the session is running on the
# V100 in the box and not calling out to Anthropic. That's the whole selling point.
#
# Short reply, so REPLY_WAIT can be low: REPLY_WAIT=45 ./record-claude-code.sh what-model
