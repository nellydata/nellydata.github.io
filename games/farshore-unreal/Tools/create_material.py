import unreal

asset_path = "/Game/Farshore/M_FarshoreTint"
if unreal.EditorAssetLibrary.does_asset_exist(asset_path):
    raise RuntimeError("Tint material already exists; refusing to overwrite it")

tools = unreal.AssetToolsHelpers.get_asset_tools()
material = tools.create_asset(
    "M_FarshoreTint", "/Game/Farshore", unreal.Material, unreal.MaterialFactoryNew()
)
if not material:
    raise RuntimeError("Failed to create tint material")
expression = unreal.MaterialEditingLibrary.create_material_expression(
    material, unreal.MaterialExpressionVectorParameter, -300, 0
)
expression.set_editor_property("parameter_name", "Color")
expression.set_editor_property("default_value", unreal.LinearColor(1, 1, 1, 1))
if not unreal.MaterialEditingLibrary.connect_material_property(
    expression, "", unreal.MaterialProperty.MP_BASE_COLOR
):
    raise RuntimeError("Failed to connect tint parameter")
unreal.MaterialEditingLibrary.recompile_material(material)
if not unreal.EditorAssetLibrary.save_loaded_asset(material):
    raise RuntimeError("Failed to save tint material")
unreal.log("FARSHORE_MATERIAL_CREATED")
