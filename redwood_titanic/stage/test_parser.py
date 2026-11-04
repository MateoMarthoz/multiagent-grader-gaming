"""Regression test for olmo3_lenient_parser.py. Runs on silver (needs vLLM):
    cd /root/stage-ckpt && .venv/bin/python test_parser.py [failed_calls.json]
The optional JSON file holds raw replies from real runs that failed to parse."""
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("p", "plugins/olmo3_lenient_parser.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
from transformers import AutoTokenizer  # noqa: E402
from vllm.entrypoints.openai.chat_completion.protocol import ChatCompletionRequest  # noqa: E402

tok = AutoTokenizer.from_pretrained("allenai/Olmo-3-7B-Instruct")


def tool(name, params):
    return {"type": "function", "function": {"name": name, "description": "x", "parameters": {
        "type": "object", "properties": {k: {"type": "string"} for k in params}, "required": params}}}


req = ChatCompletionRequest(model="m", messages=[{"role": "user", "content": "hi"}],
                            tools=[tool("bash", ["command"]), tool("post_message", ["message"]), tool("read_board", [])])
parser = p.Olmo3LenientToolParser(tok, req.tools)
EXPECT = [  # (reply, expected [(name, args)] or None for no tool call)
    ('<function_calls>bash(command="ls -la /workdir")</function_calls>', [("bash", {"command": "ls -la /workdir"})]),
    ('<function_calls>bash(cmd="ls")</function_calls>', [("bash", {"command": "ls"})]),
    ('Let me look.<function_calls>bash("ls /workdir")</function_calls>', [("bash", {"command": "ls /workdir"})]),
    ('<function_calls>bash -c "ls /opt"</function_calls>', [("bash", {"command": 'bash -c "ls /opt"'})]),
    ('<function_calls>bash ls -la /opt</function_calls>', [("bash", {"command": "ls -la /opt"})]),
    ('<function_calls>post_message("hi all")\nread_board()</function_calls>',
     [("post_message", {"message": "hi all"}), ("read_board", {})]),
    ('<function_calls>bash(command="python3 - <<EOF\nimport pandas\nprint(1)\nEOF")</function_calls>',
     [("bash", {"command": "python3 - <<EOF\nimport pandas\nprint(1)\nEOF"})]),
    # stop sequence </function_calls> removes the closing tag
    ('<function_calls>bash(command="cat eval.log")', [("bash", {"command": "cat eval.log"})]),
    ("<function_calls>bash(command=\"python3 <<'EOF'\nprint('a')\nEOF\n')</function_calls>",
     [("bash", {"command": "python3 <<'EOF'\nprint('a')\nEOF\n"})]),
    ("<function_calls>bash('python3 <<EOF\nx = s.str.extract(r',\\s*(\\w+)\\.')\nEOF')",
     [("bash", {"command": "python3 <<EOF\nx = s.str.extract(r',\\s*(\\w+)\\.')\nEOF"})]),
    ("<function_calls>post_message(message=unquoted text)</function_calls>", None),
    ("<function_calls></function_calls>", None),
    ("I am done.", None),
]
bad = 0
for reply, want in EXPECT:
    r = parser.extract_tool_calls(reply, req)
    got = [(c.function.name, json.loads(c.function.arguments)) for c in r.tool_calls] if r.tools_called else None
    ok = got == want
    bad += not ok
    print("ok  " if ok else "FAIL", repr(reply[:60]), "->", got if ok else f"{got} != {want}")
for raw in (json.load(open(sys.argv[1])) if len(sys.argv) > 1 else []):
    cut = raw.split("</function_calls>")[0]  # as with the stop sequence
    r = parser.extract_tool_calls(cut, req)
    print("real", r.tools_called, [(c.function.name, c.function.arguments[:80] + " ... " + c.function.arguments[-60:])
                                   for c in r.tool_calls])
print("failures:", bad)
