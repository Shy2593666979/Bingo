import logging
import time
from collections import deque

import httpx

from bingo.config import MapsSettings
from bingo.schemas.maps import LocationInput, LocationResults
from bingo.services.exceptions import ServiceError


class MapsService:
    def __init__(self, settings: MapsSettings):
        self.settings = settings
        self._requests: dict[str, deque[float]] = {}
        self._maps: dict[tuple, tuple[float, bytes]] = {}
        self._results: dict[tuple, tuple[float, LocationResults]] = {}
        self._client: httpx.AsyncClient | None = None
        logging.getLogger("httpx").setLevel(logging.WARNING)

    def _limit(self, user_id: str):
        if not self.settings.api_key:
            raise ServiceError(503, "位置服务暂未配置，请联系管理员")
        now = time.monotonic()
        if len(self._requests) > 2000:
            self._requests = {
                key: queue
                for key, queue in self._requests.items()
                if queue and queue[-1] > now - 60
            }
        queue = self._requests.setdefault(user_id, deque())
        while queue and queue[0] <= now - 60:
            queue.popleft()
        if len(queue) >= 60:
            raise ServiceError(429, "位置查询过于频繁，请稍后重试")
        queue.append(now)

    async def _get(self, path: str, parameters: dict):
        try:
            if self._client is None:
                self._client = httpx.AsyncClient(
                    timeout=self.settings.timeout_seconds,
                    follow_redirects=False,
                    limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
                )
            response = await self._client.get(
                f"https://restapi.amap.com/v3/{path}",
                params={**parameters, "key": self.settings.api_key},
            )
            response.raise_for_status()
            return response
        except httpx.HTTPError:
            raise ServiceError(502, "位置服务连接失败，请稍后重试") from None

    async def close(self):
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    def _cached(self, key: tuple):
        result = self._results.get(key)
        return result[1].model_copy(deep=True) if result and result[0] > time.monotonic() else None

    def _save_result(self, key: tuple, result: LocationResults):
        if len(self._results) >= 256:
            self._results.pop(next(iter(self._results)))
        self._results[key] = (time.monotonic() + 120, result.model_copy(deep=True))
        return result

    async def _json(self, path: str, parameters: dict):
        response = await self._get(path, parameters)
        try:
            data = response.json()
        except ValueError:
            raise ServiceError(502, "位置服务返回异常，请稍后重试") from None
        if not isinstance(data, dict) or data.get("status") != "1":
            raise ServiceError(502, "位置服务暂时不可用，请检查服务配置或稍后重试")
        return data

    @staticmethod
    def _text(value) -> str:
        return value.strip() if isinstance(value, str) else ""

    def _place(self, item: dict, province: str = "", city: str = "", district: str = ""):
        if not isinstance(item, dict):
            return None
        coordinates = self._text(item.get("location")).split(",")
        if len(coordinates) != 2:
            return None
        try:
            province = self._text(item.get("pname")) or province
            city = self._text(item.get("cityname")) or city or province
            district = self._text(item.get("adname")) or district
            region = province + (city if city != province else "") + district
            address = self._text(item.get("address"))
            if province and address.startswith(province):
                full_address = address
            elif city and address.startswith(city):
                full_address = (province if province != city else "") + address
            elif district and address.startswith(district):
                full_address = region + address[len(district) :]
            else:
                full_address = region + address
            return LocationInput(
                name=self._text(item.get("name")),
                address=full_address or region,
                province=province,
                city=city,
                district=district,
                longitude=float(coordinates[0]),
                latitude=float(coordinates[1]),
            )
        except ValueError:
            return None

    async def search(self, user_id: str, keywords: str, city: str = "") -> LocationResults:
        self._limit(user_id)
        key = ("search", keywords, city)
        if cached := self._cached(key):
            return cached
        data = await self._json(
            "place/text", {"keywords": keywords, "city": city, "offset": 15, "extensions": "base"}
        )
        if not isinstance(data.get("pois", []), list):
            raise ServiceError(502, "位置服务返回异常，请稍后重试")
        return self._save_result(
            key,
            LocationResults(
                places=[
                    place
                    for item in data.get("pois", [])
                    if (place := self._place(item)) is not None
                ]
            ),
        )

    async def reverse(
        self, user_id: str, longitude: float, latitude: float, coordinate_system: str = "GCJ-02"
    ) -> LocationResults:
        self._limit(user_id)
        key = ("reverse", longitude, latitude, coordinate_system)
        if cached := self._cached(key):
            return cached
        coordinate = f"{longitude},{latitude}"
        if coordinate_system == "WGS84":
            converted = await self._json(
                "assistant/coordinate/convert", {"locations": coordinate, "coordsys": "gps"}
            )
            coordinate = converted.get("locations", "")
            try:
                longitude, latitude = map(float, coordinate.split(","))
            except (ValueError, AttributeError):
                raise ServiceError(502, "位置坐标转换失败，请重试") from None
        data = await self._json(
            "geocode/regeo", {"location": coordinate, "extensions": "all", "radius": 1000}
        )
        result = data.get("regeocode", {})
        if not isinstance(result, dict) or not isinstance(result.get("addressComponent", {}), dict):
            raise ServiceError(502, "位置服务返回异常，请稍后重试")
        components = result.get("addressComponent", {})
        province = self._text(components.get("province"))
        city = self._text(components.get("city")) or province
        district = self._text(components.get("district"))
        address = self._text(result.get("formatted_address"))
        if not address:
            raise ServiceError(502, "未能解析此处地址，请选择附近地点或搜索")
        if not isinstance(result.get("pois", []), list):
            raise ServiceError(502, "位置服务返回异常，请稍后重试")
        return self._save_result(
            key,
            LocationResults(
                location=LocationInput(
                    name="地图选点",
                    address=address,
                    province=province,
                    city=city,
                    district=district,
                    longitude=longitude,
                    latitude=latitude,
                    source="map",
                ),
                places=[
                    place
                    for item in result.get("pois", [])[:15]
                    if (place := self._place(item, province, city, district)) is not None
                ],
            ),
        )

    async def map_image(
        self,
        user_id: str,
        longitude: float,
        latitude: float,
        zoom: int,
        height: int = 220,
        marker: bool = True,
    ) -> bytes:
        self._limit(user_id)
        key = (round(longitude, 6), round(latitude, 6), zoom, height, marker)
        now = time.monotonic()
        cached = self._maps.get(key)
        if cached and cached[0] > now:
            return cached[1]
        coordinate = f"{key[0]},{key[1]}"
        response = await self._get(
            "staticmap",
            {
                "location": coordinate,
                "zoom": zoom,
                "size": f"480*{height}",
                **({"markers": f"mid,0x267F67,A:{coordinate}"} if marker else {}),
            },
        )
        if (
            not response.content.startswith(b"\x89PNG\r\n\x1a\n")
            or len(response.content) > 2_000_000
        ):
            raise ServiceError(502, "地图暂时未加载，请点击重试")
        if len(self._maps) >= 256:
            self._maps.pop(next(iter(self._maps)))
        self._maps[key] = (now + 600, response.content)
        return response.content
