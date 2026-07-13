const RELEASE_TAG = 'v0.1.2';

export function ReleaseBlock() {
  return (
    <div className="wg-release" aria-label="Current Paramux release details">
      <div className="wg-release__headline">
        <span className="wg-release__signal" aria-hidden="true" />
        <span className="wg-release__label">current test build</span>
        <strong>{RELEASE_TAG}</strong>
      </div>
      <div className="wg-release__facts" aria-label="Private, Windows x64 portable ZIP, unsigned, OpenGL 4.3 or newer">
        <span>public</span>
        <span>Windows x64</span>
        <span>portable ZIP</span>
        <span>unsigned</span>
        <span>OpenGL 4.3+</span>
      </div>
      <p>
        Authorized GitHub access required. Verify the SHA-256 checksum before first run;
        the packaged install-paramux.cmd adds the folder to PATH and wires the agent hooks.
      </p>
    </div>
  );
}
