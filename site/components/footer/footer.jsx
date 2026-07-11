import { ParamuxWordmark } from '../mark/paramux-wordmark.jsx';

const REPO_URL = 'https://github.com/soldforaloss/paramux';

export function Footer() {
  return (
    <footer className="wg-footer">
      <div className="wg-footer__top">
        <ParamuxWordmark size={20} />
        <div className="wg-footer__links">
          <a href={REPO_URL} target="_blank" rel="noopener noreferrer">Repository</a>
          <a href={`${REPO_URL}/releases/tag/v0.1.0-paramux.9`} target="_blank" rel="noopener noreferrer">Latest release</a>
          <a href={`${REPO_URL}/blob/paramux/docs/paramux/capability-parity.md`} target="_blank" rel="noopener noreferrer">Capability status</a>
          <a href="https://ghostty.org" target="_blank" rel="noopener noreferrer">Ghostty ↗</a>
        </div>
      </div>
      <div className="wg-footer__bottom">
        <span>
          Paramux is the product. Ghostty and{' '}
          <a href="https://github.com/amanthanvi/winghostty" target="_blank" rel="noopener noreferrer">Winghostty</a>{' '}
          are its technical lineage.
        </span>
        <span>MIT · local-first · no public package-manager release yet</span>
      </div>
    </footer>
  );
}
