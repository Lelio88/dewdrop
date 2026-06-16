#!/usr/bin/env bash
# push_chain_test.sh — integration test of the "pensée → push" SERVER chain
# against the LOCAL Supabase stack (`supabase start`). Two parts:
#
#   A. send-thought-push Edge Function branch logic, exercised end-to-end through
#      the real local edge-runtime:
#        - no record            -> {ok:false, reason:"no record"}
#        - recipient quiet hours -> {skipped:"quiet hours"}
#        - recipient has no device -> {sent:0, reason:"no devices"}
#        - reaches the FCM send stage (quiet-hours + name + device all passed)
#      No push is ever delivered: the device token is fake. With credentials in
#      supabase/functions/.env the function reports the send attempt ({sent:N});
#      in CI (no .env) it stops at {error:"FIREBASE_SERVICE_ACCOUNT not set"}.
#      Either response proves the gating logic ran correctly.
#
#   B. thoughts RLS security model, exercised with per-user JWTs (the real path):
#        - a user CAN send a thought to an accepted friend
#        - a user CANNOT send a thought to a non-friend (RLS denies)
#        - the recipient CAN read the received thought
#        - an unrelated third user CANNOT read it (no leak)
#
# Requires a running local stack + Docker. Skips cleanly (exit 0) if the stack is
# unreachable, so it never breaks a machine without Supabase up. No deno, no
# Firebase credentials needed.
#
# Run: bash tools/test/push_chain_test.sh
set -uo pipefail

API="http://127.0.0.1:54321"
FN="$API/functions/v1/send-thought-push"

ENV=$(supabase status -o env 2>/dev/null) || { echo "SKIP: supabase CLI/stack unavailable"; exit 0; }
SR=$(echo "$ENV"   | grep '^SERVICE_ROLE_KEY=' | cut -d= -f2- | tr -d '"')
ANON=$(echo "$ENV" | grep '^ANON_KEY='         | cut -d= -f2- | tr -d '"')
[ -n "$SR" ] && [ -n "$ANON" ] || { echo "SKIP: keys unavailable (stack down?)"; exit 0; }
curl -s --max-time 5 "$API/rest/v1/" -H "apikey: $SR" >/dev/null 2>&1 \
  || { echo "SKIP: REST unreachable (run 'supabase start')"; exit 0; }

# Seeding writes go through the postgres superuser (bypasses GRANT + RLS), since
# service_role intentionally has no INSERT on the app tables. The RLS assertions
# below still use per-user JWTs — that's where the real security is exercised.
DB=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 'supabase_db')
[ -n "$DB" ] || { echo "SKIP: supabase_db container not found"; exit 0; }
psql(){ docker exec -i "$DB" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -qtA "$@"; }

pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
ko(){ echo "  FAIL  $1"; echo "        got: $2"; fail=$((fail+1)); }
has(){ if echo "$1" | grep -qF "$2"; then ok "$3"; else ko "$3" "$1"; fi; }
hasnt(){ if echo "$1" | grep -qF "$2"; then ko "$3" "$1"; else ok "$3"; fi; }
has_either(){ # resp needleA needleB name
  if echo "$1" | grep -qF "$2" || echo "$1" | grep -qF "$3"; then ok "$4"; else ko "$4" "$1"; fi; }

svc(){ curl -s -H "apikey: $SR" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" "$@"; }
postfn(){ curl -s --max-time 12 -X POST "$FN" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" -d "$1"; }
mkuser(){ svc -X POST "$API/auth/v1/admin/users" \
  -d "{\"email\":\"$1\",\"password\":\"pw123456\",\"email_confirm\":true}" \
  | grep -oE '"id":"[0-9a-f-]+"' | head -1 | cut -d'"' -f4; }
signin(){ curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" \
  -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"pw123456\"}" \
  | grep -oE '"access_token":"[^"]+"' | head -1 | cut -d'"' -f4; }
asuser(){ local tok="$1"; shift; curl -s -H "apikey: $ANON" -H "Authorization: Bearer $tok" \
  -H "Content-Type: application/json" "$@"; }

SFX="$$_$RANDOM"
declare -a USERS=()
SERVE_PID=""
cleanup(){
  for u in "${USERS[@]:-}"; do [ -n "$u" ] && \
    svc -X DELETE "$API/auth/v1/admin/users/$u" -o /dev/null; done
  [ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null
}
trap cleanup EXIT

# Ensure the Edge Function is served (start our own only if it isn't already).
if ! postfn '{"record":{}}' | grep -q "no record"; then
  echo "starting edge-runtime (supabase functions serve)…"
  nohup supabase functions serve send-thought-push --no-verify-jwt >/tmp/fnserve_test.log 2>&1 &
  SERVE_PID=$!
  for i in $(seq 1 25); do
    postfn '{"record":{}}' | grep -q "no record" && break
    sleep 2
  done
fi

# Seed users (admin API → on_auth_user_created trigger makes each profile).
U_SEND=$(mkuser   "send_$SFX@dewdrop.test");  USERS+=("$U_SEND")
U_RECIP=$(mkuser  "recip_$SFX@dewdrop.test"); USERS+=("$U_RECIP")
U_QUIET=$(mkuser  "quiet_$SFX@dewdrop.test"); USERS+=("$U_QUIET")
U_NODEV=$(mkuser  "nodev_$SFX@dewdrop.test"); USERS+=("$U_NODEV")
U_STRAN=$(mkuser  "stran_$SFX@dewdrop.test"); USERS+=("$U_STRAN")
for u in "$U_SEND" "$U_RECIP" "$U_QUIET" "$U_NODEV" "$U_STRAN"; do
  [ -n "$u" ] || { echo "FAIL: user seeding failed (got empty id)"; exit 1; }
done

# Recipient + quiet recipient get a device; quiet recipient gets quiet hours
# spanning the current UTC hour (quiet_tz null => compared in UTC by the fn).
# Accepted friendship send -> recip so the RLS thought insert below is allowed.
H=$((10#$(date -u +%H))); H1=$(( (H + 1) % 24 ))
psql -c "
  update public.profiles set quiet_start=$H, quiet_end=$H1 where id='$U_QUIET';
  insert into public.devices(user_id, token, platform) values
    ('$U_RECIP','tok_r_$SFX','android'),
    ('$U_QUIET','tok_q_$SFX','android');
  insert into public.friendships(requester_id, addressee_id, status) values
    ('$U_SEND','$U_RECIP','accepted');
" >/dev/null

rec(){ echo "{\"record\":{\"id\":\"00000000-0000-0000-0000-000000000000\",\"sender_id\":\"$U_SEND\",\"recipient_id\":\"$1\",\"is_anonymous\":false}}"; }

echo ""
echo "== A. Edge Function branches (FCM never called) =="
has "$(postfn '{"record":{}}')"            "no record"                       "no record -> short-circuits"
has "$(postfn "$(rec "$U_QUIET")")"        "quiet hours"                     "recipient in quiet hours -> skipped"
has "$(postfn "$(rec "$U_NODEV")")"        "no devices"                      "recipient without device -> no devices"
has_either "$(postfn "$(rec "$U_RECIP")")" '"sent"' "FIREBASE_SERVICE_ACCOUNT not set" "reaches FCM send stage (quiet+name+device passed)"

echo ""
echo "== B. thoughts RLS (per-user JWTs) =="
T_SEND=$(signin "send_$SFX@dewdrop.test")
T_RECIP=$(signin "recip_$SFX@dewdrop.test")
T_STRAN=$(signin "stran_$SFX@dewdrop.test")
[ -n "$T_SEND" ] && [ -n "$T_RECIP" ] && [ -n "$T_STRAN" ] || { echo "FAIL: sign-in failed"; exit 1; }

# sender -> friend : allowed
r=$(asuser "$T_SEND" -X POST "$API/rest/v1/thoughts" -H "Prefer: return=representation" \
  -d "{\"sender_id\":\"$U_SEND\",\"recipient_id\":\"$U_RECIP\"}")
has "$r" "$U_RECIP" "friend can be sent a thought (RLS insert allowed)"
# sender -> stranger (not a friend) : denied by RLS
r=$(asuser "$T_SEND" -X POST "$API/rest/v1/thoughts" -H "Prefer: return=representation" \
  -d "{\"sender_id\":\"$U_SEND\",\"recipient_id\":\"$U_STRAN\"}")
hasnt "$r" "$U_STRAN" "non-friend cannot be sent a thought (RLS insert denied)"
# recipient reads their received thought
r=$(asuser "$T_RECIP" "$API/rest/v1/thoughts?select=sender_id,recipient_id")
has "$r" "$U_SEND" "recipient can read the received thought"
# unrelated third user reads nothing
r=$(asuser "$T_STRAN" "$API/rest/v1/thoughts?select=id")
hasnt "$r" "$U_SEND" "stranger cannot read others' thoughts (no leak)"

echo ""
echo "================================"
echo "  push-chain: $pass passed, $fail failed"
echo "================================"
[ "$fail" -eq 0 ]
