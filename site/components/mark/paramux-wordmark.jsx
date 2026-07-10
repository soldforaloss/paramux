import { ParamuxMark } from '../mark.jsx';

export function ParamuxWordmark({ size = 28 }) {
  return (
    <span className="wg-wordmark">
      <ParamuxMark size={size} />
      <span className="wg-wordmark__text" style={{ fontSize: size * 0.78 }}>Paramux</span>
    </span>
  );
}
