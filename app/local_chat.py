"""Tool-free local chat streamed through the saved profile gateway."""
from http.client import HTTPConnection
import json
import model_backends
import plugin_host
from copy import deepcopy


def stream(config, profile, payload, port=8082):
    model=model_backends.normalize(profile['model'],config,validate_file=False)
    messages=payload.get('messages')
    if not isinstance(messages,list) or not messages or len(messages)>80:
        raise ValueError('Start a new conversation when the chat history is full.')
    for message in messages:
        if not isinstance(message,dict) or message.get('role') not in ('user','assistant') or not isinstance(message.get('content'),str):
            raise ValueError('Chat supports user and assistant text messages.')
    messages=deepcopy(messages)
    if messages[-1]['role']=='user':
        try:
            customized=plugin_host.run_hook(config,'chat.before_send',{'message':messages[-1]['content']})
            if not isinstance(customized.get('message'),str) or len(customized['message'])>16000:
                raise ValueError('Invalid modified message')
            messages[-1]['content']=customized['message']
        except Exception:
            raise ValueError('An approved chat plugin failed. Disable it or review its source before retrying.') from None
    if sum(len(m['content']) for m in messages)>min(160000,model['contextWindow']*2):
        raise ValueError('Chat history is getting large. Save important notes to Memory and start a new conversation.')
    body={'model':model['modelId'],'messages':messages,'stream':True,
          'max_tokens':min(profile['maxOutputTokens'],model['contextWindow']//2)}
    if payload.get('sessionId'):
        body['aibrainworx_session']={'id':payload['sessionId'],'requestId':payload['requestId']}
    connection=HTTPConnection('127.0.0.1',port,timeout=600)
    try:
        connection.request('POST',f"/profiles/{profile['id']}/v1/chat/completions",json.dumps(body).encode(),{'Content-Type':'application/json'})
        reply=connection.getresponse()
        if reply.status!=200:
            error=reply.read(4096)
            try:
                detail=json.loads(error).get('error',{})
                message=detail.get('message') if isinstance(detail,dict) else None
            except ValueError:
                message=None
            raise ValueError(message or 'The local chat request failed. Check the selected model, context and backend.')
        full=''; finish=None
        for raw in reply:
            line=raw.decode('utf-8').strip()
            if not line.startswith('data:'):
                continue
            data=line[5:].strip()
            if data=='[DONE]':
                break
            event=json.loads(data)
            if event.get('error'):
                raise ValueError('The backend returned a generation error. Check its local logs.')
            choices=event.get('choices') or []
            delta=choices[0].get('delta',{}) if choices else {}
            if choices and choices[0].get('finish_reason'):
                finish=choices[0]['finish_reason']
            if delta.get('reasoning_content'):
                print(json.dumps({'thinking':True}),flush=True)
            if isinstance(delta.get('content'),str):
                full+=delta['content'];print(json.dumps({'delta':delta['content']}),flush=True)
        if not full:
            raise ValueError('The model returned no final answer. Reasoning may have consumed the output allowance; check its effort and budget.')
        try:
            plugin_host.run_hook(config,'chat.after_reply',{'reply':full,'finishReason':finish})
        except Exception:
            print(json.dumps({'pluginWarning':'An approved reply plugin failed; your model response is intact.'}),flush=True)
        print(json.dumps({'done':True,'content':full,'finishReason':finish}),flush=True)
    finally:
        connection.close()
