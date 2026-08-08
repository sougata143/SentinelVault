/**
 * Utility to parse User-Agent headers into human-readable device labels.
 * Designed to be zero-dependency, fast, and privacy-preserving.
 */
export function parseDeviceLabel(userAgent?: string): string {
  if (!userAgent || typeof userAgent !== 'string' || userAgent.trim() === '') {
    return 'Unknown Device';
  }

  const ua = userAgent.trim();

  // 1. Identify Client / App
  let client = '';
  if (ua.includes('SentinelVault/')) {
    client = 'SentinelVault App';
  } else if (ua.includes('Edg/')) {
    client = 'Edge';
  } else if (ua.includes('Chrome/')) {
    client = 'Chrome';
  } else if (ua.includes('Firefox/')) {
    client = 'Firefox';
  } else if (ua.includes('Safari/') && !ua.includes('Chrome/')) {
    client = 'Safari';
  } else if (ua.includes('PostmanRuntime')) {
    client = 'Postman API Client';
  } else {
    client = 'Web Client';
  }

  // 2. Identify OS / Platform
  let os = '';
  if (ua.includes('iPhone') || ua.includes('iPad') || ua.includes('iPod')) {
    os = 'iOS';
  } else if (ua.includes('Android')) {
    os = 'Android';
  } else if (ua.includes('Windows')) {
    os = 'Windows';
  } else if (ua.includes('Macintosh') || ua.includes('Mac OS')) {
    os = 'macOS';
  } else if (ua.includes('Linux')) {
    os = 'Linux';
  }

  if (client && os) {
    return `${client} on ${os}`;
  } else if (os) {
    return `Device on ${os}`;
  } else if (client) {
    return client;
  }

  return 'Unknown Device';
}
