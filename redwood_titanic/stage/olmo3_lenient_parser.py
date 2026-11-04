"""Lenient Olmo 3 tool-call parser for vLLM (--tool-parser-plugin), registered as "olmo3_lenient".

Deployed on silver as /root/stage-ckpt/plugins/olmo3_lenient_parser.py. Used for every checkpoint
in the training-stage comparison, so the scaffold is identical across stages.

Order, for a reply containing <function_calls> (closing tag optional):
  1. Parse the block as Python calls to the request's tools with `ast` (one call per statement).
     Unlike vLLM's olmo3 parser, this keeps real newlines inside string arguments (that parser
     joins lines with ", ", which mangles multi-line commands such as heredocs). Positional
     arguments and a single misnamed keyword (bash("ls"), bash(command="ls")) are mapped onto the
     tool's parameters in schema order.
  2. vLLM's olmo3 parser unchanged (it also accepts JSON-style null/true/false).
  3. One call to a one-parameter tool with broken quoting (mismatched or unescaped quotes): the
     argument is the text between the first and last quote, as written (see _loose).
  4. A shell command written in place of a call, e.g. <function_calls>bash -c "ls"</function_calls>
     or <function_calls>ls -la</function_calls>, run as bash(cmd=<the text>) when there is a bash
     tool. A leading bare "bash " (not "bash -c") is dropped.
Text before <function_calls> is kept as the message content. Steps that change what the model
wrote (remapped arguments, step 3) are logged on the server as LENIENT_TOOL_PARSE with the raw text.
"""

import ast
import json
import re

from vllm.entrypoints.generate.base.protocol import ExtractedToolCallInformation
from vllm.logger import init_logger
from vllm.tool_parsers import ToolParserManager
from vllm.tool_parsers import utils as U
from vllm.tool_parsers.olmo3_tool_parser import Olmo3PythonicToolParser

logger = init_logger("vllm.tool_parsers.olmo3_lenient")  # under "vllm" so INFO lines reach the server log
BLOCK = re.compile(r"<function_calls>(.*?)(?:</function_calls>|$)", re.DOTALL)
FENCE = re.compile(r"^```[a-zA-Z]*\n?|\n?```$")


def _schemas(request) -> dict[str, list[str]]:
    out = {}
    for t in request.tools or []:
        f = getattr(t, "function", None)
        if f is None:
            continue
        params = f.parameters if isinstance(f.parameters, dict) else {}
        out[f.name] = list((params.get("properties") or {}).keys())
    return out


def _tool_call(name: str, args: dict):
    return U.ToolCall(type="function",
                      function=U.FunctionCall(name=name, arguments=json.dumps(args, ensure_ascii=False)))


def _remap(name: str, args: dict, schemas: dict) -> tuple[dict, bool]:
    """Rename a single misnamed argument of a one-parameter tool (bash(command=...) -> cmd)."""
    params = schemas.get(name, [])
    if len(params) == 1 and len(args) == 1 and params[0] not in args:
        return {params[0]: next(iter(args.values()))}, True
    return args, False


def _pythonic(inner: str, schemas: dict) -> tuple[list | None, bool]:
    """Returns (calls or None, whether anything was remapped)."""
    try:
        # raw newlines inside string arguments (multi-line scripts) are escaped first
        module = ast.parse(U.escape_ctrl_chars_in_strings(inner))
    except SyntaxError:
        return None, False
    calls, lenient = [], False
    for stmt in module.body:
        call = getattr(stmt, "value", None)
        if not (isinstance(stmt, ast.Expr) and isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                and call.func.id in schemas):
            return None, False
        params = schemas[call.func.id]
        args = {}
        try:
            if len(call.args) > len(params):
                return None, False
            for p, node in zip(params, call.args):
                args[p] = ast.literal_eval(node)
                lenient = True
            for kw in call.keywords:
                if kw.arg is None:  # **kwargs
                    return None, False
                args[kw.arg] = ast.literal_eval(kw.value)
        except (ValueError, SyntaxError):
            return None, False
        args, remapped = _remap(call.func.id, args, schemas)
        if any(k not in params for k in args):
            return None, False
        lenient |= remapped
        calls.append(_tool_call(call.func.id, args))
    return (calls or None), lenient


LOOSE = re.compile(r"^(\w+)\(\s*(?:(\w+)\s*=\s*)?(['\"]{1,3})(.*)(['\"]{1,3})\s*\)\s*$", re.DOTALL)


def _loose(inner: str, schemas: dict) -> list | None:
    """A single call to a one-parameter tool whose string argument has broken quoting, e.g.
    bash(command="python3 <<'EOF' ... EOF')  (mismatched quotes) or bash('... r',\\s*' ...')
    (unescaped inner quotes): the argument is everything between the first quote after the
    opening parenthesis and the last quote before the closing one, taken as written. If it has
    no real newlines but has \\n escapes, the common escapes are decoded."""
    m = LOOSE.match(inner.strip())
    if not m or m.group(1) not in schemas or len(schemas[m.group(1)]) != 1:
        return None
    arg = m.group(4)
    if "\n" not in arg and "\\n" in arg:
        for a, b in (("\\n", "\n"), ("\\t", "\t"), ('\\"', '"'), ("\\'", "'"), ("\\\\", "\\")):
            arg = arg.replace(a, b)
    return [_tool_call(m.group(1), {schemas[m.group(1)][0]: arg})] if arg.strip() else None


def _shell(inner: str, schemas: dict) -> list | None:
    if "bash" not in schemas or not schemas["bash"]:
        return None
    cmd = FENCE.sub("", inner.strip()).strip()
    if not cmd:
        return None
    head = re.match(r"(\w+)\(", cmd)
    if head and head.group(1) in schemas:  # a broken call to a known tool, not a shell command
        return None
    cmd = re.sub(r"^bash\s+(?!-)", "", cmd)
    return [_tool_call("bash", {schemas["bash"][0]: cmd})]


@ToolParserManager.register_module("olmo3_lenient")
class Olmo3LenientToolParser(Olmo3PythonicToolParser):
    def extract_tool_calls(self, model_output, request):
        m = BLOCK.search(model_output) if request.tools else None
        if m is None:
            return super().extract_tool_calls(model_output, request)
        inner = m.group(1).strip()
        before = model_output[:m.start()].strip() or None
        schemas = _schemas(request)
        calls, lenient = _pythonic(inner, schemas)
        if calls is None:
            res = super().extract_tool_calls(model_output, request)
            if res.tools_called:
                calls = []
                for c in res.tool_calls:
                    args, remapped = _remap(c.function.name, json.loads(c.function.arguments), schemas)
                    lenient |= remapped
                    calls.append(_tool_call(c.function.name, args))
            else:
                calls, lenient = _loose(inner, schemas) or _shell(inner, schemas), True
                if not calls:
                    return res
        if lenient:
            logger.info("LENIENT_TOOL_PARSE raw=%r -> %s", model_output[-1500:],
                        [(c.function.name, c.function.arguments[:300]) for c in calls])
        return ExtractedToolCallInformation(tools_called=True, tool_calls=calls, content=before)
