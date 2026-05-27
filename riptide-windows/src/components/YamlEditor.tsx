import { useRef, useEffect } from 'react';
import { EditorView, basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { yaml } from '@codemirror/lang-yaml';
import { linter, type Diagnostic } from '@codemirror/lint';
import * as YAML from 'yaml';

export interface YamlEditorProps {
  value: string;
  onChange: (value: string) => void;
  readOnly?: boolean;
  height?: string;
  className?: string;
}

type YamlParseError = Error & {
  pos?: [number, number];
};

// YAML linter that checks for syntax errors
const yamlLinter = linter((view) => {
  const diagnostics: Diagnostic[] = [];
  const doc = view.state.doc.toString();

  if (doc.trim()) {
    try {
      YAML.parse(doc);
    } catch (error) {
      const yamlError = error as YamlParseError;
      if (yamlError.pos) {
        const from = Math.min(yamlError.pos[0], doc.length);
        const to = Math.min(yamlError.pos[1] || from + 1, doc.length);
        diagnostics.push({
          from,
          to,
          severity: 'error',
          message: yamlError.message,
        });
      }
    }
  }

  return diagnostics;
});

// Dark theme for CodeMirror
const darkTheme = EditorView.theme({
  '&': {
    backgroundColor: 'var(--code-bg)',
    color: 'var(--code-text)',
  },
  '.cm-content': {
    caretColor: 'var(--accent-primary)',
    fontFamily: "'Cascadia Code', 'Fira Code', 'Consolas', monospace",
  },
  '.cm-cursor, .cm-dropCursor': {
    borderLeftColor: 'var(--accent-primary)',
  },
  '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection': {
    backgroundColor: 'var(--code-selection)',
  },
  '.cm-panels': {
    backgroundColor: 'var(--bg-secondary)',
    color: 'var(--text-primary)',
  },
  '.cm-panels.cm-panels-top': {
    borderBottom: '1px solid var(--border-primary)',
  },
  '.cm-panels.cm-panels-bottom': {
    borderTop: '1px solid var(--border-primary)',
  },
  '.cm-searchMatch': {
    backgroundColor: 'var(--accent-bg)',
    outline: '1px solid var(--accent-primary)',
  },
  '.cm-searchMatch.cm-searchMatch-selected': {
    backgroundColor: 'var(--success-bg)',
  },
  '.cm-activeLine': {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
  },
  '.cm-selectionMatch': {
    backgroundColor: 'var(--accent-bg)',
  },
  '&.cm-focused .cm-matchingBracket, &.cm-focused .cm-nonmatchingBracket': {
    backgroundColor: 'var(--warning-bg)',
    outline: '1px solid var(--warning)',
  },
  '.cm-gutters': {
    backgroundColor: 'var(--code-bg)',
    color: 'var(--code-line-number)',
    border: 'none',
    borderRight: '1px solid var(--border-primary)',
  },
  '.cm-activeLineGutter': {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
  },
  '.cm-foldPlaceholder': {
    backgroundColor: 'var(--accent-bg)',
    color: 'var(--accent-primary)',
    border: '1px solid var(--accent-primary)',
  },
  '.cm-tooltip': {
    backgroundColor: 'var(--bg-elevated)',
    color: 'var(--text-primary)',
    border: '1px solid var(--border-primary)',
  },
  '.cm-tooltip .cm-tooltip-arrow:before': {
    borderTopColor: 'var(--border-primary)',
    borderBottomColor: 'var(--border-primary)',
  },
  '.cm-tooltip .cm-tooltip-arrow:after': {
    borderTopColor: 'var(--bg-elevated)',
    borderBottomColor: 'var(--bg-elevated)',
  },
  '.cm-tooltip-autocomplete': {
    '& > ul > li[aria-selected]': {
      backgroundColor: 'var(--accent-bg)',
      color: 'var(--text-primary)',
    },
  },
}, { dark: true });

export function YamlEditor({
  value,
  onChange,
  readOnly = false,
  height = '300px',
  className = '',
}: YamlEditorProps) {
  const editorRef = useRef<HTMLDivElement>(null);
  const viewRef = useRef<EditorView | null>(null);

  useEffect(() => {
    if (!editorRef.current) return;

    const extensions = [
      basicSetup,
      yaml(),
      yamlLinter,
      darkTheme,
      EditorView.lineWrapping,
    ];

    if (readOnly) {
      extensions.push(EditorState.readOnly.of(true));
    }

    if (!readOnly) {
      extensions.push(
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            onChange(update.state.doc.toString());
          }
        })
      );
    }

    const state = EditorState.create({
      doc: value,
      extensions,
    });

    const view = new EditorView({
      state,
      parent: editorRef.current,
    });

    viewRef.current = view;

    return () => {
      view.destroy();
      viewRef.current = null;
    };
  }, []); // Only run once on mount

  // Update value when it changes externally
  useEffect(() => {
    const view = viewRef.current;
    if (!view) return;

    const currentValue = view.state.doc.toString();
    if (currentValue !== value) {
      view.dispatch({
        changes: {
          from: 0,
          to: currentValue.length,
          insert: value,
        },
      });
    }
  }, [value]);

  return (
    <div
      ref={editorRef}
      className={`border border-primary rounded-md overflow-hidden ${className}`}
      style={{ height }}
    />
  );
}

// Read-only variant for diff display
export function YamlViewer({
  value,
  height = '300px',
  className = '',
}: {
  value: string;
  height?: string;
  className?: string;
}) {
  return (
    <YamlEditor
      value={value}
      onChange={() => {}}
      readOnly={true}
      height={height}
      className={className}
    />
  );
}
