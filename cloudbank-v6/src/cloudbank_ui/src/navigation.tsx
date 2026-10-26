import { useEffect, useState, type AnchorHTMLAttributes, type ReactNode } from 'react';

export function go(path: string) {
  window.history.pushState({}, '', path);
  window.dispatchEvent(new Event('cloudbank:navigate'));
  window.scrollTo({ top: 0, behavior: 'instant' });
}

export function usePath() {
  const [path, setPath] = useState(() => window.location.pathname + window.location.search);
  useEffect(() => {
    const update = () => setPath(window.location.pathname + window.location.search);
    window.addEventListener('popstate', update);
    window.addEventListener('cloudbank:navigate', update);
    return () => { window.removeEventListener('popstate', update); window.removeEventListener('cloudbank:navigate', update); };
  }, []);
  return path;
}

export function Link({ href, children, className = '', ...props }: AnchorHTMLAttributes<HTMLAnchorElement> & { href: string; children: ReactNode }) {
  return <a href={href} className={className} {...props} onClick={event => {
    props.onClick?.(event);
    if (!event.defaultPrevented && event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey) {
      event.preventDefault(); go(href);
    }
  }}>{children}</a>;
}
