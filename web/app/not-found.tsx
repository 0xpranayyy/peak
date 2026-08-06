export default function NotFound() {
  return (
    <div className="shell not-found">
      <h1>This market isn’t here.</h1>
      <p>
        It may have resolved and been removed upstream, or the link may be
        mistyped. Live markets are under Markets.
      </p>
      <p className="not-found__cta">
        <a className="cta" href="/markets">
          Browse markets
        </a>
      </p>
    </div>
  );
}
