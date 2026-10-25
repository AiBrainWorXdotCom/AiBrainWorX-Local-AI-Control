# SPDX-License-Identifier: MIT
"""Original optional Blender add-on. Install/enable manually; localhost only."""
bl_info={'name':'AiBrainWorX Inspection Bridge','author':'AiBrainWorX','version':(0,1,0),'blender':(4,0,0),'location':'3D View > Sidebar > AiBrainWorX','description':'Bounded read-only scene inspection for local coding clients','category':'Development'}
import bpy
import json,queue,socket,threading
from pathlib import Path

_server=None
_thread=None
_stop=threading.Event()
_requests=queue.Queue(maxsize=16)
_ALLOWED={'blender_project_status','blender_list_objects','blender_inspect_object','blender_render_settings'}


def inspect(request):
    name=request.get('tool');args=request.get('arguments') or {}
    if request.get('service')!='aibrainworx-blender' or name not in _ALLOWED or not isinstance(args,dict):raise ValueError()
    properties={'query','limit'} if name=='blender_list_objects' else {'name'} if name=='blender_inspect_object' else set()
    if set(args)-properties:raise ValueError()
    for key,value in args.items():
        if key=='limit':
            if type(value) is not int or not 1<=value<=100:raise ValueError()
        elif not isinstance(value,str) or len(value)>160:raise ValueError()
    scene=bpy.context.scene
    if name=='blender_project_status':return {'version':bpy.app.version_string,'scene':scene.name,'objects':len(scene.objects),'file':Path(bpy.data.filepath).name if bpy.data.filepath else None,'read_only':True}
    if name=='blender_list_objects':
        query=args.get('query','').casefold();result=[]
        for obj in scene.objects:
            if query in obj.name.casefold():result.append({'name':obj.name,'type':obj.type})
            if len(result)>=args.get('limit',50):break
        return {'objects':result}
    if name=='blender_inspect_object':
        obj=scene.objects.get(args.get('name',''))
        if obj is None:raise ValueError()
        result={'name':obj.name,'type':obj.type,'location':list(obj.location),'rotationEuler':list(obj.rotation_euler),'scale':list(obj.scale),'dimensions':list(obj.dimensions)}
        if obj.type=='MESH':result.update(vertices=len(obj.data.vertices),edges=len(obj.data.edges),polygons=len(obj.data.polygons))
        return result
    return {'engine':scene.render.engine,'resolution':[scene.render.resolution_x,scene.render.resolution_y],'scalePercent':scene.render.resolution_percentage,'camera':scene.camera.name if scene.camera else None}


def pump():
    for _ in range(8):
        try:job=_requests.get_nowait()
        except queue.Empty:break
        if job['expired']:job['event'].set();continue
        try:job['reply']={'service':'aibrainworx-blender','result':inspect(job['request'])}
        except Exception:job['reply']={'service':'aibrainworx-blender','error':'Invalid or unavailable scene inspection.'}
        job['event'].set()
    return .1 if not _stop.is_set() else None


def serve(server):
    while not _stop.is_set():
        try:connection,_=server.accept()
        except socket.timeout:continue
        except OSError:return
        with connection:
            try:
                connection.settimeout(2)
                with connection.makefile('rb') as stream:raw=stream.readline(65537)
                if len(raw)>65536:raise ValueError()
                job={'request':json.loads(raw),'event':threading.Event(),'reply':None,'expired':False};_requests.put_nowait(job)
                if not job['event'].wait(4):job['expired']=True;raise ValueError()
                data=json.dumps(job['reply']).encode()
                if len(data)>512*1024:raise ValueError()
                connection.sendall(data+b'\n')
            except (OSError,ValueError,queue.Full):
                try:connection.sendall(b'{"service":"aibrainworx-blender","error":"Inspection unavailable"}\n')
                except OSError:pass


def start():
    global _server,_thread
    if _server:return
    server=socket.socket();server.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    try:server.bind(('127.0.0.1',9877));server.listen(4);server.settimeout(.3)
    except Exception:server.close();raise
    _stop.clear();_server=server
    if not bpy.app.timers.is_registered(pump):bpy.app.timers.register(pump,first_interval=.1,persistent=True)
    _thread=threading.Thread(target=serve,args=(server,),daemon=True);_thread.start()


def stop():
    global _server,_thread
    _stop.set()
    if _server:_server.close()
    if _thread:_thread.join(timeout=1)
    _server=None;_thread=None
    if bpy.app.timers.is_registered(pump):bpy.app.timers.unregister(pump)
    while not _requests.empty():
        try:job=_requests.get_nowait();job['expired']=True;job['event'].set()
        except queue.Empty:break


class AWX_OT_start(bpy.types.Operator):
    bl_idname='awx.start_inspection_bridge';bl_label='Start inspection bridge'
    def execute(self,context):
        try:start();return {'FINISHED'}
        except OSError:self.report({'ERROR'},'Loopback port 9877 is unavailable.');return {'CANCELLED'}


class AWX_OT_stop(bpy.types.Operator):
    bl_idname='awx.stop_inspection_bridge';bl_label='Stop inspection bridge'
    def execute(self,context):stop();return {'FINISHED'}


class AWX_PT_bridge(bpy.types.Panel):
    bl_label='AiBrainWorX';bl_idname='AWX_PT_inspection_bridge';bl_space_type='VIEW_3D';bl_region_type='UI';bl_category='AiBrainWorX'
    def draw(self,context):
        self.layout.label(text='Read-only / localhost only')
        self.layout.label(text='Running on 9877' if _server else 'Stopped')
        self.layout.operator('awx.stop_inspection_bridge' if _server else 'awx.start_inspection_bridge')


CLASSES=(AWX_OT_start,AWX_OT_stop,AWX_PT_bridge)
def register():
    for cls in CLASSES:bpy.utils.register_class(cls)
def unregister():
    stop()
    for cls in reversed(CLASSES):bpy.utils.unregister_class(cls)
