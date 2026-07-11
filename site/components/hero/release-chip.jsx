import { ColorDots } from './color-dots.jsx';

export const PARAMUX_VERSION = '0.1.0-paramux.9';

export function ReleaseChip() {
  return (
    <span className="wg-hero__badge">
      <ColorDots />
      <span className="wg-hero__badge-version">{`v${PARAMUX_VERSION}`}</span>
      <span className="wg-hero__badge-latest">public prerelease</span>
      <span className="wg-hero__badge-sep" aria-hidden="true" />
      <span className="wg-hero__badge-meta">Windows 10/11 · x64 portable</span>
      <span className="wg-hero__badge-sep" aria-hidden="true" />
      <span className="wg-hero__badge-stack">unsigned · OpenGL 4.3+</span>
    </span>
  );
}
