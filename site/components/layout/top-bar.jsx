import { ParamuxToggle } from '../mark/paramux-toggle.jsx';
import { ParamuxWordmark } from '../mark/paramux-wordmark.jsx';

export function TopBar({ theme, setTheme }) {
  return (
    <header className="wg-topbar">
      <div className="wg-container wg-topbar__inner">
        <a href="/" className="wg-wordmark-link" aria-label="Paramux home">
          <ParamuxWordmark size={24} />
        </a>
        <div className="wg-topbar__actions">
          <span className="wg-topbar__status">private preview</span>
          <ParamuxToggle theme={theme} onToggle={() => setTheme(theme === 'dark' ? 'light' : 'dark')} />
        </div>
      </div>
    </header>
  );
}
