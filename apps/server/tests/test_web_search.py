import json
from typing import Any

import pytest

from bingo.tools import web_search

_BING_RESULTS = """
<ol id="b_results">
  <li class="b_algo">
    <h2><a href="https://example.com/weather">北京今日天气</a></h2>
    <div class="b_caption"><p>今天晴朗，最高温度 25 度。</p></div>
  </li>
  <li class="b_algo">
    <h2><a href="https://example.com/news"><strong>人工智能</strong>新闻</a></h2>
    <div class="b_caption"><p>最新行业动态。</p></div>
  </li>
</ol>
"""


class _Response:
    text = _BING_RESULTS

    def raise_for_status(self) -> None:
        return None


class _Client:
    request: dict[str, Any] = {}

    def __init__(self, **options: Any) -> None:
        self.request["options"] = options

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args: Any) -> None:
        return None

    async def get(self, url: str, **options: Any) -> _Response:
        self.request.update({"url": url, **options})
        return _Response()


@pytest.mark.asyncio
async def test_web_search_uses_bing_and_parses_results(monkeypatch) -> None:
    monkeypatch.setattr(web_search.httpx, "AsyncClient", _Client)

    result = await web_search.WebSearchTool().run(None, query=" 北京天气 ", max_results=1)
    content = json.loads(result.content)

    assert _Client.request["url"] == "https://cn.bing.com/search"
    assert _Client.request["params"] == {"q": "北京天气", "setlang": "zh-hans"}
    assert content == {
        "query": "北京天气",
        "results": [
            {
                "url": "https://example.com/weather",
                "title": "北京今日天气",
                "snippet": "今天晴朗，最高温度 25 度。",
            }
        ],
    }


def test_bing_parser_keeps_nested_title_text() -> None:
    parser = web_search._BingResultParser()
    parser.feed(_BING_RESULTS)

    assert len(parser.results) == 2
    assert parser.results[1]["title"] == "人工智能新闻"
