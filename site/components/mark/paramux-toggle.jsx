import { ParamuxMark } from '../mark.jsx';

const { useEffect, useRef, useState } = React;

export function ParamuxToggle({ theme, onToggle, size = 22 }) {
  const [blinking, setBlinking] = useState(false);
  const blinkTimerRef = useRef(null);

  useEffect(() => () => {
    if (blinkTimerRef.current) clearTimeout(blinkTimerRef.current);
  }, []);

  const triggerBlink = () => {
    if (blinking) return;
    onToggle();
    setBlinking(true);
    blinkTimerRef.current = setTimeout(() => {
      setBlinking(false);
      blinkTimerRef.current = null;
    }, 220);
  };

  return (
    <button
      type="button"
      className={`wg-theme-toggle${blinking ? ' is-blinking' : ''}`}
      onClick={triggerBlink}
      aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
      title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
    >
      <ParamuxMark size={size} animated />
    </button>
  );
}
