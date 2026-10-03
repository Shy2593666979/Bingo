import asyncio
import json
from datetime import date

import httpx


class WeatherService:
    async def forecast(self, region: dict | None, today: date, timezone: str) -> str:
        if not region:
            return ""
        try:
            async with asyncio.timeout(12), httpx.AsyncClient(timeout=5) as client:
                province = region["province"].removesuffix("省").removesuffix("市")
                place = None
                for name in dict.fromkeys([region["district"], region["city"] or province]):
                    name = name.removesuffix("市")
                    response = await client.get(
                        "https://geocoding-api.open-meteo.com/v1/search",
                        params={
                            "name": name,
                            "countryCode": "CN",
                            "language": "zh",
                            "count": 10,
                        },
                    )
                    response.raise_for_status()
                    results = response.json().get("results", [])
                    matched = next(
                        (
                            item
                            for item in results
                            if item.get("country_code") == "CN"
                            and item.get("admin1", "").removesuffix("省").removesuffix("市")
                            == province
                        ),
                        None,
                    )
                    if matched:
                        place = matched
                        break
                if not place:
                    return ""
                response = await client.get(
                    "https://api.open-meteo.com/v1/forecast",
                    params={
                        "latitude": place["latitude"],
                        "longitude": place["longitude"],
                        "timezone": timezone,
                        "forecast_days": 1,
                        "daily": "weather_code,temperature_2m_max,temperature_2m_min",
                    },
                )
                response.raise_for_status()
                daily = response.json().get("daily", {})
                if daily.get("time") != [today.isoformat()]:
                    return ""
                report = {
                    "来源": "Open-Meteo",
                    "地区": place["name"],
                    "日期": today.isoformat(),
                    "级别": "地区级当日预报，不是具体位置的实况",
                    "天气": _weather_description(daily["weather_code"][0]),
                    "最低温度摄氏": daily["temperature_2m_min"][0],
                    "最高温度摄氏": daily["temperature_2m_max"][0],
                }
                if (
                    report["天气"] == ""
                    or report["最低温度摄氏"] is None
                    or report["最高温度摄氏"] is None
                ):
                    return ""
                return json.dumps(report, ensure_ascii=False)
        except (httpx.HTTPError, TimeoutError, KeyError, IndexError, TypeError, ValueError):
            return ""


def _weather_description(code: int) -> str:
    if code == 0:
        return "晴"
    if code in {1, 2, 3}:
        return "晴间多云" if code < 3 else "阴"
    if code in {45, 48}:
        return "雾"
    if code in {51, 53, 55, 56, 57}:
        return "毛毛雨"
    if code in {61, 63, 65, 66, 67, 80, 81, 82}:
        return "雨"
    if code in {71, 73, 75, 77, 85, 86}:
        return "雪"
    if code in {95, 96, 99}:
        return "雷雨"
    return ""
