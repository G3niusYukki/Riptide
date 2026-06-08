use thiserror::Error;

#[derive(Debug, Error)]
pub enum ScriptError {
    #[error("script compilation failed: {0}")]
    CompilationFailed(String),
    #[error("script runtime error: {0}")]
    RuntimeError(String),
    #[error("context creation failed")]
    ContextCreationFailed,
}
