// Hero — Paramux product story and the one truthful release path.

import { ReleaseBlock } from './release/release-block.jsx';
import { ReleaseChip } from './hero/release-chip.jsx';
import { ParamuxMissionControl } from './mission-control.jsx';

const RELEASE_URL = 'https://github.com/soldforaloss/paramux/releases/tag/v0.1.8';

export function HeroColorPop() {
  return (
    <section className="wg-hero" id="download" aria-labelledby="hero-title">
      <div className="wg-hero-copy">
        <ReleaseChip />

        <div className="wg-hero__intro">
          <h1 className="wg-hero__title" id="hero-title">
            Every agent<span className="wg-accent-red">,</span>
            <br /> in sight<span className="wg-accent-blue">.</span>
          </h1>
          <p className="wg-hero__caption">
            Paramux is a native Windows command center for parallel coding agents: cmux/tmux/wmux-inspired
            panes and workspaces, live sidebar metadata, four-state attention, and local automation on
            Ghostty&apos;s GPU terminal core.{' '}
            <a href="https://github.com/soldforaloss/paramux#readme">See a real capture in the README.</a>
          </p>
        </div>

        <div className="wg-hero__actions">
          <a
            className="wg-button wg-button--primary"
            href={RELEASE_URL}
            target="_blank"
            rel="noreferrer"
          >
            Open latest release ↗
          </a>
          <ReleaseBlock />
        </div>

        <div className="wg-hero__terminal">
          <ParamuxMissionControl />
        </div>
      </div>
    </section>
  );
}
