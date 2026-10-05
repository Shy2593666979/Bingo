import json
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class LocationInput(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    address: str = Field(min_length=1, max_length=300)
    province: str = Field(default="", max_length=60)
    city: str = Field(default="", max_length=60)
    district: str = Field(default="", max_length=60)
    longitude: float | None = Field(default=None, ge=-180, le=180, allow_inf_nan=False)
    latitude: float | None = Field(default=None, ge=-85, le=85, allow_inf_nan=False)
    coordinate_system: Literal["GCJ-02"] = "GCJ-02"
    source: Literal["poi", "current", "map", "user_shared_region"] = "poi"
    precision: Literal["point", "approximate", "district"] = "point"
    accuracy_m: float | None = Field(default=None, ge=0, le=100000, allow_inf_nan=False)

    @model_validator(mode="after")
    def check_coordinates(self):
        if self.precision == "district":
            if self.longitude is not None or self.latitude is not None:
                raise ValueError("区县位置不能包含精确坐标")
            if not self.province or not self.district:
                raise ValueError("区县位置需要省份与区县")
            region = (
                self.province + (self.city if self.city != self.province else "") + self.district
            )
            self.name = region
            self.address = region
            self.accuracy_m = None
            self.source = "user_shared_region"
        elif self.longitude is None or self.latitude is None:
            raise ValueError("地点位置需要完整经纬度")
        return self

    def model_content(self, caption: str = "") -> str:
        return json.dumps(
            {
                "type": "location",
                "location": self.model_dump(exclude_none=True),
                "caption": caption,
            },
            ensure_ascii=False,
        )


class LocationResults(BaseModel):
    location: LocationInput | None = None
    places: list[LocationInput] = Field(default_factory=list)
