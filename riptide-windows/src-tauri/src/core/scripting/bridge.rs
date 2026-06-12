use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use boa_engine::{
    js_string, object::FunctionObjectBuilder, Context, JsValue, NativeFunction, Source,
};
use serde::{Deserialize, Serialize};

use super::error::ScriptError;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScriptRequest {
    pub url: String,
    pub method: String,
    pub headers: HashMap<String, String>,
    pub body: Option<String>,
    pub id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScriptResponse {
    pub status: u16,
    pub headers: HashMap<String, String>,
    pub body: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScriptResult {
    pub action: ScriptAction,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ScriptAction {
    Modified(ScriptResponse),
    Rejected,
    Passthrough,
}

/// Surge-compatible script bridge. Injects `$request`, `$done`, `$response`,
/// `$persistentStore`, and `$notification` globals into a fresh `boa_engine`
/// context and evaluates a Surge/Loon/Quantumult X script.
pub struct SurgeScriptBridge {
    /// Simple in-memory key-value store backing `$persistentStore`.
    store: Arc<Mutex<HashMap<String, String>>>,
}

impl SurgeScriptBridge {
    pub fn new() -> Self {
        Self {
            store: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Evaluate a Surge-style HTTP request script.
    /// The script receives `$request` and may call `$done({response:{…}})`
    /// to modify or reject the request.
    pub fn evaluate_request_script(
        &self,
        script: &str,
        request: ScriptRequest,
    ) -> Result<ScriptResult, ScriptError> {
        let mut ctx = Context::default();

        // Shared cell for the $done result
        let done_result: Arc<Mutex<Option<ScriptResult>>> = Arc::new(Mutex::new(None));

        // Inject $request
        self.inject_request(&mut ctx, &request)?;

        // Inject $done
        self.inject_done_request(&mut ctx, done_result.clone())?;

        // Inject $persistentStore
        self.inject_persistent_store(&mut ctx)?;

        // Inject $notification (no-op on Windows)
        self.inject_notification(&mut ctx)?;

        // Execute the script
        ctx.eval(Source::from_bytes(script.as_bytes()))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        // Check if $done was called
        let result = done_result
            .lock()
            .map_err(|_| ScriptError::RuntimeError("lock poisoned".into()))?;
        Ok(result.clone().unwrap_or(ScriptResult {
            action: ScriptAction::Passthrough,
        }))
    }

    /// Evaluate a Surge-style HTTP response script.
    /// The script receives `$request` + `$response` and may call `$done()`.
    pub fn evaluate_response_script(
        &self,
        script: &str,
        request: ScriptRequest,
        response: ScriptResponse,
    ) -> Result<ScriptResult, ScriptError> {
        let mut ctx = Context::default();

        let done_result: Arc<Mutex<Option<ScriptResult>>> = Arc::new(Mutex::new(None));

        // Inject $request
        self.inject_request(&mut ctx, &request)?;

        // Inject $response
        self.inject_response(&mut ctx, &response)?;

        // Inject $done
        self.inject_done_response(&mut ctx, done_result.clone(), response.clone())?;

        // Inject $persistentStore
        self.inject_persistent_store(&mut ctx)?;

        // Inject $notification (no-op on Windows)
        self.inject_notification(&mut ctx)?;

        // Execute the script
        ctx.eval(Source::from_bytes(script.as_bytes()))
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        let result = done_result
            .lock()
            .map_err(|_| ScriptError::RuntimeError("lock poisoned".into()))?;
        Ok(result.clone().unwrap_or(ScriptResult {
            action: ScriptAction::Passthrough,
        }))
    }

    // ── Private injection helpers ────────────────────────────────────────

    fn inject_request(
        &self,
        ctx: &mut Context,
        request: &ScriptRequest,
    ) -> Result<(), ScriptError> {
        let obj = boa_engine::JsObject::with_null_proto();
        obj.set(js_string!("url"), JsValue::from(js_string!(request.url.as_str())), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
        obj.set(js_string!("method"), JsValue::from(js_string!(request.method.as_str())), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
        obj.set(js_string!("body"), JsValue::from(js_string!(request.body.as_deref().unwrap_or(""))), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
        obj.set(js_string!("id"), JsValue::from(js_string!(request.id.as_str())), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        // Headers as nested object
        let headers_obj = self.hashmap_to_js_object(ctx, &request.headers)?;
        obj.set(js_string!("headers"), headers_obj, true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        ctx.register_global_property(
            js_string!("$request"),
            JsValue::from(obj),
            boa_engine::property::Attribute::all(),
        );
        Ok(())
    }

    fn inject_response(
        &self,
        ctx: &mut Context,
        response: &ScriptResponse,
    ) -> Result<(), ScriptError> {
        let obj = boa_engine::JsObject::with_null_proto();
        obj.set(js_string!("status"), JsValue::from(response.status as i32), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
        obj.set(js_string!("body"), JsValue::from(js_string!(response.body.as_deref().unwrap_or(""))), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        let headers_obj = self.hashmap_to_js_object(ctx, &response.headers)?;
        obj.set(js_string!("headers"), headers_obj, true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        ctx.register_global_property(
            js_string!("$response"),
            JsValue::from(obj),
            boa_engine::property::Attribute::all(),
        );
        Ok(())
    }

    /// Inject `$done` for a request script.
    /// When called with `{response:{status,headers,body}}` → Modified.
    /// When called with no args or `undefined` → Rejected.
    fn inject_done_request(
        &self,
        ctx: &mut Context,
        result_cell: Arc<Mutex<Option<ScriptResult>>>,
    ) -> Result<(), ScriptError> {
        let cell = result_cell.clone();
        // SAFETY: The closure captures only `Arc<Mutex<...>>` which is not
        // GC-traced. No JS objects are captured, so the GC cannot corrupt
        // the closure state.
        let done_fn = unsafe {
            NativeFunction::from_closure(move |_this, args, ctx| {
                let action = if let Some(JsValue::Object(obj)) = args.first() {
                    // Check for $done({response:{status,headers,body}})
                    let response_val = obj
                        .get(js_string!("response"), ctx)
                        .unwrap_or(JsValue::undefined());
                    if let JsValue::Object(resp_obj) = response_val {
                        let status = resp_obj
                            .get(js_string!("status"), ctx)
                            .ok()
                            .and_then(|v| v.as_number())
                            .map(|n| n as u16)
                            .unwrap_or(200);
                        let headers = js_object_to_hashmap(ctx, &resp_obj).unwrap_or_default();
                        let body = resp_obj
                            .get(js_string!("body"), ctx)
                            .ok()
                            .and_then(|v| v.as_string().and_then(|s| s.to_std_string().ok()));
                        ScriptAction::Modified(ScriptResponse {
                            status,
                            headers,
                            body,
                        })
                    } else {
                        ScriptAction::Rejected
                    }
                } else {
                    ScriptAction::Rejected
                };

                if let Ok(mut slot) = cell.lock() {
                    *slot = Some(ScriptResult { action });
                }
                Ok(JsValue::undefined())
            })
        };
        let done_js_fn = FunctionObjectBuilder::new(ctx, done_fn).build();
        ctx.register_global_property(
            js_string!("$done"),
            JsValue::from(done_js_fn),
            boa_engine::property::Attribute::all(),
        );
        Ok(())
    }

    /// Inject `$done` for a response script.
    /// When called with modified response fields → Modified.
    /// When called with no args → Passthrough.
    fn inject_done_response(
        &self,
        ctx: &mut Context,
        result_cell: Arc<Mutex<Option<ScriptResult>>>,
        original: ScriptResponse,
    ) -> Result<(), ScriptError> {
        let cell = result_cell.clone();
        // SAFETY: Same as inject_done_request — captures only Arc<Mutex<..>>.
        let done_fn = unsafe {
            NativeFunction::from_closure(move |_this, args, ctx| {
                let action = if let Some(JsValue::Object(obj)) = args.first() {
                    let status = obj
                        .get(js_string!("status"), ctx)
                        .ok()
                        .and_then(|v| v.as_number())
                        .map(|n| n as u16)
                        .unwrap_or(original.status);
                    let headers = js_object_to_hashmap(ctx, obj)
                        .ok()
                        .filter(|h| !h.is_empty())
                        .unwrap_or_else(|| original.headers.clone());
                    let body = obj
                        .get(js_string!("body"), ctx)
                        .ok()
                        .and_then(|v| v.as_string().and_then(|s| s.to_std_string().ok()))
                        .or_else(|| original.body.clone());
                    ScriptAction::Modified(ScriptResponse {
                        status,
                        headers,
                        body,
                    })
                } else {
                    ScriptAction::Passthrough
                };

                if let Ok(mut slot) = cell.lock() {
                    *slot = Some(ScriptResult { action });
                }
                Ok(JsValue::undefined())
            })
        };
        let done_js_fn = FunctionObjectBuilder::new(ctx, done_fn).build();
        ctx.register_global_property(
            js_string!("$done"),
            JsValue::from(done_js_fn),
            boa_engine::property::Attribute::all(),
        );
        Ok(())
    }

    fn inject_persistent_store(&self, ctx: &mut Context) -> Result<(), ScriptError> {
        let store = self.store.clone();

        let read_fn = {
            let store = store.clone();
            // SAFETY: captures only Arc<Mutex<..>>.
            unsafe {
                NativeFunction::from_closure(move |_this, args, _ctx| {
                    let key = args
                        .first()
                        .and_then(|v| v.as_string())
                        .and_then(|s| s.to_std_string().ok())
                        .unwrap_or_default();
                    let value = store
                        .lock()
                        .ok()
                        .and_then(|m| m.get(&key).cloned())
                        .map(|s| JsValue::from(js_string!(s.as_str())))
                        .unwrap_or(JsValue::null());
                    Ok(value)
                })
            }
        };

        // SAFETY: captures only Arc<Mutex<..>>.
        let write_fn = unsafe {
            NativeFunction::from_closure(move |_this, args, _ctx| {
                let key = args
                    .first()
                    .and_then(|v| v.as_string())
                    .and_then(|s| s.to_std_string().ok())
                    .unwrap_or_default();
                let value = args
                    .get(1)
                    .and_then(|v| v.as_string())
                    .and_then(|s| s.to_std_string().ok())
                    .unwrap_or_default();
                if let Ok(mut m) = store.lock() {
                    m.insert(key, value);
                }
                Ok(JsValue::undefined())
            })
        };

        let store_obj = boa_engine::JsObject::with_null_proto();
        let read_js_fn = FunctionObjectBuilder::new(ctx, read_fn).build();
        store_obj
            .set(js_string!("read"), JsValue::from(read_js_fn), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
        let write_js_fn = FunctionObjectBuilder::new(ctx, write_fn).build();
        store_obj
            .set(js_string!("write"), JsValue::from(write_js_fn), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        ctx.register_global_property(
            js_string!("$persistentStore"),
            JsValue::from(store_obj),
            boa_engine::property::Attribute::all(),
        );
        Ok(())
    }

    fn inject_notification(&self, ctx: &mut Context) -> Result<(), ScriptError> {
        // No-op on Windows — real notifications go through the Tauri plugin
        // SAFETY: no captures.
        let post_fn = unsafe {
            NativeFunction::from_closure(|_this, _args, _ctx| Ok(JsValue::undefined()))
        };

        let notif_obj = boa_engine::JsObject::with_null_proto();
        let post_js_fn = FunctionObjectBuilder::new(ctx, post_fn).build();
        notif_obj
            .set(js_string!("post"), JsValue::from(post_js_fn), true, ctx)
            .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

        ctx.register_global_property(
            js_string!("$notification"),
            JsValue::from(notif_obj),
            boa_engine::property::Attribute::all(),
        );
        Ok(())
    }

    fn hashmap_to_js_object(
        &self,
        ctx: &mut Context,
        map: &HashMap<String, String>,
    ) -> Result<boa_engine::JsObject, ScriptError> {
        let obj = boa_engine::JsObject::with_null_proto();
        for (k, v) in map {
            obj.set(js_string!(k.as_str()), JsValue::from(js_string!(v.as_str())), true, ctx)
                .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
        }
        Ok(obj)
    }
}

/// Extract a `HashMap<String, String>` from a JS object's enumerable own properties.
fn js_object_to_hashmap(
    ctx: &mut Context,
    obj: &boa_engine::JsObject,
) -> Result<HashMap<String, String>, ScriptError> {
    // boa_engine 0.17 removed `JsObject::own_property_keys`. Use the JS
    // `Object.keys()` builtin instead, which returns the same set of
    // enumerable own property names.
    let keys_value = ctx
        .eval(Source::from_bytes(
            b"(function(o){return Object.keys(o);})",
        ))
        .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
    let keys_fn = keys_value
        .as_object()
        .ok_or_else(|| ScriptError::RuntimeError("Object.keys wrapper missing".into()))?
        .clone();

    let result = keys_fn
        .call(&JsValue::undefined(), &[JsValue::from(obj.clone())], ctx)
        .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;

    let mut map = HashMap::new();
    if let Some(keys_array) = result.as_object() {
        let length = keys_array
            .get(js_string!("length"), ctx)
            .ok()
            .and_then(|v| v.as_number())
            .unwrap_or(0.0) as usize;
        for i in 0..length {
            let key_val = keys_array
                .get(i, ctx)
                .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
            let Some(k) = key_val.as_string() else { continue };
            let Ok(k_std) = k.to_std_string() else { continue };
            let v = obj
                .get(k.clone(), ctx)
                .map_err(|e| ScriptError::RuntimeError(e.to_string()))?;
            if let Ok(v_str) = v.to_string(ctx) {
                if let Ok(v_std) = v_str.to_std_string() {
                    map.insert(k_std, v_std);
                }
            }
        }
    }
    Ok(map)
}
