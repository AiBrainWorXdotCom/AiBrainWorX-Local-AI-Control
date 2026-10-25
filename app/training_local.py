"""Explicit offline tiny-text LoRA jobs. Optional training libraries load in workers.

Models/datasets/jobs remain outside Git. No downloads, remote code, base-weight
overwrites or automatic inference shutdown. Execution is opt-in per profile.
"""
from __future__ import annotations
import json,math,os,re,struct,subprocess,sys,time,uuid
from pathlib import Path

DEFAULTS=dict(python='',modelPath='',datasetPath='',outputRoot='',useCuda=True,rank=8,maxLength=256,maxExamples=1000,maxSteps=50)
DEPENDENCIES=('torch','transformers','peft','accelerate','safetensors')


def settings(profile,config):
    value={**DEFAULTS,**profile.get('training',{})}
    value['python']=value['python'] or config['PythonExecutable']
    return value


def validate_settings(value):
    if not isinstance(value,dict) or set(value)-set(DEFAULTS):raise ValueError('Unsupported training settings.')
    value={**DEFAULTS,**value}
    for key in ('python','modelPath','datasetPath','outputRoot'):
        if not isinstance(value[key],str) or any(c in value[key] for c in '\x00\r\n"'):raise ValueError('Invalid training path.')
        if value[key] and not Path(value[key]).is_absolute():raise ValueError('Training paths must be absolute.')
    for key,lo,hi in [('rank',4,16),('maxLength',64,1024),('maxExamples',1,20000),('maxSteps',1,500)]:
        if type(value[key]) is not int or not lo<=value[key]<=hi:raise ValueError('Training limits are outside the small-model workflow.')
    if value['rank'] not in (4,8,16) or type(value['useCuda']) is not bool:raise ValueError('Invalid training options.')
    return value


def inspect_weights(folder):
    root=Path(folder)
    if not root.is_dir() or not (root/'config.json').is_file():raise ValueError('Choose a local Hugging Face checkpoint folder with config.json and safetensors weights.')
    if (root/'adapter_config.json').exists():raise ValueError('Choose the complete base checkpoint, not an adapter-only folder.')
    if not (root/'tokenizer_config.json').is_file() or not any((root/name).is_file() for name in ('tokenizer.json','tokenizer.model')):
        raise ValueError('The local checkpoint needs its tokenizer configuration and tokenizer files too.')
    raw=(root/'config.json').read_bytes()
    if len(raw)>1024*1024:raise ValueError('Model config is too large.')
    cfg=json.loads(raw)
    if cfg.get('model_type') not in ('qwen2','qwen3','llama','gemma3_text') or cfg.get('quantization_config'):
        raise ValueError('Initial training supports tiny dense text checkpoints in HF safetensors format, not GGUF, MoE, vision or pre-quantized weights.')
    weights=sorted(root.glob('*.safetensors'))
    if not weights or len(weights)>64:raise ValueError('Local safetensors weights are required.')
    total=0
    for file in weights:
        if file.is_symlink():raise ValueError('Use checkpoint files directly, without weight-file symlinks.')
        with file.open('rb') as stream:
            length_bytes=stream.read(8)
            if len(length_bytes)!=8:raise ValueError('Invalid safetensors file.')
            length=struct.unpack('<Q',length_bytes)[0]
            if not 2<=length<=16*1024*1024:raise ValueError('Invalid safetensors header size.')
            header=json.loads(stream.read(length))
        for name,tensor in header.items():
            if name=='__metadata__':continue
            shape=tensor.get('shape')
            if not isinstance(shape,list) or len(shape)>8 or any(type(n) is not int or n<0 for n in shape):raise ValueError('Invalid tensor shape.')
            if tensor.get('dtype') not in ('F16','BF16','F32'):raise ValueError('Use ordinary floating-point safetensors for this LoRA workflow.')
            total+=math.prod(shape)
            if total>1_200_000_000:raise ValueError('Initial LoRA training is limited to about 1B parameters (1.2B stored-tensor cap).')
            offsets=tensor.get('data_offsets')
            size=math.prod(shape)*(4 if tensor['dtype']=='F32' else 2)
            if not isinstance(offsets,list) or len(offsets)!=2 or any(type(n) is not int or n<0 for n in offsets) or offsets[1]-offsets[0]!=size or offsets[1]>file.stat().st_size-8-length:
                raise ValueError('Tensor offsets do not match the local safetensors data.')
    return {'architecture':cfg['model_type'],'storedParameters':total,'weightFiles':len(weights)}


def read_examples(path,limit):
    source=Path(path)
    if source.suffix.lower()!='.jsonl' or not source.is_file() or source.stat().st_size>128*1024*1024:
        raise ValueError('Choose a local JSONL dataset, up to 128 MB. Prepare a small subset first.')
    examples=[]
    with source.open(encoding='utf-8-sig') as stream:
        for number,line in enumerate(stream,1):
            if not line.strip():continue
            if len(line)>65536:raise ValueError('A dataset row exceeds 64K characters.')
            row=json.loads(line)
            if not isinstance(row,dict):raise ValueError('Each dataset row must be an object.')
            if isinstance(row.get('text'),str) and row['text'].strip():examples.append({'text':row['text']})
            elif isinstance(row.get('messages'),list) and 1<=len(row['messages'])<=64:
                for message in row['messages']:
                    if not isinstance(message,dict) or message.get('role') not in ('system','user','assistant') or not isinstance(message.get('content'),str):raise ValueError('Use text-only system/user/assistant messages.')
                examples.append({'messages':row['messages']})
            else:raise ValueError('Rows need nonempty text or a text-only messages list.')
            if len(examples)>=limit:break
    if not examples:raise ValueError('The local dataset contains no training examples.')
    return examples


def dependencies(python):
    if not Path(python).is_file():raise ValueError('Choose the Python executable in your separate training environment.')
    code="import importlib.metadata as m,json; r={};\nfor x in "+repr(DEPENDENCIES)+":\n try:r[x]=m.version(x)\n except m.PackageNotFoundError:r[x]=None\nprint(json.dumps(r))"
    run=subprocess.run([python,'-I','-c',code],capture_output=True,timeout=15,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    if run.returncode:raise ValueError('Could not inspect the training Python environment.')
    return json.loads(run.stdout)


def preflight(config,profile):
    opts=validate_settings(settings(profile,config));model=inspect_weights(opts['modelPath']);rows=read_examples(opts['datasetPath'],opts['maxExamples'])
    output=Path(opts['outputRoot'])
    if not output.is_dir():raise ValueError('Choose an existing output folder. Each job creates a new subfolder.')
    versions=dependencies(opts['python']);missing=[key for key in DEPENDENCIES if not versions.get(key)]
    return {'ready':not missing,'model':model,'examples':len(rows),'missing':missing,'versions':versions,
            'limits':{key:opts[key] for key in ('rank','maxLength','maxExamples','maxSteps','useCuda')},
            'note':'Offline LoRA, full-sequence loss, batch 1. Saves an adapter separately. No downloads or training occurred. Close other GPU workloads before starting.'}


def job_dir(config,identity):
    if not isinstance(identity,str) or not re.fullmatch('[a-f0-9]{32}',identity):raise ValueError('Invalid training job identifier.')
    return Path(config['StateRoot'])/'training/jobs'/identity


def write_json(path,value):
    temporary=path.with_suffix('.tmp');temporary.write_text(json.dumps(value,indent=2),encoding='utf-8');temporary.replace(path)


def start(config,profile):
    import control_core
    with control_core.state_lock(config):
        return _start(config,profile)


def _start(config,profile):
    if not profile.get('allowTraining'):raise ValueError('Training starts are disabled. Enable them explicitly in this profile’s Training page after reviewing paths and licenses.')
    check=preflight(config,profile)
    if not check['ready']:raise ValueError('Install the missing packages in the selected separate training environment first.')
    jobs=Path(config['StateRoot'])/'training/jobs'
    for file in jobs.glob('*/status.json'):
        try:
            prior=json.loads(file.read_text(encoding='utf-8'))
            if prior.get('state') in ('starting','running'):
                raise ValueError('Another training job is active or needs inspection. Stop it or wait; no second job was started.')
        except (OSError,json.JSONDecodeError):continue
    opts=settings(profile,config);identity=uuid.uuid4().hex;job=job_dir(config,identity);job.mkdir(parents=True)
    request={'id':identity,'profileId':profile['id'],'settings':opts,'output':str(Path(opts['outputRoot'])/('awx-lora-'+identity))}
    write_json(job/'request.json',request);write_json(job/'status.json',{'state':'starting','updated':time.time(),'profileId':profile['id'],'id':identity})
    try:
        with (job/'worker.log').open('ab') as log:
            process=subprocess.Popen([opts['python'],str(Path(__file__).resolve()),'--job',str(job)],stdin=subprocess.DEVNULL,stdout=log,stderr=log,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    except OSError:
        write_json(job/'status.json',{'state':'failed','updated':time.time(),'profileId':profile['id'],'id':identity,'phase':'Could not start the selected training Python.'})
        raise ValueError('Could not start the selected training Python. No training was performed.')
    write_json(job/'process.json',{'pid':process.pid});return {'id':identity,'state':'starting','note':'Offline LoRA job started. Original weights are not overwritten.'}


def status(config,profile,identity):
    folder=job_dir(config,identity);value=json.loads((folder/'status.json').read_text(encoding='utf-8'))
    if value.get('profileId')!=profile['id']:raise ValueError('This job belongs to another profile.')
    return value


def stop(config,profile,identity):
    state=status(config,profile,identity)
    if state['state'] in ('starting','running'):(job_dir(config,identity)/'STOP').touch()
    return {'id':identity,'note':'Stop requested at the next training callback. Loading a checkpoint may take time; no unrelated process was killed.'}


def latest(config,profile):
    files=sorted((Path(config['StateRoot'])/'training/jobs').glob('*/status.json'),key=lambda p:p.stat().st_mtime,reverse=True)[:200]
    for file in files:
        try:
            value=json.loads(file.read_text(encoding='utf-8'))
            if value.get('profileId')==profile['id']:return value
        except (OSError,ValueError):continue
    return {'state':'none','id':'','note':'No training job has been started for this profile.'}


def worker(folder):
    folder=Path(folder);request=json.loads((folder/'request.json').read_text(encoding='utf-8'));opts=validate_settings(request['settings'])
    def update(state,**extra):write_json(folder/'status.json',{'id':request['id'],'profileId':request['profileId'],'state':state,'updated':time.time(),**extra})
    try:
        os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_DATASETS_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',TOKENIZERS_PARALLELISM='false')
        update('running',phase='checking local inputs');inspect_weights(opts['modelPath']);examples=read_examples(opts['datasetPath'],opts['maxExamples'])
        import torch
        from transformers import AutoTokenizer,AutoModelForCausalLM,Trainer,TrainingArguments,TrainerCallback,DataCollatorForLanguageModeling
        from peft import LoraConfig,get_peft_model
        cuda=opts['useCuda']
        if cuda and not torch.cuda.is_available():raise ValueError('CUDA is unavailable; choose CPU explicitly or configure a supported training environment.')
        if cuda and torch.cuda.mem_get_info()[0]<3*1024**3:raise ValueError('Less than 3 GB GPU memory is free. Stop inference in its owning app first.')
        if (folder/'STOP').exists():update('cancelled',phase='before loading');return
        update('running',phase='loading local checkpoint')
        tokenizer=AutoTokenizer.from_pretrained(opts['modelPath'],local_files_only=True,trust_remote_code=False)
        if tokenizer.pad_token_id is None:tokenizer.pad_token=tokenizer.eos_token
        model=AutoModelForCausalLM.from_pretrained(opts['modelPath'],local_files_only=True,trust_remote_code=False,use_safetensors=True,torch_dtype=torch.float16 if cuda else torch.float32)
        if sum(p.numel() for p in model.parameters())>1_200_000_000:raise ValueError('Loaded model exceeds the tiny-model cap.')
        model.config.use_cache=False
        model=get_peft_model(model,LoraConfig(r=opts['rank'],lora_alpha=opts['rank']*2,lora_dropout=.05,target_modules='all-linear',task_type='CAUSAL_LM'))
        class Examples(torch.utils.data.Dataset):
            def __len__(self):return len(examples)
            def __getitem__(self,index):
                row=examples[index]
                text=row['text'] if 'text' in row else tokenizer.apply_chat_template(row['messages'],tokenize=False,add_generation_prompt=False)
                return tokenizer(text,truncation=True,max_length=opts['maxLength'],add_special_tokens=('text' in row))
        class Progress(TrainerCallback):
            def on_step_end(self,args,state,control,**kwargs):
                update('running',phase='training',step=state.global_step,totalSteps=state.max_steps)
                if (folder/'STOP').exists():control.should_training_stop=True
            def on_log(self,args,state,control,logs=None,**kwargs):
                update('running',phase='training',step=state.global_step,totalSteps=state.max_steps,loss=(logs or {}).get('loss'))
        output=Path(request['output'])
        if output.exists():raise ValueError('The unique output directory already exists; original files were kept.')
        arguments=TrainingArguments(output_dir=str(output),max_steps=opts['maxSteps'],per_device_train_batch_size=1,gradient_accumulation_steps=4,learning_rate=2e-4,save_strategy='no',logging_steps=1,report_to=[],disable_tqdm=True,fp16=cuda,use_cpu=not cuda,seed=42)
        Trainer(model=model,args=arguments,train_dataset=Examples(),data_collator=DataCollatorForLanguageModeling(tokenizer,mlm=False),callbacks=[Progress()]).train()
        model.save_pretrained(output/'adapter',safe_serialization=True);tokenizer.save_pretrained(output/'adapter')
        update('cancelled' if (folder/'STOP').exists() else 'completed',phase='adapter saved',output=str(output/'adapter'))
    except Exception:
        import traceback;traceback.print_exc();update('failed',phase='See the private worker.log; no base model weights were changed.')


if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--job':worker(sys.argv[2])
