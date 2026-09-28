import json
import re
from html.parser import HTMLParser
from typing import Any

import httpx

from bingo.tools.base import BaseTool, ToolContext, ToolResult

_SEARCH_URL = "https://cn.bing.com/search"
_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 Chrome/140 Safari/537.36"
    ),
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
}


# DuckDuckGo Lite 搜索效果通常优于必应，但仅适用于能够访问外网的环境。
_DUCKDUCKGO_SEARCH_URL = "https://lite.duckduckgo.com/lite/"
_NEWS_QUERY_SUFFIX = re.compile(
    r"(?:有(?:什么|啥))?的?(?:最新)?(?:新闻|资讯)[？?。.!！]*$"
)
_QUERY_PREFIXES = (
    "麻烦帮我",
    "帮我",
    "请帮我",
    "请",
    "查一下",
    "查查",
    "搜索",
    "搜一下",
    "看一下",
    "看看",
)
_TIME_PREFIXES = ("今天", "今日", "最近", "当前")


class _DuckDuckGoResultParser(HTMLParser):
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


class _BingResultParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.results: list[dict[str, str]] = []
        self._in_result = False
        self._nested_list_items = 0
        self._in_heading = False
        self._caption_depth = 0
        self._capture_link = False
        self._capture_snippet = False
        self._current: dict[str, str] = {}
        self._buffer = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        classes = set((attributes.get("class", "") or "").split())
        if tag == "li":
            if self._in_result:
                self._nested_list_items += 1
            elif "b_algo" in classes:
                self._in_result = True
                self._current = {}
            return
        if not self._in_result:
            return
        if tag == "h2":
            self._in_heading = True
        elif tag == "a" and self._in_heading and not self._current.get("url"):
            self._current = {"url": attributes.get("href", "") or "", "title": ""}
            self._capture_link = True
            self._buffer = ""
        elif tag == "div":
            if self._caption_depth:
                self._caption_depth += 1
            elif "b_caption" in classes:
                self._caption_depth = 1
        elif tag == "p" and self._caption_depth:
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
        elif self._capture_snippet and tag == "p":
            self._current["snippet"] = self._buffer.strip()
            self._capture_snippet = False
            self._buffer = ""

        if tag == "h2":
            self._in_heading = False
        elif tag == "div" and self._caption_depth:
            self._caption_depth -= 1
        elif tag == "li" and self._in_result:
            if self._nested_list_items:
                self._nested_list_items -= 1
            else:
                if self._current.get("title") and self._current.get("url"):
                    self._current.setdefault("snippet", "")
                    self.results.append(self._current.copy())
                self._current = {}
                self._in_result = False
                self._in_heading = False
                self._caption_depth = 0


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
        search_query = _normalize_search_query(query)
        async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
            response = await client.get(
                _SEARCH_URL,
                params={"q": search_query, "setlang": "zh-hans"},
                headers=_HEADERS,
            )
            # 保留旧的 DuckDuckGo 请求，供能够访问外网的部署环境切换使用。
            # response = await client.post(
            #     _DUCKDUCKGO_SEARCH_URL,
            #     data={"q": query},
            #     headers=_HEADERS,
            # )
            response.raise_for_status()
        parser = _BingResultParser()
        parser.feed(response.text)
        return ToolResult(
            content=json.dumps(
                {"query": query, "results": parser.results[:max_results]},
                ensure_ascii=False,
            )
        )


def _normalize_search_query(query: str) -> str:
    match = _NEWS_QUERY_SUFFIX.search(query)
    if match is None:
        return query

    topic = query[: match.start()].strip()
    changed = True
    while changed:
        changed = False
        for prefix in (*_QUERY_PREFIXES, *_TIME_PREFIXES):
            if topic.startswith(prefix):
                topic = topic[len(prefix) :].strip()
                changed = True
                break
    return f"{topic} 最新新闻" if topic else query
