from datetime import date

import httpx
import pytest

from bingo.services import weather


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "forecast_date,country,province,expected",
    [
        ("2026-10-03", "CN", "北京市", True),
        ("2026-10-02", "CN", "北京市", False),
        ("2026-10-03", "US", "北京市", False),
        ("2026-10-03", "CN", "河南省", False),
    ],
)
async def test_forecast_requires_matching_date_and_correct_country(
    monkeypatch, forecast_date, country, province, expected
):
    requests = []

    class Client:
        def __init__(self, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            pass

        async def get(self, url, params):
            requests.append((url, params))
            value = (
                {
                    "results": [
                        {
                            "country_code": country,
                            "admin1": province,
                            "latitude": 39.9,
                            "longitude": 116.3,
                            "name": "北京",
                        }
                    ]
                }
                if "geocoding" in url
                else {
                    "daily": {
                        "time": [forecast_date],
                        "weather_code": [0],
                        "temperature_2m_min": [18],
                        "temperature_2m_max": [25],
                    }
                }
            )
            return httpx.Response(200, json=value, request=httpx.Request("GET", url))

    monkeypatch.setattr(weather.httpx, "AsyncClient", Client)
    region = {"province": "北京市", "city": "", "district": "海淀区"}
    result = await weather.WeatherService().forecast(region, date(2026, 10, 3), "Asia/Shanghai")
    assert bool(result) is expected
    assert requests[0][1]["countryCode"] == "CN"
    assert requests[0][1]["name"] == "海淀区"
    if country != "CN" or province != "北京市":
        assert all("geocoding" in url for url, params in requests)
    if expected:
        assert "Open-Meteo" in result and "晴" in result and "25" in result


@pytest.mark.asyncio
async def test_weather_failure_or_missing_region_returns_no_weather(monkeypatch):
    class Client:
        def __init__(self, **kwargs):
            raise httpx.ConnectError("offline")

    monkeypatch.setattr(weather.httpx, "AsyncClient", Client)
    service = weather.WeatherService()
    assert await service.forecast(None, date(2026, 10, 3), "Asia/Shanghai") == ""
    assert (
        await service.forecast(
            {"province": "北京市", "city": "", "district": "海淀区"},
            date(2026, 10, 3),
            "Asia/Shanghai",
        )
        == ""
    )
