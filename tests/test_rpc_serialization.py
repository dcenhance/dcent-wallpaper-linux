"""The QML client parses every helper response with JavaScript's JSON.parse.

JavaScript rejects bare ``NaN``/``Infinity`` tokens and non-object payloads, and
an exception while building a response used to kill the websocket answer loop,
which made the KCM hang until the RPC timeout. These tests pin the contract:
every response is strict JSON and every request is answered.
"""
from __future__ import annotations

import asyncio
import importlib.util
import json
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).parents[1] / "plasma-plugin" / "contents" / "pyext.py"
spec = importlib.util.spec_from_file_location("dcent_rpc_pyext", MODULE_PATH)
pyext = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(pyext)


def parse_like_javascript(text: str) -> dict:
    """Parse exactly like JSON.parse: reject NaN/Infinity and empty input."""
    def reject_constant(token: str):
        raise ValueError(f"bare {token} is not valid JavaScript JSON")

    if not text.strip():
        raise ValueError("empty message")
    return json.loads(text, parse_constant=reject_constant)


def response_for(method: str, *params) -> dict:
    rpc = pyext.Jsonrpc()

    @rpc.add_method
    def probe():
        return params[0]

    rpc.method_map[method] = rpc.method_map.pop("probe")
    return parse_like_javascript(rpc.handle(json.dumps({"id": 1, "method": method, "params": []})))


def test_not_finite_numbers_never_reach_the_client_as_bare_tokens():
    result = response_for("non_finite", {"a": float("nan"), "b": float("inf"), "c": float("-inf"), "d": 1.5})
    assert "error" not in result, result
    assert result["result"] == {"a": None, "b": None, "c": None, "d": 1.5}


def test_unserializable_results_answer_with_an_error_instead_of_dying():
    payload = {"path": Path("/tmp/wallpaper"), "raw": b"\x00\x01", "kind": {"b", "a"}}
    result = response_for("unsupported", payload)
    assert result["id"] == 1
    assert "error" not in result, result
    assert isinstance(result["result"]["path"], str)
    assert isinstance(result["result"]["raw"], str)
    assert isinstance(result["result"]["kind"], list)


def test_deeply_nested_values_do_not_break_serialization():
    nested = current = {}
    for _ in range(40):
        current["child"] = {}
        current = current["child"]
    result = response_for("deep", nested)
    assert result["id"] == 1
    parse_like_javascript(json.dumps(result))


def test_handler_exceptions_still_answer_with_a_valid_error_message():
    rpc = pyext.Jsonrpc()

    @rpc.add_method
    def explode():
        raise RuntimeError("boom")

    text = rpc.handle(json.dumps({"id": 7, "method": "explode", "params": []}))
    parsed = parse_like_javascript(text)
    assert parsed["id"] == 7
    assert "boom" in parsed["error"]


def test_websocket_loop_answers_even_when_handling_raises(monkeypatch):
    class FakeSocket:
        def __init__(self):
            self.sent: list[str] = []
            self._incoming = [json.dumps({"id": 5, "method": "explode", "params": []})]

        async def recv(self):
            if self._incoming:
                return self._incoming.pop(0)
            await asyncio.sleep(0)
            raise RuntimeError("closed")

        async def send(self, message: str):
            self.sent.append(message)

    rpc = pyext.Jsonrpc()

    @rpc.add_method
    def explode():
        raise RuntimeError("handler died")

    async def fake_connect(uri):
        socket = FakeSocket()
        pending: set[asyncio.Task] = set()

        async def respond(message: str) -> None:
            response = await rpc.handle_async(message)
            await socket.send(response)

        try:
            while True:
                task = asyncio.create_task(respond(await socket.recv()))
                pending.add(task)
                task.add_done_callback(pending.discard)
        except RuntimeError:
            for task in pending:
                task.cancel()
            if pending:
                await asyncio.gather(*pending, return_exceptions=True)
        return socket

    async def exercise():
        socket = await fake_connect("ws://test")
        await asyncio.sleep(0.05)
        return socket

    socket = asyncio.run(exercise())
    assert socket.sent, "the helper must always answer a request"
    parsed = parse_like_javascript(socket.sent[0])
    assert parsed["id"] == 5
    assert "error" in parsed


def test_helper_never_sends_a_payload_javascript_cannot_parse():
    rpc = pyext.Jsonrpc()

    @rpc.add_method
    def messy():
        return {"values": [float("nan"), {"deep": float("-inf")}], "path": Path("/tmp/x")}

    text = rpc.handle(json.dumps({"id": 2, "method": "messy", "params": []}))
    parse_like_javascript(text)
    assert "NaN" not in text
    assert "Infinity" not in text
