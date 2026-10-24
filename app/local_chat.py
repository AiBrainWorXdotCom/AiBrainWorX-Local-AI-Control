"""Tool-free local chat streamed through the saved profile gateway."""
from http.client import HTTPConnection
import json
import model_backends


def stream(config, profile, payload, port=8082):
    model=model_backends.normalize(profile['model'],config,validate_file=False)
    messages=payload.get('messages')
    if not isinstance(messages,list) or not messages or len(messages)>80:
        raise ValueError('Start a new conversation when the chat history is full.')
    for message in messages:
        if not isinstance(message,dict) or message.get('role') not in ('user','assistant') or not isinstance(message.get('content'),str):
            raise ValueError('Chat supports user and assistant text messages.')
    if sum(len(m['content']) for m in messages)>min(160000,model['contextWindow']*2):
        raise ValueError('Chat history is getting large. Save important notes to Memory and start a new conversation.')
    body={'model':model['modelId'],'messages':messages,'stream':True,
          'max_tokens':min(profile['maxOutputTokens'],model['contextWindow']//2)}
    connection=HTTPConnection('127.0.0.1',port,timeout=600)
    try:
        connection.request('POST',f"/profiles/{profile['id']}/v1/chat/completions",json.dumps(body).encode(),{'Content-Type':'application/json'})
        reply=connection.getresponse()
        if reply.status!=200:
            reply.read(4096)
            raise ValueError('The local chat request failed. Check the selected model, context and backend.')
        full=''
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
            if delta.get('reasoning_content'):
                print(json.dumps({'thinking':True}),flush=True)
            if isinstance(delta.get('content'),str):
                full+=delta['content'];print(json.dumps({'delta':delta['content']}),flush=True)
        if not full:
            raise ValueError('The model returned no final answer. Reasoning may have consumed the output allowance; check its effort and budget.')
        print(json.dumps({'done':True,'content':full}),flush=True)
    finally:
        connection.close()
