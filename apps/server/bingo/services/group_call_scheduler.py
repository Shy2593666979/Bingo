"""Choose a speaker, never a character's opinion; all choices are locally validated."""

import json
import random
from dataclasses import dataclass

from bingo.agent.model_client import ModelMessage
from bingo.prompts.group_call import SCHEDULER


def json_object(text):
    if not isinstance(text, str) or len(text) > 12000:
        return {}
    try:
        value = json.loads(text.strip().removeprefix("```json").removesuffix("```").strip())
        return value if isinstance(value, dict) else {}
    except (ValueError, TypeError):
        return {}


@dataclass(frozen=True)
class TurnDecision:
    action: str
    speaker_id: str = ""


class TurnScheduler:
    async def next_turn(self, engine, state):
        roles = list(engine.roles)
        if not roles:
            return TurnDecision("finish")
        latest = engine.history[-1] if engine.history else {}
        # Only genuine invitations count; mentioning someone's view is not an invitation.
        if latest.get("role_id"):
            named, strong = engine.targets(latest["text"], exclude=latest["role_id"])
        else:
            named = [r for r in roles if r.nickname in latest.get("text", "")]
            strong = bool(named)
        if strong and named:
            return TurnDecision("speak", random.choice(named).id)
        # Rules supply the fallback weights; no per-agent assessment calls are needed.
        weights = [
            (0.25 if r.id == state.last_speaker_id else 1)
            / (1 + state.recent_speakers[-6:].count(r.id))
            for r in roles
        ]
        fallback = random.choices(roles, weights=weights, k=1)[0]
        if latest and latest.get("role_id") is None and state.ai_silent_turns == 0:
            # A new user contribution deserves a direct response, including emotions and questions.
            return TurnDecision("speak", fallback.id)
        result = json_object(
            await engine.complete(
                [
                    ModelMessage(role="system", content=SCHEDULER),
                    ModelMessage(
                        role="user",
                        content=json.dumps(
                            {
                                "topic": state.topic,
                                "summary": state.topic_summary,
                                "recent": engine.history[-12:],
                                "candidates": [
                                    {
                                        "id": r.id,
                                        "name": r.nickname,
                                        "persona": r.context_prompt[:250],
                                    }
                                    for r in roles
                                ],
                                "recent_speakers": state.recent_speakers[-6:],
                                "winding_down": state.phase == "winding_down",
                            },
                            ensure_ascii=False,
                        ),
                    ),
                ]
            )
        )
        action = result.get("action")
        if isinstance(action, str) and action in {"finish", "yield"}:
            return TurnDecision(result["action"])
        identifiers = result.get("speaker_ids", [result.get("speaker_id")])
        if action == "speak" and isinstance(identifiers, list):
            eligible = [
                (r, weight) for r, weight in zip(roles, weights, strict=True) if r.id in identifiers
            ]
            if eligible:
                chosen = random.choices(
                    [r for r, _ in eligible], weights=[w for _, w in eligible], k=1
                )[0]
                return TurnDecision("speak", chosen.id)
        return TurnDecision("speak", fallback.id)
