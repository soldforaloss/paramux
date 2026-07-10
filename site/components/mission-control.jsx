// A compact product demo: agent metadata on the left, local control on the right.

import { TerminalLine } from './terminal/terminal-line.jsx';

const { useEffect, useReducer, useState } = React;

const REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

function initialReducedMotion() {
  return typeof window !== 'undefined'
    && typeof window.matchMedia === 'function'
    && window.matchMedia(REDUCED_MOTION_QUERY).matches;
}

const PANES = [
  { agent: 'codex · api', state: 'working', meta: 'main* · api · :3000' },
  { agent: 'claude · auth', state: 'waiting', meta: 'feat/pkce · auth' },
  { agent: 'tests · pwsh', state: 'done', meta: 'main · desktop' },
  { agent: 'gemini · docs', state: 'error', meta: 'docs/sidebar · docs' },
];

const SCENES = [
  {
    title: 'agent attention',
    lines: [
      { kind: 'cmd', text: 'paramux +notify --state=waiting "Review auth diff"' },
      { kind: 'out', t: '→ pane 42 · waiting · sidebar + tab + pane ring', c: 'waiting' },
      { kind: 'out', t: '→ native toast + taskbar attention', c: 'dim' },
    ],
  },
  {
    title: 'drive a pane',
    lines: [
      { kind: 'cmd', text: 'paramux +send --surface-id=42 "npm test"' },
      { kind: 'out', t: '→ exact bounded input · token-gated · pane-targeted', c: 'fg' },
      { kind: 'out', t: '→ paramux +send-key --surface-id=42 enter', c: 'dim' },
    ],
  },
  {
    title: 'split locally',
    lines: [
      { kind: 'cmd', text: 'paramux +perform-action new_split:right' },
      { kind: 'out', t: '→ split created in the active tab', c: 'done' },
      { kind: 'out', t: '→ independent ConPTY pane · drag to resize', c: 'dim' },
    ],
  },
  {
    title: 'discover panes',
    lines: [
      { kind: 'cmd', text: 'paramux +list-windows' },
      { kind: 'out', t: '→ paramux.windows.v2 · 1 window · 2 tabs · 4 panes', c: 'fg' },
      { kind: 'out', t: '→ local-only discovery; sensitive calls stay token-gated', c: 'dim' },
    ],
  },
].map((scene) => ({
  ...scene,
  lines: scene.lines.map((line, index) => ({
    ...line,
    id: `${scene.title}:${index}:${line.kind}:${line.text || line.t}`,
  })),
}));

const PROMPT = 'PS C:\\work\\paramux>';
const initialState = { sceneIndex: 0, lineIndex: 0, typed: '' };

function reducer(state, action) {
  switch (action.type) {
    case 'type':
      return { ...state, typed: action.text };
    case 'next-line':
      return { ...state, lineIndex: state.lineIndex + 1, typed: '' };
    case 'next-output':
      return { ...state, lineIndex: state.lineIndex + 1 };
    case 'next-scene':
      return { sceneIndex: (state.sceneIndex + 1) % SCENES.length, lineIndex: 0, typed: '' };
    default:
      return state;
  }
}

export function ParamuxMissionControl() {
  const [{ sceneIndex, lineIndex, typed }, dispatch] = useReducer(reducer, initialState);
  const [reducedMotion, setReducedMotion] = useState(initialReducedMotion);
  const scene = SCENES[sceneIndex];
  const line = scene.lines[lineIndex];

  useEffect(() => {
    const media = window.matchMedia(REDUCED_MOTION_QUERY);
    const update = (event) => setReducedMotion(event.matches);
    if (typeof media.addEventListener === 'function') {
      media.addEventListener('change', update);
      return () => media.removeEventListener('change', update);
    }
    media.addListener(update);
    return () => media.removeListener(update);
  }, []);

  useEffect(() => {
    if (reducedMotion) return undefined;

    if (lineIndex >= scene.lines.length) {
      const timer = window.setTimeout(() => dispatch({ type: 'next-scene' }), 1900);
      return () => window.clearTimeout(timer);
    }

    if (line.kind === 'cmd') {
      if (typed.length < line.text.length) {
        const timer = window.setTimeout(
          () => dispatch({ type: 'type', text: line.text.slice(0, typed.length + 1) }),
          24 + Math.random() * 34,
        );
        return () => window.clearTimeout(timer);
      }

      const timer = window.setTimeout(() => dispatch({ type: 'next-line' }), 420);
      return () => window.clearTimeout(timer);
    }

    const timer = window.setTimeout(() => dispatch({ type: 'next-output' }), 300);
    return () => window.clearTimeout(timer);
  }, [line, lineIndex, reducedMotion, scene, typed]);

  const visible = reducedMotion
    ? scene.lines.map((entry) => ({ key: entry.id, line: entry }))
    : scene.lines.slice(0, lineIndex).map((entry) => ({ key: entry.id, line: entry }));
  if (!reducedMotion) {
    if (line?.kind === 'cmd') {
      visible.push({ key: `${line.id}:typing`, line: { kind: 'cmd', text: typed, cursor: true } });
    } else if (lineIndex >= scene.lines.length) {
      visible.push({ key: `${scene.title}:idle`, line: { kind: 'cmd', text: '', cursor: true } });
    }
  }

  return (
    <div className="wg-terminal" aria-label="Paramux mission-control preview">
      <div className="wg-terminal__chrome">
        <div className="wg-terminal__title">paramux · active workspace · {scene.title}</div>
        <div className="wg-terminal__caption" aria-hidden="true">
          <span className="wg-terminal__caption-btn" />
          <span className="wg-terminal__caption-btn" />
          <span className="wg-terminal__caption-btn wg-terminal__caption-btn--close" />
        </div>
      </div>
      <div className="wg-terminal__workspace">
        <aside className="wg-mission-sidebar" aria-label="Active workspace panes">
          <div className="wg-mission-sidebar__header">
            <span>active tab</span>
            <span>{PANES.length} panes</span>
          </div>
          <div className="wg-mission-sidebar__rows">
            {PANES.map((pane, index) => (
              <div
                className={`wg-agent-row${index === 1 ? ' is-active' : ''}`}
                data-state={pane.state}
                key={pane.agent}
              >
                <span className="wg-agent-row__dot" aria-hidden="true" />
                <span className="wg-agent-row__copy">
                  <strong>{pane.agent}</strong>
                  <span>{pane.meta}</span>
                </span>
                <span className="wg-agent-row__state">{pane.state}</span>
              </div>
            ))}
          </div>
        </aside>
        <div className="wg-terminal__body">
          <div className="wg-terminal__pane-label">
            <span>claude · auth</span>
            <span className="wg-terminal__pane-state">waiting</span>
          </div>
          {visible.map(({ key, line: visibleLine }) => {
            if (visibleLine.kind === 'cmd') {
              return <TerminalLine key={key} prompt={PROMPT} text={visibleLine.text} cursor={visibleLine.cursor} />;
            }

            return (
              <div key={key} className={`wg-terminal__line wg-terminal__line--${visibleLine.c || 'fg'}`}>
                {visibleLine.t}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
