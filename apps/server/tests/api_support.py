def api_payload(response):
    envelope = response.json()
    assert set(envelope) == {"code", "message", "data"}
    if 200 <= response.status_code < 300:
        assert envelope["code"] == 0
        return envelope["data"]
    assert envelope["code"] == response.status_code
    return {"detail": envelope["message"]}
