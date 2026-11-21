import { secureHeaders } from 'hono/secure-headers';

// API の返事に付けるセキュリティのヘッダー（ADR-028・S1-26）
// API は JSON しか返さないので、CSP は「何も読み込まない・どこにも埋め込ませない」にする
export const securityHeaders = () =>
  secureHeaders({
    contentSecurityPolicy: {
      defaultSrc: ["'none'"],
      baseUri: ["'none'"],
      formAction: ["'none'"],
      frameAncestors: ["'none'"],
    },
    // includeSubDomains は付けない（このホストだけに効かせる）
    strictTransportSecurity: 'max-age=15552000',
    xFrameOptions: 'DENY',
    referrerPolicy: 'no-referrer',
    permissionsPolicy: { camera: [], microphone: [], geolocation: [] },
  });
