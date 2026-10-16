import { parseInvitation } from './parser.mjs';
import { allowedOrigins, installationURL } from './config.mjs';
export function renderInvitation(document, href, origins, installURL) {
  const code = parseInvitation(href, origins);
  const codeElement = document.getElementById('room-code');
  const status = document.getElementById('status');
  if (code) {
    codeElement.textContent = code;
    codeElement.setAttribute('aria-label', `Room code ${code.split('').join(' ')}`);
    codeElement.hidden = false;
    status.textContent = "Install GridRace, then reopen this same invitation from your friend's message. Or enter this code in Live race.";
    const reopen = document.getElementById('reopen');
    reopen.href = href;
    reopen.hidden = false;
    const install = document.getElementById('install');
    if (installURL && /^https:\/\/apps\.apple\.com\//.test(installURL)) {
      install.href = installURL;
      install.hidden = false;
    }
  } else {
    status.textContent = 'This invitation link is not supported. Ask your friend for the six-character room code.';
  }
}
if (typeof window !== 'undefined') {
  renderInvitation(document, window.location.href, allowedOrigins, installationURL);
}
