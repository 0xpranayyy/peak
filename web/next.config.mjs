/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Privy pulls walletconnect / noble packages that need transpilation in Next.
  transpilePackages: ["@privy-io/react-auth"],
  images: {
    // Market artwork comes from Polymarket's CDNs. Listed explicitly rather than
    // allowing any host — this app renders third-party URLs from an API response.
    remotePatterns: [
      { protocol: "https", hostname: "polymarket-upload.s3.us-east-2.amazonaws.com" },
      { protocol: "https", hostname: "polymarket.com" },
      { protocol: "https", hostname: "**.polymarket.com" },
    ],
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "X-Frame-Options", value: "DENY" },
          {
            key: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()",
          },
        ],
      },
    ];
  },
  webpack: (config) => {
    config.externals.push("pino-pretty", "lokijs", "encoding");
    return config;
  },
};

export default nextConfig;
