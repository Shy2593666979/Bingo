import json
import re

import pytest

from bingo.agent.handoffs import agent_broadcast_targets, ensure_human_mention, normalize_agent_addresses


@pytest.mark.parametrize("text,expected", [
    ("你觉得呢？", "@小鱼 你觉得呢？"),
    ("@我，你觉得呢？", "@小鱼，你觉得呢？"),
    ("@human-id 你觉得呢？", "@小鱼 你觉得呢？"),
    ("@小鱼 你觉得呢？", "@小鱼 你觉得呢？"),
    ("她说“@小鱼”。你觉得呢？", "@小鱼 她说“@小鱼”。你觉得呢？"),
])
def test_confirmed_human_mention_uses_the_real_name_in_body(text, expected):
    targets = [{"type": "user", "id": "human-id"}]
    assert ensure_human_mention(text, targets, "human-id", "小鱼") == expected
    assert ensure_human_mention(text, [], "human-id", "小鱼") == text
from bingo.agent.model_client import ModelTextDelta
from tests.api_support import api_payload
from tests.test_group_chat import P, create, group_app, wait  # noqa: F401
from tests.test_group_v2 import v2  # noqa: F401

PEOPLE = [('role', 'warm', '暖暖'), ('role', 'sweet', '甜甜'), ('user', 'human', '小云')]


@pytest.mark.parametrize('label', ['全部搭子', '全体搭子'])
def test_ai_broadcast_targets_other_roles_without_self_or_human(label):
    text = f'@{label} 每个人说一句吧。'
    expected = [{'type':'role','id':'warm'}]
    assert agent_broadcast_targets(text, PEOPLE, 'sweet') == (True, expected)
    assert normalize_agent_addresses(text, PEOPLE, 'sweet') == (text, expected)
    assert agent_broadcast_targets(f'不要@{label}，先休息。', PEOPLE, 'sweet') == (False, [])
    assert agent_broadcast_targets(f'原话是“@{label} 每个人说一句”。', PEOPLE, 'sweet') == (False, [])
    assert agent_broadcast_targets(f'@{label}们 早上好', PEOPLE, 'sweet')[0]
    assert agent_broadcast_targets(f'@{label}子', PEOPLE, 'sweet') == (False, [])


@pytest.mark.parametrize('label,metadata', [('全体搭子',True),('全部搭子',False)])
def test_ai_broadcast_forces_all_seven_other_roles_even_when_they_choose_silence(v2,label,metadata):
    client, ((headers,_),_), roles, _ = v2
    roles=roles[:8]
    source=roles[0]
    group=create(client,headers,roles)
    class BroadcastModel:
        async def complete(self,messages):
            return '{"action":"silent"}'
        async def stream(self,messages,tools=None):
            sender=re.search(r'你的Role ID=([^；]+)',messages[0].content).group(1)
            if sender==source['id']:
                yield ModelTextDelta(json.dumps({'mentionAll':metadata,'mentionTargets':[]})+'\n')
                yield ModelTextDelta('@'+label+' 每个人说一句晚安吧。')
            else:
                yield ModelTextDelta('{"mentionTargets":[]}\n晚安，收到你的邀请啦。')
    client.app.state.services.group_chat.model=BroadcastModel()
    run=api_payload(client.post(P+f"/groups/{group['id']}/chat",headers=headers,json={
        'content':'你先开个头吧','mentions':[source['id']],
        'clientMessageId':'ai-broadcast-'+label}))
    wait(client)
    rows=api_payload(client.get(P+f"/groups/{group['id']}/messages",headers=headers))
    ai=[m for m in rows if m['sender_type']=='assistant']
    assert len(ai)==8
    first=ai[0]
    assert first['sender_role_id']==source['id'] and first['mention_all'] is True
    assert set(first['mentions'])=={r['id'] for r in roles[1:]}
    assert source['id'] not in first['mentions']
    assert all(t['type']=='role' for t in first['mention_targets'])
    assert {m['sender_role_id'] for m in ai[1:]}=={r['id'] for r in roles[1:]}
    assert all(m['reply_to_message_id']==first['id'] for m in ai[1:])
    events=api_payload(client.get(P+f"/groups/{group['id']}/runs/{run['run_id']}/events",headers=headers))
    end=next(e for e in events['events'] if e['type']=='message_end')
    assert end['message']['mention_all'] is True


@pytest.mark.parametrize('allow,mentions', [(False,True),(True,False),(True,True)])
def test_broadcast_respects_settings_and_repeated_broadcasts_cannot_exceed_ten(v2,allow,mentions):
    client, ((headers,_),_), roles, _ = v2
    group=create(client,headers,roles[:8])
    api_payload(client.patch(P+f"/groups/{group['id']}",headers=headers,
        json={'allow_ai_to_ai':allow,'mentions_enabled':mentions}))
    class EveryoneBroadcasts:
        async def complete(self,messages):
            return '{"action":"silent"}'
        async def stream(self,messages,tools=None):
            yield ModelTextDelta('{"mentionAll":true,"mentionTargets":[]}\n@全体搭子 说一句吧。')
    client.app.state.services.group_chat.model=EveryoneBroadcasts()
    response=client.post(P+f"/groups/{group['id']}/chat",headers=headers,json={
        'content':'你先说吧','mentions':[roles[0]['id']] if mentions else [],
        'clientMessageId':f'broadcast-guards-{allow}-{mentions}'})
    assert response.status_code==200
    wait(client)
    rows=api_payload(client.get(P+f"/groups/{group['id']}/messages",headers=headers))
    ai=[m for m in rows if m['sender_type']=='assistant']
    assert len(ai)==(10 if mentions else 1)
    for m in ai:
        assert m['sender_role_id'] not in m['mentions']
        assert m['mention_all'] == mentions


@pytest.mark.parametrize('addressing', ['named', 'all', 'none'])
def test_free_chatter_off_still_answers_explicit_ai_mentions(v2,addressing):
    client, ((headers,_),_), roles, _ = v2
    roles=roles[:4]
    source=roles[0]
    group=create(client,headers,roles)
    api_payload(client.patch(P+f"/groups/{group['id']}",headers=headers,
                            json={'allow_ai_to_ai':False}))
    class ExplicitOnlyModel:
        async def complete(self,messages):
            return '{"action":"silent"}'
        async def stream(self,messages,tools=None):
            sender=re.search(r'你的Role ID=([^；]+)',messages[0].content).group(1)
            targets=[{'type':'role','id':r['id']} for r in roles[1:]] if addressing=='named' and sender==source['id'] else []
            yield ModelTextDelta(json.dumps({'mentionTargets':targets})+'\n')
            if sender==source['id'] and addressing=='all':
                yield ModelTextDelta('@全体搭子 大家说一句晚安。')
            elif sender==source['id'] and addressing=='named':
                yield ModelTextDelta('、'.join('@'+r['nickname'] for r in roles[1:])+' 大家说一句晚安。')
            else:
                yield ModelTextDelta('今天辛苦了，晚安。')
    client.app.state.services.group_chat.model=ExplicitOnlyModel()
    response=client.post(P+f"/groups/{group['id']}/chat",headers=headers,json={
        'content':'你先邀请大家说晚安','mentions':[source['id']],
        'clientMessageId':'explicit-off-'+addressing})
    assert response.status_code==200
    wait(client)
    rows=api_payload(client.get(P+f"/groups/{group['id']}/messages",headers=headers))
    ai=[m for m in rows if m['sender_type']=='assistant']
    assert len(ai)==(1 if addressing=='none' else 4)
    if addressing!='none':
        assert {m['sender_role_id'] for m in ai[1:]}=={r['id'] for r in roles[1:]}
        assert all(m['reply_to_message_id']==ai[0]['id'] for m in ai[1:])
    assert api_payload(client.get(P+f"/groups/{group['id']}",headers=headers))['allow_ai_to_ai'] is False


@pytest.mark.parametrize('text', ['大家轮流来一句，暖暖先接吧。', '暖暖，你来接一句吧。', '请暖暖说一句。'])
def test_direct_invitation_becomes_a_real_role_mention(text):
    content, targets = normalize_agent_addresses(text, PEOPLE, 'sweet')
    assert '@暖暖' in content
    assert targets == [{'type': 'role', 'id': 'warm'}]


@pytest.mark.parametrize('text', [
    '暖暖喜欢音乐，甜甜喜欢热牛奶。', '暖暖说得很好。',
    '有人说“暖暖先接吧。”我觉得不用了。', '不要请暖暖说一句。',
    '别@暖暖，先休息。', '代码 `@暖暖` 不需要执行。',
])
def test_background_names_quotes_and_negative_requests_are_not_mentions(text):
    assert normalize_agent_addresses(text, PEOPLE, 'sweet') == (text, [])


def test_literal_mentions_are_bound_without_duplicate_at_or_fuzzy_names():
    content, targets = normalize_agent_addresses('@暖暖 你来接一下，@小云 你觉得呢？', PEOPLE, 'sweet')
    assert content == '@暖暖 你来接一下，@小云 你觉得呢？'
    assert targets == [{'type': 'role', 'id': 'warm'}, {'type': 'user', 'id': 'human'}]
    assert normalize_agent_addresses('@暖暖子 你好', PEOPLE)[1] == []
    assert normalize_agent_addresses('甜甜先接吧。', PEOPLE, 'sweet')[1] == []
    ambiguous = [*PEOPLE, ('role', 'warm2', '暖暖')]
    assert normalize_agent_addresses('暖暖先接吧。', ambiguous)[1] == []


@pytest.mark.parametrize('enabled', [True, False])
def test_completed_message_and_event_bind_the_actual_recipient(v2, enabled):
    client, ((headers, _), _), roles, _ = v2
    source, target = roles[:2]
    group = create(client, headers, [source, target])
    api_payload(client.patch(P+f"/groups/{group['id']}", headers=headers,
       json={'allow_ai_to_ai':False,'mentions_enabled':enabled}))

    class CalloutModel:
        async def complete(self, messages):
            return '{"action":"silent"}'
        async def stream(self, messages, tools=None):
            # Deliberately simulate a provider omitting structured metadata.
            yield ModelTextDelta('{"mentionTargets":[]}\n大家轮流来一句，')
            sender = re.search(r'你的Role ID=([^；]+)', messages[0].content).group(1)
            recipient = target if sender != target['id'] else source
            yield ModelTextDelta(recipient['nickname']+'先接吧。')
    client.app.state.services.group_chat.model = CalloutModel()
    run = api_payload(client.post(P+f"/groups/{group['id']}/chat", headers=headers,
        json={'content':'你先说一句', 'mentions':[source['id']] if enabled else [],
              'clientMessageId':'callout-binding-'+str(enabled)}))
    wait(client)
    messages = api_payload(client.get(P+f"/groups/{group['id']}/messages",headers=headers))
    events = api_payload(client.get(P+f"/groups/{group['id']}/runs/{run['run_id']}/events",headers=headers))
    ai_rows = [m for m in messages if m['sender_type']=='assistant']
    assert ai_rows, events
    ai = ai_rows[0]
    recipient = target if ai['sender_role_id'] != target['id'] else source
    expected = [{'type':'role','id':recipient['id']}] if enabled else []
    assert ai['mention_targets'] == expected
    assert ('@'+recipient['nickname'] in ai['content']) == enabled
    end = next(e for e in events['events'] if e['type']=='message_end')
    assert end['message']['mention_targets'] == expected
    assert end['message']['content'] == ai['content']
