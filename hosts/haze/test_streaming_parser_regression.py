#!/usr/bin/env python3
"""
test_streaming_parser_regression.py
=============================================================================
Nemotron Streaming Tool-Call Parser Regression Test Suite
Authority: S-6 Signal & Telemetry Watchstander
Context: Incident cc-wisp-6a4av / cc-wisp-9aq16 (Worker cc-ysbv Turn 18 Failure)

Tests:
1. Exact failing Turn 18 payload from session ses_f10288044ffeOflU1kJ4c8CAzG
   (worker cc-ysbv on gcs-6fu, cmd/gc/clock_inject_test.go edit)
2. Nested curly braces '{ ... }' inside multiline Go test code
3. Escaped double-quotes and escape sequences (\"GC_INJECT_CLOCK\", \n, \t)
4. Granular token-by-token and multi-character incremental streaming chunks
5. Live vLLM / NIM endpoint streaming verification on colt-gpu-01 (http://10.82.0.3:8000)
=============================================================================
"""

import json
import os
import sys
import unittest
import urllib.request
import urllib.error

# Ensure hosts/haze is importable
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from llama_nemotron_toolcall_parser_streaming import (
    LlamaNemotronJSONToolParser,
    ChatCompletionRequest,
)

# Exact Turn 18 model generation payload from worker cc-ysbv (gcs-6fu)
TURN18_FAILING_PAYLOAD = r'''<TOOLCALL>[{"name": "edit", "arguments": {"filePath": "/home/camp-colt-mayor-agent/colony/rigs/gascity/worktrees/gcs-6fu/cmd/gc/clock_inject_test.go", "oldString": "func TestClockInjectPrefixClaude(t *testing.T) {\n\tt.Setenv(\"GC_INJECT_CLOCK\", \"\")\n\tvar buf bytes.Buffer\n\tif line := clockInjectLine(); line != \"\" {\n\t\t_ = writeProviderHookContextForEvent(&buf, \"\", \"UserPromptSubmit\", line)\n\t}\n\tif !strings.Contains(buf.String(), \"Current time: \") {\n\t\tt.Errorf(\"clock inject prefix (claude) should emit a clock line, got %q\", buf.String())\n\t}\n}", "newString": "func TestClockInjectPrefixClaude(t *testing.T) {\n\tt.Setenv(\"GC_INJECT_CLOCK\", \"\")\n\tvar buf bytes.Buffer\n\tif line := clockInjectLine(); line != \"\" {\n\t\t_ = writeProviderHookContextForEvent(&buf, \"\", \"UserPromptSubmit\", line)\n\t// New verification: injected line is suffix\n\tif line != \"\" {\n\t\tif !strings.HasSuffix(buf.String(), line+\"\\n\") {\n\t\t\tt.Errorf(\"clock line not at end of buffer, got %q\", buf.String())\n\t\t}\n\t}\n\tif !strings.Contains(buf.String(), \"Current time: \") {\n\t\tt.Errorf(\"clock inject prefix (claude) should emit a clock line, got %q\", buf.String())\n\t}\n}"}}]</TOOLCALL>'''


class TestNemotronStreamingParserRegression(unittest.TestCase):
    """Regression test cases verifying string-aware balanced-brace tool call parsing."""

    def setUp(self):
        self.parser = LlamaNemotronJSONToolParser()
        self.request = ChatCompletionRequest()

    def test_turn18_non_streaming_extraction(self):
        """Verify non-streaming extraction parses Turn 18 payload into valid ToolCall."""
        extracted = self.parser.extract_tool_calls(TURN18_FAILING_PAYLOAD, self.request)
        self.assertTrue(extracted.tools_called, "tools_called must be True")
        self.assertEqual(len(extracted.tool_calls), 1)

        tc = extracted.tool_calls[0]
        self.assertEqual(tc.function.name, "edit")

        # Arguments must be valid, complete JSON without syntax error
        args = json.loads(tc.function.arguments)
        self.assertEqual(
            args["filePath"],
            "/home/camp-colt-mayor-agent/colony/rigs/gascity/worktrees/gcs-6fu/cmd/gc/clock_inject_test.go"
        )
        self.assertIn("func TestClockInjectPrefixClaude", args["oldString"])
        self.assertIn("strings.HasSuffix", args["newString"])
        self.assertIn('"GC_INJECT_CLOCK"', args["oldString"])

    def test_turn18_incremental_streaming_simulation(self):
        """Verify incremental streaming simulation with varying chunk sizes."""
        # Test varying chunk sizes (1 char, 4 chars, 16 chars) to stress boundary detection
        for chunk_size in (1, 4, 13, 37):
            with self.subTest(chunk_size=chunk_size):
                stream_parser = LlamaNemotronJSONToolParser()
                accumulated_text = ""
                streamed_name = ""
                streamed_args = ""

                for i in range(0, len(TURN18_FAILING_PAYLOAD), chunk_size):
                    chunk = TURN18_FAILING_PAYLOAD[i:i + chunk_size]
                    prev_text = accumulated_text
                    accumulated_text += chunk

                    delta = stream_parser.extract_tool_calls_streaming(
                        previous_text=prev_text,
                        current_text=accumulated_text,
                        delta_text=chunk,
                        previous_token_ids=[],
                        current_token_ids=[],
                        delta_token_ids=[],
                        request=self.request,
                    )
                    if delta and delta.tool_calls:
                        for tc in delta.tool_calls:
                            fn = tc.function
                            if isinstance(fn, dict):
                                if "name" in fn and fn["name"]:
                                    streamed_name += fn["name"]
                                if "arguments" in fn and fn["arguments"]:
                                    streamed_args += fn["arguments"]

                self.assertEqual(streamed_name, "edit")
                self.assertTrue(len(streamed_args) > 0)

                # Parsed JSON must be intact and match original
                parsed_args = json.loads(streamed_args)
                self.assertIn("filePath", parsed_args)
                self.assertIn("oldString", parsed_args)
                self.assertIn("newString", parsed_args)
                self.assertIn("TestClockInjectPrefixClaude", parsed_args["oldString"])
                self.assertIn("strings.HasSuffix", parsed_args["newString"])

    def test_nested_curly_braces_in_code_string(self):
        """Verify deeply nested braces inside string arguments are not treated as object boundaries."""
        deep_nested_payload = r'''<TOOLCALL>[{"name": "write", "arguments": {"path": "main.go", "code": "package main\n\nfunc A() {\n\tif true {\n\t\tfor i := 0; i < 10; i++ {\n\t\t\tswitch i {\n\t\t\tcase 1:\n\t\t\t\tprintln(\"1\")\n\t\t\tdefault:\n\t\t\t\tprintln(\"def\")\n\t\t\t}\n\t\t}\n\t}\n}"}}]</TOOLCALL>'''
        
        extracted = self.parser.extract_tool_calls(deep_nested_payload, self.request)
        self.assertTrue(extracted.tools_called)
        args = json.loads(extracted.tool_calls[0].function.arguments)
        self.assertEqual(args["path"], "main.go")
        self.assertIn("switch i {", args["code"])
        self.assertIn("case 1:", args["code"])

    def test_live_backend_endpoint(self):
        """Optional probe against live inference endpoint on colt-gpu-01 (10.82.0.3:8000)."""
        endpoint = "http://10.82.0.3:8000/v1/chat/completions"
        payload = {
            "model": "nvidia/llama-3.3-nemotron-super-49b-v1.5",
            "messages": [
                {
                    "role": "user",
                    "content": "Invoke tool edit with parameters filePath: \"probe_test.go\", oldString: \"func Probe() { return 100 }\", newString: \"func Probe() { return 200 }\"."
                }
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "edit",
                        "description": "Edit file",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "filePath": {"type": "string"},
                                "oldString": {"type": "string"},
                                "newString": {"type": "string"}
                            },
                            "required": ["filePath", "oldString", "newString"]
                        }
                    }
                }
            ],
            "stream": True,
            "temperature": 0.1,
            "max_tokens": 1024
        }

        try:
            req = urllib.request.Request(
                endpoint,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                self.assertEqual(resp.status, 200)
                streamed_name = ""
                streamed_args = ""
                for line in resp:
                    line = line.decode("utf-8").strip()
                    if not line or line.startswith(":") or line == "data: [DONE]":
                        continue
                    if line.startswith("data: "):
                        data = json.loads(line[6:])
                        choices = data.get("choices", [])
                        if choices:
                            delta = choices[0].get("delta", {})
                            for tc in delta.get("tool_calls", []):
                                fn = tc.get("function", {})
                                if fn.get("name"):
                                    streamed_name += fn["name"]
                                if fn.get("arguments"):
                                    streamed_args += fn["arguments"]

                if streamed_name:
                    self.assertEqual(streamed_name, "edit")
                    parsed = json.loads(streamed_args)
                    self.assertEqual(parsed.get("filePath"), "probe_test.go")
                    self.assertIn("Probe()", parsed.get("oldString", ""))
                    self.assertIn("Probe()", parsed.get("newString", ""))
        except (urllib.error.URLError, TimeoutError) as e:
            self.skipTest(f"Live endpoint unreachable: {e}")


if __name__ == "__main__":
    unittest.main()
