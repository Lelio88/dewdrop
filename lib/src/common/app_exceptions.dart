// App-level exceptions surfaced to the presentation layer. The data layer
// translates infrastructure errors (e.g. a Postgres `rate_limited`
// check-violation) into these typed exceptions, so the UI never has to know
// about PostgrestException or any transport detail.

/// The server's anti-flood cap rejected the send: 25 pensées/min for a 1-to-1
/// send, 150/min for a group fan-out. Surfaced so the UI can show a friendly
/// "you're sending a bit fast" message instead of a generic failure.
class RateLimitedException implements Exception {
  const RateLimitedException();
}
