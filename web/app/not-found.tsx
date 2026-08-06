export default function NotFound() {
  return (
    <div className="shell detail">
      <h1 style={{ fontSize: 28, letterSpacing: "-0.03em" }}>
        This market isn’t here.
      </h1>
      <p style={{ color: "var(--text-2)", marginTop: 12, maxWidth: "56ch" }}>
        It may have resolved and been removed upstream, or the link may be
        mistyped. Live markets are on the home page.
      </p>
      <p style={{ marginTop: 24 }}>
        <a className="cta" href="/">
          Browse markets
        </a>
      </p>
    </div>
  );
}
