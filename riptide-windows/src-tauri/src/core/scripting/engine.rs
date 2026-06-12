use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use boa_engine::{js_string, Context, JsValue, Source};
use serde::{Deserialize, Serialize};

use super::error::ScriptError;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScriptContext {
    pub name: String,
    pub source: String,
    pub script_type: ScriptType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ScriptType {
    RequestModify,
    ResponseModify,
    RuleProvider,
    ProfileScript,
}

/// Stored script metadata. The JS runtime (`boa_engine::Context`) is `!Send`,
/// so we keep only the source text and compile fresh on each execution.
/// This matches the macOS actor pattern where each call runs on the actor's
/// serial executor — here each call gets its own `Context`.
struct StoredScript {
    source: String,
    script_type: ScriptType,
}

pub struct ScriptEngine {
    scripts: Arc<Mutex<HashMap<String, StoredScript>>>,
}

impl ScriptEngine {
    pub fn new() -> Self {
        Self {
            scripts: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Load (compile) a script. Returns the script name on success.
    pub fn load_script(&self, ctx: ScriptContext) -> Result<String, ScriptError> {
        // Compile to verify syntax
        let mut js_ctx = Context::default();
        js_ctx
            .eval(Source::from_bytes(ctx.source.as_bytes()))
            .map_err(|e| ScriptError::CompilationFailed(e.to_string()))?;

        let mut scripts = self
            .scripts
            .lock()
            .map_err(|_| ScriptError::RuntimeError("lock poisoned".into()))?;
        scripts.insert(
            ctx.name.clone(),
            StoredScript {
                source: ctx.source,
                script_type: ctx.script_type,
            },
        );
        Ok(ctx.name)
    }

    /// Execute a request-modify script. Injects `request` as a global JS object
    /// and calls `handleRequestModify(request)`. Returns modified headers or
    /// the originals if the script does not modify them.
    pub fn execute_request_modify(
        &self,
        script_name: &str,
        headers: HashMap<String, String>,
    ) -> Result<HashMap<String, String>, ScriptError> {
        let source = {
            let scripts = self
                .scripts
                .lock()
                .map_err(|_| ScriptError::RuntimeError("lock poisoned".into()))?;
            let stored = scripts
                .get(script_name)
                .ok_or_else(|| ScriptError::RuntimeError(format!("script not loaded: {script_name}")))?;
            stored.source.clone()
        };

        let mut ctx = Context::default();

        // Inject `request` as a global object with the headers
        let request_obj = boa_engine::JsObject::with_null_proto();
        for (k, v) in &headers {
            request_obj
                .set(js_string!(k.as_str()), JsValue::from(js_string!(v.as_str())), true, &mut ctx)
                .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
        }
        ctx.register_global_property(js_string!("request"), request_obj, boa_engine::property::Attribute::all());

        // Compile and execute the script
        ctx.eval(Source::from_bytes(source.as_bytes()))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        // Call handleRequestModify(request)
        let result = ctx
            .eval(Source::from_bytes(b"handleRequestModify(request)"))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        // Extract result as HashMap
        match result {
            JsValue::Object(obj) => {
                let mut output = HashMap::new();
                // boa 0.17 removed JsObject::own_property_keys.
                // Use Object.keys() via JS eval to get enumerable own property names.
                let keys_fn = ctx
                    .eval(Source::from_bytes(
                        b"(function(o){return Object.keys(o);})",
                    ))
                    .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
                let keys_callable = keys_fn
                    .as_object()
                    .ok_or_else(|| {
                        ScriptError::RuntimeError("Object.keys wrapper missing".into())
                    })?
                    .clone();
                let keys_result = keys_callable
                    .call(&JsValue::undefined(), &[JsValue::from(obj.clone())], &mut ctx)
                    .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
                if let Some(keys_array) = keys_result.as_object() {
                    let length = keys_array
                        .get(js_string!("length"), &mut ctx)
                        .ok()
                        .and_then(|v| v.as_number())
                        .unwrap_or(0.0) as usize;
                    for i in 0..length {
                        let key_val = keys_array
                            .get(i, &mut ctx)
                            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
                        let Some(js_str) = key_val.as_string() else { continue };
                        let Ok(key_str) = js_str.to_std_string() else { continue };
                        let val = obj
                            .get(js_str, &mut ctx)
                            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
                        if let Ok(val_jsstr) = val.to_string(&mut ctx) {
                            output.insert(key_str, val_jsstr.to_std_string().unwrap_or_default());
                        }
                    }
                }
                if output.is_empty() {
                    Ok(headers)
                } else {
                    Ok(output)
                }
            }
            _ => Ok(headers),
        }
    }

    /// Execute a response-modify script. Injects `response` as a global JS
    /// object and calls `handleResponseModify(response)`.
    pub fn execute_response_modify(
        &self,
        script_name: &str,
        response_body: &str,
    ) -> Result<String, ScriptError> {
        let source = {
            let scripts = self
                .scripts
                .lock()
                .map_err(|_| ScriptError::RuntimeError("lock poisoned".into()))?;
            let stored = scripts
                .get(script_name)
                .ok_or_else(|| ScriptError::RuntimeError(format!("script not loaded: {script_name}")))?;
            stored.source.clone()
        };

        let mut ctx = Context::default();

        // Inject `response` as a global string
        ctx.register_global_property(
            js_string!("response"),
            JsValue::from(js_string!(response_body)),
            boa_engine::property::Attribute::all(),
        );

        // Compile and execute the script
        ctx.eval(Source::from_bytes(source.as_bytes()))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        // Call handleResponseModify(response)
        let result = ctx
            .eval(Source::from_bytes(b"handleResponseModify(response)"))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        match result.to_string(&mut ctx) {
            Ok(js_str) => Ok(js_str.to_std_string().unwrap_or_default()),
            Err(_) => Ok(response_body.to_string()),
        }
    }

    /// Execute a profile transformation script.
    /// The script should define a `transform(config)` function.
    pub fn execute_profile_script(
        &self,
        script_name: &str,
        config_json: &str,
    ) -> Result<String, ScriptError> {
        let source = {
            let scripts = self
                .scripts
                .lock()
                .map_err(|_| ScriptError::RuntimeError("lock poisoned".into()))?;
            let stored = scripts
                .get(script_name)
                .ok_or_else(|| ScriptError::RuntimeError(format!("script not loaded: {script_name}")))?;
            stored.source.clone()
        };

        let mut ctx = Context::default();

        // Parse config JSON and set as global
        let escaped = serde_json::to_string(config_json)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
        let parse_code = format!("var config = JSON.parse({escaped});");
        ctx.eval(Source::from_bytes(parse_code.as_bytes()))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        // Compile and execute the user script
        ctx.eval(Source::from_bytes(source.as_bytes()))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        // Call transform(config)
        let result = ctx
            .eval(Source::from_bytes(b"JSON.stringify(transform(config))"))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        result
            .to_string(&mut ctx)
            .map(|s| s.to_std_string().unwrap_or_default())
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))
    }

    pub fn unload_script(&self, name: &str) {
        if let Ok(mut scripts) = self.scripts.lock() {
            scripts.remove(name);
        }
    }

    pub fn list_scripts(&self) -> Vec<String> {
        self.scripts
            .lock()
            .map(|s| s.keys().cloned().collect())
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_engine() -> ScriptEngine {
        ScriptEngine::new()
    }

    #[test]
    fn load_script_compiles_valid_js() {
        let engine = make_engine();
        let ctx = ScriptContext {
            name: "test1".into(),
            source: "function handleRequestModify(r) { return r; }".into(),
            script_type: ScriptType::RequestModify,
        };
        let name = engine.load_script(ctx).unwrap();
        assert_eq!(name, "test1");
    }

    #[test]
    fn load_script_rejects_invalid_js() {
        let engine = make_engine();
        let ctx = ScriptContext {
            name: "bad".into(),
            source: "function {{{ invalid".into(),
            script_type: ScriptType::RequestModify,
        };
        let err = engine.load_script(ctx).unwrap_err();
        assert!(
            matches!(err, ScriptError::CompilationFailed(_)),
            "expected CompilationFailed, got: {err:?}"
        );
    }

    #[test]
    fn execute_request_modify_returns_modified_headers() {
        let engine = make_engine();
        engine
            .load_script(ScriptContext {
                name: "mod".into(),
                source: r#"
                    function handleRequestModify(request) {
                        request["X-Injected"] = "yes";
                        return request;
                    }
                "#
                .into(),
                script_type: ScriptType::RequestModify,
            })
            .unwrap();

        let mut headers = HashMap::new();
        headers.insert("Accept".into(), "text/html".into());

        let result = engine.execute_request_modify("mod", headers).unwrap();
        assert_eq!(result.get("X-Injected").unwrap(), "yes");
        assert_eq!(result.get("Accept").unwrap(), "text/html");
    }

    #[test]
    fn execute_request_modify_returns_original_on_no_change() {
        let engine = make_engine();
        engine
            .load_script(ScriptContext {
                name: "noop".into(),
                source: r#"
                    function handleRequestModify(request) {
                        return request;
                    }
                "#
                .into(),
                script_type: ScriptType::RequestModify,
            })
            .unwrap();

        let mut headers = HashMap::new();
        headers.insert("Accept".into(), "text/html".into());

        let result = engine.execute_request_modify("noop", headers.clone()).unwrap();
        assert_eq!(result, headers);
    }

    #[test]
    fn execute_response_modify_returns_modified_body() {
        let engine = make_engine();
        engine
            .load_script(ScriptContext {
                name: "resmod".into(),
                source: r#"
                    function handleResponseModify(response) {
                        return response + " (modified)";
                    }
                "#
                .into(),
                script_type: ScriptType::ResponseModify,
            })
            .unwrap();

        let result = engine
            .execute_response_modify("resmod", "original body")
            .unwrap();
        assert_eq!(result, "original body (modified)");
    }

    #[test]
    fn unload_script_removes_context() {
        let engine = make_engine();
        engine
            .load_script(ScriptContext {
                name: "temp".into(),
                source: "var x = 1;".into(),
                script_type: ScriptType::RequestModify,
            })
            .unwrap();

        assert!(engine.list_scripts().contains(&"temp".to_string()));
        engine.unload_script("temp");
        assert!(!engine.list_scripts().contains(&"temp".to_string()));
    }

    #[test]
    fn list_scripts_returns_loaded_names() {
        let engine = make_engine();
        engine
            .load_script(ScriptContext {
                name: "a".into(),
                source: "var x = 1;".into(),
                script_type: ScriptType::RequestModify,
            })
            .unwrap();
        engine
            .load_script(ScriptContext {
                name: "b".into(),
                source: "var y = 2;".into(),
                script_type: ScriptType::ResponseModify,
            })
            .unwrap();

        let mut names = engine.list_scripts();
        names.sort();
        assert_eq!(names, vec!["a", "b"]);
    }

    #[test]
    fn surge_bridge_evaluate_request_passthrough() {
        let bridge = super::super::bridge::SurgeScriptBridge::new();
        let request = super::super::bridge::ScriptRequest {
            url: "https://example.com".into(),
            method: "GET".into(),
            headers: HashMap::new(),
            body: None,
            id: "test-id".into(),
        };
        // Script that never calls $done → passthrough
        let script = r#"var x = 1 + 1;"#;

        let result = bridge
            .evaluate_request_script(script, request)
            .unwrap();
        assert!(
            matches!(result.action, super::super::bridge::ScriptAction::Passthrough),
            "expected Passthrough, got {:?}",
            result.action
        );
    }
}
