# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: LicenseRef-NvidiaProprietary
import ast
import contextlib
import json
import re
from collections.abc import Sequence
from typing import Any, Optional

try:
    import vllm
    from vllm.logger import init_logger
    from vllm.utils import random_uuid
except ImportError:
    import logging
    vllm = None
    def init_logger(name):
        return logging.getLogger(name)
    import uuid
    def random_uuid():
        return str(uuid.uuid4())

def _parse_vllm_version(version: str) -> tuple[int, int, int]:
    """Parse vLLM version string into (major, minor, patch) for comparisons."""
    parts: list[int] = []
    for segment in version.split(".")[:3]:
        digits = ""
        for char in segment:
            if char.isdigit():
                digits += char
            else:
                break
        parts.append(int(digits) if digits else 0)
    while len(parts) < 3:
        parts.append(0)
    return parts[0], parts[1], parts[2]

if vllm is not None:
    _VLLM_VERSION = _parse_vllm_version(vllm.__version__)
else:
    _VLLM_VERSION = (0, 27, 0)

# Tool parsers moved to vllm.tool_parsers in v0.13.0.
try:
    if _VLLM_VERSION >= (0, 13, 0):
        from vllm.tool_parsers import ToolParser, ToolParserManager
    else:
        from vllm.entrypoints.openai.tool_parsers.abstract_tool_parser import (
            ToolParser,
            ToolParserManager,
        )
except ImportError:
    class ToolParser:
        def __init__(self, tokenizer=None, tools=None):
            self.tokenizer = tokenizer
            self.tools = tools
    class ToolParserManager:
        @classmethod
        def register_module(cls, name):
            def decorator(c):
                return c
            return decorator

try:
    if _VLLM_VERSION >= (0, 15, 0):
        from vllm.entrypoints.openai.chat_completion.protocol import ChatCompletionRequest
        from vllm.entrypoints.openai.engine.protocol import (
            DeltaFunctionCall,
            DeltaMessage,
            DeltaToolCall,
            ExtractedToolCallInformation,
            FunctionCall,
            ToolCall,
        )
    else:
        from vllm.entrypoints.openai.protocol import (
            ChatCompletionRequest,
            DeltaFunctionCall,
            DeltaMessage,
            DeltaToolCall,
            ExtractedToolCallInformation,
            FunctionCall,
            ToolCall,
        )
except ImportError:
    class ChatCompletionRequest:
        def __init__(self, tools=None, **kwargs):
            self.tools = tools
    class FunctionCall:
        def __init__(self, name="", arguments=""):
            self.name = name
            self.arguments = arguments
    class ToolCall:
        def __init__(self, id="", type="function", function=None):
            self.id = id
            self.type = type
            self.function = function
    class ExtractedToolCallInformation:
        def __init__(self, tools_called=False, tool_calls=None, content=None):
            self.tools_called = tools_called
            self.tool_calls = tool_calls or []
            self.content = content
    class DeltaFunctionCall:
        def __init__(self, name=None, arguments=None):
            self.name = name
            self.arguments = arguments
        def model_dump(self, exclude_none=True):
            d = {}
            if self.name is not None:
                d["name"] = self.name
            if self.arguments is not None:
                d["arguments"] = self.arguments
            return d
    class DeltaToolCall:
        def __init__(self, index=0, type=None, id=None, function=None):
            self.index = index
            self.type = type
            self.id = id
            self.function = function
    class DeltaMessage:
        def __init__(self, content=None, tool_calls=None):
            self.content = content
            self.tool_calls = tool_calls or []

try:
    from vllm.entrypoints.chat_utils import make_tool_call_id
except ImportError:
    def make_tool_call_id() -> str:
        return f"call_{random_uuid()[:8]}"

logger = init_logger(__name__)

_TOOL_PARSER_ACCEPTS_TOOLS = _VLLM_VERSION >= (0, 19, 0)


def partial_tag_overlap(text: str, tag: str) -> int:
    """Return length of longest suffix of text that matches a prefix of tag."""
    max_overlap = min(len(text), len(tag) - 1)
    for k in range(max_overlap, 0, -1):
        if text.endswith(tag[:k]):
            return k
    return 0


def is_complete_json(text: str) -> bool:
    """Test whether a string is valid, complete JSON."""
    try:
        json.loads(text)
        return True
    except Exception:
        return False


@ToolParserManager.register_module("llama_nemotron_json")
class LlamaNemotronJSONToolParser(ToolParser):
    """Streaming and non-streaming tool-call parser for Nemotron Llama 3.3 models.

    Parses outputs formatted with <TOOLCALL>[{"name": "...", "arguments": {...}}]</TOOLCALL>.
    Supports full incremental streaming via DeltaMessage and DeltaToolCall objects.
    """
    def __init__(self, tokenizer=None, tools=None):
        if _TOOL_PARSER_ACCEPTS_TOOLS:
            super().__init__(tokenizer, tools)
        else:
            super().__init__(tokenizer)

        self.tool_call_start_token: str = "<TOOLCALL>"
        self.tool_call_end_token: str = "</TOOLCALL>"
        self.tool_call_regex = re.compile(r"<TOOLCALL>(.*?)</TOOLCALL>", re.DOTALL)

        # Streaming state tracking
        self._sent_content_idx: int = 0
        self.prev_tool_call_arr: list[dict] = []
        self.streamed_args_for_tool: list[str] = []

    def extract_tool_calls(
        self,
        model_output: str,
        request: ChatCompletionRequest,
    ) -> ExtractedToolCallInformation:
        """Non-streaming extraction of tool calls."""
        if self.tool_call_start_token not in model_output:
            return ExtractedToolCallInformation(
                tools_called=False,
                tool_calls=[],
                content=model_output,
            )

        try:
            tool_call_matches = self.tool_call_regex.findall(model_output)
            if not tool_call_matches:
                # Handle unclosed <TOOLCALL> tag gracefully
                start_idx = model_output.find(self.tool_call_start_token)
                str_tool_calls = model_output[start_idx + len(self.tool_call_start_token):].strip()
            else:
                str_tool_calls = tool_call_matches[0].strip()

            if not str_tool_calls.startswith("["):
                str_tool_calls = "[" + str_tool_calls
            if not str_tool_calls.endswith("]"):
                str_tool_calls = str_tool_calls + "]"

            json_tool_calls = json.loads(str_tool_calls)
            tool_calls = []
            for tool_call in json_tool_calls:
                if not isinstance(tool_call, dict) or "name" not in tool_call:
                    continue
                try:
                    args = tool_call.get("arguments", {})
                    args_str = json.dumps(args, ensure_ascii=False) if isinstance(args, dict) else str(args)
                    tool_calls.append(
                        ToolCall(
                            id=make_tool_call_id(),
                            type="function",
                            function=FunctionCall(
                                name=tool_call["name"],
                                arguments=args_str,
                            ),
                        )
                    )
                except Exception:
                    continue

            content = model_output[: model_output.find(self.tool_call_start_token)].strip()

            return ExtractedToolCallInformation(
                tools_called=len(tool_calls) > 0,
                tool_calls=tool_calls,
                content=content if content else None,
            )

        except Exception:
            logger.exception("Error in extracting tool call from response. Response: %s", model_output)
            return ExtractedToolCallInformation(
                tools_called=False,
                tool_calls=[],
                content=model_output,
            )

    def _extract_content(self, current_text: str) -> Optional[str]:
        """Return unsent non-tool-call text, holding back any partial <TOOLCALL> prefix."""
        if self.tool_call_start_token not in current_text:
            overlap_length = partial_tag_overlap(current_text, self.tool_call_start_token)
            sendable_idx = len(current_text) - overlap_length
        else:
            sendable_idx = current_text.index(self.tool_call_start_token)

        if sendable_idx > self._sent_content_idx:
            content = current_text[self._sent_content_idx:sendable_idx]
            self._sent_content_idx = sendable_idx
            return content
        return None

    def _extract_tool_call_blocks(self, text: str) -> list[tuple[str, bool]]:
        """Extract (tool_json_str, is_complete) for all tool calls inside <TOOLCALL>...</TOOLCALL> using a string-aware state machine."""
        results: list[tuple[str, bool]] = []
        start = text.find(self.tool_call_start_token)
        if start == -1:
            return results

        raw_inside = text[start + len(self.tool_call_start_token):]
        end = raw_inside.find(self.tool_call_end_token)
        is_all_complete = (end != -1)

        if is_all_complete:
            body = raw_inside[:end].strip()
        else:
            overlap = partial_tag_overlap(raw_inside, self.tool_call_end_token)
            body = raw_inside[:-overlap].strip() if overlap else raw_inside.strip()

        if not body:
            return results

        s = body.lstrip()
        if s.startswith('['):
            s = s[1:].lstrip()

        i = 0
        n = len(s)

        while i < n:
            while i < n and s[i] not in ('{',):
                i += 1
            if i >= n:
                break

            start_idx = i
            brace_depth = 0
            in_string = False
            escape = False
            is_complete = False

            while i < n:
                c = s[i]
                if escape:
                    escape = False
                elif c == '\\' and in_string:
                    escape = True
                elif c == '"':
                    in_string = not in_string
                elif not in_string:
                    if c == '{':
                        brace_depth += 1
                    elif c == '}':
                        brace_depth -= 1
                        if brace_depth == 0:
                            is_complete = True
                            i += 1
                            break
                i += 1

            obj_str = s[start_idx:i].strip()
            results.append((obj_str, is_complete))

            while i < n and s[i] in (',', ' ', '\t', '\n', '\r'):
                i += 1

        return results

    @staticmethod
    def _extract_tool_name(tc_json: str) -> Optional[str]:
        """Extract tool name from JSON snippet."""
        match = re.search(r'"name"\s*:\s*"([^"]+)"', tc_json)
        return match.group(1) if match else None

    @staticmethod
    def _extract_tool_args(tc_json: str, is_complete: bool) -> Optional[str]:
        """Extract tool arguments string from tool call JSON using string-aware brace matching."""
        idx = tc_json.find('"arguments"')
        if idx == -1:
            return None
        colon_idx = tc_json.find(':', idx + len('"arguments"'))
        if colon_idx == -1:
            return None

        s = tc_json[colon_idx + 1:].lstrip()
        if not s:
            return ""

        if not s.startswith('{'):
            return s

        brace_depth = 0
        in_string = False
        escape = False
        i = 0
        n = len(s)

        while i < n:
            c = s[i]
            if escape:
                escape = False
            elif c == '\\' and in_string:
                escape = True
            elif c == '"':
                in_string = not in_string
            elif not in_string:
                if c == '{':
                    brace_depth += 1
                elif c == '}':
                    brace_depth -= 1
                    if brace_depth == 0:
                        i += 1
                        break
            i += 1

        return s[:i]

    def _compute_args_diff(self, index: int, tc_json: str, is_complete: bool) -> Optional[str]:
        """Return new argument text not yet sent for tool at index, or None."""
        args = self._extract_tool_args(tc_json, is_complete)
        if args is None:
            return None
        already_sent = len(self.streamed_args_for_tool[index])
        if len(args) <= already_sent:
            return None
        diff = args[already_sent:]
        self.streamed_args_for_tool[index] = args
        self.prev_tool_call_arr[index]["arguments"] = args
        return diff

    def extract_tool_calls_streaming(
        self,
        previous_text: str,
        current_text: str,
        delta_text: str,
        previous_token_ids: Sequence[int],
        current_token_ids: Sequence[int],
        delta_token_ids: Sequence[int],
        request: ChatCompletionRequest,
    ) -> Optional[DeltaMessage]:
        """Incrementally stream tool call deltas from accumulated output."""
        try:
            content = self._extract_content(current_text)
            tool_call_blocks = self._extract_tool_call_blocks(current_text)
            tool_call_deltas: list[DeltaToolCall] = []

            for i, (tc_json, is_complete) in enumerate(tool_call_blocks):
                if i >= len(self.prev_tool_call_arr):
                    self.prev_tool_call_arr.append({})
                    self.streamed_args_for_tool.append("")

                # Stream tool name first
                if "name" not in self.prev_tool_call_arr[i]:
                    name = self._extract_tool_name(tc_json)
                    if not name:
                        break
                    self.prev_tool_call_arr[i]["name"] = name
                    tool_call_deltas.append(
                        DeltaToolCall(
                            index=i,
                            type="function",
                            id=make_tool_call_id(),
                            function=DeltaFunctionCall(name=name).model_dump(exclude_none=True),
                        )
                    )

                # Stream argument chunks
                args_diff = self._compute_args_diff(i, tc_json, is_complete)
                if args_diff:
                    tool_call_deltas.append(
                        DeltaToolCall(
                            index=i,
                            function=DeltaFunctionCall(arguments=args_diff).model_dump(exclude_none=True),
                        )
                    )

            if content or tool_call_deltas:
                return DeltaMessage(
                    content=content,
                    tool_calls=tool_call_deltas,
                )

            return None

        except Exception:
            logger.exception("Error trying to handle streaming tool call in Nemotron JSON parser.")
            return None


@ToolParserManager.register_module("llama_nemotron_xml")
class LlamaNemotronXMLToolParser(LlamaNemotronJSONToolParser):
    """Compatibility alias."""
    pass


@ToolParserManager.register_module("llama_nemotron_pythonic")
class LlamaNemotronPythonicToolParser(LlamaNemotronJSONToolParser):
    """Compatibility alias."""
    pass
