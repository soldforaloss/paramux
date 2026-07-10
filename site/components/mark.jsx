// Paramux prompt-and-cursor mark.

export function ParamuxMark({ size = 28, animated = false }) {
  return (
    <svg
      className={animated ? 'wg-paramux-mark is-animated' : 'wg-paramux-mark'}
      width={size}
      height={size}
      viewBox="0 0 32 32"
      fill="none"
      aria-hidden="true"
    >
      <rect x="1" y="1" width="30" height="30" rx="7" fill="#16161e" />
      <rect x="1.5" y="1.5" width="29" height="29" rx="6.5" stroke="currentColor" strokeOpacity="0.16" />
      <path
        d="m9.7 10.6 6.8 5.4-6.8 5.4"
        stroke="#7aa2f7"
        strokeWidth="3.1"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect className="wg-paramux-mark__cursor" x="18.1" y="18.4" width="5.2" height="3.5" rx="1" fill="#7aa2f7" />
    </svg>
  );
}
