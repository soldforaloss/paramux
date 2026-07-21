const PRODUCT_FACTS = [
  {
    q: 'Who is Paramux for?',
    a: 'Windows developers running several coding-agent CLIs at once who need one place to organize them and see which pane needs attention.',
  },
  {
    q: 'What does the sidebar know?',
    a: 'For panes in the active tab, it shows the title, working directory, git branch and dirty state, listening ports, and the current attention color.',
  },
  {
    q: 'How does agent attention work?',
    a: 'Hooks and terminal notifications drive working, waiting, done, and error. The state appears on the pane, tab, and sidebar; alerting states can also raise a Windows toast and taskbar flash.',
  },
  {
    q: 'Does automation leave the machine?',
    a: 'No. The control surface is local-only. Pane reads, bounded input, and mutating actions require a per-instance token stored under %LOCALAPPDATA%\\paramux.',
  },
  {
    q: 'What can I download today?',
    a: 'A public, unsigned Windows x64 portable prerelease: v0.1.17. It ships the agent-hook adapters, the +send/+send-key automation verbs, and the fully Paramux-branded package.',
  },
  {
    q: 'What is not published yet?',
    a: 'There is no public WinGet or Scoop package, signed installer, or verified ARM64 release yet. The portable x64 build is the only current distribution.',
  },
];

export function ProductFacts() {
  return (
    <div className="wg-why-grid">
      {PRODUCT_FACTS.map((item, idx) => (
        <div key={item.q} className="wg-why-item">
          <span className="wg-why-item__index">{String(idx + 1).padStart(2, '0')}</span>
          <div>
            <h2>{item.q}</h2>
            <p>{item.a}</p>
          </div>
        </div>
      ))}
    </div>
  );
}
