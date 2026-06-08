use tauri::State;
use tauri::State;

use crate::core::scripting::engine::{ScriptContext, ScriptEngine, ScriptType};

#[tauri::command]
pub fn script_eval(
    engine: State<'_, ScriptEngine>,
    code: String,
    context: Option<String>,
) -> Result<String, String> {
    let name = context.unwrap_or_else(|| format!("eval-{}", uuid::Uuid::new_v4()));
    engine
        .load_script(ScriptContext {
            name: name.clone(),
            source: code,
            script_type: ScriptType::RequestModify,
        })
        .map_err(|e| e.to_string())?;
    Ok(name)
}

#[tauri::command]
pub fn script_list_loaded(engine: State<'_, ScriptEngine>) -> Vec<String> {
    engine.list_scripts()
}

#[tauri::command]
pub fn script_unload(engine: State<'_, ScriptEngine>, name: String) -> Result<(), String> {
    engine.unload_script(&name);
    Ok(())
}
