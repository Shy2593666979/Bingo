import json
from html.parser import HTMLParser
from typing import Any

import httpx

from bingo.tools.base import BaseTool, ToolContext, ToolResult

_SEARCH_URL = "https://lite.duckduckgo.com/lite/"
_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Android 14; Mobile) AppleWebKit/537.36",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
}


class _ResultParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.results: list[dict[str, str]] = []
        self._capture_link = False
        self._capture_snippet = False
        self._current: dict[str, str] = {}
        self._buffer = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        css_class = attributes.get("class", "") or ""
        if tag == "a" and "result-link" in css_class:
            self._current = {"url": attributes.get("href", "") or "", "title": ""}
            self._capture_link = True
            self._buffer = ""
        elif tag == "td" and "result-snippet" in css_class:
            self._capture_snippet = True
            self._buffer = ""

    def handle_data(self, data: str) -> None:
        if self._capture_link or self._capture_snippet:
            self._buffer += data

    def handle_endtag(self, tag: str) -> None:
        if self._capture_link and tag == "a":
            self._current["title"] = self._buffer.strip()
            self._capture_link = False
            self._buffer = ""
        elif self._capture_snippet and tag == "td":
            self._current["snippet"] = self._buffer.strip()
            self._capture_snippet = False
            self._buffer = ""
            if self._current.get("title"):
                self.results.append(self._current.copy())
                self._current = {}


class WebSearchTool(BaseTool):
    name = "web_search"
    description = "搜索互联网以获取最新信息，返回标题、网址和摘要。"
    parameters = {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "搜索关键词"},
            "max_results": {
                "type": "integer",
                "description": "结果数量，1 到 8，默认 5",
                "minimum": 1,
                "maximum": 8,
            },
        },
        "required": ["query"],
        "additionalProperties": False,
    }

    async def run(self, context: ToolContext, **arguments: Any) -> ToolResult:
        query = str(arguments.get("query", "")).strip()
        if not query:
            raise ValueError("query 不能为空")
        max_results = max(1, min(int(arguments.get("max_results", 5)), 8))
        async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
            response = await client.post(
                _SEARCH_URL,
                data={"q": query},
                headers=_HEADERS,
            )
            response.raise_for_status()
        parser = _ResultParser()
        parser.feed(response.text)
        return ToolResult(
            content=json.dumps(
                {"query": query, "results": parser.results[:max_results]},
                ensure_ascii=False,
            )
        )
