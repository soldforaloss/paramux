const RELEASE_TAG = 'v0.1.0-paramux.4';

export function ReleaseBlock() {
  return (
    <div className="wg-release" aria-label="Current Paramux release details">
      <div className="wg-release__headline">
        <span className="wg-release__signal" aria-hidden="true" />
        <span className="wg-release__label">current test build</span>
        <strong>{RELEASE_TAG}</strong>
      </div>
      <div className="wg-release__facts" aria-label="Private, Windows x64 portable ZIP, unsigned, OpenGL 4.3 or newer">
        <span>private</span>
        <span>Windows x64</span>
        <span>portable ZIP</span>
        <span>unsigned</span>
        <span>OpenGL 4.3+</span>
      </div>
      <p>
        Authorized GitHub access required. The live v4 ZIP predates the package-level README,
        completion, and VERSIONINFO rebrand; use it only as a legacy test artifact.
      </p>
    </div>
  );
}
