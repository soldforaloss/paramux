import { FeatureCard } from './feature-card.jsx';

const FEATURES = [
  {
    k: 'workspaces',
    title: 'Panes that stay organized',
    body: 'Independent ConPTY panes, horizontal and vertical splits, tabbed workspaces, pane zoom, and drag-to-resize dividers.',
  },
  {
    k: 'sidebar',
    title: 'Context without tab hunting',
    body: 'The active workspace sidebar shows each pane\'s title, directory, git branch and dirty state, listening ports, and attention color.',
  },
  {
    k: 'attention',
    title: 'Four states, one signal',
    body: 'Working, waiting, done, and error use the same color across the sidebar, tab strip, and pane ring, with native alerts when attention is needed.',
  },
  {
    k: 'automation',
    title: 'Local automation surface',
    body: 'Discover panes, trigger safe actions, read output, send bounded input, and set notifications over a token-gated local named pipe.',
  },
  {
    k: 'gpu',
    title: 'A real Windows terminal',
    body: 'Native Win32, ConPTY, and WGL/OpenGL 4.3 rendering. No Electron shell, browser terminal, or xterm.js WebView in the terminal path.',
  },
  {
    k: 'ghostty',
    title: 'Ghostty at the core',
    body: 'Paramux keeps Ghostty\'s mature terminal, font, theme, and GPU rendering foundation while building the Windows agent workflow around it.',
  },
];

export function FeatureGrid() {
  return (
    <div className="wg-feature-grid">
      {FEATURES.map((feature) => <FeatureCard key={feature.k} feature={feature} />)}
    </div>
  );
}
