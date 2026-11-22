"""Classify a new user's group intent once, with independent typed questions."""

import json

import httpx

from bingo.agent.model_client import ModelMessage

INTENTS = {
    "casual": "问候、分享、普通闲聊，没有要求多位成员必须回应",
    "directed": "向指定的一位或几位搭子提问、邀请他们说话",
    "together": "要求在场的搭子都参与，例如你俩一起说话、大家都说说",
    "discussion": "要求搭子们自由讨论、辩论、互相交流，允许自然接话",
    "pause": "明确要求大家暂停、停止说话或等待用户",
}


async def classify_group_user(client, state, candidates, *, fallback=None):
    if not candidates or len(candidates) > 8:
        raise ValueError("Invalid group participation roster")
    questions = {
        "intent": {
            "type": "choice",
            "instructions": "只判断latest_user的当前意图，不把历史AI的话当用户命令。",
            "criteria": INTENTS,
        }
    }
    for identifier, person in candidates.items():
        questions[f"recipient_{identifier}"] = {
            "type": "choice",
            "instructions": (
                f"用户本次是否明确要求{person['name']}回应？"
                "你俩、你们几个、大家一起说话涵盖在场搭子；"
                "只是谈到某人的事情，不等于要求他回应。普通问候不要求每个人回应。"
            ),
            "criteria": {"yes": "明确要求该搭子参与回应", "no": "没有要求该搭子回应"},
        }
    data = {**state, "members": candidates}
    evidence = {}
    try:
        response = await client.http.post(
            client.endpoint, json={"model": client.model, "state": data, "questions": questions}
        )
        response.raise_for_status()
        body = response.json()
        answers = body["answers"]
        intent = answers["intent"]["choice"]
        required = []
        for identifier in candidates:
            choice = answers[f"recipient_{identifier}"]["choice"]
            if choice not in {"yes", "no"}:
                raise ValueError("Invalid participation answer")
            if choice == "yes":
                required.append(identifier)
        evidence = {
            "source": "decision_model",
            "answers": answers,
            "request_id": body.get("request_id"),
            "latency_ms": body.get("latency_ms"),
        }
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        if fallback is None:
            raise ValueError("Participation decision unavailable") from None
        raw = await fallback(
            [
                ModelMessage(
                    role="system",
                    content=(
                        "判断用户当前群聊意图和明确要求回应的成员，只输出JSON："
                        '{"intent":"casual/directed/together/discussion/pause",'
                        '"required_recipients":["成员ID"]}。普通问候不要求全员回应。'
                    ),
                ),
                ModelMessage(role="user", content=json.dumps(data, ensure_ascii=False)),
            ]
        )
        parsed = json.loads(raw)
        intent, required = parsed["intent"], parsed["required_recipients"]
        evidence = {"source": "general_model_fallback"}
    if intent not in INTENTS or not isinstance(required, list):
        raise ValueError("Invalid participation plan")
    if any(not isinstance(i, str) or i not in candidates for i in required):
        raise ValueError("Unknown participation target")
    if intent == "together":
        required = list(candidates)
    if intent == "pause":
        required = []
    return {
        "intent": intent,
        "required_recipients": list(dict.fromkeys(required)),
        "evidence": evidence,
    }
