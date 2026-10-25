"""Boundaries for optional platform bridges and offline training (no model load)."""
import importlib,json,os,struct,socketserver,sys,tempfile,threading,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'app'),str(ROOT/'bridge')]
import android_mcp as android
import blender_mcp as blender
import training_local as training
import control_core as core


class PlatformTraining(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.model=self.root/'model';self.model.mkdir();self.output=self.root/'output';self.output.mkdir()
  (self.model/'config.json').write_text('{"model_type":"qwen3"}')
  (self.model/'tokenizer_config.json').write_text('{}');(self.model/'tokenizer.json').write_text('{}')
  header=json.dumps({'w':{'dtype':'F32','shape':[10],'data_offsets':[0,40]}}).encode()
  (self.model/'model.safetensors').write_bytes(struct.pack('<Q',len(header))+header+b'\0'*40)
  self.data=self.root/'data.jsonl';self.data.write_text('{"text":"An example."}\n{"messages":[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello"}]}\n')
  self.config=dict(StateRoot=str(self.root/'state'),WorkspaceRoot=str(self.root),PythonExecutable=sys.executable,HarnessEntry=__file__,ModelBackend='ollama',ModelId='tiny:local',ModelBaseUrl='http://127.0.0.1:11434/v1')
  self.profile=core.default_profile(self.config);self.profile['training'].update(python=sys.executable,modelPath=str(self.model),datasetPath=str(self.data),outputRoot=str(self.output))
 def tearDown(self):self.temp.cleanup()

 def test_training_needs_explicit_opt_in(self):
  with patch.object(training,'preflight') as check:
   with self.assertRaises(ValueError):training.start(self.config,self.profile)
   check.assert_not_called()

 def test_local_weights_and_schema_preflight(self):
  with patch.object(training,'dependencies',return_value={k:'test' for k in training.DEPENDENCIES}):
   r=training.preflight(self.config,self.profile)
  self.assertTrue(r['ready']);self.assertEqual(r['examples'],2);self.assertEqual(r['model']['storedParameters'],10)
  self.data.write_text('{"messages":[{"role":"tool","content":"untrusted"}]}')
  with self.assertRaises(ValueError):training.read_examples(self.data,10)

 def test_training_rejects_unsupported_or_large_weights(self):
  (self.model/'config.json').write_text('{"model_type":"qwen3_moe"}')
  with self.assertRaises(ValueError):training.inspect_weights(self.model)
  (self.model/'config.json').write_text('{"model_type":"qwen3"}')
  header=json.dumps({'w':{'dtype':'F16','shape':[1300000000],'data_offsets':[0,0]}}).encode()
  (self.model/'model.safetensors').write_bytes(struct.pack('<Q',len(header))+header)
  with self.assertRaises(ValueError):training.inspect_weights(self.model)

 def test_one_training_job_and_profile_owned_stop(self):
  self.profile['allowTraining']=True
  with patch.object(training,'preflight',return_value={'ready':True}),patch.object(training.subprocess,'Popen') as process:
   process.return_value.pid=123;r=training.start(self.config,self.profile)
   self.assertEqual(r['state'],'starting')
   with self.assertRaises(ValueError):training.start(self.config,self.profile)
  training.stop(self.config,self.profile,r['id']);self.assertTrue((training.job_dir(self.config,r['id'])/'STOP').exists())
  with self.assertRaises(ValueError):training.status(self.config,dict(self.profile,id='other'),r['id'])
  self.assertEqual(training.latest(self.config,self.profile)['id'],r['id'])

 def test_android_static_scope_and_manifest(self):
  path=self.root/'app/src/main';path.mkdir(parents=True)
  (path/'AndroidManifest.xml').write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example"><uses-permission android:name="android.permission.CAMERA"/><application><activity android:name="Main" android:exported="false"/></application></manifest>')
  with patch.object(android,'PROJECT',self.root):
   self.assertEqual(android.execute('android_list_modules',{})['modules'],['app'])
   self.assertEqual(android.execute('android_inspect_manifest',{'module':'app'})['package'],'com.example')
   for value in ['../outside','C:/outside','/outside','a\\..\\b']:
    with self.assertRaises(ValueError):android.safe_file(value)
   with self.assertRaises(ValueError):android.execute('android_project_status',{'command':'build'})
   (path/'AndroidManifest.xml').write_text('<!DOCTYPE x><manifest/>')
   with self.assertRaises(ValueError):android.manifest('app')

 def test_android_adb_is_fixed_inventory_and_hides_serial(self):
  requests=[]
  class Handler(socketserver.BaseRequestHandler):
   def handle(self):
    size=int(self.request.recv(4),16);requests.append(self.request.recv(size));body=b'private-serial device product:pixel model:Pixel_7\n'
    self.request.sendall(b'OKAY'+f'{len(body):04x}'.encode()+body)
  with socketserver.TCPServer(('127.0.0.1',0),Handler) as server:
   t=threading.Thread(target=server.handle_request);t.start();r=android.devices(server.server_address[1]);t.join(3)
  self.assertEqual(requests,[b'host:devices-l']);self.assertEqual(r['devices'][0]['model'],'Pixel_7');self.assertNotIn('private-serial',json.dumps(r))

 def test_blender_only_exposes_inspection(self):
  self.assertEqual(len(blender.TOOLS),4)
  with self.assertRaises(ValueError):blender.validate('execute_python',{'code':'anything'})
  with self.assertRaises(ValueError):blender.validate('blender_list_objects',{'limit':True})
  self.assertTrue(all(t['annotations']['readOnlyHint'] for t in blender.TOOLS))

 def test_bundled_workflows_are_available_without_training_permission(self):
  import training_mcp
  guides=training_mcp.execute('workflow_list',{})['guides']
  self.assertEqual(len(guides),8)
  result=training_mcp.execute('workflow_read',{'id':'awx-offline-lora'})
  self.assertEqual(result['license'],'MIT');self.assertIn('LoRA',result['markdown'])
  with self.assertRaises(ValueError):training_mcp.execute('workflow_read',{'id':'../config.local.json'})

 def test_bridge_configs_are_optional_and_training_is_scoped(self):
  with patch.object(core,'port_open',return_value=False):
   state=core.ensure_state(self.config);p=state['profiles'][0];p.update(useAndroid=True,useBlender=True);core.save_profile(self.config,{'profile':p,'revision':state['revision'],'saveAsNew':False})
   result=core.prepare_clients(self.config)
  text=(Path(result['CodexHome'])/'aibrainworx-local.config.toml').read_text(encoding='utf-8')
  self.assertIn('[mcp_servers.android_local]',text);self.assertIn('[mcp_servers.blender_local]',text);self.assertIn('[mcp_servers.awx_training]',text)
  self.assertFalse(core.get_profile(core.ensure_state(self.config))['allowTraining'])


if __name__=='__main__':unittest.main()
