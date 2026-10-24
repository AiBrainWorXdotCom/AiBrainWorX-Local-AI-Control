"""Fixed editor-side read operations. Executed on Unreal's Python/game thread."""
def run(request):
    import unreal

    name = request["tool"]
    arguments = request["arguments"]
    editor = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    world = editor.get_editor_world()
    assert world, 'No editor world available'

    def vector(v):
        return [v.x, v.y, v.z]

    def brief(actor):
        rotation = actor.get_actor_rotation()
        return dict(label=actor.get_actor_label(), path=actor.get_path_name(), cls=actor.get_class().get_name(),
                    location=vector(actor.get_actor_location()), rotation=[rotation.pitch, rotation.yaw, rotation.roll],
                    scale=vector(actor.get_actor_scale3d()), folder=str(actor.get_folder_path()))

    if name == 'unreal_get_selection':
        return dict(map=world.get_path_name(), actors=[brief(a) for a in actors.get_selected_level_actors()][:200])
    if name == 'unreal_list_actors':
        query = arguments.get('query', '').casefold()
        matching = [a for a in actors.get_all_level_actors()
                    if query in a.get_actor_label().casefold() or query in a.get_class().get_name().casefold()]
        return dict(map=world.get_path_name(), total=len(matching), actors=[brief(a) for a in matching[:arguments.get('limit', 50)]])
    if name == 'unreal_inspect_actor':
        matching = [a for a in actors.get_all_level_actors() if a.get_actor_label() == arguments['label']]
        assert len(matching) == 1, 'Actor label is missing or ambiguous; list actors first'
        actor = matching[0]
        result = brief(actor)
        center, extent = actor.get_actor_bounds(False)
        result['bounds'] = dict(center=vector(center), extent=vector(extent))
        result['components'] = []
        for component in actor.get_components_by_class(unreal.StaticMeshComponent)[:60]:
            result['components'].append(dict(name=component.get_name(), mesh=component.static_mesh.get_path_name() if component.static_mesh else None,
                collision=str(component.get_collision_enabled()), profile=str(component.get_collision_profile_name()),
                instance_count=component.get_instance_count() if isinstance(component, unreal.InstancedStaticMeshComponent) else 1))
        return result
    if name == 'unreal_find_assets':
        query = arguments.get('query', '').casefold()
        registry = unreal.AssetRegistryHelpers.get_asset_registry()
        limit = arguments.get('limit', 50)
        matches = []
        total = 0
        for asset in registry.get_assets_by_path(unreal.Name(arguments.get('folder', '/Game')), recursive=True):
            if query not in str(asset.asset_name).casefold():
                continue
            total += 1
            if len(matches) < limit:
                matches.append(dict(name=str(asset.asset_name), package=str(asset.package_name), cls=str(asset.asset_class_path)))
        return dict(total=total, assets=matches)
    raise ValueError('Unsupported read-only Unreal operation')


import json
print('DK_UNREAL_READ_RESULT:' + json.dumps(run(request)))
