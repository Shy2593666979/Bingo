from bingo.agent.model_client import (
    AgentModelClient,
    ModelMessage,
    _chat_messages,
    _responses_input,
)
from bingo.config import Settings


def test_responses_input_combines_text_and_image_content() -> None:
    result = _responses_input(
        [
            ModelMessage(role="system", content="system"),
            ModelMessage(
                role="user",
                content="这是什么？",
                image_data_urls=("data:image/jpeg;base64,abc",),
            ),
        ]
    )

    assert result[-1] == {
        "role": "user",
        "content": [
            {"type": "input_text", "text": "这是什么？"},
            {
                "type": "input_image",
                "image_url": "data:image/jpeg;base64,abc",
                "detail": "low",
            },
        ],
    }


def test_chat_completions_input_combines_text_and_image_content() -> None:
    result = _chat_messages(
        [
            ModelMessage(
                role="user",
                image_data_urls=("data:image/png;base64,abc",),
            )
        ]
    )

    assert result == [
        {
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {
                        "url": "data:image/png;base64,abc",
                        "detail": "low",
                    },
                }
            ],
        }
    ]


def test_image_messages_select_dedicated_vision_configuration() -> None:
    settings = Settings(
        model={
            "provider": "openai_compat",
            "api_key": "main-key",
            "model": "main-model",
        },
        vision={
            "api_key": "vision-key",
            "model": "vision-model",
            "base_url": "https://vision.example/v1",
        },
    )
    client = AgentModelClient(settings)

    _, text_model, _, _ = client._route([ModelMessage(role="user", content="hello")])
    options, image_model, _, _ = client._route(
        [ModelMessage(role="user", image_data_urls=("data:image/jpeg;base64,abc",))]
    )

    assert text_model == "main-model"
    assert image_model == "vision-model"
    assert options["api_key"] == "vision-key"
    assert options["base_url"] == "https://vision.example/v1"
