from pydantic import BaseModel, ConfigDict, Field, model_validator

MUNICIPALITIES = {"北京市", "天津市", "上海市", "重庆市"}


class RegionLocation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    province: str = Field(min_length=2, max_length=30, pattern=r"^[\u4e00-\u9fff·]+$")
    city: str = Field(default="", max_length=30, pattern=r"^[\u4e00-\u9fff·]*$")
    district: str = Field(min_length=2, max_length=30, pattern=r"^[\u4e00-\u9fff·]+$")

    @model_validator(mode="after")
    def require_region_levels(self):
        if self.province in MUNICIPALITIES:
            if self.city and self.city != self.province:
                raise ValueError("直辖市地区信息不一致")
            self.city = ""
        elif not self.city:
            raise ValueError("请提供省、市、区县信息")
        return self

    @property
    def display(self) -> str:
        return self.province + self.city + self.district
